pub mod claude;
pub mod cursor;
pub mod mock;
pub mod openai;

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

pub const fn provider_capabilities(provider: ProviderKind) -> Option<ProviderCapabilities> {
    match provider {
        ProviderKind::OpenAi => Some(openai::CAPABILITIES),
        ProviderKind::Mock => Some(mock::CAPABILITIES),
        ProviderKind::Claude | ProviderKind::Cursor => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn distinguishes_usage_and_cost_reporting() {
        let openai = provider_capabilities(ProviderKind::OpenAi).expect("OpenAI capabilities");
        assert_eq!(
            (openai.usage_buckets, openai.cost_buckets),
            (
                BucketCapabilities::DAILY_AND_HOURLY,
                BucketCapabilities::DAILY,
            )
        );
        assert!(openai.supports_usage_model_breakdown);
        assert!(!openai.supports_cost_model_breakdown);

        let mock = provider_capabilities(ProviderKind::Mock).expect("mock capabilities");
        assert_eq!(
            (mock.usage_buckets, mock.cost_buckets),
            (BucketCapabilities::NONE, BucketCapabilities::NONE)
        );
    }

    #[test]
    fn leaves_unimplemented_provider_capabilities_unknown() {
        assert_eq!(provider_capabilities(ProviderKind::Claude), None);
        assert_eq!(provider_capabilities(ProviderKind::Cursor), None);
    }
}
