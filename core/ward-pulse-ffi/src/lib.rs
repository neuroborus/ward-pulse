use std::error::Error as StdError;
use std::ffi::{c_char, CStr, CString};
use std::fmt;
use std::ptr;

use ward_pulse_core::model::{DashboardSnapshot, ProviderSnapshot};
use ward_pulse_core::time::DateTimeUtc;
use ward_pulse_core::{
    apply_alert_settings, build_dashboard_snapshot, exhausted_windows, plan_recoveries,
    reconcile_plan_recoveries, AlertSettings, PendingRecovery, WindowKey,
};
use ward_pulse_providers::claude::{
    anthropic_provider_snapshot_from_report_json, claude_provider_snapshot_from_report_json,
    AnthropicReportError, ClaudeReportError,
};
use ward_pulse_providers::codex::{codex_provider_snapshot_from_report_json, CodexReportError};
use ward_pulse_providers::cursor::{
    cursor_plan_snapshot_from_report_json, cursor_platform_snapshot_from_report_json,
    CursorPlanReportError, CursorPlatformReportError,
};
use ward_pulse_providers::mock::{
    debug_multi_provider_dashboard_json, debug_multi_provider_dashboard_json_at,
    mock_provider_snapshot_from_usage_fixture, DebugDemoDashboardError, MockUsageFixtureError,
};
use ward_pulse_providers::openai::{openai_provider_snapshot_from_report_json, OpenAiReportError};

const MOCK_USAGE_TODAY_FIXTURE: &str =
    include_str!("../../../fixtures/providers/mock/usage_today.json");

#[derive(Debug)]
enum DashboardSnapshotJsonError {
    Anthropic(AnthropicReportError),
    Claude(ClaudeReportError),
    Codex(CodexReportError),
    CursorPlan(CursorPlanReportError),
    CursorPlatform(CursorPlatformReportError),
    DebugDemo(DebugDemoDashboardError),
    Fixture(MockUsageFixtureError),
    OpenAi(OpenAiReportError),
    EmptySnapshots,
    Deserialize(serde_json::Error),
    Serialize(serde_json::Error),
    AlertSettings(serde_json::Error),
    PlanRecovery(serde_json::Error),
}

impl fmt::Display for DashboardSnapshotJsonError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Anthropic(error) => {
                write!(formatter, "failed to normalize Anthropic report: {error}")
            }
            Self::Claude(error) => {
                write!(formatter, "failed to normalize Claude report: {error}")
            }
            Self::Codex(error) => {
                write!(formatter, "failed to normalize Codex report: {error}")
            }
            Self::CursorPlan(error) => {
                write!(formatter, "failed to normalize Cursor plan report: {error}")
            }
            Self::CursorPlatform(error) => write!(
                formatter,
                "failed to normalize Cursor platform report: {error}"
            ),
            Self::DebugDemo(error) => write!(formatter, "{error}"),
            Self::Fixture(error) => {
                write!(formatter, "failed to build dashboard snapshot: {error}")
            }
            Self::OpenAi(error) => {
                write!(formatter, "failed to normalize OpenAI report: {error}")
            }
            Self::EmptySnapshots => formatter.write_str("no dashboard snapshots to merge"),
            Self::Deserialize(error) => {
                write!(
                    formatter,
                    "failed to deserialize dashboard snapshots: {error}"
                )
            }
            Self::Serialize(error) => {
                write!(formatter, "failed to serialize dashboard snapshot: {error}")
            }
            Self::PlanRecovery(error) => {
                write!(formatter, "failed to read a plan recovery request: {error}")
            }
            Self::AlertSettings(error) => {
                write!(formatter, "failed to parse alert settings: {error}")
            }
        }
    }
}

impl StdError for DashboardSnapshotJsonError {
    fn source(&self) -> Option<&(dyn StdError + 'static)> {
        match self {
            Self::Anthropic(error) => Some(error),
            Self::Claude(error) => Some(error),
            Self::Codex(error) => Some(error),
            Self::CursorPlan(error) => Some(error),
            Self::CursorPlatform(error) => Some(error),
            Self::DebugDemo(error) => Some(error),
            Self::Fixture(error) => Some(error),
            Self::OpenAi(error) => Some(error),
            Self::EmptySnapshots => None,
            Self::Deserialize(error)
            | Self::Serialize(error)
            | Self::AlertSettings(error)
            | Self::PlanRecovery(error) => Some(error),
        }
    }
}

fn dashboard_json(
    generated_at: DateTimeUtc,
    accounts: Vec<ProviderSnapshot>,
) -> Result<String, DashboardSnapshotJsonError> {
    let snapshot = build_dashboard_snapshot(generated_at, accounts);

    serde_json::to_string(&snapshot).map_err(DashboardSnapshotJsonError::Serialize)
}

fn codex_dashboard_snapshot_json(report_json: &str) -> Result<String, DashboardSnapshotJsonError> {
    let report = codex_provider_snapshot_from_report_json(report_json)
        .map_err(DashboardSnapshotJsonError::Codex)?;

    dashboard_json(report.generated_at, vec![report.provider_snapshot])
}

fn dashboard_snapshot_json() -> Result<String, DashboardSnapshotJsonError> {
    let fixture = mock_provider_snapshot_from_usage_fixture("mock-local", MOCK_USAGE_TODAY_FIXTURE)
        .map_err(DashboardSnapshotJsonError::Fixture)?;

    dashboard_json(fixture.generated_at, vec![fixture.provider_snapshot])
}

fn debug_dashboard_snapshot_json(seed: u64) -> Result<String, DashboardSnapshotJsonError> {
    debug_multi_provider_dashboard_json(seed).map_err(DashboardSnapshotJsonError::DebugDemo)
}

