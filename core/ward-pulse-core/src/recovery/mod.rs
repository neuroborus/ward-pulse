//! Plan windows coming back: the one edge worth interrupting a user for.
//!
//! An exhausted plan window is the state a user is actively waiting to leave, so
//! leaving it is news. It is an edge, not a condition: it happens once, has no
//! steady state, and nothing about it is configurable. Alerts stay what they
//! are — thresholds that hold while they hold — and recoveries never join them.
//!
//! An edge needs a past, and the phone is what remembers it across a process
//! that does not survive between polls. It stores [`WindowKey`]s rather than a
//! whole snapshot — that keeps the rule here, in one place, instead of teaching
//! a shell what "exhausted" means.

use serde::{Deserialize, Serialize};

use crate::model::{AccountId, AllowanceState, DashboardSnapshot, ProviderKind};
use crate::time::DateTimeUtc;

/// One plan window, named the only way it is unique: allowance ids repeat
/// across accounts, so an account has to carry its own.
#[derive(Clone, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WindowKey {
    pub account_id: AccountId,
    pub allowance_id: String,
}

/// A window that was exhausted and has room again.
///
/// Carries only what delivery needs to name and time the notification: no
/// money, no raw provider fields, no credentials.
#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PlanRecovery {
    pub account_id: AccountId,
    /// Which family the window belongs to. Two subscriptions can both call a
    /// window "Weekly plan", so the family is what tells a reader which one is
    /// back.
    pub provider: ProviderKind,
    pub allowance_id: String,
    pub label: String,
    /// When the window is next expected to roll, as the new snapshot reports it.
    pub resets_at: Option<DateTimeUtc>,
}

/// Windows with nothing left in them — what to remember until the next poll.
pub fn exhausted_windows(snapshot: &DashboardSnapshot) -> Vec<WindowKey> {
    snapshot
        .accounts
        .iter()
        .flat_map(|account| {
            account
                .allowances
                .iter()
                .filter(|allowance| is_exhausted(allowance))
                .map(|allowance| WindowKey {
                    account_id: account.account_id.clone(),
                    allowance_id: allowance.id.clone(),
                })
        })
        .collect()
}

/// Windows from `exhausted` that the new snapshot reports usable again.
///
/// A window the snapshot no longer reports stays silent: a disconnected
/// provider has not recovered, it has stopped saying anything.
pub fn plan_recoveries(exhausted: &[WindowKey], next: &DashboardSnapshot) -> Vec<PlanRecovery> {
    let mut recoveries = Vec::new();
    for account in &next.accounts {
        for allowance in &account.allowances {
            let was_exhausted = exhausted.iter().any(|key| {
                key.account_id == account.account_id && key.allowance_id == allowance.id
            });
            if was_exhausted && has_room(allowance) {
                recoveries.push(PlanRecovery {
                    account_id: account.account_id.clone(),
                    provider: account.provider,
                    allowance_id: allowance.id.clone(),
                    label: allowance.label.clone(),
                    resets_at: allowance.resets_at.clone(),
                });
            }
        }
    }
    recoveries
}

/// A window with nothing left. An unlimited window can never be here, and one
/// reporting no percentage says nothing either way.
fn is_exhausted(allowance: &AllowanceState) -> bool {
    !allowance.unlimited
        && allowance
            .used_percent
            .is_some_and(|percent| percent >= 100.0)
}

