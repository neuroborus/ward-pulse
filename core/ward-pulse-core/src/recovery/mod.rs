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
//! Recovery requires fresh usable included capacity across the target's complete
//! applicable scope, even after its own raw window resets.

use serde::{Deserialize, Serialize};

use crate::model::{
    deserialize_recovery_requirements, AccountId, AllowanceSource, AllowanceState,
    DashboardSnapshot, HistoryOwner, ProviderIdentity, ProviderSnapshot, ProviderStatus,
    RecoveryRequirements,
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

/// Reconcile history before evaluating fresh included capacity. A target stays
/// pending until all its known necessary Plan constraints are usable together.
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
            if !current.is_some_and(|scope| scope.allowance_ids.contains(&entry.key.allowance_id)) {
                requirements.complete = false;
            }
        }
    }
    let mut recoveries = Vec::new();
    for entry in &remembered {
        if !pending.iter().any(|previous| previous.key == entry.key) {
            continue;
        }
        let mut accounts = snapshot.accounts.iter().filter(|account| {
            account.account_id == entry.key.account_id
                && account.history_owner == entry.key.history_owner
        });
        let Some(account) = accounts.next() else {
            continue;
        };
        if accounts.next().is_some() || !applicable_capacity_is_usable(account, entry) {
            continue;
        }
        let allowance = account
            .allowances
            .iter()
            .find(|allowance| allowance.id == entry.key.allowance_id)
            .expect("complete requirements include the target");
        recoveries.push(PlanRecovery {
            account_id: account.account_id.clone(),
            history_owner: account.history_owner.clone(),
            provider: account.source.provider(),
            allowance_id: allowance.id.clone(),
            label: allowance.label.clone(),
            resets_at: allowance.resets_at.clone(),
        });
    }
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

