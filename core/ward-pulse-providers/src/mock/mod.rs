use ward_pulse_core::budget::calculate_budget_state;
use ward_pulse_core::model::{
    BudgetPeriod, ModelUsage, Money, ProviderKind, ProviderSnapshot, ProviderStatus, UsageBucket,
};

fn usd(cents: i64) -> Money {
    Money::minor_units(cents, "USD")
}

pub fn mock_provider_snapshot(account_id: impl Into<String>) -> ProviderSnapshot {
    ProviderSnapshot {
        account_id: account_id.into(),
        provider: ProviderKind::Mock,
        status: ProviderStatus::Ok,
        today: calculate_budget_state(
            BudgetPeriod::Today,
            Some(usd(1_240)),
            Some(usd(5_000)),
            None,
        ),
        week: calculate_budget_state(
            BudgetPeriod::Week,
            Some(usd(7_130)),
            Some(usd(25_000)),
            Some(usd(22_800)),
        ),
        month: calculate_budget_state(
            BudgetPeriod::Month,
            Some(usd(21_210)),
            Some(usd(80_000)),
            Some(usd(74_200)),
        ),
        credits: Vec::new(),
        buckets: vec![UsageBucket {
            start_at: "2026-06-27T00:00:00Z".into(),
            end_at: "2026-06-27T18:42:00Z".into(),
            cost: Some(usd(1_240)),
            input_tokens: Some(120_000),
            output_tokens: Some(42_000),
            cached_tokens: None,
            requests: Some(186),
            model: Some("mock-fast".to_string()),
            project: None,
            user: None,
        }],
        model_breakdown: vec![ModelUsage {
            model: "mock-fast".to_string(),
            cost: Some(usd(810)),
            input_tokens: Some(120_000),
            output_tokens: Some(42_000),
            requests: Some(186),
        }],
        last_successful_sync_at: Some("2026-06-27T18:42:00Z".into()),
        last_error: None,
    }
}
