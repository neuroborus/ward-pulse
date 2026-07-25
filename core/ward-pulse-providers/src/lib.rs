mod allowance;
pub mod claude;
pub mod codex;
pub mod cursor;
pub mod mock;
pub mod openai;
pub mod poll;

use ward_pulse_core::model::ProviderKind;

pub use mock::mock_provider_snapshot;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct BucketCapabilities {
    pub daily: bool,
    pub hourly: bool,
}

impl BucketCapabilities {
    pub const NONE: Self = Self {
        daily: false,
        hourly: false,
    };
    pub const DAILY: Self = Self {
        daily: true,
        hourly: false,
    };
    pub const DAILY_AND_HOURLY: Self = Self {
        daily: true,
        hourly: true,
    };
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ProviderCapabilities {
    pub supports_cost: bool,
    pub supports_tokens: bool,
    pub supports_requests: bool,
    pub supports_credits: bool,
    pub usage_buckets: BucketCapabilities,
    pub cost_buckets: BucketCapabilities,
    pub supports_usage_model_breakdown: bool,
    pub supports_cost_model_breakdown: bool,
    pub supports_workspace_breakdown: bool,
    pub supports_active_agents: bool,
}

pub const fn provider_capabilities(provider: ProviderKind) -> ProviderCapabilities {
    match provider {
        ProviderKind::OpenAi => openai::CAPABILITIES,
        ProviderKind::Codex => codex::CAPABILITIES,
        ProviderKind::Claude => claude::CAPABILITIES,
        ProviderKind::Cursor => cursor::CAPABILITIES,
        ProviderKind::Mock => mock::CAPABILITIES,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn distinguishes_usage_and_cost_reporting() {
        let openai = provider_capabilities(ProviderKind::OpenAi);
        assert_eq!(
            (openai.usage_buckets, openai.cost_buckets),
            (
                BucketCapabilities::DAILY_AND_HOURLY,
                BucketCapabilities::DAILY,
            )
        );
        assert!(openai.supports_usage_model_breakdown);
        assert!(!openai.supports_cost_model_breakdown);

        let mock = provider_capabilities(ProviderKind::Mock);
        assert_eq!(
            (mock.usage_buckets, mock.cost_buckets),
            (BucketCapabilities::NONE, BucketCapabilities::NONE)
        );

        let codex = provider_capabilities(ProviderKind::Codex);
        assert_eq!(codex.usage_buckets, BucketCapabilities::DAILY);
        assert!(codex.supports_tokens);
        assert!(codex.supports_credits);
    }

    #[test]
    fn registers_claude_and_cursor_capabilities() {
        let claude = provider_capabilities(ProviderKind::Claude);
        assert!(claude.supports_cost);
        assert!(claude.supports_credits);
        assert_eq!(claude.usage_buckets, BucketCapabilities::DAILY_AND_HOURLY);

        let cursor = provider_capabilities(ProviderKind::Cursor);
        assert!(cursor.supports_cost);
        assert!(cursor.supports_requests);
        assert_eq!(cursor.usage_buckets, BucketCapabilities::DAILY);
    }
}
