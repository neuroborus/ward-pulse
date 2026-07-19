use std::error::Error as StdError;
use std::ffi::{c_char, CStr, CString};
use std::fmt;
use std::ptr;

use ward_pulse_core::build_dashboard_snapshot;
use ward_pulse_providers::mock::{
    mock_provider_snapshot_from_usage_fixture, MockUsageFixtureError,
};
use ward_pulse_providers::openai::{openai_provider_snapshot_from_report_json, OpenAiReportError};

const MOCK_USAGE_TODAY_FIXTURE: &str =
    include_str!("../../../fixtures/providers/mock/usage_today.json");

#[derive(Debug)]
enum DashboardSnapshotJsonError {
    Fixture(MockUsageFixtureError),
    OpenAi(OpenAiReportError),
    Json(serde_json::Error),
}

impl fmt::Display for DashboardSnapshotJsonError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Fixture(error) => {
                write!(formatter, "failed to build dashboard snapshot: {error}")
            }
            Self::OpenAi(error) => {
                write!(formatter, "failed to normalize OpenAI report: {error}")
            }
            Self::Json(error) => {
                write!(formatter, "failed to serialize dashboard snapshot: {error}")
            }
        }
    }
}

impl StdError for DashboardSnapshotJsonError {
    fn source(&self) -> Option<&(dyn StdError + 'static)> {
        match self {
            Self::Fixture(error) => Some(error),
            Self::OpenAi(error) => Some(error),
            Self::Json(error) => Some(error),
        }
    }
}

fn dashboard_snapshot_json() -> Result<String, DashboardSnapshotJsonError> {
    let fixture = mock_provider_snapshot_from_usage_fixture("mock-local", MOCK_USAGE_TODAY_FIXTURE)
        .map_err(DashboardSnapshotJsonError::Fixture)?;
    let snapshot = build_dashboard_snapshot(fixture.generated_at, vec![fixture.provider_snapshot]);

    serde_json::to_string(&snapshot).map_err(DashboardSnapshotJsonError::Json)
}

fn openai_dashboard_snapshot_json(report_json: &str) -> Result<String, DashboardSnapshotJsonError> {
    let report = openai_provider_snapshot_from_report_json(report_json)
        .map_err(DashboardSnapshotJsonError::OpenAi)?;
    let snapshot = build_dashboard_snapshot(report.generated_at, vec![report.provider_snapshot]);

    serde_json::to_string(&snapshot).map_err(DashboardSnapshotJsonError::Json)
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
}