fn openai_dashboard_snapshot_json(report_json: &str) -> Result<String, DashboardSnapshotJsonError> {
    let report = openai_provider_snapshot_from_report_json(report_json)
        .map_err(DashboardSnapshotJsonError::OpenAi)?;

    dashboard_json(report.generated_at, vec![report.provider_snapshot])
}

fn anthropic_dashboard_snapshot_json(
    report_json: &str,
) -> Result<String, DashboardSnapshotJsonError> {
    let report = anthropic_provider_snapshot_from_report_json(report_json)
        .map_err(DashboardSnapshotJsonError::Anthropic)?;

    dashboard_json(report.generated_at, vec![report.provider_snapshot])
}

fn claude_dashboard_snapshot_json(report_json: &str) -> Result<String, DashboardSnapshotJsonError> {
    let report = claude_provider_snapshot_from_report_json(report_json)
        .map_err(DashboardSnapshotJsonError::Claude)?;

    dashboard_json(report.generated_at, vec![report.provider_snapshot])
}

fn cursor_plan_dashboard_snapshot_json(
    report_json: &str,
) -> Result<String, DashboardSnapshotJsonError> {
    let report = cursor_plan_snapshot_from_report_json(report_json)
        .map_err(DashboardSnapshotJsonError::CursorPlan)?;

    dashboard_json(report.generated_at, vec![report.provider_snapshot])
}

fn cursor_platform_dashboard_snapshot_json(
    report_json: &str,
) -> Result<String, DashboardSnapshotJsonError> {
    let report = cursor_platform_snapshot_from_report_json(report_json)
        .map_err(DashboardSnapshotJsonError::CursorPlatform)?;

    dashboard_json(report.generated_at, vec![report.provider_snapshot])
}

fn merge_dashboard_snapshots_json(
    snapshots_json: &str,
) -> Result<String, DashboardSnapshotJsonError> {
    let snapshots: Vec<DashboardSnapshot> =
        serde_json::from_str(snapshots_json).map_err(DashboardSnapshotJsonError::Deserialize)?;
    let generated_at = snapshots
        .iter()
        .map(|snapshot| &snapshot.generated_at)
        .max()
        .cloned()
        .ok_or(DashboardSnapshotJsonError::EmptySnapshots)?;
    let accounts = snapshots
        .into_iter()
        .flat_map(|snapshot| snapshot.accounts)
        .collect();

    dashboard_json(generated_at, accounts)
}

fn apply_alert_settings_json(request_json: &str) -> Result<String, DashboardSnapshotJsonError> {
    let value: serde_json::Value =
        serde_json::from_str(request_json).map_err(DashboardSnapshotJsonError::AlertSettings)?;
    let snapshot: DashboardSnapshot = serde_json::from_value(
        value
            .get("snapshot")
            .cloned()
            .unwrap_or(serde_json::Value::Null),
    )
    .map_err(DashboardSnapshotJsonError::AlertSettings)?;
    let settings: AlertSettings = match value.get("settings") {
        Some(settings) => serde_json::from_value(settings.clone())
            .map_err(DashboardSnapshotJsonError::AlertSettings)?,
        None => AlertSettings::default(),
    };
    let snapshot = apply_alert_settings(snapshot, &settings);
    serde_json::to_string(&snapshot).map_err(DashboardSnapshotJsonError::Serialize)
}

/// Windows the phone should remember as spent, from a snapshot it just loaded.
fn exhausted_windows_json(snapshot_json: &str) -> Result<String, DashboardSnapshotJsonError> {
    let snapshot: DashboardSnapshot =
        serde_json::from_str(snapshot_json).map_err(DashboardSnapshotJsonError::PlanRecovery)?;
    serde_json::to_string(&exhausted_windows(&snapshot))
        .map_err(DashboardSnapshotJsonError::Serialize)
}

/// Windows from `exhausted` that the snapshot reports usable again.
///
/// Both halves arrive in one object, as alert settings do: the shared string
/// transform takes a single argument.
fn plan_recoveries_json(request_json: &str) -> Result<String, DashboardSnapshotJsonError> {
    let value: serde_json::Value =
        serde_json::from_str(request_json).map_err(DashboardSnapshotJsonError::PlanRecovery)?;
    let snapshot: DashboardSnapshot = serde_json::from_value(
        value
            .get("snapshot")
            .cloned()
            .unwrap_or(serde_json::Value::Null),
    )
    .map_err(DashboardSnapshotJsonError::PlanRecovery)?;
    let exhausted: Vec<WindowKey> = match value.get("exhausted") {
        Some(exhausted) => serde_json::from_value(exhausted.clone())
            .map_err(DashboardSnapshotJsonError::PlanRecovery)?,
        None => Vec::new(),
    };
    serde_json::to_string(&plan_recoveries(&exhausted, &snapshot))
        .map_err(DashboardSnapshotJsonError::Serialize)
}

fn reconcile_plan_recoveries_json(
    request_json: &str,
) -> Result<String, DashboardSnapshotJsonError> {
    let value: serde_json::Value =
        serde_json::from_str(request_json).map_err(DashboardSnapshotJsonError::PlanRecovery)?;
    let snapshot: DashboardSnapshot = serde_json::from_value(
        value
            .get("snapshot")
            .cloned()
            .unwrap_or(serde_json::Value::Null),
    )
    .map_err(DashboardSnapshotJsonError::PlanRecovery)?;
    let pending: Vec<PendingRecovery> = serde_json::from_value(
        value
            .get("pending")
            .cloned()
            .unwrap_or(serde_json::Value::Null),
    )
    .map_err(DashboardSnapshotJsonError::PlanRecovery)?;
    serde_json::to_string(&reconcile_plan_recoveries(&snapshot, &pending))
        .map_err(DashboardSnapshotJsonError::Serialize)
}

fn snapshot_result_json(result: Result<String, DashboardSnapshotJsonError>) -> Option<String> {
    result_json("dashboardJson", result)
}

