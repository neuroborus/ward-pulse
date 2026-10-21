//! Cursor team Admin API normalization (`/teams/daily-usage-data`, `/teams/spend`).

use std::collections::BTreeMap;
use std::error::Error as StdError;
use std::fmt;

use serde::Deserialize;
use ward_pulse_core::budget::calculate_budget_state;
use ward_pulse_core::model::{
    connection, BudgetPeriod, Money, ProviderKind, ProviderSnapshot, ProviderStatus, UsageBucket,
};
use ward_pulse_core::time::DateTimeUtc;

#[derive(Clone, Debug, PartialEq)]
pub struct CursorPlatformReportSnapshot {
    pub generated_at: DateTimeUtc,
    pub provider_snapshot: ProviderSnapshot,
}

#[derive(Debug)]
pub enum CursorPlatformReportError {
    Json(serde_json::Error),
    InvalidDate,
    NumericOverflow,
}

impl fmt::Display for CursorPlatformReportError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Json(error) => write!(
                formatter,
                "invalid Cursor Admin report JSON at line {} column {}",
                error.line(),
                error.column()
            ),
            Self::InvalidDate => formatter.write_str("invalid Cursor usage date"),
            Self::NumericOverflow => formatter.write_str("Cursor report value overflow"),
        }
    }
}

impl StdError for CursorPlatformReportError {
    fn source(&self) -> Option<&(dyn StdError + 'static)> {
        match self {
            Self::Json(error) => Some(error),
            Self::InvalidDate | Self::NumericOverflow => None,
        }
    }
}

/// Normalizes sanitized Cursor team Admin daily-usage and spend pages.
pub fn cursor_platform_snapshot_from_report_json(
    report_json: &str,
) -> Result<CursorPlatformReportSnapshot, CursorPlatformReportError> {
    let report: RawReport =
        serde_json::from_str(report_json).map_err(CursorPlatformReportError::Json)?;

    let mut requests_by_day = BTreeMap::<String, Option<u64>>::new();
    for page_json in &report.daily_usage_pages {
        let page: RawDailyUsagePage =
            serde_json::from_str(page_json).map_err(CursorPlatformReportError::Json)?;
        for row in page.data {
            let day = row.day.ok_or(CursorPlatformReportError::InvalidDate)?;
            // Funding channels count raw events; feature counters overlap those events.
            let requests = match (
                row.subscription_included_reqs,
                row.usage_based_reqs,
                row.api_key_reqs,
            ) {
                (Some(included), Some(usage_based), Some(api_key)) => {
                    Some(included.saturating_add(usage_based).saturating_add(api_key))
                }
                _ => None,
            };
            let entry = requests_by_day.entry(day).or_insert(Some(0));
            *entry = entry
                .zip(requests)
                .map(|(total, requests)| total.saturating_add(requests));
        }
    }

    let mut spend_cents = 0_i64;
    let mut complete_spend = !report.spend_pages.is_empty();
    for page_json in &report.spend_pages {
        let page: RawSpendPage =
            serde_json::from_str(page_json).map_err(CursorPlatformReportError::Json)?;
        let Some(members) = page.team_member_spend else {
            complete_spend = false;
            continue;
        };
        for member in members {
            let cents = member.overall_spend_cents.or_else(|| {
                member
                    .included_spend_cents
                    .zip(member.spend_cents)
                    .map(|(included, on_demand)| included + on_demand)
            });
            let Some(cents) = cents else {
                complete_spend = false;
                continue;
            };
            let cents = cents.round();
            // i64::MAX rounds to 2^63 as f64, so the upper bound must be exclusive.
            if !cents.is_finite() || !(i64::MIN as f64..-(i64::MIN as f64)).contains(&cents) {
                return Err(CursorPlatformReportError::NumericOverflow);
            }
            spend_cents = spend_cents
                .checked_add(cents as i64)
                .ok_or(CursorPlatformReportError::NumericOverflow)?;
        }
    }

    let buckets = requests_by_day
        .into_iter()
        .map(|(day, requests)| {
            let end = next_date(&day)?;
            Ok(UsageBucket {
                start_at: DateTimeUtc::new(format!("{day}T00:00:00Z")),
                end_at: DateTimeUtc::new(format!("{end}T00:00:00Z")),
                cost: None,
                input_tokens: None,
                output_tokens: None,
                cached_tokens: None,
                total_tokens: None,
                requests,
                model: None,
                project: None,
                user: None,
            })
        })
        .collect::<Result<Vec<_>, _>>()?;

    let spent = complete_spend.then(|| Money::minor_units(spend_cents, "USD"));
    // `/teams/spend` is billing-cycle scoped, not day/week. Leave shorter periods unknown.
    let unknown = |period| calculate_budget_state(period, None, None, None);

    Ok(CursorPlatformReportSnapshot {
        generated_at: report.generated_at.clone(),
        provider_snapshot: ProviderSnapshot {
            account_id: report.account_id,
            provider: ProviderKind::Cursor,
            connection: Some(connection::CURSOR_PLATFORM.to_string()),
            status: ProviderStatus::Ok,
            today: unknown(BudgetPeriod::Today),
            week: unknown(BudgetPeriod::Week),
            month: calculate_budget_state(BudgetPeriod::Month, spent, None, None),
            credits: Vec::new(),
            allowances: Vec::new(),
            buckets,
            model_breakdown: Vec::new(),
            last_successful_sync_at: Some(report.generated_at),
            last_error: None,
        },
    })
}

