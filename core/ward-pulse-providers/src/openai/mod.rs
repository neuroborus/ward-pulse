use crate::{BucketCapabilities, ProviderCapabilities};

pub const PROVIDER_NAME: &str = "OpenAI";

pub(crate) const CAPABILITIES: ProviderCapabilities = ProviderCapabilities {
    supports_cost: true,
    supports_tokens: true,
    supports_requests: true,
    supports_credits: false,
    usage_buckets: BucketCapabilities::DAILY_AND_HOURLY,
    cost_buckets: BucketCapabilities::DAILY,
    supports_usage_model_breakdown: true,
    supports_cost_model_breakdown: false,
    supports_workspace_breakdown: false,
    supports_active_agents: false,
};
