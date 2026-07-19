use crate::alerts::alerts_for_budget_state;
use crate::budget::calculate_budget_state;
use crate::model::{
    BudgetPeriod, BudgetState, DashboardSnapshot, Money, ProviderSnapshot, ProviderStatus,
    WatchSummary,
};
use crate::time::DateTimeUtc;

pub fn build_dashboard_snapshot(
    generated_at: DateTimeUtc,
    accounts: Vec<ProviderSnapshot>,
) -> DashboardSnapshot {
    let today_total = total_state(
        BudgetPeriod::Today,
        accounts.iter().map(|account| &account.today),
    );
    let week_total = total_state(
        BudgetPeriod::Week,
        accounts.iter().map(|account| &account.week),
    );
    let month_total = total_state(
        BudgetPeriod::Month,
        accounts.iter().map(|account| &account.month),
    );
    let overall_status = accounts
        .iter()
        .map(|account| account.status)
        .chain([today_total.status, week_total.status, month_total.status])
        .fold(ProviderStatus::Ok, worst_status);

    let mut alerts = Vec::new();
    alerts.extend(alerts_for_budget_state("Today", &today_total));
    alerts.extend(alerts_for_budget_state("Week", &week_total));
    alerts.extend(alerts_for_budget_state("Month", &month_total));

    let watch_summary = WatchSummary {
        today_used_percent: today_total.used_percent,
        week_used_percent: week_total.used_percent,
        status: overall_status,
    };

    DashboardSnapshot {
        generated_at,
        overall_status,
        accounts,
        today_total,
        week_total,
        month_total,
        alerts,
        watch_summary,
    }
}

fn total_state<'a>(
    period: BudgetPeriod,
    states: impl Iterator<Item = &'a BudgetState>,
) -> BudgetState {
    let mut spent = MoneyTotal::default();
    let mut limit = MoneyTotal::default();
    let mut projected_total = MoneyTotal::default();

    for state in states {
        if let Some(value) = &state.spent {
            spent.add(value);
        }
        if let Some(value) = &state.limit {
            limit.add(value);
        }
        if let Some(value) = &state.projected_total {
            projected_total.add(value);
        }
    }

    calculate_budget_state(
        period,
        spent.into_option(),
        limit.into_option(),
        projected_total.into_option(),
    )
}

#[derive(Default)]
enum MoneyTotal {
    #[default]
    Empty,
    Sum(Money),
    MixedCurrencies,
}

impl MoneyTotal {
    fn add(&mut self, next: &Money) {
        match self {
            Self::Empty => *self = Self::Sum(next.clone()),
            Self::Sum(total) if total.currency == next.currency => {
                total.minor_units += next.minor_units;
            }
            Self::Sum(_) | Self::MixedCurrencies => *self = Self::MixedCurrencies,
        }
    }

    fn into_option(self) -> Option<Money> {
        match self {
            Self::Sum(total) => Some(total),
            Self::Empty | Self::MixedCurrencies => None,
        }
    }
}

fn worst_status(left: ProviderStatus, right: ProviderStatus) -> ProviderStatus {
    if status_rank(&right) > status_rank(&left) {
        right
    } else {
        left
    }
}

fn status_rank(status: &ProviderStatus) -> u8 {
    match status {
        ProviderStatus::Ok => 1,
        ProviderStatus::Unknown => 2,
        ProviderStatus::Stale => 3,
        ProviderStatus::Warning => 4,
        ProviderStatus::RateLimited => 5,
        ProviderStatus::AuthRequired => 6,
        ProviderStatus::Error => 7,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn usd(cents: i64) -> Money {
        Money::minor_units(cents, "USD")
    }

    fn eur(cents: i64) -> Money {
        Money::minor_units(cents, "EUR")
    }

    fn budget_state(period: BudgetPeriod, spent: Money, limit: Money) -> BudgetState {
        calculate_budget_state(period, Some(spent), Some(limit), None)
    }

    fn provider_snapshot(account_id: &str, today: BudgetState) -> ProviderSnapshot {
        ProviderSnapshot {
            account_id: account_id.to_string(),
            provider: crate::model::ProviderKind::Mock,
            status: ProviderStatus::Ok,
            today,
            week: budget_state(BudgetPeriod::Week, usd(0), usd(100)),
            month: budget_state(BudgetPeriod::Month, usd(0), usd(100)),
            credits: Vec::new(),
            allowances: Vec::new(),
            buckets: Vec::new(),
            model_breakdown: Vec::new(),
            last_successful_sync_at: None,
            last_error: None,
        }
    }

    #[test]
    fn sums_totals_when_currency_matches() {
        let snapshot = build_dashboard_snapshot(
            DateTimeUtc::from("2026-06-27T18:42:00Z"),
            vec![
                provider_snapshot("a", budget_state(BudgetPeriod::Today, usd(100), usd(1_000))),
                provider_snapshot("b", budget_state(BudgetPeriod::Today, usd(200), usd(1_000))),
            ],
        );

        assert_eq!(snapshot.today_total.spent, Some(usd(300)));
        assert_eq!(snapshot.today_total.limit, Some(usd(2_000)));
        assert_eq!(snapshot.today_total.used_percent, Some(15.0));
    }

    #[test]
    fn omits_total_when_currencies_are_mixed() {
        let snapshot = build_dashboard_snapshot(
            DateTimeUtc::from("2026-06-27T18:42:00Z"),
            vec![
                provider_snapshot("a", budget_state(BudgetPeriod::Today, usd(100), usd(1_000))),
                provider_snapshot("b", budget_state(BudgetPeriod::Today, eur(200), eur(1_000))),
            ],
        );

        assert_eq!(snapshot.today_total.spent, None);
        assert_eq!(snapshot.today_total.limit, None);
        assert_eq!(snapshot.today_total.used_percent, None);
        assert_eq!(snapshot.today_total.status, ProviderStatus::Unknown);
    }
}
