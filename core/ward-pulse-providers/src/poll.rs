//! Per-connection polling floors and freshness guidance.
//!
//! Cadence counterpart of [`crate::provider_capabilities`]. Reporting and
//! administration endpoints are rate-limited independently from model inference
//! and agent traffic, so polling usage reports does not consume agent capacity
//! and cannot slow down a running agent. Every floor below is a report-polling
//! floor only.

use std::time::Duration;

/// Homogeneous connection identity used for cadence lookup.
///
/// Matches the phone Settings plan/platform split.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ProviderConnectionKind {
    OpenAiPlatform,
    CodexPlan,
    AnthropicPlatform,
    ClaudePlan,
    CursorPlan,
    CursorPlatform,
}

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
/// floor is conservative. See [`CURSOR_USAGE_FRESHNESS_NOTE`].
pub const CURSOR_PLAN_MIN_POLL: Duration = Duration::from_secs(5 * 60);

/// Cursor team Admin API, capped at 20 requests per minute
/// (<https://cursor.com/docs/api>) and polled at five minutes like the other
/// connections. See [`CURSOR_USAGE_FRESHNESS_NOTE`].
pub const CURSOR_PLATFORM_MIN_POLL: Duration = Duration::from_secs(5 * 60);

/// Visible Settings note for Cursor rows. Freshness guidance does not clamp
/// the poll cadence.
pub const CURSOR_USAGE_FRESHNESS_NOTE: &str =
    "Cursor aggregates usage about once an hour, so refreshed values may lag.";

/// Strictest hard floor across connections, rounded up. Bounds the global
/// refresh slider lower end.
pub const GLOBAL_REFRESH_MIN: Duration = Duration::from_secs(5 * 60);

/// Global refresh slider upper bound.
pub const GLOBAL_REFRESH_MAX: Duration = Duration::from_secs(60 * 60);

/// Cadence lookup for one connection.
pub const fn guidance(connection: ProviderConnectionKind) -> Guidance {
    match connection {
        ProviderConnectionKind::OpenAiPlatform => Guidance {
            min_interval: OPENAI_PLATFORM_MIN_POLL,
            freshness_note: None,
        },
        ProviderConnectionKind::CodexPlan => Guidance {
            min_interval: CODEX_PLAN_MIN_POLL,
            freshness_note: None,
        },
        ProviderConnectionKind::AnthropicPlatform => Guidance {
            min_interval: ANTHROPIC_PLATFORM_MIN_POLL,
            freshness_note: None,
        },
        ProviderConnectionKind::ClaudePlan => Guidance {
            min_interval: CLAUDE_PLAN_MIN_POLL,
            freshness_note: None,
        },
        ProviderConnectionKind::CursorPlan => Guidance {
            min_interval: CURSOR_PLAN_MIN_POLL,
            freshness_note: Some(CURSOR_USAGE_FRESHNESS_NOTE),
        },
        ProviderConnectionKind::CursorPlatform => Guidance {
            min_interval: CURSOR_PLATFORM_MIN_POLL,
            freshness_note: Some(CURSOR_USAGE_FRESHNESS_NOTE),
        },
    }
}

/// `max(user_setting, provider_minimum)` for one connection.
pub const fn effective_interval(
    user_setting: Duration,
    connection: ProviderConnectionKind,
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

    const ALL_CONNECTIONS: [ProviderConnectionKind; 6] = [
        ProviderConnectionKind::OpenAiPlatform,
        ProviderConnectionKind::CodexPlan,
        ProviderConnectionKind::AnthropicPlatform,
        ProviderConnectionKind::ClaudePlan,
        ProviderConnectionKind::CursorPlan,
        ProviderConnectionKind::CursorPlatform,
    ];

    #[test]
    fn documents_per_connection_floors() {
        assert_eq!(
            guidance(ProviderConnectionKind::OpenAiPlatform).min_interval,
            OPENAI_PLATFORM_MIN_POLL
        );
        assert_eq!(
            guidance(ProviderConnectionKind::CodexPlan).min_interval,
            CODEX_PLAN_MIN_POLL
        );
        assert_eq!(
            guidance(ProviderConnectionKind::AnthropicPlatform).min_interval,
            ANTHROPIC_PLATFORM_MIN_POLL
        );
        assert_eq!(
            guidance(ProviderConnectionKind::ClaudePlan).min_interval,
            CLAUDE_PLAN_MIN_POLL
        );
        assert_eq!(
            guidance(ProviderConnectionKind::CursorPlan).min_interval,
            CURSOR_PLAN_MIN_POLL
        );
        assert_eq!(
            guidance(ProviderConnectionKind::CursorPlatform).min_interval,
            CURSOR_PLATFORM_MIN_POLL
        );
    }

    #[test]
    fn surfaces_cursor_freshness_without_clamping() {
        let plan = guidance(ProviderConnectionKind::CursorPlan);
        assert_eq!(plan.freshness_note, Some(CURSOR_USAGE_FRESHNESS_NOTE));
        assert_eq!(plan.min_interval, CURSOR_PLAN_MIN_POLL);
        assert!(plan.min_interval < Duration::from_secs(60 * 60));
    }

    #[test]
    fn clamps_user_setting_to_connection_floor() {
        let under = Duration::from_secs(60);
        assert_eq!(
            effective_interval(under, ProviderConnectionKind::OpenAiPlatform),
            OPENAI_PLATFORM_MIN_POLL
        );
        let over = Duration::from_secs(15 * 60);
        assert_eq!(
            effective_interval(over, ProviderConnectionKind::OpenAiPlatform),
            over
        );
        assert_eq!(
            effective_interval(under, ProviderConnectionKind::AnthropicPlatform),
            ANTHROPIC_PLATFORM_MIN_POLL
        );
    }

    #[test]
    fn global_slider_lower_bound_satisfies_every_floor() {
        for connection in ALL_CONNECTIONS {
            assert_eq!(
                effective_interval(GLOBAL_REFRESH_MIN, connection),
                GLOBAL_REFRESH_MIN,
                "{connection:?} floor exceeds the global slider minimum"
            );
        }
        assert_eq!(GLOBAL_REFRESH_MAX, Duration::from_secs(60 * 60));
    }
}