/// The result envelope every entry point returns, named by what it carries.
fn result_json(
    payload_key: &str,
    result: Result<String, DashboardSnapshotJsonError>,
) -> Option<String> {
    let envelope = match result {
        Ok(payload) => serde_json::json!({
            "status": "success",
            payload_key: payload,
        }),
        Err(error) => serde_json::json!({
            "status": "error",
            "message": error.to_string(),
        }),
    };
    serde_json::to_string(&envelope).ok()
}

/// Builds the bundled mock dashboard and returns a JSON result envelope.
#[no_mangle]
pub extern "C" fn ward_pulse_dashboard_snapshot_result_json() -> *mut c_char {
    result_json_into_raw(dashboard_snapshot_json)
}

/// Builds a seeded multi-provider debug dashboard for the phone Mock data toggle
/// and returns a JSON result envelope.
#[no_mangle]
pub extern "C" fn ward_pulse_debug_dashboard_snapshot_result_json(seed: u64) -> *mut c_char {
    result_json_into_raw(move || debug_dashboard_snapshot_json(seed))
}

/// Builds a seeded debug dashboard at an explicit `YYYY-MM-DDTHH:MM:SSZ` UTC anchor.
/// Invalid dates return an error envelope, never an undated fallback. Free every
/// non-null result with [`ward_pulse_string_free`]; the caller retains the input.
/// The original seed-only entry point and its output are unchanged.
///
/// # Safety
///
/// Non-null `capture_anchor` must point to a valid null-terminated byte string.
/// Null and non-UTF-8 inputs return null.
#[no_mangle]
pub unsafe extern "C" fn ward_pulse_debug_dashboard_snapshot_at_result_json(
    seed: u64,
    capture_anchor: *const c_char,
) -> *mut c_char {
    transform_report_json(capture_anchor, |anchor| {
        snapshot_result_json(
            debug_multi_provider_dashboard_json_at(seed, Some(anchor))
                .map_err(DashboardSnapshotJsonError::DebugDemo),
        )
    })
}

/// Wraps a snapshot build in the shared result envelope and hands the string
/// to the caller, who releases it with [`ward_pulse_string_free`].
fn result_json_into_raw(
    build: impl FnOnce() -> Result<String, DashboardSnapshotJsonError> + std::panic::UnwindSafe,
) -> *mut c_char {
    match std::panic::catch_unwind(|| {
        snapshot_result_json(build()).and_then(|result| CString::new(result).ok())
    }) {
        Ok(Some(result)) => result.into_raw(),
        Ok(None) | Err(_) => ptr::null_mut(),
    }
}

/// Normalizes OpenAI reporting pages and returns a JSON result envelope.
///
/// # Safety
///
/// `report_json` must be a non-null pointer to a valid, null-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn ward_pulse_openai_dashboard_snapshot_result_json(
    report_json: *const c_char,
) -> *mut c_char {
    transform_report_json(report_json, |json| {
        snapshot_result_json(openai_dashboard_snapshot_json(json))
    })
}

/// Normalizes a sanitized Codex account report and returns a JSON result envelope.
///
/// # Safety
///
/// `report_json` must be a non-null pointer to a valid, null-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn ward_pulse_codex_dashboard_snapshot_result_json(
    report_json: *const c_char,
) -> *mut c_char {
    transform_report_json(report_json, |json| {
        snapshot_result_json(codex_dashboard_snapshot_json(json))
    })
}

/// Normalizes Anthropic Admin reporting pages and returns a JSON result envelope.
///
/// # Safety
///
/// `report_json` must be a non-null pointer to a valid, null-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn ward_pulse_anthropic_dashboard_snapshot_result_json(
    report_json: *const c_char,
) -> *mut c_char {
    transform_report_json(report_json, |json| {
        snapshot_result_json(anthropic_dashboard_snapshot_json(json))
    })
}

/// Normalizes a Claude oauth usage report and returns a JSON result envelope.
///
/// # Safety
///
/// `report_json` must be a non-null pointer to a valid, null-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn ward_pulse_claude_dashboard_snapshot_result_json(
    report_json: *const c_char,
) -> *mut c_char {
    transform_report_json(report_json, |json| {
        snapshot_result_json(claude_dashboard_snapshot_json(json))
    })
}

/// Normalizes a Cursor plan usage summary and returns a JSON result envelope.
///
/// # Safety
///
/// `report_json` must be a non-null pointer to a valid, null-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn ward_pulse_cursor_plan_dashboard_snapshot_result_json(
    report_json: *const c_char,
) -> *mut c_char {
    transform_report_json(report_json, |json| {
        snapshot_result_json(cursor_plan_dashboard_snapshot_json(json))
    })
}

/// Normalizes Cursor team Admin reporting pages and returns a JSON result envelope.
///
/// # Safety
///
/// `report_json` must be a non-null pointer to a valid, null-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn ward_pulse_cursor_platform_dashboard_snapshot_result_json(
    report_json: *const c_char,
) -> *mut c_char {
    transform_report_json(report_json, |json| {
        snapshot_result_json(cursor_platform_dashboard_snapshot_json(json))
    })
}

/// Lists the plan windows a snapshot reports as spent, for the phone to keep
/// until its next poll, and returns a JSON result envelope.
///
/// # Safety
///
/// `snapshot_json` must be a non-null pointer to a valid, null-terminated UTF-8
/// string.
#[no_mangle]
pub unsafe extern "C" fn ward_pulse_exhausted_windows_result_json(
    snapshot_json: *const c_char,
) -> *mut c_char {
    transform_report_json(snapshot_json, |json| {
        result_json("windowsJson", exhausted_windows_json(json))
    })
}

/// Reports which remembered windows have room again and returns a JSON result
/// envelope. The request carries `snapshot` and `exhausted` in one object.
///
/// # Safety
///
/// `request_json` must be a non-null pointer to a valid, null-terminated UTF-8
/// string.
#[no_mangle]
pub unsafe extern "C" fn ward_pulse_plan_recoveries_result_json(
    request_json: *const c_char,
) -> *mut c_char {
    transform_report_json(request_json, |json| {
        result_json("recoveriesJson", plan_recoveries_json(json))
    })
}

