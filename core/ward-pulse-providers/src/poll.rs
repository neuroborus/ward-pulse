//! Per-connection polling floors and freshness guidance.
//!
//! Cadence counterpart of [`crate::connection_capabilities`]. Reporting and
//! administration endpoints are rate-limited independently from model inference
//! and agent traffic, so polling usage reports does not consume agent capacity
//! and cannot slow down a running agent. Every floor below is a report-polling
//! floor only.

use std::time::Duration;

use ward_pulse_core::model::{ConnectionKind, ProviderConnectionId, ProviderFamily};

/// Minimum poll interval and optional non-clamping freshness guidance.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Guidance {
    pub min_interval: Duration,
    /// Surfaced on Settings rows; does not clamp the poll cadence.
    pub freshness_note: Option<&'static str>,
}

/// OpenAI Platform organization reporting: no published per-endpoint limit, so
/// the floor is conservative.
pub const OPENAI_PLATFORM_MIN_POLL: Duration = Duration::from_secs(5 * 60);

/// Codex subscription usage: unpublished compatibility contract, so the floor
/// is conservative.
pub const CODEX_PLAN_MIN_POLL: Duration = Duration::from_secs(5 * 60);

/// Anthropic organization Usage & Cost Admin API, documented to support polling
/// once per minute
/// (<https://platform.claude.com/docs/en/manage-claude/usage-cost-api>).
pub const ANTHROPIC_PLATFORM_MIN_POLL: Duration = Duration::from_secs(60);

/// Claude subscription usage: undocumented compatibility contract. Community
/// monitors observe stable behavior near three minutes; WardPulse stays
/// conservative at five.
pub const CLAUDE_PLAN_MIN_POLL: Duration = Duration::from_secs(5 * 60);

/// Cursor plan session endpoints: unpublished compatibility contract, so the
/// floor is conservative. No freshness note — hourly aggregation is not a
/// documented personal-plan contract.
pub const CURSOR_PLAN_MIN_POLL: Duration = Duration::from_secs(5 * 60);

/// Cursor team Admin API, capped at 20 requests per minute
/// (<https://cursor.com/docs/api>) and polled at five minutes like the other
/// connections. See [`CURSOR_USAGE_FRESHNESS_NOTE`].
pub const CURSOR_PLATFORM_MIN_POLL: Duration = Duration::from_secs(5 * 60);

/// Visible Settings note for the Cursor Team Admin API row only. Freshness
/// guidance does not clamp the poll cadence.
pub const CURSOR_USAGE_FRESHNESS_NOTE: &str =
    "Cursor aggregates usage about once an hour, so refreshed values may lag.";

/// Strictest hard floor across connections, rounded up. Bounds the global
/// refresh slider lower end.
pub const GLOBAL_REFRESH_MIN: Duration = Duration::from_secs(5 * 60);

/// Global refresh slider upper bound.
pub const GLOBAL_REFRESH_MAX: Duration = Duration::from_secs(60 * 60);

/// Cadence lookup for one connection.
pub const fn guidance(connection: ProviderConnectionId) -> Guidance {
    match (connection.family, connection.kind) {
        (ProviderFamily::OpenAi, ConnectionKind::Platform) => Guidance {
            min_interval: OPENAI_PLATFORM_MIN_POLL,
            freshness_note: None,
        },
        (ProviderFamily::OpenAi, ConnectionKind::Plan) => Guidance {
            min_interval: CODEX_PLAN_MIN_POLL,
            freshness_note: None,
        },
        (ProviderFamily::Anthropic, ConnectionKind::Platform) => Guidance {
            min_interval: ANTHROPIC_PLATFORM_MIN_POLL,
            freshness_note: None,
        },
        (ProviderFamily::Anthropic, ConnectionKind::Plan) => Guidance {
            min_interval: CLAUDE_PLAN_MIN_POLL,
            freshness_note: None,
        },
        (ProviderFamily::Cursor, ConnectionKind::Plan) => Guidance {
            min_interval: CURSOR_PLAN_MIN_POLL,
            freshness_note: None,
        },
        (ProviderFamily::Cursor, ConnectionKind::Platform) => Guidance {
            min_interval: CURSOR_PLATFORM_MIN_POLL,
            freshness_note: Some(CURSOR_USAGE_FRESHNESS_NOTE),
        },
    }
}

/// `max(user_setting, provider_minimum)` for one connection.
pub const fn effective_interval(
    user_setting: Duration,
    connection: ProviderConnectionId,
) -> Duration {
    let floor = guidance(connection).min_interval;
    // `Duration` comparison is not const; whole-second floors make this exact.
    if user_setting.as_secs() > floor.as_secs() {
        user_setting
    } else {
        floor
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn documents_per_connection_floors() {
        for (id, seconds) in [
            (ProviderConnectionId::OPENAI_PLATFORM, 300),
            (ProviderConnectionId::OPENAI_PLAN, 300),
            (ProviderConnectionId::ANTHROPIC_PLATFORM, 60),
            (ProviderConnectionId::ANTHROPIC_PLAN, 300),
            (ProviderConnectionId::CURSOR_PLAN, 300),
            (ProviderConnectionId::CURSOR_PLATFORM, 300),
        ] {
            let guidance = guidance(id);
            assert_eq!(
                guidance.min_interval,
                Duration::from_secs(seconds),
                "{id:?}"
            );
            assert_eq!(
                guidance.freshness_note,
                if id == ProviderConnectionId::CURSOR_PLATFORM {
                    Some(CURSOR_USAGE_FRESHNESS_NOTE)
                } else {
                    None
                }
            );
        }
    }

    #[test]
    fn surfaces_cursor_admin_freshness_without_clamping() {
        let plan = guidance(ProviderConnectionId::CURSOR_PLAN);
        assert_eq!(plan.freshness_note, None);
        assert_eq!(plan.min_interval, CURSOR_PLAN_MIN_POLL);

        let platform = guidance(ProviderConnectionId::CURSOR_PLATFORM);
        assert_eq!(platform.freshness_note, Some(CURSOR_USAGE_FRESHNESS_NOTE));
        assert_eq!(platform.min_interval, CURSOR_PLATFORM_MIN_POLL);
        assert!(platform.min_interval < Duration::from_secs(60 * 60));
    }

    #[test]
    fn clamps_user_setting_to_connection_floor() {
        let under = Duration::from_secs(60);
        assert_eq!(
            effective_interval(under, ProviderConnectionId::OPENAI_PLATFORM),
            OPENAI_PLATFORM_MIN_POLL
        );
        let over = Duration::from_secs(15 * 60);
        assert_eq!(
            effective_interval(over, ProviderConnectionId::OPENAI_PLATFORM),
            over
        );
        assert_eq!(
            effective_interval(under, ProviderConnectionId::ANTHROPIC_PLATFORM),
            ANTHROPIC_PLATFORM_MIN_POLL
        );
    }

    #[test]
    fn global_slider_lower_bound_satisfies_every_floor() {
        for connection in ProviderConnectionId::ALL {
            assert_eq!(
                effective_interval(GLOBAL_REFRESH_MIN, connection),
                GLOBAL_REFRESH_MIN,
                "{connection:?} floor exceeds the global slider minimum"
            );
        }
        assert_eq!(GLOBAL_REFRESH_MAX, Duration::from_secs(60 * 60));
    }
}