/// A window a user can spend against again.
fn has_room(allowance: &AllowanceState) -> bool {
    allowance.unlimited
        || allowance
            .used_percent
            .is_some_and(|percent| percent < 100.0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{
        AllowanceSource, BudgetPeriod, ProviderKind, ProviderSnapshot, ProviderStatus,
    };

    fn allowance(id: &str, used_percent: Option<f64>) -> AllowanceState {
        AllowanceState {
            id: id.to_string(),
            source: AllowanceSource::Plan,
            label: format!("{id} window"),
            used_percent,
            used: None,
            limit: None,
            remaining: None,
            unlimited: false,
            window_minutes: None,
            resets_at: Some(DateTimeUtc::new("2026-08-16T12:00:00Z")),
            status: ProviderStatus::Ok,
        }
    }

    fn account(id: &str, allowances: Vec<AllowanceState>) -> ProviderSnapshot {
        let budget = |period| crate::budget::calculate_budget_state(period, None, None, None);
        ProviderSnapshot {
            account_id: id.to_string(),
            provider: ProviderKind::Claude,
            connection: None,
            status: ProviderStatus::Ok,
            today: budget(BudgetPeriod::Today),
            week: budget(BudgetPeriod::Week),
            month: budget(BudgetPeriod::Month),
            credits: Vec::new(),
            allowances,
            buckets: Vec::new(),
            model_breakdown: Vec::new(),
            last_successful_sync_at: None,
            last_error: None,
        }
    }

    fn snapshot(accounts: Vec<ProviderSnapshot>) -> DashboardSnapshot {
        crate::dashboard::build_dashboard_snapshot(
            DateTimeUtc::new("2026-08-16T12:00:00Z"),
            accounts,
        )
    }

    fn key(account_id: &str, allowance_id: &str) -> WindowKey {
        WindowKey {
            account_id: account_id.to_string(),
            allowance_id: allowance_id.to_string(),
        }
    }

    #[test]
    fn only_spent_windows_are_worth_remembering() {
        let mut unlimited = allowance("burst", Some(100.0));
        unlimited.unlimited = true;
        let snapshot = snapshot(vec![account(
            "claude",
            vec![
                allowance("weekly", Some(100.0)),
                allowance("session", Some(40.0)),
                allowance("opus", None),
                unlimited,
            ],
        )]);

        assert_eq!(exhausted_windows(&snapshot), vec![key("claude", "weekly")]);
    }

    #[test]
    fn windows_of_two_accounts_keep_their_own_names() {
        let snapshot = snapshot(vec![
            account("claude", vec![allowance("weekly", Some(100.0))]),
            account("codex", vec![allowance("weekly", Some(100.0))]),
        ]);

        assert_eq!(
            exhausted_windows(&snapshot),
            vec![key("claude", "weekly"), key("codex", "weekly")]
        );
    }

    #[test]
    fn a_remembered_window_with_room_again_is_a_recovery() {
        let next = snapshot(vec![account(
            "claude",
            vec![allowance("weekly", Some(4.0))],
        )]);

        let recoveries = plan_recoveries(&[key("claude", "weekly")], &next);

        assert_eq!(recoveries.len(), 1);
        assert_eq!(recoveries[0].account_id, "claude");
        assert_eq!(recoveries[0].provider, ProviderKind::Claude);
        assert_eq!(recoveries[0].allowance_id, "weekly");
        assert_eq!(
            recoveries[0].resets_at,
            Some(DateTimeUtc::new("2026-08-16T12:00:00Z"))
        );
    }

    #[test]
    fn a_window_nobody_remembered_is_not_news() {
        let next = snapshot(vec![account(
            "claude",
            vec![allowance("weekly", Some(0.0))],
        )]);

        assert!(plan_recoveries(&[], &next).is_empty());
    }

    #[test]
    fn a_window_that_is_still_exhausted_waits() {
        let next = snapshot(vec![account(
            "claude",
            vec![allowance("weekly", Some(100.0))],
        )]);

        assert!(plan_recoveries(&[key("claude", "weekly")], &next).is_empty());
    }

    #[test]
    fn a_disconnected_account_reports_nothing() {
        let next = snapshot(Vec::new());

        assert!(plan_recoveries(&[key("claude", "weekly")], &next).is_empty());
    }

    #[test]
    fn a_key_does_not_reach_across_accounts() {
        let next = snapshot(vec![account("codex", vec![allowance("weekly", Some(4.0))])]);

        assert!(plan_recoveries(&[key("claude", "weekly")], &next).is_empty());
    }

    #[test]
    fn a_window_that_stopped_reporting_a_percentage_is_no_edge() {
        let next = snapshot(vec![account("claude", vec![allowance("weekly", None)])]);

        assert!(plan_recoveries(&[key("claude", "weekly")], &next).is_empty());
    }
}