/// Reconciles pending Plan targets and returns `reconciliationJson` in the result envelope.
///
/// # Safety
///
/// `request_json` must be a non-null pointer to a valid, null-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn ward_pulse_reconcile_plan_recoveries_result_json(
    request_json: *const c_char,
) -> *mut c_char {
    transform_report_json(request_json, |json| {
        result_json("reconciliationJson", reconcile_plan_recoveries_json(json))
    })
}

unsafe fn transform_report_json(
    report_json: *const c_char,
    transform: impl FnOnce(&str) -> Option<String> + std::panic::UnwindSafe,
) -> *mut c_char {
    if report_json.is_null() {
        return ptr::null_mut();
    }

    match std::panic::catch_unwind(|| {
        let report_json = unsafe { CStr::from_ptr(report_json) }.to_str().ok()?;
        transform(report_json).and_then(|result| CString::new(result).ok())
    }) {
        Ok(Some(result)) => result.into_raw(),
        Ok(None) | Err(_) => ptr::null_mut(),
    }
}

/// Merges normalized dashboard snapshots and returns a JSON result envelope.
///
/// # Safety
///
/// `snapshots_json` must be a non-null pointer to a valid, null-terminated UTF-8 JSON array.
#[no_mangle]
pub unsafe extern "C" fn ward_pulse_merge_dashboard_snapshots_result_json(
    snapshots_json: *const c_char,
) -> *mut c_char {
    transform_report_json(snapshots_json, |json| {
        snapshot_result_json(merge_dashboard_snapshots_json(json))
    })
}

/// Applies user alert threshold settings to a dashboard snapshot JSON.
///
/// Request body: `{ "snapshot": <DashboardSnapshot>, "settings": <AlertSettings> }`.
///
/// # Safety
///
/// `request_json` must be a non-null pointer to a valid, null-terminated UTF-8 JSON object.
#[no_mangle]
pub unsafe extern "C" fn ward_pulse_apply_alert_settings_result_json(
    request_json: *const c_char,
) -> *mut c_char {
    transform_report_json(request_json, |json| {
        snapshot_result_json(apply_alert_settings_json(json))
    })
}

/// Releases a string returned by a WardPulse dashboard snapshot function.
///
/// # Safety
///
/// `value` must be null or a pointer returned by
/// a WardPulse dashboard snapshot function that has not already been released.
#[no_mangle]
pub unsafe extern "C" fn ward_pulse_string_free(value: *mut c_char) {
    if !value.is_null() {
        drop(unsafe { CString::from_raw(value) });
    }
}

#[cfg(test)]
mod tests {
    use std::ffi::{CStr, CString};

    use super::*;

    #[test]
    fn snapshot_json_matches_golden_fixture() {
        let actual: serde_json::Value =
            serde_json::from_str(&dashboard_snapshot_json().expect("serialize dashboard snapshot"))
                .expect("parse dashboard snapshot JSON");
        let expected: serde_json::Value = serde_json::from_str(include_str!(
            "../../../fixtures/snapshots/dashboard_today.json"
        ))
        .expect("parse golden dashboard snapshot");

        assert_eq!(actual, expected);
        let legacy: DashboardSnapshot = serde_json::from_value(expected).unwrap();
        assert!(legacy.alert_conditions.is_empty());
        assert!(serde_json::to_value(legacy)
            .unwrap()
            .get("alertConditions")
            .is_none());
    }

    /// Real budget and snapshot production for USD 0.04 spent of USD 100.00:
    /// 0.04% used, which the phone must not publish to Wear as zero.
    ///
    /// With `WARDPULSE_WATCH_WITNESS_DIR` set, the produced bytes are first
    /// written to a new file there for the phone regression to read.
    #[test]
    fn fractional_watch_snapshot_matches_fixture() {
        use ward_pulse_core::budget::calculate_budget_state;
        use ward_pulse_core::model::{connection, BudgetPeriod, Money, ProviderKind};

        let generated_at = DateTimeUtc::new("2026-06-27T18:42:00Z");
        let usd = |minor_units| Some(Money::minor_units(minor_units, "USD"));
        let today = calculate_budget_state(BudgetPeriod::Today, usd(4), usd(10_000), None);
        let account = ProviderSnapshot {
            account_id: "openai-platform-local".to_owned(),
            provider: ProviderKind::OpenAi,
            connection: Some(connection::OPENAI_PLATFORM.to_owned()),
            history_owner: None,
            status: today.status,
            today,
            week: calculate_budget_state(BudgetPeriod::Week, None, None, None),
            month: calculate_budget_state(BudgetPeriod::Month, None, None, None),
            credits: Vec::new(),
            allowances: Vec::new(),
            buckets: Vec::new(),
            model_breakdown: Vec::new(),
            last_successful_sync_at: Some(generated_at.clone()),
            last_error: None,
        };
        let produced = dashboard_json(generated_at, vec![account]).expect("serialize snapshot");

        if let Some(dir) = std::env::var_os("WARDPULSE_WATCH_WITNESS_DIR") {
            use std::io::Write;
            // `create_new` refuses a file left by an earlier run.
            std::fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(std::path::PathBuf::from(dir).join("dashboard_watch_fractional.json"))
                .and_then(|mut file| file.write_all(produced.as_bytes()))
                .expect("export a fresh producer witness");
        }

        let actual: serde_json::Value =
            serde_json::from_str(&produced).expect("parse produced snapshot");
        let expected: serde_json::Value = serde_json::from_str(include_str!(
            "../../../fixtures/snapshots/dashboard_watch_fractional.json"
        ))
        .expect("parse fractional snapshot fixture");
        assert_eq!(actual, expected);
        assert_eq!(actual["accounts"][0]["today"]["usedPercent"], 0.04);
    }

