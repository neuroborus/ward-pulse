use std::error::Error as StdError;
use std::ffi::{c_char, CStr, CString};
use std::fmt;
use std::ptr;

use ward_pulse_core::build_dashboard_snapshot;
use ward_pulse_core::model::DashboardSnapshot;
use ward_pulse_providers::codex::{codex_provider_snapshot_from_report_json, CodexReportError};
use ward_pulse_providers::mock::{
    mock_provider_snapshot_from_usage_fixture, MockUsageFixtureError,
};
use ward_pulse_providers::openai::{openai_provider_snapshot_from_report_json, OpenAiReportError};

const MOCK_USAGE_TODAY_FIXTURE: &str =
    include_str!("../../../fixtures/providers/mock/usage_today.json");

#[derive(Debug)]
enum DashboardSnapshotJsonError {
    Codex(CodexReportError),
    Fixture(MockUsageFixtureError),
    OpenAi(OpenAiReportError),
    EmptySnapshots,
    Deserialize(serde_json::Error),
    Serialize(serde_json::Error),
}

impl fmt::Display for DashboardSnapshotJsonError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Codex(error) => {
                write!(formatter, "failed to normalize Codex report: {error}")
            }
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
        }
    }
}

impl StdError for DashboardSnapshotJsonError {
    fn source(&self) -> Option<&(dyn StdError + 'static)> {
        match self {
            Self::Codex(error) => Some(error),
            Self::Fixture(error) => Some(error),
            Self::OpenAi(error) => Some(error),
            Self::EmptySnapshots => None,
            Self::Deserialize(error) | Self::Serialize(error) => Some(error),
        }
    }
}

fn codex_dashboard_snapshot_json(report_json: &str) -> Result<String, DashboardSnapshotJsonError> {
    let report = codex_provider_snapshot_from_report_json(report_json)
        .map_err(DashboardSnapshotJsonError::Codex)?;
    let snapshot = build_dashboard_snapshot(report.generated_at, vec![report.provider_snapshot]);

    serde_json::to_string(&snapshot).map_err(DashboardSnapshotJsonError::Serialize)
}

fn dashboard_snapshot_json() -> Result<String, DashboardSnapshotJsonError> {
    let fixture = mock_provider_snapshot_from_usage_fixture("mock-local", MOCK_USAGE_TODAY_FIXTURE)
        .map_err(DashboardSnapshotJsonError::Fixture)?;
    let snapshot = build_dashboard_snapshot(fixture.generated_at, vec![fixture.provider_snapshot]);

    serde_json::to_string(&snapshot).map_err(DashboardSnapshotJsonError::Serialize)
}

fn openai_dashboard_snapshot_json(report_json: &str) -> Result<String, DashboardSnapshotJsonError> {
    let report = openai_provider_snapshot_from_report_json(report_json)
        .map_err(DashboardSnapshotJsonError::OpenAi)?;
    let snapshot = build_dashboard_snapshot(report.generated_at, vec![report.provider_snapshot]);

    serde_json::to_string(&snapshot).map_err(DashboardSnapshotJsonError::Serialize)
}

fn merge_dashboard_snapshots_json(
    snapshots_json: &str,
) -> Result<String, DashboardSnapshotJsonError> {
    let snapshots: Vec<DashboardSnapshot> =
        serde_json::from_str(snapshots_json).map_err(DashboardSnapshotJsonError::Deserialize)?;
    let generated_at = snapshots
        .iter()
        .map(|snapshot| &snapshot.generated_at)
        .max_by(|left, right| left.as_str().cmp(right.as_str()))
        .cloned()
        .ok_or(DashboardSnapshotJsonError::EmptySnapshots)?;
    let accounts = snapshots
        .into_iter()
        .flat_map(|snapshot| snapshot.accounts)
        .collect();
    let snapshot = build_dashboard_snapshot(generated_at, accounts);

    serde_json::to_string(&snapshot).map_err(DashboardSnapshotJsonError::Serialize)
}

fn openai_dashboard_snapshot_result_json(report_json: &str) -> Option<String> {
    let result = match openai_dashboard_snapshot_json(report_json) {
        Ok(dashboard_json) => serde_json::json!({
            "status": "success",
            "dashboardJson": dashboard_json,
        }),
        Err(error) => serde_json::json!({
            "status": "error",
            "message": error.to_string(),
        }),
    };

    serde_json::to_string(&result).ok()
}

fn codex_dashboard_snapshot_result_json(report_json: &str) -> Option<String> {
    let result = match codex_dashboard_snapshot_json(report_json) {
        Ok(dashboard_json) => serde_json::json!({
            "status": "success",
            "dashboardJson": dashboard_json,
        }),
        Err(error) => serde_json::json!({
            "status": "error",
            "message": error.to_string(),
        }),
    };

    serde_json::to_string(&result).ok()
}