fn applicable_capacity_is_usable(account: &ProviderSnapshot, entry: &PendingRecovery) -> bool {
    // Stale retained reports are not fresh evidence. Aggregate exhaustion or
    // Unknown from an unrelated meter does not veto a qualified target.
    if matches!(
        account.status,
        ProviderStatus::Stale | ProviderStatus::Error | ProviderStatus::AuthRequired
    ) {
        return false;
    }
    let Some(requirements) = &entry.requirements else {
        return false;
    };
    requirements.complete
        && requirements.allowance_ids.contains(&entry.key.allowance_id)
        && requirements.allowance_ids.iter().all(|id| {
            let mut matches = account
                .allowances
                .iter()
                .filter(|allowance| allowance.id == *id);
            matches.next().is_some_and(has_room) && matches.next().is_none()
        })
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
    // A narrowed current scope cannot qualify or retire remembered constraints.
    let complete = current.is_some_and(|requirements| {
        requirements.complete
            && !requirements.allowance_ids.is_empty()
            && ids.iter().all(|id| requirements.allowance_ids.contains(id))
            && requirements
                .allowance_ids
                .iter()
                .enumerate()
                .all(|(index, id)| {
                    !id.is_empty() && !requirements.allowance_ids[..index].contains(id)
                })
    });
    Some(RecoveryRequirements {
        allowance_ids: ids,
        complete,
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
    /// Display identity of the window. Two subscriptions can both call a
    /// window "Weekly plan", so its display label tells a reader which one is back.
    pub provider: ProviderIdentity,
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
/// Key-only callers use current applicability; contextual callers should use
/// [`reconcile_plan_recoveries`] to retain necessary constraints across reports.
pub fn plan_recoveries(exhausted: &[WindowKey], next: &DashboardSnapshot) -> Vec<PlanRecovery> {
    let pending: Vec<_> = exhausted
        .iter()
        .map(|key| PendingRecovery {
            key: key.clone(),
            requirements: None,
        })
        .collect();
    reconcile_plan_recoveries(next, &pending).recoveries
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
    if allowance.source != AllowanceSource::Plan
        || matches!(
            allowance.status,
            ProviderStatus::Stale | ProviderStatus::Error | ProviderStatus::AuthRequired
        )
    {
        return false;
    }
    // An explicit unlimited Plan report needs no usage percentage.
    allowance.unlimited
        || (matches!(
            allowance.status,
            ProviderStatus::Ok | ProviderStatus::Warning
        ) && allowance
            .used_percent
            .is_some_and(|percent| (0.0..100.0).contains(&percent)))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{AllowanceSource, BudgetPeriod, ProviderSnapshot, ProviderStatus};

    fn allowance(id: &str, used_percent: Option<f64>) -> AllowanceState {
        AllowanceState {
            recovery_requirements: Some(RecoveryRequirements {
                allowance_ids: vec![id.into()],
                complete: true,
            }),
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
            source: crate::model::ProviderSource::from_legacy(
                crate::model::ProviderKind::Claude,
                None,
            ),
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
    fn reconciliation_persists_new_constraints_until_capacity_recovers_after_reload() {
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
        assert!(!singleton.pending[0].requirements.as_ref().unwrap().complete);
        assert_eq!(
            singleton.pending[0]
                .requirements
                .as_ref()
                .unwrap()
                .allowance_ids,
            ["session", "weekly"]
        );

        // Own-window room must persist the newly observed exhausted dependency.
        session.used_percent = Some(0.0);
        let mut room = snapshot(vec![account(
            "claude",
            vec![session, allowance("weekly", Some(100.0))],
        )]);
        let next = reconcile_plan_recoveries(&room, &retained.pending);
        assert!(next.recoveries.is_empty());
        assert_eq!(next.pending.len(), 2);
        assert_eq!(next.pending[0].requirements, result.pending[0].requirements);
        let reloaded: Vec<PendingRecovery> =
            serde_json::from_str(&serde_json::to_string(&next.pending).unwrap()).unwrap();
        room.accounts[0].allowances[1].used_percent = Some(10.0);
        let recovered = reconcile_plan_recoveries(&room, &reloaded);
        assert_eq!(recovered.recoveries.len(), 2);
        assert!(recovered.pending.is_empty());
        assert!(reconcile_plan_recoveries(&room, &recovered.pending)
            .recoveries
            .is_empty());
        room.accounts[0].allowances[0].used_percent = Some(100.0);
        let rearmed = reconcile_plan_recoveries(&room, &[]);
        assert_eq!(rearmed.pending.len(), 1);
        room.accounts[0].allowances[0].used_percent = Some(10.0);
        assert_eq!(
            reconcile_plan_recoveries(&room, &rearmed.pending)
                .recoveries
                .len(),
            1
        );
    }

    #[test]
    fn only_necessary_fresh_valid_plan_capacity_can_clear_a_pending_target() {
        let mut target = allowance("session", Some(10.0));
        target.recovery_requirements = Some(RecoveryRequirements {
            allowance_ids: vec!["session".into(), "weekly".into()],
            complete: true,
        });
        let snap = snapshot(vec![account(
            "a",
            vec![target, allowance("weekly", Some(20.0))],
        )]);
        let pending = [PendingRecovery {
            key: key("a", "session"),
            requirements: Some(RecoveryRequirements {
                allowance_ids: vec!["session".into()],
                complete: false,
            }),
        }];
        let mut blocked = Vec::new();
        for percent in [None, Some(-1.0), Some(f64::NAN), Some(100.0)] {
            let mut value = snap.clone();
            value.accounts[0].allowances[1].used_percent = percent;
            blocked.push(value);
        }
        for status in [
            ProviderStatus::Unknown,
            ProviderStatus::Stale,
            ProviderStatus::Error,
        ] {
            let mut value = snap.clone();
            value.accounts[0].allowances[1].status = status;
            blocked.push(value);
        }
        let mut missing = snap.clone();
        missing.accounts[0].allowances.pop();
        blocked.push(missing);
        let mut purchased = snap.clone();
        purchased.accounts[0].allowances[1].source = AllowanceSource::Purchased;
        blocked.push(purchased);
        let mut stale = snap.clone();
        stale.accounts[0].status = ProviderStatus::Stale;
        blocked.push(stale);
        let mut unknown_scope = snap.clone();
        unknown_scope.accounts[0].allowances[0].recovery_requirements = None;
        blocked.push(unknown_scope);
        let mut malformed_scope = snap.clone();
        malformed_scope.accounts[0].allowances[0]
            .recovery_requirements
            .as_mut()
            .unwrap()
            .allowance_ids = vec!["weekly".into()];
        blocked.push(malformed_scope);
        for value in blocked {
            let result = reconcile_plan_recoveries(&value, &pending);
            assert!(result.recoveries.is_empty());
            assert!(result
                .pending
                .iter()
                .any(|entry| entry.key == pending[0].key));
            assert_eq!(
                reconcile_plan_recoveries(&snap, &result.pending).recoveries[0].allowance_id,
                "session"
            );
        }
        let mut unlimited = snap.clone();
        unlimited.accounts[0].allowances[1].unlimited = true;
        unlimited.accounts[0].allowances[1].used_percent = None;
        unlimited.accounts[0].allowances[1].status = ProviderStatus::Unknown;
        assert_eq!(
            reconcile_plan_recoveries(&unlimited, &pending)
                .recoveries
                .len(),
            1
        );
        // Aggregate Unknown and an unrelated exhausted meter are not global policy.
        let mut independent = snap;
        independent.accounts[0].status = ProviderStatus::Unknown;
        independent.accounts[0]
            .allowances
            .push(allowance("other", Some(100.0)));
        assert_eq!(
            reconcile_plan_recoveries(&independent, &pending)
                .recoveries
                .len(),
            1
        );
    }

    #[test]
    fn threshold_decoration_preserves_scoped_recovery_uncertainty() {
        let mut target = allowance("session", Some(10.0));
        target.recovery_requirements = Some(RecoveryRequirements {
            allowance_ids: vec!["session".into(), "weekly".into()],
            complete: true,
        });
        let fresh = snapshot(vec![account(
            "a",
            vec![target, allowance("weekly", Some(20.0))],
        )]);
        let pending = [PendingRecovery {
            key: key("a", "session"),
            requirements: None,
        }];
        let settings = serde_json::from_value(serde_json::json!({
            "connections": {"anthropic.plan": {"plan": {"at": 0}}}
        }))
        .unwrap();
        for (account_status, weekly_status) in [
            (ProviderStatus::Stale, ProviderStatus::Ok),
            (ProviderStatus::Ok, ProviderStatus::Stale),
            (ProviderStatus::Ok, ProviderStatus::Unknown),
        ] {
            let mut uncertain = fresh.clone();
            uncertain.accounts[0].status = account_status;
            uncertain.accounts[0].allowances[1].status = weekly_status;
            let applied = crate::apply_alert_settings(uncertain, &settings);
            assert_eq!(applied.accounts[0].status, ProviderStatus::Warning);
            let result = reconcile_plan_recoveries(&applied, &pending);
            assert!(result.recoveries.is_empty());
            assert_eq!(result.pending[0].key, pending[0].key);
            let applied = crate::apply_alert_settings(fresh.clone(), &settings);
            assert_eq!(
                reconcile_plan_recoveries(&applied, &result.pending)
                    .recoveries
                    .len(),
                1
            );
        }
        // An unrelated Unknown meter cannot veto a qualified target.
        let mut independent = fresh.clone();
        independent.accounts[0].allowances[1].status = ProviderStatus::Unknown;
        independent.accounts[0].allowances[0]
            .recovery_requirements
            .as_mut()
            .unwrap()
            .allowance_ids = vec!["session".into()];
        let applied = crate::apply_alert_settings(independent, &settings);
        assert_eq!(
            reconcile_plan_recoveries(&applied, &pending)
                .recoveries
                .len(),
            1
        );

        let mut unlimited = fresh;
        unlimited.accounts[0].allowances[1].unlimited = true;
        unlimited.accounts[0].allowances[1].status = ProviderStatus::Unknown;
        let applied = crate::apply_alert_settings(unlimited, &settings);
        assert_eq!(
            reconcile_plan_recoveries(&applied, &pending)
                .recoveries
                .len(),
            1
        );
    }

    #[test]
    fn narrowed_scope_cannot_qualify_remembered_capacity_after_status_decoration() {
        let mut current = snapshot(vec![account(
            "a",
            vec![
                allowance("session", Some(10.0)),
                allowance("weekly", Some(20.0)),
            ],
        )]);
        current.accounts[0].allowances[1].status = ProviderStatus::Unknown;
        let scope = RecoveryRequirements {
            allowance_ids: vec!["session".into(), "weekly".into()],
            complete: true,
        };
        let pending = [PendingRecovery {
            key: key("a", "session"),
            requirements: Some(scope.clone()),
        }];
        let settings = serde_json::from_value(serde_json::json!({
            "connections": {"anthropic.plan": {"plan": {"at": 0}}}
        }))
        .unwrap();
        let applied = crate::apply_alert_settings(current.clone(), &settings);
        assert_eq!(
            applied.accounts[0].allowances[1].status,
            ProviderStatus::Warning
        );
        let result = reconcile_plan_recoveries(&applied, &pending);
        assert!(result.recoveries.is_empty());
        assert_eq!(result.pending[0].key, pending[0].key);
        let retained = result.pending[0].requirements.as_ref().unwrap();
        assert_eq!(retained.allowance_ids, scope.allowance_ids);
        assert!(!retained.complete);
        let reloaded: Vec<PendingRecovery> =
            serde_json::from_str(&serde_json::to_string(&result.pending).unwrap()).unwrap();

        // Room alone cannot qualify a scope that still omits a remembered dependency.
        current.accounts[0].allowances[1].status = ProviderStatus::Ok;
        let applied = crate::apply_alert_settings(current.clone(), &settings);
        assert!(reconcile_plan_recoveries(&applied, &reloaded)
            .recoveries
            .is_empty());
        current.accounts[0].allowances[0].recovery_requirements = Some(scope);
        let applied = crate::apply_alert_settings(current, &settings);
        let recovered = reconcile_plan_recoveries(&applied, &reloaded);
        assert_eq!(recovered.recoveries.len(), 1);
        assert_eq!(recovered.recoveries[0].allowance_id, "session");
        assert!(recovered.pending.is_empty());
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
        assert_eq!(
            recoveries[0].provider.legacy_provider(),
            crate::model::ProviderKind::Claude
        );
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
                provider: crate::model::ProviderKind::Claude.into(),
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