    /// The golden both sides read: this crate builds it, and the phone parses
    /// the same file. A drift here is a contract break, not a test detail.
    #[test]
    fn plan_recoveries_match_the_golden_fixture() {
        let golden: serde_json::Value = serde_json::from_str(include_str!(
            "../../../fixtures/snapshots/plan_recovery.json"
        ))
        .expect("parse golden plan recovery");

        let spent = snapshot_with_weekly_percent(100.0);
        let windows: serde_json::Value =
            serde_json::from_str(&exhausted_windows_json(&spent).expect("list exhausted windows"))
                .expect("parse exhausted windows");
        assert_eq!(windows, golden["exhausted"]);

        let request = serde_json::json!({
            "snapshot": serde_json::from_str::<serde_json::Value>(&snapshot_with_weekly_percent(
                4.0,
            ))
            .expect("parse snapshot"),
            "exhausted": golden["exhausted"],
        });
        let recoveries: serde_json::Value = serde_json::from_str(
            &plan_recoveries_json(&request.to_string()).expect("list recoveries"),
        )
        .expect("parse recoveries");

        assert_eq!(recoveries, golden["recoveries"]);
    }

    #[test]
    fn reconciliation_envelope_preserves_requirements_through_merge_and_settings() {
        let normalized = codex_dashboard_snapshot_json(include_str!(
            "../../../fixtures/providers/codex/recovery_report.json"
        ))
        .unwrap();
        let snapshot: serde_json::Value = serde_json::from_str(&normalized).unwrap();
        let merged =
            merge_dashboard_snapshots_json(&serde_json::json!([snapshot]).to_string()).unwrap();
        let applied = apply_alert_settings_json(&serde_json::json!({
            "snapshot": serde_json::from_str::<serde_json::Value>(&merged).unwrap(), "settings": {}
        }).to_string()).unwrap();
        let request = serde_json::json!({"snapshot": serde_json::from_str::<serde_json::Value>(&applied).unwrap(), "pending": []});
        let encoded = result_json(
            "reconciliationJson",
            reconcile_plan_recoveries_json(&request.to_string()),
        )
        .unwrap();
        let envelope: serde_json::Value = serde_json::from_str(&encoded).unwrap();
        let result: serde_json::Value =
            serde_json::from_str(envelope["reconciliationJson"].as_str().unwrap()).unwrap();
        assert_eq!(result["pending"][0]["accountId"], "codex-local");
        assert_eq!(result["pending"][0]["requirements"]["complete"], true);
        assert_eq!(
            result["pending"][0]["requirements"]["allowanceIds"],
            serde_json::json!(["codex-primary", "codex-secondary"])
        );
        assert!(result["recoveries"].as_array().unwrap().is_empty());
    }

    #[test]
    fn a_recovery_request_without_remembered_windows_is_empty() {
        let request = serde_json::json!({
            "snapshot": serde_json::from_str::<serde_json::Value>(&snapshot_with_weekly_percent(
                4.0,
            ))
            .expect("parse snapshot"),
        });

        let recoveries = plan_recoveries_json(&request.to_string()).expect("list recoveries");

        assert_eq!(recoveries, "[]");
    }

    #[test]
    fn normalized_json_transforms_preserve_private_history_owners() {
        let owner = serde_json::json!({
            "connection": "anthropic.plan",
            "identity": "a".repeat(64),
        });
        let mut snapshot: serde_json::Value =
            serde_json::from_str(&snapshot_with_weekly_percent(100.0)).unwrap();
        snapshot["accounts"][0]["connection"] = owner["connection"].clone();
        snapshot["accounts"][0]["historyOwner"] = owner.clone();
        let merged: serde_json::Value = serde_json::from_str(
            &merge_dashboard_snapshots_json(&serde_json::json!([snapshot]).to_string()).unwrap(),
        )
        .unwrap();
        assert_eq!(merged["accounts"][0]["historyOwner"], owner);

        let request = serde_json::json!({
            "snapshot": merged,
            "settings": {"connections": {"anthropic.plan": {"plan": {"at": 80}}}},
        });
        let mut applied: serde_json::Value =
            serde_json::from_str(&apply_alert_settings_json(&request.to_string()).unwrap())
                .unwrap();
        assert_eq!(applied["accounts"][0]["historyOwner"], owner);
        assert_eq!(applied["alertConditions"].as_array().unwrap().len(), 2);
        for condition in applied["alertConditions"].as_array().unwrap() {
            assert_eq!(condition["key"]["historyOwner"], owner);
        }
        assert!(applied["watchSummary"].get("historyOwner").is_none());
        assert!(!applied["alerts"]
            .to_string()
            .contains(owner["identity"].as_str().unwrap()));

        let exhausted: serde_json::Value =
            serde_json::from_str(&exhausted_windows_json(&applied.to_string()).unwrap()).unwrap();
        assert_eq!(exhausted.as_array().unwrap().len(), 2);
        for key in exhausted.as_array().unwrap() {
            assert_eq!(key["historyOwner"], owner);
        }
        applied["accounts"][0]["allowances"][0]["usedPercent"] = serde_json::json!(20.0);
        let request = serde_json::json!({"snapshot": applied, "exhausted": exhausted});
        let recoveries: serde_json::Value =
            serde_json::from_str(&plan_recoveries_json(&request.to_string()).unwrap()).unwrap();
        assert!(recoveries.as_array().unwrap().is_empty());
        let mut usable = request;
        usable["snapshot"]["accounts"][0]["allowances"][1]["usedPercent"] = serde_json::json!(20.0);
        let recoveries: serde_json::Value =
            serde_json::from_str(&plan_recoveries_json(&usable.to_string()).unwrap()).unwrap();
        assert_eq!(recoveries.as_array().unwrap().len(), 2);
        for recovery in recoveries.as_array().unwrap() {
            assert_eq!(recovery["historyOwner"], owner);
        }
    }