fn merge_dashboard_snapshots_result_json(snapshots_json: &str) -> Option<String> {
    let result = match merge_dashboard_snapshots_json(snapshots_json) {
        Ok(dashboard_json) => serde_json::json!({
            "status": "success",
            "dashboardJson": dashboard_json,
        }),
        Err(error) => serde_json::json!({
            "status": "error",
            "message": error.to_string(),
        }),
    };

    serde_json::to_string(&result).ok()
}

#[no_mangle]
pub extern "C" fn ward_pulse_dashboard_snapshot_json() -> *mut c_char {
    match std::panic::catch_unwind(|| {
        dashboard_snapshot_json()
            .ok()
            .and_then(|snapshot| CString::new(snapshot).ok())
    }) {
        Ok(Some(snapshot)) => snapshot.into_raw(),
        Ok(None) | Err(_) => ptr::null_mut(),
    }
}

/// Normalizes OpenAI reporting pages into an owned dashboard snapshot JSON string.
///
/// # Safety
///
/// `report_json` must be a non-null pointer to a valid, null-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn ward_pulse_openai_dashboard_snapshot_json(
    report_json: *const c_char,
) -> *mut c_char {
    if report_json.is_null() {
        return ptr::null_mut();
    }

    match std::panic::catch_unwind(|| {
        let report_json = unsafe { CStr::from_ptr(report_json) }.to_str().ok()?;
        openai_dashboard_snapshot_json(report_json)
            .ok()
            .and_then(|snapshot| CString::new(snapshot).ok())
    }) {
        Ok(Some(snapshot)) => snapshot.into_raw(),
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
    if report_json.is_null() {
        return ptr::null_mut();
    }

    match std::panic::catch_unwind(|| {
        let report_json = unsafe { CStr::from_ptr(report_json) }.to_str().ok()?;
        openai_dashboard_snapshot_result_json(report_json)
            .and_then(|result| CString::new(result).ok())
    }) {
        Ok(Some(result)) => result.into_raw(),
        Ok(None) | Err(_) => ptr::null_mut(),
    }
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
    if report_json.is_null() {
        return ptr::null_mut();
    }

    match std::panic::catch_unwind(|| {
        let report_json = unsafe { CStr::from_ptr(report_json) }.to_str().ok()?;
        codex_dashboard_snapshot_result_json(report_json)
            .and_then(|result| CString::new(result).ok())
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
    if snapshots_json.is_null() {
        return ptr::null_mut();
    }

    match std::panic::catch_unwind(|| {
        let snapshots_json = unsafe { CStr::from_ptr(snapshots_json) }.to_str().ok()?;
        merge_dashboard_snapshots_result_json(snapshots_json)
            .and_then(|result| CString::new(result).ok())
    }) {
        Ok(Some(result)) => result.into_raw(),
        Ok(None) | Err(_) => ptr::null_mut(),
    }
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
    }

    #[test]
    fn c_api_returns_owned_snapshot_json() {
        let value = ward_pulse_dashboard_snapshot_json();
        assert!(!value.is_null());

        let json = unsafe { CStr::from_ptr(value) }
            .to_str()
            .expect("dashboard snapshot is UTF-8");
        let snapshot: serde_json::Value =
            serde_json::from_str(json).expect("parse dashboard snapshot JSON");
        assert_eq!(snapshot["accounts"][0]["accountId"], "mock-local");

        unsafe { ward_pulse_string_free(value) };
    }

    #[test]
    fn c_api_accepts_null_free() {
        unsafe { ward_pulse_string_free(ptr::null_mut()) };
    }

    #[test]
    fn c_api_normalizes_openai_report_json() {
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

        let value = unsafe { ward_pulse_openai_dashboard_snapshot_json(request.as_ptr()) };
        assert!(!value.is_null());

        let snapshot: serde_json::Value = serde_json::from_str(
            unsafe { CStr::from_ptr(value) }
                .to_str()
                .expect("dashboard snapshot is UTF-8"),
        )
        .expect("parse dashboard snapshot JSON");
        assert_eq!(snapshot["accounts"][0]["provider"], "openai");
        assert_eq!(snapshot["todayTotal"]["spent"]["minorUnits"], 50);

        unsafe { ward_pulse_string_free(value) };
    }

    #[test]
    fn c_api_rejects_invalid_openai_report_json() {
        let request = CString::new("{}").expect("request has no null bytes");

        let value = unsafe { ward_pulse_openai_dashboard_snapshot_json(request.as_ptr()) };

        assert!(value.is_null());
    }

    #[test]
    fn result_api_normalizes_codex_report_json() {
        let request = CString::new(include_str!(
            "../../../fixtures/providers/codex/report.json"
        ))
        .expect("request has no null bytes");

        let value = unsafe { ward_pulse_codex_dashboard_snapshot_result_json(request.as_ptr()) };
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
        assert_eq!(snapshot["accounts"][0]["provider"], "codex");
        assert_eq!(
            snapshot["accounts"][0]["allowances"][0]["usedPercent"],
            84.0
        );

        unsafe { ward_pulse_string_free(value) };
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