fn next_date(value: &str) -> Result<String, CursorPlatformReportError> {
    let mut parts = value.split('-');
    let mut year = parts
        .next()
        .and_then(|part| part.parse::<u32>().ok())
        .ok_or(CursorPlatformReportError::InvalidDate)?;
    let mut month = parts
        .next()
        .and_then(|part| part.parse::<u32>().ok())
        .ok_or(CursorPlatformReportError::InvalidDate)?;
    let mut day = parts
        .next()
        .and_then(|part| part.parse::<u32>().ok())
        .ok_or(CursorPlatformReportError::InvalidDate)?;
    if parts.next().is_some() || !(1..=12).contains(&month) {
        return Err(CursorPlatformReportError::InvalidDate);
    }

    let days_in_month = match month {
        2 if year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) => 29,
        2 => 28,
        4 | 6 | 9 | 11 => 30,
        _ => 31,
    };
    if day == 0 || day > days_in_month {
        return Err(CursorPlatformReportError::InvalidDate);
    }

    if day < days_in_month {
        day += 1;
    } else if month < 12 {
        month += 1;
        day = 1;
    } else {
        year = year
            .checked_add(1)
            .ok_or(CursorPlatformReportError::InvalidDate)?;
        month = 1;
        day = 1;
    }

    Ok(format!("{year:04}-{month:02}-{day:02}"))
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawReport {
    account_id: String,
    generated_at: DateTimeUtc,
    daily_usage_pages: Vec<String>,
    spend_pages: Vec<String>,
}