    /// A one-account dashboard whose weekly window sits at `used_percent`.
    fn snapshot_with_weekly_percent(used_percent: f64) -> String {
        let mut snapshot: serde_json::Value = serde_json::from_str(include_str!(
            "../../../fixtures/snapshots/dashboard_today.json"
        ))
        .expect("parse golden dashboard snapshot");
        snapshot["accounts"] = serde_json::json!([{
            "accountId": "claude-local",
            "provider": "claude",
            "status": "ok",
            "today": snapshot["todayTotal"],
            "week": snapshot["weekTotal"],
            "month": snapshot["monthTotal"],
            "credits": [],
            "allowances": [
                {
                    "id": "claude-weekly",
                    "recoveryRequirements": {"allowanceIds":["claude-weekly","claude-session"],"complete":true},
                    "source": "plan",
                    "label": "Weekly plan",
                    "usedPercent": used_percent,
                    "used": null,
                    "limit": null,
                    "remaining": null,
                    "windowMinutes": null,
                    "resetsAt": "2026-08-17T09:00:00Z",
                    "status": "ok"
                },
                {
                    "id": "claude-session",
                    "recoveryRequirements": {"allowanceIds":["claude-session","claude-weekly"],"complete":true},
                    "source": "plan",
                    "label": "5-hour session",
                    "usedPercent": 100.0,
                    "used": null,
                    "limit": null,
                    "remaining": null,
                    "windowMinutes": 300,
                    "resetsAt": "2026-08-17T09:00:00Z",
                    "status": "warning"
                }
            ],
            "buckets": [],
            "modelBreakdown": [],
            "lastSuccessfulSyncAt": null,
            "lastError": null
        }]);
        snapshot.to_string()
    }

    #[test]
    fn debug_dashboard_includes_all_providers() {
        let json = debug_dashboard_snapshot_json(99).expect("debug dashboard");
        let snapshot: serde_json::Value =
            serde_json::from_str(&json).expect("parse debug dashboard");
        let providers: Vec<&str> = snapshot["accounts"]
            .as_array()
            .expect("accounts")
            .iter()
            .filter_map(|account| account["provider"].as_str())
            .collect();
        assert!(providers.contains(&"openai"));
        assert!(providers.contains(&"codex"));
        assert!(providers.contains(&"claude"));
        assert!(providers.contains(&"cursor"));
        assert!(!providers.contains(&"mock"));
    }

    #[test]
    fn dated_debug_api_owns_results_but_borrows_its_anchor() {
        for (anchor, status) in [
            ("2026-11-02T12:00:00Z", "success"),
            ("2026-02-30T12:00:00Z", "error"),
            ("", "error"),
        ] {
            let request = CString::new(anchor).unwrap();
            let result =
                unsafe { ward_pulse_debug_dashboard_snapshot_at_result_json(7, request.as_ptr()) };
            assert!(!result.is_null());
            let envelope: serde_json::Value =
                serde_json::from_str(unsafe { CStr::from_ptr(result) }.to_str().unwrap()).unwrap();
            unsafe { ward_pulse_string_free(result) };
            assert_eq!(envelope["status"], status);
            assert_eq!(request.to_str().unwrap(), anchor);
            if status == "success" {
                let snapshot: serde_json::Value =
                    serde_json::from_str(envelope["dashboardJson"].as_str().unwrap()).unwrap();
                assert_eq!(snapshot["generatedAt"], anchor);
            } else {
                assert!(envelope["message"]
                    .as_str()
                    .unwrap()
                    .contains("capture anchor"));
                assert!(envelope.get("dashboardJson").is_none());
            }
        }
        let invalid_utf8 = CString::new(vec![0xff]).unwrap();
        for input in [ptr::null(), invalid_utf8.as_ptr()] {
            assert!(
                unsafe { ward_pulse_debug_dashboard_snapshot_at_result_json(7, input) }.is_null()
            );
        }
    }

    #[test]
    fn c_api_returns_owned_snapshot_envelope() {
        let value = ward_pulse_dashboard_snapshot_result_json();
        assert!(!value.is_null());

        let json = unsafe { CStr::from_ptr(value) }
            .to_str()
            .expect("dashboard envelope is UTF-8");
        let envelope: serde_json::Value =
            serde_json::from_str(json).expect("parse dashboard envelope JSON");
        assert_eq!(envelope["status"], "success");

        let snapshot: serde_json::Value =
            serde_json::from_str(envelope["dashboardJson"].as_str().expect("dashboard JSON"))
                .expect("parse dashboard snapshot JSON");
        assert_eq!(snapshot["accounts"][0]["accountId"], "mock-local");

        unsafe { ward_pulse_string_free(value) };
    }

    #[test]
    fn c_api_accepts_null_free() {
        unsafe { ward_pulse_string_free(ptr::null_mut()) };
    }

    #[test]
    fn result_api_normalizes_openai_report_json() {
        let usage = include_str!("../../../fixtures/providers/openai/usage_completions.json");
        let costs = include_str!("../../../fixtures/providers/openai/costs.json");
        let request = CString::new(
            serde_json::json!({
                "accountId": "openai-local",
                "generatedAt": "2026-07-19T12:00:00Z",
                "todayStart": 1_784_419_200_i64,
                "weekStart": 1_783_900_800_i64,
                "monthStart": 1_782_864_000_i64,
                "usagePages": [usage],
                "costPages": [costs]
            })
            .to_string(),
        )
        .expect("request has no null bytes");

        let value = unsafe { ward_pulse_openai_dashboard_snapshot_result_json(request.as_ptr()) };
        assert!(!value.is_null());

        let result: serde_json::Value = serde_json::from_str(
            unsafe { CStr::from_ptr(value) }
                .to_str()
                .expect("result is UTF-8"),
        )
        .expect("parse result JSON");
        assert_eq!(result["status"], "success");

        let snapshot: serde_json::Value =
            serde_json::from_str(result["dashboardJson"].as_str().expect("dashboard JSON"))
                .expect("parse dashboard JSON");
        assert_eq!(snapshot["accounts"][0]["provider"], "openai");
        assert_eq!(snapshot["todayTotal"]["spent"]["minorUnits"], 50);

        unsafe { ward_pulse_string_free(value) };
    }

