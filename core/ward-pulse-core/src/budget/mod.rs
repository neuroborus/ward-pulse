use crate::model::{BudgetPeriod, BudgetState, Money, ProviderStatus};

pub const DEFAULT_BUDGET_WARN_AT_PERCENT: u8 = 80;

pub fn calculate_budget_state(
    period: BudgetPeriod,
    spent: Option<Money>,
    limit: Option<Money>,
    projected_total: Option<Money>,
) -> BudgetState {
    calculate_budget_state_with_warn_at(
        period,
        spent,
        limit,
        projected_total,
        DEFAULT_BUDGET_WARN_AT_PERCENT,
    )
}

pub fn calculate_budget_state_with_warn_at(
    period: BudgetPeriod,
    spent: Option<Money>,
    limit: Option<Money>,
    projected_total: Option<Money>,
    warn_at_percent: u8,
) -> BudgetState {
    let used_percent = match (&spent, &limit) {
        (Some(spent), Some(limit)) if limit.minor_units > 0 => {
            Some((spent.minor_units as f64 / limit.minor_units as f64) * 100.0)
        }
        _ => None,
    };

    let remaining = match (&spent, &limit) {
        (Some(spent), Some(limit)) => Some(Money::minor_units(
            (limit.minor_units - spent.minor_units).max(0),
            limit.currency.clone(),
        )),
        _ => None,
    };

    let warn_at_percent = warn_at_percent.clamp(1, 100);
    let status = match used_percent {
        Some(percent) if percent >= 100.0 => ProviderStatus::Error,
        Some(percent) if percent >= f64::from(warn_at_percent) => ProviderStatus::Warning,
        Some(_) => ProviderStatus::Ok,
        None => ProviderStatus::Unknown,
    };

    BudgetState {
        period,
        spent,
        limit,
        remaining,
        used_percent,
        projected_total,
        status,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn usd(cents: i64) -> Money {
        Money::minor_units(cents, "USD")
    }

    #[test]
    fn calculates_budget_percentage_and_remaining() {
        let state = calculate_budget_state(
            BudgetPeriod::Today,
            Some(usd(1_250)),
            Some(usd(5_000)),
            None,
        );

        assert_eq!(state.used_percent, Some(25.0));
        assert_eq!(state.remaining, Some(usd(3_750)));
        assert_eq!(state.status, ProviderStatus::Ok);
    }

    #[test]
    fn marks_budget_warning_at_eighty_percent() {
        let state = calculate_budget_state(
            BudgetPeriod::Week,
            Some(usd(8_000)),
            Some(usd(10_000)),
            None,
        );

        assert_eq!(state.status, ProviderStatus::Warning);
    }

    #[test]
    fn supports_custom_warning_thresholds() {
        let state = calculate_budget_state_with_warn_at(
            BudgetPeriod::Month,
            Some(usd(7_500)),
            Some(usd(10_000)),
            None,
            70,
        );

        assert_eq!(state.used_percent, Some(75.0));
        assert_eq!(state.status, ProviderStatus::Warning);
    }

    #[test]
    fn clamps_zero_warning_threshold_to_one_percent() {
        let state = calculate_budget_state_with_warn_at(
            BudgetPeriod::Today,
            Some(usd(0)),
            Some(usd(10_000)),
            None,
            0,
        );

        assert_eq!(state.used_percent, Some(0.0));
        assert_eq!(state.status, ProviderStatus::Ok);
    }
}
