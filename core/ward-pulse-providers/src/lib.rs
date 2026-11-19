mod allowance;
pub mod claude;
pub mod codex;
pub mod cursor;
pub mod mock;
pub mod openai;
pub mod poll;

use ward_pulse_core::model::ProviderKind;

pub use mock::{
    debug_multi_provider_dashboard, debug_multi_provider_dashboard_json, mock_provider_snapshot,
    DebugDemoDashboardError,
};

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
    use serde_json::{json, Value};
    use ward_pulse_core::model::DashboardSnapshot;
    use ward_pulse_core::time::DateTimeUtc;
    use ward_pulse_core::{build_dashboard_snapshot, reconcile_plan_recoveries, PendingRecovery};

    fn codex_recovery_snapshot(report: &Value) -> DashboardSnapshot {
        let parsed = codex::codex_provider_snapshot_from_report_json(&report.to_string()).unwrap();
        build_dashboard_snapshot(parsed.generated_at, vec![parsed.provider_snapshot])
    }

    fn root_bucket(report: &mut Value) -> &mut Value {
        // Use the supported legacy-root shape, retaining qualification evidence.
        report["rateLimits"]
            .as_object_mut()
            .unwrap()
            .remove("rateLimitsByLimitId");
        &mut report["rateLimits"]["rateLimits"]
    }

    #[test]
    fn codex_singletons_require_qualified_evidence_and_do_not_retire_remembered_siblings() {
        let mut single: Value = serde_json::from_str(include_str!(
            "../../../fixtures/providers/codex/recovery_singleton_report.json"
        ))
        .unwrap();
        let pending = reconcile_plan_recoveries(&codex_recovery_snapshot(&single), &[]).pending;
        root_bucket(&mut single)["primary"]["usedPercent"] = json!(10);
        let result = reconcile_plan_recoveries(&codex_recovery_snapshot(&single), &pending);
        assert_eq!(result.recoveries.len(), 1);
        assert!(result.pending.is_empty());
        for (field, value) in [
            ("secondary", json!("omitted")),
            ("secondary", json!("malformed")),
            ("loss", json!(true)),
            ("collision", json!(true)),
            ("allowed", json!(false)), // false/false with room is denial, not recovery.
        ] {
            let mut unresolved = single.clone();
            root_bucket(&mut unresolved)["evidence"][field] = value;
            let result = reconcile_plan_recoveries(&codex_recovery_snapshot(&unresolved), &pending);
            assert!(result.recoveries.is_empty(), "{field}");
            assert_eq!(result.pending.len(), 1);
        }
        let pair: Value = serde_json::from_str(include_str!(
            "../../../fixtures/providers/codex/recovery_report.json"
        ))
        .unwrap();
        let remembered = reconcile_plan_recoveries(&codex_recovery_snapshot(&pair), &[]).pending;
        let result = reconcile_plan_recoveries(&codex_recovery_snapshot(&single), &remembered);
        assert!(result.recoveries.is_empty());
        assert_eq!(
            result.pending[0]
                .requirements
                .as_ref()
                .unwrap()
                .allowance_ids,
            ["codex-primary", "codex-secondary"]
        );
    }

    #[test]
    fn codex_pair_recovery_is_included_bucket_local_capacity_not_access_or_credits() {
        let mut report: Value = serde_json::from_str(include_str!(
            "../../../fixtures/providers/codex/recovery_report.json"
        ))
        .unwrap();
        let pending = reconcile_plan_recoveries(&codex_recovery_snapshot(&report), &[]).pending;
        // Spark remains exhausted and unresolved; it cannot veto root recovery.
        report["rateLimits"]["rateLimitsByLimitId"]["codex"]["primary"]["usedPercent"] = json!(10);
        let recovered = reconcile_plan_recoveries(&codex_recovery_snapshot(&report), &pending);
        assert_eq!(recovered.recoveries.len(), 1);
        assert_eq!(recovered.recoveries[0].allowance_id, "codex-primary");
        assert!(recovered
            .pending
            .iter()
            .any(|entry| entry.key.allowance_id == "spark-secondary"));

        root_bucket(&mut report)["primary"]["usedPercent"] = json!(10);
        assert_eq!(
            reconcile_plan_recoveries(&codex_recovery_snapshot(&report), &pending)
                .recoveries
                .len(),
            1
        );
        let mut blocked = Vec::new();
        let mut exhausted = report.clone();
        root_bucket(&mut exhausted)["secondary"]["usedPercent"] = json!(100);
        root_bucket(&mut exhausted)["credits"] =
            json!({"hasCredits":true,"unlimited":false,"balance":"50"});
        blocked.push(exhausted);
        for (field, value) in [("limitReached", json!(true)), ("allowed", Value::Null)] {
            let mut unresolved = report.clone();
            root_bucket(&mut unresolved)["evidence"][field] = value;
            blocked.push(unresolved);
        }
        let mut lossy = report.clone();
        root_bucket(&mut lossy)
            .as_object_mut()
            .unwrap()
            .remove("evidence");
        blocked.push(lossy);
        for value in blocked {
            let result = reconcile_plan_recoveries(&codex_recovery_snapshot(&value), &pending);
            assert!(result.recoveries.is_empty());
            let primary = result
                .pending
                .iter()
                .find(|entry| entry.key.allowance_id == "codex-primary")
                .unwrap();
            assert_eq!(
                primary.requirements.as_ref().unwrap().allowance_ids,
                ["codex-primary", "codex-secondary"]
            );
        }
    }

    #[test]
    fn normalized_cursor_and_claude_targets_recover_beside_unrelated_exhaustion_and_unknowns() {
        let cursor = cursor::cursor_plan_snapshot_from_report_json(include_str!(
            "../../../fixtures/providers/cursor/usage_summary.json"
        ))
        .unwrap()
        .provider_snapshot;
        let claude = claude::claude_provider_snapshot_from_report_json(
            &json!({
                "generatedAt":"2026-07-19T12:00:00Z",
                "five_hour":{"utilization":10}, "seven_day":{"utilization":20},
                "limits":[{"kind":"weekly_scoped","group":"weekly","percent":100,
                    "scope":{"model":{"id":null,"display_name":"Fable"},"surface":null}}],
                "weekly_scoped_shares":[{"limit_index":0,"used_percent_of_weekly":50,
                    "allowance_percent_of_weekly":50}]
            })
            .to_string(),
        )
        .unwrap()
        .provider_snapshot;
        let codex = codex_recovery_snapshot(
            &serde_json::from_str::<Value>(include_str!(
                "../../../fixtures/providers/codex/report_two_limits.json"
            ))
            .unwrap(),
        )
        .accounts
        .remove(0);
        let snapshot = build_dashboard_snapshot(
            DateTimeUtc::new("2026-07-19T12:00:00Z"),
            vec![cursor, claude, codex],
        );
        let pending: Vec<PendingRecovery> = snapshot
            .accounts
            .iter()
            .flat_map(|account| {
                account
                    .allowances
                    .iter()
                    .map(move |allowance| PendingRecovery {
                        key: ward_pulse_core::WindowKey {
                            account_id: account.account_id.clone(),
                            allowance_id: allowance.id.clone(),
                            history_owner: account.history_owner.clone(),
                        },
                        requirements: None,
                    })
            })
            .collect();
        let result = reconcile_plan_recoveries(&snapshot, &pending);
        let ids: Vec<_> = result
            .recoveries
            .iter()
            .map(|recovery| recovery.allowance_id.as_str())
            .collect();
        assert_eq!(
            ids,
            ["cursor-plan-models", "claude-five-hour", "claude-seven-day"]
        );
        assert!(result
            .pending
            .iter()
            .any(|entry| entry.key.allowance_id == "cursor-plan-other"));
        assert!(result
            .pending
            .iter()
            .any(|entry| entry.key.allowance_id == "claude-seven-day-fable"));
    }

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