    #[test]
    fn result_api_normalizes_codex_report_json() {
        for (generated_at, expected) in [
            ("2026-07-19T12:00:00Z", "2026-07-19T12:00:00Z"),
            ("2026-11-14T09:00:00.100Z", "2026-11-14T09:00:00.1Z"),
            ("2026-11-14T09:00:00.800Z", "2026-11-14T09:00:00.8Z"),
            ("2026-11-14T09:00:00.123456Z", "2026-11-14T09:00:00.123456Z"),
        ] {
            let mut report: serde_json::Value = serde_json::from_str(include_str!(
                "../../../fixtures/providers/codex/report.json"
            ))
            .expect("parse sanitized Codex report");
            report["generatedAt"] = generated_at.into();
            let request = CString::new(report.to_string()).expect("request has no null bytes");

            let value =
                unsafe { ward_pulse_codex_dashboard_snapshot_result_json(request.as_ptr()) };
            assert!(!value.is_null());

            let result: serde_json::Value = serde_json::from_str(
                unsafe { CStr::from_ptr(value) }
                    .to_str()
                    .expect("result is UTF-8"),
            )
            .expect("parse result JSON");
            unsafe { ward_pulse_string_free(value) };
            assert_eq!(result["status"], "success");

            let snapshot: serde_json::Value =
                serde_json::from_str(result["dashboardJson"].as_str().expect("dashboard JSON"))
                    .expect("parse dashboard JSON");
            assert_eq!(snapshot["accounts"][0]["provider"], "codex");
            assert_eq!(
                snapshot["accounts"][0]["allowances"][0]["usedPercent"],
                84.0
            );
            assert_eq!(snapshot["generatedAt"], expected);
            assert_eq!(snapshot["accounts"][0]["lastSuccessfulSyncAt"], expected);
        }
    }

    #[test]
    fn merge_selects_positive_fraction_after_its_whole_second() {
        let whole = "2026-11-14T09:00:00Z";
        let fraction = "2026-11-14T09:00:00.1Z";
        for times in [[whole, fraction], [fraction, whole]] {
            let snapshots = times.map(|time| build_dashboard_snapshot(time.into(), vec![]));
            let merged = merge_dashboard_snapshots_json(
                &serde_json::to_string(&snapshots).expect("serialize snapshots"),
            )
            .expect("merge snapshots");
            let snapshot: DashboardSnapshot =
                serde_json::from_str(&merged).expect("parse snapshot");
            assert_eq!(snapshot.generated_at.as_str(), fraction);
        }
    }

    #[test]
    fn result_api_merges_provider_snapshots() {
        let mock: serde_json::Value = serde_json::from_str(
            &dashboard_snapshot_json().expect("serialize mock dashboard snapshot"),
        )
        .expect("parse mock dashboard snapshot");
        let codex: serde_json::Value = serde_json::from_str(
            &codex_dashboard_snapshot_json(include_str!(
                "../../../fixtures/providers/codex/report.json"
            ))
            .expect("serialize Codex dashboard snapshot"),
        )
        .expect("parse Codex dashboard snapshot");
        let request = CString::new(serde_json::json!([mock, codex]).to_string())
            .expect("request has no null bytes");

        let value = unsafe { ward_pulse_merge_dashboard_snapshots_result_json(request.as_ptr()) };
        assert!(!value.is_null());
        let result: serde_json::Value = serde_json::from_str(
            unsafe { CStr::from_ptr(value) }
                .to_str()
                .expect("result is UTF-8"),
        )
        .expect("parse result JSON");
        let snapshot: serde_json::Value =
            serde_json::from_str(result["dashboardJson"].as_str().expect("dashboard JSON"))
                .expect("parse dashboard JSON");

        assert_eq!(snapshot["accounts"].as_array().unwrap().len(), 2);
        assert_eq!(snapshot["accounts"][0]["provider"], "mock");
        assert_eq!(snapshot["accounts"][1]["provider"], "codex");

        unsafe { ward_pulse_string_free(value) };
    }

    #[test]
    fn result_api_applies_alert_settings() {
        let snapshot: serde_json::Value = serde_json::from_str(
            &dashboard_snapshot_json().expect("serialize mock dashboard snapshot"),
        )
        .expect("parse mock dashboard snapshot");
        let request = CString::new(
            serde_json::json!({
                "snapshot": snapshot,
                "settings": {
                    "connections": {
                        "mock.plan": { "today": { "at": 20 } }
                    }
                }
            })
            .to_string(),
        )
        .expect("request has no null bytes");

        let value = unsafe { ward_pulse_apply_alert_settings_result_json(request.as_ptr()) };
        assert!(!value.is_null());
        let result: serde_json::Value = serde_json::from_str(
            unsafe { CStr::from_ptr(value) }
                .to_str()
                .expect("result is UTF-8"),
        )
        .expect("parse result JSON");
        assert_eq!(result["status"], "success");
        let applied: serde_json::Value =
            serde_json::from_str(result["dashboardJson"].as_str().expect("dashboard JSON"))
                .expect("parse dashboard JSON");
        let alerts = applied["alerts"].as_array().expect("alerts");
        assert_eq!(alerts.len(), 1);
        assert_eq!(alerts[0]["severity"], "warning");
        let condition = &applied["alertConditions"][0];
        assert_eq!(condition["state"], "crossed");
        assert_eq!(condition["alert"], alerts[0]);
        assert_eq!(
            condition["key"],
            serde_json::json!({
                "provider": "mock", "accountId": "mock-local", "connection": "mock.plan",
                "target": {"kind": "budget", "period": "today"}
            })
        );

        unsafe { ward_pulse_string_free(value) };
    }

