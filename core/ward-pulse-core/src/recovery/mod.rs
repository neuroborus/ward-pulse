//! Plan windows coming back: the one edge worth interrupting a user for.
//!
//! An exhausted plan window is the state a user is actively waiting to leave, so
//! leaving it is news. It is an edge, not a condition: it happens once, has no
//! steady state, and nothing about it is configurable. Alerts stay what they
//! are — thresholds that hold while they hold — and recoveries never join them.
//!
//! An edge needs a past, and the phone is what remembers it across a process
//! that does not survive between polls. It stores [`PendingRecovery`] entries,
//! keeping each [`WindowKey`] and its known constraints rather than a whole
//! snapshot. The shell never decides what "exhausted" means.

use serde::{Deserialize, Serialize};

use crate::model::{
    deserialize_recovery_requirements, AccountId, AllowanceSource, AllowanceState,
    DashboardSnapshot, HistoryOwner, ProviderKind, RecoveryRequirements,
};
use crate::time::DateTimeUtc;

/// One plan window, named the only way it is unique: allowance ids repeat
/// across accounts and accepted connection owners.
#[derive(Clone, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WindowKey {
    pub account_id: AccountId,
    pub allowance_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub history_owner: Option<HistoryOwner>,
}

/// Persisted target identity and its known necessary constraints. The flattened
/// key keeps storage compatible with records written before applicability existed.
#[derive(Clone, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PendingRecovery {
    #[serde(flatten)]
    pub key: WindowKey,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "deserialize_recovery_requirements"
    )]
    pub requirements: Option<RecoveryRequirements>,
}

#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RecoveryReconciliation {
    pub pending: Vec<PendingRecovery>,
    pub recoveries: Vec<PlanRecovery>,
}

/// Reconcile the phone's history in one deterministic operation. This staged
/// boundary still uses per-window eligibility; applicable-capacity evaluation
/// is activated separately without changing this API or its wire types.
pub fn reconcile_plan_recoveries(
    snapshot: &DashboardSnapshot,
    pending: &[PendingRecovery],
) -> RecoveryReconciliation {
    let mut remembered: Vec<PendingRecovery> = Vec::new();
    for entry in pending {
        if let Some(existing) = remembered.iter_mut().find(|item| item.key == entry.key) {
            existing.requirements =
                merge_requirements(existing.requirements.as_ref(), entry.requirements.as_ref());
        } else {
            remembered.push(entry.clone());
        }
    }
    for key in exhausted_windows(snapshot) {
        if !remembered.iter().any(|entry| entry.key == key) {
            remembered.push(PendingRecovery {
                key,
                requirements: None,
            });
        }
    }
    for entry in &mut remembered {
        let current = snapshot
            .accounts
            .iter()
            .find(|account| {
                account.account_id == entry.key.account_id
                    && account.history_owner == entry.key.history_owner
            })
            .and_then(|account| {
                account
                    .allowances
                    .iter()
                    .find(|allowance| allowance.id == entry.key.allowance_id)
            })
            .and_then(|allowance| allowance.recovery_requirements.as_ref());
        entry.requirements = merge_requirements(entry.requirements.as_ref(), current);
        if let Some(requirements) = &mut entry.requirements {
            if !requirements.allowance_ids.contains(&entry.key.allowance_id) {
                requirements.complete = false;
            }
        }
    }
    let keys: Vec<_> = pending.iter().map(|entry| entry.key.clone()).collect();
    let mut recoveries = plan_recoveries(&keys, snapshot);
    let mut delivered = Vec::new();
    recoveries.retain(|recovery| {
        let key = WindowKey {
            account_id: recovery.account_id.clone(),
            history_owner: recovery.history_owner.clone(),
            allowance_id: recovery.allowance_id.clone(),
        };
        if delivered.contains(&key) {
            return false;
        }
        delivered.push(key);
        true
    });
    remembered.retain(|entry| {
        !recoveries.iter().any(|recovery| {
            recovery.account_id == entry.key.account_id
                && recovery.history_owner == entry.key.history_owner
                && recovery.allowance_id == entry.key.allowance_id
        })
    });
    RecoveryReconciliation {
        pending: remembered,
        recoveries,
    }
}

fn merge_requirements(
    saved: Option<&RecoveryRequirements>,
    current: Option<&RecoveryRequirements>,
) -> Option<RecoveryRequirements> {
    let mut ids = Vec::new();
    for id in saved
        .into_iter()
        .chain(current)
        .flat_map(|requirements| &requirements.allowance_ids)
    {
        if !ids.contains(id) {
            ids.push(id.clone());
        }
    }
    if ids.is_empty() {
        return None;
    }
    // A current complete scope cannot retire previously necessary constraints.
    Some(RecoveryRequirements {
        allowance_ids: ids,
        complete: current.is_some_and(|requirements| requirements.complete),
    })
}