#[derive(Debug, Deserialize)]
struct RawDailyUsagePage {
    data: Vec<RawDailyUsageRow>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawDailyUsageRow {
    #[serde(default)]
    day: Option<String>,
    #[serde(default)]
    subscription_included_reqs: Option<u64>,
    #[serde(default)]
    usage_based_reqs: Option<u64>,
    #[serde(default)]
    api_key_reqs: Option<u64>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawSpendPage {
    #[serde(default, alias = "teamMembers")]
    team_member_spend: Option<Vec<RawSpendMember>>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawSpendMember {
    #[serde(default)]
    overall_spend_cents: Option<f64>,
    #[serde(default)]
    included_spend_cents: Option<f64>,
    #[serde(default)]
    spend_cents: Option<f64>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_daily_usage_and_spend() {
        let daily = include_str!("../../../../fixtures/providers/cursor/daily_usage.json");
        let spend = include_str!("../../../../fixtures/providers/cursor/spend.json");
        let report = serde_json::json!({
            "accountId": "cursor-team-local",
            "generatedAt": "2026-07-19T12:00:00Z",
            "dailyUsagePages": [daily],
            "spendPages": [spend]
        })
        .to_string();

        let snapshot =
            cursor_platform_snapshot_from_report_json(&report).expect("normalize Cursor platform");
        assert_eq!(snapshot.provider_snapshot.provider, ProviderKind::Cursor);
        assert_eq!(
            snapshot.provider_snapshot.month.spent,
            Some(Money::minor_units(4326, "USD"))
        );
        assert!(snapshot.provider_snapshot.today.spent.is_none());
        assert!(snapshot.provider_snapshot.week.spent.is_none());
        assert_eq!(
            snapshot
                .provider_snapshot
                .buckets
                .iter()
                .map(|bucket| bucket.requests)
                .collect::<Vec<_>>(),
            vec![Some(45), Some(64)]
        );
    }

    #[test]
    fn normalizes_complete_spend_shapes() {
        for collection in ["teamMemberSpend", "teamMembers"] {
            for (members, expected) in [
                (serde_json::json!([]), 0),
                (
                    serde_json::json!([{"includedSpendCents": 12.25, "spendCents": 7.25}]),
                    20,
                ),
                (
                    serde_json::json!([
                        {"overallSpendCents": 8.5, "includedSpendCents": 100, "spendCents": 200},
                        {"overallSpendCents": 0, "includedSpendCents": 100, "spendCents": 200}
                    ]),
                    9,
                ),
                (
                    serde_json::json!([{"includedSpendCents": 0, "spendCents": 0}]),
                    0,
                ),
                (
                    serde_json::json!([
                        {"overallSpendCents": 0.5},
                        {"overallSpendCents": null, "includedSpendCents": 0.25, "spendCents": 0.25}
                    ]),
                    2,
                ),
                (
                    serde_json::json!([{"includedSpendCents": -0.25, "spendCents": -0.25}]),
                    -1,
                ),
            ] {
                let mut page = serde_json::json!({});
                page[collection] = members;
                let report = serde_json::json!({
                    "accountId": "team-local",
                    "generatedAt": "2026-07-19T12:00:00Z",
                    "dailyUsagePages": [],
                    "spendPages": [page.to_string()]
                })
                .to_string();
                let snapshot = cursor_platform_snapshot_from_report_json(&report)
                    .expect("normalize complete spend");
                assert_eq!(
                    snapshot.provider_snapshot.month.spent,
                    Some(Money::minor_units(expected, "USD")),
                    "{page}"
                );
                assert!(snapshot.provider_snapshot.today.spent.is_none());
                assert!(snapshot.provider_snapshot.week.spent.is_none());
            }
        }
    }

    #[test]
    fn preserves_unknown_spend_across_members_and_pages() {
        let known = r#"{"teamMemberSpend":[{"overallSpendCents":5}]}"#;
        for pages in [
            vec![],
            vec![known, "{}", known],
            vec![known, r#"{"teamMemberSpend":null}"#, known],
            vec![known, r#"{"teamMembers":null}"#, known],
            vec![r#"{"teamMemberSpend":[{"overallSpendCents":5},{}]}"#],
            vec![r#"{"teamMemberSpend":[{"overallSpendCents":null}]}"#],
            vec![r#"{"teamMemberSpend":[{"includedSpendCents":5}]}"#],
            vec![r#"{"teamMemberSpend":[{"spendCents":5}]}"#],
            vec![r#"{"teamMemberSpend":[{"includedSpendCents":null,"spendCents":0}]}"#],
            vec![known, r#"{"teamMembers":[{}]}"#, known],
        ] {
            let report = serde_json::json!({
                "accountId": "team-local",
                "generatedAt": "2026-07-19T12:00:00Z",
                "dailyUsagePages": [],
                "spendPages": pages
            })
            .to_string();
            let snapshot = cursor_platform_snapshot_from_report_json(&report)
                .expect("normalize incomplete spend");
            assert!(snapshot.provider_snapshot.month.spent.is_none(), "{report}");
        }
    }

    #[test]
    fn rejects_malformed_spend_collections() {
        for page in [
            r#"{"teamMemberSpend":{}}"#,
            r#"{"teamMembers":1}"#,
            r#"{"teamMemberSpend":[null]}"#,
        ] {
            let report = serde_json::json!({
                "accountId": "team-local",
                "generatedAt": "2026-07-19T12:00:00Z",
                "dailyUsagePages": [],
                "spendPages": [page]
            })
            .to_string();
            assert!(matches!(
                cursor_platform_snapshot_from_report_json(&report),
                Err(CursorPlatformReportError::Json(_))
            ));
        }
    }

    #[test]
    fn checks_spend_conversion_and_aggregate_bounds() {
        // The largest f64 below 2^63 is 2^63 - 1024; -2^63 is exactly representable.
        for cents in [9_223_372_036_854_774_784_i64, i64::MIN] {
            let report = serde_json::json!({
                "accountId": "team-local",
                "generatedAt": "2026-07-19T12:00:00Z",
                "dailyUsagePages": [],
                "spendPages": [serde_json::json!({
                    "teamMemberSpend": [{"overallSpendCents": cents}]
                }).to_string()]
            })
            .to_string();
            let snapshot = cursor_platform_snapshot_from_report_json(&report)
                .expect("normalize representable spend boundary");
            assert_eq!(
                snapshot.provider_snapshot.month.spent,
                Some(Money::minor_units(cents, "USD"))
            );
        }

        for pages in [
            vec![r#"{"teamMemberSpend":[{"overallSpendCents":9223372036854775808}]}"#],
            vec![r#"{"teamMemberSpend":[{"overallSpendCents":-9223372036854777856}]}"#],
            vec![
                r#"{"teamMemberSpend":[{"includedSpendCents":4611686018427387904,"spendCents":4611686018427387904}]}"#,
            ],
            vec![r#"{"teamMemberSpend":[{"includedSpendCents":1e308,"spendCents":1e308}]}"#],
            vec![
                r#"{"teamMemberSpend":[{"overallSpendCents":9223372036854774784},{"overallSpendCents":1024}]}"#,
            ],
            vec![
                r#"{"teamMemberSpend":[{"overallSpendCents":-9223372036854775808}]}"#,
                r#"{"teamMemberSpend":[{"overallSpendCents":-1}]}"#,
            ],
        ] {
            let report = serde_json::json!({
                "accountId": "team-local",
                "generatedAt": "2026-07-19T12:00:00Z",
                "dailyUsagePages": [],
                "spendPages": pages
            })
            .to_string();
            assert!(
                matches!(
                    cursor_platform_snapshot_from_report_json(&report),
                    Err(CursorPlatformReportError::NumericOverflow)
                ),
                "{report}"
            );
        }
    }

    #[test]
    fn preserves_canonical_zero_and_saturates_raw_event_counts() {
        let report = serde_json::json!({
            "accountId": "team-local",
            "generatedAt": "2027-01-01T12:00:00Z",
            "dailyUsagePages": [
                serde_json::json!({"data": [
                    {"day": "2026-12-31", "subscriptionIncludedReqs": 0,
                     "usageBasedReqs": 0, "apiKeyReqs": 0,
                     "composerRequests": 2, "chatRequests": 3, "agentRequests": 4},
                    {"day": "2027-01-01", "subscriptionIncludedReqs": u64::MAX,
                     "usageBasedReqs": 1, "apiKeyReqs": 1}
                ]}).to_string(),
                serde_json::json!({"data": [
                    {"day": "2027-01-01", "subscriptionIncludedReqs": 1,
                     "usageBasedReqs": 0, "apiKeyReqs": 0}
                ]}).to_string()
            ],
            "spendPages": []
        })
        .to_string();
        let snapshot = cursor_platform_snapshot_from_report_json(&report)
            .expect("normalize funding-channel counts");
        let buckets = snapshot.provider_snapshot.buckets;
        assert_eq!(buckets.len(), 2);
        assert_eq!(buckets[0].requests, Some(0));
        assert_eq!(buckets[0].start_at.as_str(), "2026-12-31T00:00:00Z");
        assert_eq!(buckets[0].end_at.as_str(), "2027-01-01T00:00:00Z");
        assert_eq!(buckets[1].requests, Some(u64::MAX));
    }

    #[test]
    fn preserves_unknown_daily_counts_across_rows_and_pages() {
        for mut incomplete in [
            serde_json::json!({}),
            serde_json::json!({"composerRequests": 2, "chatRequests": 3, "agentRequests": 4}),
            serde_json::json!({"subscriptionIncludedReqs": 2, "usageBasedReqs": 3}),
            serde_json::json!({"subscriptionIncludedReqs": 2, "apiKeyReqs": 4}),
            serde_json::json!({"usageBasedReqs": 3, "apiKeyReqs": 4}),
            serde_json::json!({"subscriptionIncludedReqs": null, "usageBasedReqs": 0, "apiKeyReqs": 0}),
        ] {
            incomplete["day"] = serde_json::json!("2026-07-18");
            let complete = serde_json::json!({
                "day": "2026-07-18", "subscriptionIncludedReqs": 2,
                "usageBasedReqs": 3, "apiKeyReqs": 4
            });
            let report = serde_json::json!({
                "accountId": "team-local",
                "generatedAt": "2026-07-19T12:00:00Z",
                "dailyUsagePages": [
                    serde_json::json!({"data": [complete]}).to_string(),
                    serde_json::json!({"data": [incomplete, complete,
                        {"day": "2026-07-19", "subscriptionIncludedReqs": 1,
                         "usageBasedReqs": 0, "apiKeyReqs": 0}
                    ]}).to_string()
                ],
                "spendPages": []
            })
            .to_string();
            let snapshot = cursor_platform_snapshot_from_report_json(&report)
                .expect("normalize incomplete funding-channel counts");
            assert_eq!(snapshot.provider_snapshot.buckets.len(), 2);
            assert_eq!(
                snapshot.provider_snapshot.buckets[0].requests, None,
                "{report}"
            );
            assert_eq!(snapshot.provider_snapshot.buckets[1].requests, Some(1));
        }
    }
}
