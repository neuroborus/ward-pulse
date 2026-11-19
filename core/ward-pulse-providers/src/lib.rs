mod allowance;
pub mod anthropic;

pub mod cursor;
pub mod mock;
pub mod openai;
pub mod poll;

/// Legacy Claude entrypoints, backed by the Anthropic family adapters.
pub use anthropic as claude;
/// Legacy Codex entrypoints, backed by the OpenAI plan adapter.
pub use openai::plan as codex;

use ward_pulse_core::model::{ConnectionKind, ProviderConnectionId, ProviderFamily};

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

/// Capabilities belong to a source, never to a union of sibling connections.
pub const fn connection_capabilities(connection: ProviderConnectionId) -> ProviderCapabilities {
    match (connection.family, connection.kind) {
        (ProviderFamily::OpenAi, ConnectionKind::Plan) => openai::plan::CAPABILITIES,
        (ProviderFamily::OpenAi, ConnectionKind::Platform) => openai::platform::CAPABILITIES,
        (ProviderFamily::Anthropic, ConnectionKind::Plan) => anthropic::plan::CAPABILITIES,
        (ProviderFamily::Anthropic, ConnectionKind::Platform) => anthropic::platform::CAPABILITIES,
        (ProviderFamily::Cursor, ConnectionKind::Plan) => cursor::plan::CAPABILITIES,
        (ProviderFamily::Cursor, ConnectionKind::Platform) => cursor::platform::CAPABILITIES,
    }
}

/// Synthetic data has no production connection identity.
pub const fn mock_capabilities() -> ProviderCapabilities {
    mock::CAPABILITIES
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
        let openai = connection_capabilities(ProviderConnectionId::OPENAI_PLATFORM);
        assert_eq!(
            (openai.usage_buckets, openai.cost_buckets),
            (
                BucketCapabilities::DAILY_AND_HOURLY,
                BucketCapabilities::DAILY,
            )
        );
        assert!(openai.supports_usage_model_breakdown);
        assert!(!openai.supports_cost_model_breakdown);
        assert!(openai.supports_cost);
        assert!(openai.supports_tokens);
        assert!(openai.supports_requests);
        assert!(!openai.supports_credits);
        assert!(!openai.supports_workspace_breakdown);
        assert!(!openai.supports_active_agents);

        let mock = mock_capabilities();
        assert_eq!(
            (mock.usage_buckets, mock.cost_buckets),
            (BucketCapabilities::NONE, BucketCapabilities::NONE)
        );

        let codex = connection_capabilities(ProviderConnectionId::OPENAI_PLAN);
        assert_eq!(codex.usage_buckets, BucketCapabilities::DAILY);
        assert!(codex.supports_tokens);
        assert!(codex.supports_credits);
        assert!(!codex.supports_cost);
        assert!(!codex.supports_requests);
        assert_eq!(codex.cost_buckets, BucketCapabilities::NONE);
        assert!(!codex.supports_usage_model_breakdown);
        assert!(!codex.supports_cost_model_breakdown);
        assert!(!codex.supports_workspace_breakdown);
        assert!(!codex.supports_active_agents);
    }

    #[test]
    fn distinguishes_plan_and_reporting_capabilities() {
        for id in [
            ProviderConnectionId::ANTHROPIC_PLAN,
            ProviderConnectionId::CURSOR_PLAN,
        ] {
            let plan = connection_capabilities(id);
            assert!(plan.supports_credits);
            assert!(!plan.supports_cost);
            assert!(!plan.supports_tokens);
            assert!(!plan.supports_requests);
            assert_eq!(plan.usage_buckets, BucketCapabilities::NONE);
            assert_eq!(plan.cost_buckets, BucketCapabilities::NONE);
            assert!(!plan.supports_usage_model_breakdown);
            assert!(!plan.supports_cost_model_breakdown);
            assert!(!plan.supports_workspace_breakdown);
            assert!(!plan.supports_active_agents);
        }
        let anthropic = connection_capabilities(ProviderConnectionId::ANTHROPIC_PLATFORM);
        assert!(anthropic.supports_cost);
        assert!(anthropic.supports_tokens);
        assert!(!anthropic.supports_requests);
        assert!(!anthropic.supports_credits);
        assert_eq!(
            anthropic.usage_buckets,
            BucketCapabilities::DAILY_AND_HOURLY
        );
        assert_eq!(anthropic.cost_buckets, BucketCapabilities::DAILY);
        assert!(anthropic.supports_usage_model_breakdown);
        assert!(anthropic.supports_workspace_breakdown);
        assert!(!anthropic.supports_cost_model_breakdown);
        assert!(!anthropic.supports_active_agents);
        let cursor = connection_capabilities(ProviderConnectionId::CURSOR_PLATFORM);
        assert!(cursor.supports_cost);
        assert!(cursor.supports_requests);
        assert!(!cursor.supports_credits);
        assert!(!cursor.supports_tokens);
        assert_eq!(cursor.usage_buckets, BucketCapabilities::DAILY);
        assert_eq!(cursor.cost_buckets, BucketCapabilities::DAILY);
        assert!(!cursor.supports_usage_model_breakdown);
        assert!(!cursor.supports_cost_model_breakdown);
        assert!(!cursor.supports_workspace_breakdown);
        assert!(!cursor.supports_active_agents);
    }
}