/// A plan window that was exhausted and has room again.
///
/// Carries delivery identity and timing, including private history ownership:
/// no money, raw provider fields or credentials.
#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PlanRecovery {
    pub account_id: AccountId,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub history_owner: Option<HistoryOwner>,
    /// Which family the window belongs to. Two subscriptions can both call a
    /// window "Weekly plan", so the family is what tells a reader which one is
    /// back.
    pub provider: ProviderKind,
    pub allowance_id: String,
    pub label: String,
    /// When the window is next expected to roll, as the new snapshot reports it.
    pub resets_at: Option<DateTimeUtc>,
}

/// Plan windows with nothing left in them — what to remember until the next poll.
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
                    history_owner: account.history_owner.clone(),
                })
        })
        .collect()
}

/// Plan windows from `exhausted` that the new snapshot reports usable again.
///
/// Purchased allowances stay silent even when their keys are remembered.
/// A window the snapshot no longer reports stays silent: a disconnected
/// provider has not recovered, it has stopped saying anything.
pub fn plan_recoveries(exhausted: &[WindowKey], next: &DashboardSnapshot) -> Vec<PlanRecovery> {
    let mut recoveries = Vec::new();
    for account in &next.accounts {
        for allowance in &account.allowances {
            let was_exhausted = exhausted.iter().any(|key| {
                key.account_id == account.account_id
                    && key.allowance_id == allowance.id
                    && key.history_owner == account.history_owner
            });
            if was_exhausted && has_room(allowance) {
                recoveries.push(PlanRecovery {
                    account_id: account.account_id.clone(),
                    history_owner: account.history_owner.clone(),
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

/// A plan window with nothing left. An unlimited window can never be here, and one
/// reporting no percentage says nothing either way.
fn is_exhausted(allowance: &AllowanceState) -> bool {
    allowance.source == AllowanceSource::Plan
        && !allowance.unlimited
        && allowance
            .used_percent
            .is_some_and(|percent| percent >= 100.0)
}

/// A plan window a user can spend against again.
fn has_room(allowance: &AllowanceState) -> bool {
    allowance.source == AllowanceSource::Plan
        && (allowance.unlimited
            || allowance
                .used_percent
                .is_some_and(|percent| percent < 100.0))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{
        AllowanceSource, BudgetPeriod, ProviderKind, ProviderSnapshot, ProviderStatus,
    };

    fn allowance(id: &str, used_percent: Option<f64>) -> AllowanceState {
        AllowanceState {
            recovery_requirements: None,
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
            history_owner: None,
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
            history_owner: None,
        }
    }

    #[test]
    fn reconciliation_remembers_context_and_keeps_staged_per_window_eligibility() {
        let mut session = allowance("session", Some(100.0));
        session.recovery_requirements = Some(RecoveryRequirements {
            allowance_ids: vec!["session".into(), "weekly".into()],
            complete: true,
        });
        let initial = snapshot(vec![account(
            "claude",
            vec![session.clone(), allowance("weekly", None)],
        )]);
        let result = reconcile_plan_recoveries(&initial, &[]);
        assert!(result.recoveries.is_empty());
        assert_eq!(
            result.pending[0].requirements,
            session.recovery_requirements
        );
        let mut omitted = initial.clone();
        omitted.accounts[0].allowances.clear();
        let retained = reconcile_plan_recoveries(&omitted, &result.pending);
        assert_eq!(
            retained.pending[0]
                .requirements
                .as_ref()
                .unwrap()
                .allowance_ids,
            ["session", "weekly"]
        );
        assert!(!retained.pending[0].requirements.as_ref().unwrap().complete);
        let mut singleton = initial.clone();
        singleton.accounts[0].allowances.truncate(1);
        singleton.accounts[0].allowances[0].recovery_requirements = Some(RecoveryRequirements {
            allowance_ids: vec!["session".into()],
            complete: true,
        });
        let singleton = reconcile_plan_recoveries(&singleton, &retained.pending);
        assert_eq!(
            singleton.pending[0]
                .requirements
                .as_ref()
                .unwrap()
                .allowance_ids,
            ["session", "weekly"]
        );

        // Commit 1 deliberately still permits the premature own-window edge.
        // Its production module is the API-compatible OLD for policy activation.
        session.used_percent = Some(0.0);
        let room = snapshot(vec![account(
            "claude",
            vec![session, allowance("weekly", Some(100.0))],
        )]);
        let next = reconcile_plan_recoveries(&room, &retained.pending);
        assert_eq!(next.recoveries.len(), 1);
        assert_eq!(next.recoveries[0].allowance_id, "session");
        assert_eq!(next.pending[0].key.allowance_id, "weekly");
    }

    #[test]
    fn pending_wire_context_is_optional_and_never_loses_a_valid_key() {
        let legacy = serde_json::json!({"accountId":"a", "allowanceId":"session"});
        for value in [
            serde_json::Value::Null,
            serde_json::json!({"complete":true}),
            serde_json::json!({"allowanceIds":[1],"complete":true}),
        ] {
            let mut entry = legacy.clone();
            entry["requirements"] = value;
            let pending: PendingRecovery = serde_json::from_value(entry).unwrap();
            assert_eq!(pending.key, key("a", "session"));
            assert!(pending.requirements.is_none());
        }
        let pending: PendingRecovery = serde_json::from_value(legacy).unwrap();
        let mut owned = pending;
        owned.key.history_owner = Some(HistoryOwner {
            connection: "connection-a".into(),
            identity: "a".repeat(64),
        });
        owned.requirements = Some(RecoveryRequirements {
            allowance_ids: vec!["session".into(), "weekly".into()],
            complete: false,
        });
        let encoded = serde_json::to_string(&owned).unwrap();
        assert_eq!(
            serde_json::from_str::<PendingRecovery>(&encoded).unwrap(),
            owned
        );
        let snap = snapshot(vec![account("a", vec![allowance("session", None)])]);
        let result = reconcile_plan_recoveries(&snap, &[owned.clone(), owned.clone()]);
        assert_eq!(result.pending.len(), 1);
        assert_eq!(result.pending[0], owned);
        assert!(result.recoveries.is_empty());
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
    fn only_exhausted_plan_windows_are_remembered() {
        let mut purchased = allowance("extra", Some(100.0));
        purchased.source = AllowanceSource::Purchased;
        let snapshot = snapshot(vec![account(
            "claude",
            vec![allowance("weekly", Some(100.0)), purchased],
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
    fn recovery_history_requires_the_same_accepted_owner() {
        let owner = HistoryOwner {
            connection: "connection-a".into(),
            identity: "a".repeat(64),
        };
        let mut previous = account("fixed-id", vec![allowance("weekly", Some(100.0))]);
        previous.history_owner = Some(owner.clone());
        let exhausted = exhausted_windows(&snapshot(vec![previous.clone()]));
        let mut next = previous;
        next.allowances[0].used_percent = Some(20.0);

        let recoveries = plan_recoveries(&exhausted, &snapshot(vec![next.clone()]));
        assert_eq!(recoveries.len(), 1);
        assert_eq!(recoveries[0].history_owner, Some(owner.clone()));
        assert_eq!(exhausted[0].history_owner, Some(owner.clone()));

        for other in [
            None,
            Some(HistoryOwner {
                identity: "b".repeat(64),
                ..owner.clone()
            }),
            Some(HistoryOwner {
                connection: "connection-b".into(),
                ..owner.clone()
            }),
        ] {
            next.history_owner = other;
            assert!(plan_recoveries(&exhausted, &snapshot(vec![next.clone()])).is_empty());
        }

        // Legacy history stays unbound rather than being adopted on first sync.
        next.history_owner = Some(owner);
        assert!(plan_recoveries(&[key("fixed-id", "weekly")], &snapshot(vec![next])).is_empty());
    }

    #[test]
    fn remembered_purchased_windows_do_not_recover_after_reset() {
        let mut plan = allowance("weekly", Some(0.0));
        plan.label = "Weekly plan".to_string();
        plan.resets_at = Some(DateTimeUtc::new("2026-08-23T12:00:00Z"));
        let mut purchased = allowance("extra", Some(0.0));
        purchased.source = AllowanceSource::Purchased;
        purchased.resets_at = Some(DateTimeUtc::new("2026-09-16T12:00:00Z"));
        let next = snapshot(vec![account("claude", vec![plan, purchased])]);

        assert_eq!(
            plan_recoveries(&[key("claude", "weekly"), key("claude", "extra")], &next),
            vec![PlanRecovery {
                account_id: "claude".to_string(),
                history_owner: None,
                provider: ProviderKind::Claude,
                allowance_id: "weekly".to_string(),
                label: "Weekly plan".to_string(),
                resets_at: Some(DateTimeUtc::new("2026-08-23T12:00:00Z")),
            }]
        );
    }

    #[test]
    fn a_remembered_unlimited_plan_window_recovers_without_a_percentage() {
        let mut unlimited = allowance("weekly", None);
        unlimited.unlimited = true;
        let next = snapshot(vec![account("claude", vec![unlimited])]);

        let recoveries = plan_recoveries(&[key("claude", "weekly")], &next);

        assert_eq!(recoveries.len(), 1);
        assert_eq!(recoveries[0].allowance_id, "weekly");
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