    #[test]
    fn result_api_applies_legacy_and_sparse_plan_window_settings() {
        let mut snapshot: serde_json::Value =
            serde_json::from_str(&snapshot_with_weekly_percent(80.0)).expect("parse snapshot");
        let account = &mut snapshot["accounts"][0];
        account["connection"] = serde_json::json!("anthropic.plan");
        account["today"]["spent"] = serde_json::json!({"minorUnits": 50, "currency": "USD"});
        account["allowances"][1]["status"] = serde_json::json!("ok");
        let mut extra = account["allowances"][0].clone();
        extra["source"] = serde_json::json!("purchased");
        extra["label"] = serde_json::json!("Extra usage");
        let mut unknown = account["allowances"][0].clone();
        unknown["id"] = serde_json::json!("dynamic-window/42");
        unknown["usedPercent"] = serde_json::Value::Null;
        unknown["status"] = serde_json::json!("unknown");
        let mut zero = unknown.clone();
        zero["id"] = serde_json::json!("zero-window");
        zero["usedPercent"] = serde_json::json!(0.0);
        zero["status"] = serde_json::json!("ok");
        account["allowances"]
            .as_array_mut()
            .unwrap()
            .extend([extra, unknown, zero]);

        for (rules, alert_count, statuses, budget_status, condition_states) in [
            (
                serde_json::json!({
                    "plan": {"warnAt": 80}, "purchased": {"at": 80},
                    "today": {"at": 50}, "budget": {"today": 100}
                }),
                4,
                ["warning", "warning", "warning", "unknown", "ok"],
                "warning",
                vec![
                    "crossed", "crossed", "crossed", "crossed", "unknown", "clear",
                ],
            ),
            (
                serde_json::json!({
                    "plan": {"at": 80},
                    "planWindows": {"claude-weekly": {}, "claude-session": {"at": 100}},
                    "purchased": {"at": 80}, "today": {"at": 50}, "budget": {"today": 100}
                }),
                3,
                ["ok", "warning", "warning", "unknown", "ok"],
                "warning",
                vec!["crossed", "crossed", "crossed", "unknown", "clear"],
            ),
            (
                serde_json::json!({
                    "planWindows": {
                        "claude-weekly": {"at": 80}, "claude-session": {},
                        "dynamic-window/42": {"at": 0}
                    },
                    "budget": {"today": 100}
                }),
                1,
                ["warning", "ok", "ok", "unknown", "ok"],
                "ok",
                vec!["crossed", "unknown"],
            ),
        ] {
            let request = CString::new(
                serde_json::json!({
                    "snapshot": snapshot,
                    "settings": {"connections": {"anthropic.plan": rules}}
                })
                .to_string(),
            )
            .expect("request has no null bytes");
            let value = unsafe { ward_pulse_apply_alert_settings_result_json(request.as_ptr()) };
            assert!(!value.is_null());
            let result: serde_json::Value = serde_json::from_str(
                unsafe { CStr::from_ptr(value) }
                    .to_str()
                    .expect("result is UTF-8"),
            )
            .expect("parse result JSON");
            unsafe { ward_pulse_string_free(value) };

            assert_eq!(result["status"], "success");
            assert_eq!(result.as_object().unwrap().len(), 2);
            let applied: serde_json::Value =
                serde_json::from_str(result["dashboardJson"].as_str().expect("dashboard JSON"))
                    .expect("parse dashboard JSON");
            assert_eq!(applied["alerts"].as_array().unwrap().len(), alert_count);
            let conditions = applied["alertConditions"].as_array().unwrap();
            assert_eq!(
                conditions
                    .iter()
                    .map(|condition| condition["state"].as_str().unwrap())
                    .collect::<Vec<_>>(),
                condition_states
            );
            assert_eq!(
                conditions
                    .iter()
                    .filter_map(|condition| condition.get("alert"))
                    .cloned()
                    .collect::<Vec<_>>(),
                *applied["alerts"].as_array().unwrap()
            );
            let decoded: DashboardSnapshot = serde_json::from_value(applied.clone()).unwrap();
            assert_eq!(serde_json::to_value(decoded).unwrap(), applied);
            let account = &applied["accounts"][0];
            assert_eq!(account["status"], "warning");
            assert_eq!(account["today"]["usedPercent"], 50.0);
            assert_eq!(account["today"]["status"], budget_status);
            assert_eq!(
                account["allowances"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .map(|window| window["status"].as_str().unwrap())
                    .collect::<Vec<_>>(),
                statuses
            );
            assert!(applied["todayTotal"]["usedPercent"].is_null());
            assert!(applied["watchSummary"]["todayUsedPercent"].is_null());
        }
    }

    #[test]
    fn merge_api_describes_invalid_snapshot_json() {
        let error = merge_dashboard_snapshots_json("{}").expect_err("reject invalid snapshots");

        assert!(error
            .to_string()
            .contains("failed to deserialize dashboard snapshots"));
    }

    #[test]
    fn result_api_describes_invalid_openai_report_json() {
        let request = CString::new("{}").expect("request has no null bytes");

        let value = unsafe { ward_pulse_openai_dashboard_snapshot_result_json(request.as_ptr()) };
        assert!(!value.is_null());

        let result: serde_json::Value = serde_json::from_str(
            unsafe { CStr::from_ptr(value) }
                .to_str()
                .expect("result is UTF-8"),
        )
        .expect("parse result JSON");
        assert_eq!(result["status"], "error");
        assert!(result["message"]
            .as_str()
            .expect("error message")
            .contains("invalid OpenAI report JSON"));

        unsafe { ward_pulse_string_free(value) };
    }
}
