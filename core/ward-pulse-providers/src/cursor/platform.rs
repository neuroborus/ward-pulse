//! Cursor team daily history and extra-paid calendar usage-event normalization.

use std::collections::BTreeMap;
use std::error::Error as StdError;
use std::fmt;

use serde::Deserialize;
use serde_json::{Number, Value};
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
    InvalidReport,
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
            Self::InvalidReport => formatter.write_str("invalid Cursor usage-event report"),
            Self::NumericOverflow => formatter.write_str("Cursor report value overflow"),
        }
    }
}

impl StdError for CursorPlatformReportError {
    fn source(&self) -> Option<&(dyn StdError + 'static)> {
        match self {
            Self::Json(error) => Some(error),
            Self::InvalidDate | Self::InvalidReport | Self::NumericOverflow => None,
        }
    }
}

/// Normalizes sanitized team reports without inferring charges from included usage.
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

    let spend = calendar_spend(&report)?;

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

    Ok(CursorPlatformReportSnapshot {
        generated_at: report.generated_at.clone(),
        provider_snapshot: ProviderSnapshot {
            account_id: report.account_id,
            provider: ProviderKind::Cursor,
            connection: Some(connection::CURSOR_PLATFORM.to_string()),
            status: ProviderStatus::Ok,
            today: calculate_budget_state(BudgetPeriod::Today, spend[0].clone(), None, None),
            week: calculate_budget_state(BudgetPeriod::Week, spend[1].clone(), None, None),
            month: calculate_budget_state(BudgetPeriod::Month, spend[2].clone(), None, None),
            credits: Vec::new(),
            allowances: Vec::new(),
            buckets,
            model_breakdown: Vec::new(),
            last_successful_sync_at: Some(report.generated_at),
            last_error: None,
        },
    })
}

fn calendar_spend(report: &RawReport) -> Result<[Option<Money>; 3], CursorPlatformReportError> {
    use CursorPlatformReportError::{InvalidDate, InvalidReport, NumericOverflow};
    let starts = [
        report.today_start_ms,
        report.week_start_ms,
        report.month_start_ms,
    ];
    if report.request_start_ms != report.week_start_ms.min(report.month_start_ms)
        || report.today_start_ms < report.week_start_ms
        || report.today_start_ms < report.month_start_ms
    {
        return Err(InvalidReport);
    }
    if report.usage_event_pages.is_empty() {
        return Ok([None, None, None]);
    }
    if report.request_start_ms >= report.end_exclusive_ms || report.usage_event_pages.len() > 100 {
        return Err(InvalidReport);
    }
    let mut advertised = None;
    let mut rows = 0_i64;
    let mut terminal = false;
    let mut complete = true;
    let mut totals = [Decimal::ZERO; 3];
    for (index, raw) in report.usage_event_pages.iter().enumerate() {
        if terminal {
            return Err(InvalidReport);
        }
        let page: RawEventPage =
            serde_json::from_str(raw).map_err(CursorPlatformReportError::Json)?;
        let total = integral(&page.total_usage_events_count)?;
        let count = integral(&page.pagination.num_pages)?;
        let current = integral(&page.pagination.current_page)?;
        let size = integral(&page.pagination.page_size)?;
        let next = page.pagination.has_next_page;
        let previous = page.pagination.has_previous_page;
        if total < 0
            || size != 1000
            || page.usage_events.len() > 1000
            || integral(&page.period.start_date)? != report.request_start_ms
            || integral(&page.period.end_date)? != report.end_exclusive_ms - 1
        {
            return Err(InvalidReport);
        }
        let terminal_empty = index == 0
            && total == 0
            && page.usage_events.is_empty()
            && !next
            && !previous
            && (0..=1).contains(&count)
            && (0..=1).contains(&current);
        if !terminal_empty
            && (count < 1
                || current != index as i64 + 1
                || current > count
                || previous != (current > 1)
                || next != (current < count))
        {
            return Err(InvalidReport);
        }
        if advertised.is_some_and(|metadata| metadata != (count, size, total)) {
            return Err(InvalidReport);
        }
        advertised = Some((count, size, total));
        rows = rows
            .checked_add(page.usage_events.len() as i64)
            .ok_or(NumericOverflow)?;
        if rows > total || (!next && rows != total) {
            return Err(InvalidReport);
        }
        terminal = !next;
        for event in page.usage_events {
            let (Some(timestamp), Some(chargeable)) = (event.timestamp, event.is_chargeable) else {
                complete = false;
                continue;
            };
            let digits = timestamp.strip_prefix('-').unwrap_or(&timestamp);
            if digits.is_empty() || !digits.bytes().all(|byte| byte.is_ascii_digit()) {
                return Err(InvalidDate);
            }
            let timestamp = timestamp.parse::<i64>().map_err(|_| InvalidDate)?;
            if !chargeable {
                continue;
            }
            let Some(Value::Number(amount)) = event.charged_cents else {
                complete = false;
                continue;
            };
            let amount = Decimal::parse(&amount)?;
            for (start, sum) in starts.iter().zip(&mut totals) {
                if timestamp >= *start && timestamp < report.end_exclusive_ms {
                    sum.add(amount)?;
                }
            }
        }
    }
    if !terminal {
        return Err(InvalidReport);
    }
    let mut spent = [None, None, None];
    for ((start, total), money) in starts.iter().zip(totals).zip(&mut spent) {
        if complete && *start < report.end_exclusive_ms {
            *money = Some(Money::minor_units(total.round()?, "USD"));
        }
    }
    Ok(spent)
}

/// Decimal cents remain exact through summation; the public model receives rounded cents.
#[derive(Clone, Copy, Debug)]
struct Decimal {
    coefficient: i128,
    scale: u32,
}

impl Decimal {
    const ZERO: Self = Self {
        coefficient: 0,
        scale: 0,
    };

    fn parse(number: &Number) -> Result<Self, CursorPlatformReportError> {
        use CursorPlatformReportError::NumericOverflow;
        let raw = number.to_string();
        let (mantissa, exponent) = raw.split_once(['e', 'E']).unwrap_or((&raw, "0"));
        let negative = mantissa.starts_with('-');
        let mantissa = mantissa.trim_start_matches('-');
        let fraction = mantissa
            .split_once('.')
            .map_or(0, |(_, fraction)| fraction.len());
        let digits = mantissa.replace('.', "");
        let digits = digits.trim_start_matches('0');
        if digits.is_empty() {
            return Ok(Self::ZERO);
        }
        let significant = digits.trim_end_matches('0');
        let trailing = digits.len() - significant.len();
        let exponent = exponent.parse::<i64>().map_err(|_| NumericOverflow)?;
        let scale = (fraction as i64)
            .checked_sub(exponent)
            .and_then(|value| value.checked_sub(trailing as i64))
            .ok_or(NumericOverflow)?;
        let signed = if negative {
            format!("-{significant}")
        } else {
            significant.to_string()
        };
        let mut coefficient = signed.parse::<i128>().map_err(|_| NumericOverflow)?;
        let scale = if scale < 0 {
            let power = u32::try_from(scale.checked_neg().ok_or(NumericOverflow)?)
                .map_err(|_| NumericOverflow)?;
            coefficient = coefficient
                .checked_mul(power_of_ten(power)?)
                .ok_or(NumericOverflow)?;
            0
        } else {
            let scale = u32::try_from(scale).map_err(|_| NumericOverflow)?;
            power_of_ten(scale)?;
            scale
        };
        Ok(Self { coefficient, scale })
    }

    fn add(&mut self, other: Self) -> Result<(), CursorPlatformReportError> {
        use CursorPlatformReportError::NumericOverflow;
        let scale = self.scale.max(other.scale);
        let left = self
            .coefficient
            .checked_mul(power_of_ten(scale - self.scale)?);
        let right = other
            .coefficient
            .checked_mul(power_of_ten(scale - other.scale)?);
        self.coefficient = left
            .zip(right)
            .and_then(|(a, b)| a.checked_add(b))
            .ok_or(NumericOverflow)?;
        self.scale = scale;
        while self.scale > 0 && self.coefficient % 10 == 0 {
            self.coefficient /= 10;
            self.scale -= 1;
        }
        Ok(())
    }

    fn round(self) -> Result<i64, CursorPlatformReportError> {
        use CursorPlatformReportError::NumericOverflow;
        let divisor = power_of_ten(self.scale)?;
        let mut cents = self.coefficient / divisor;
        if self.scale > 0 && (self.coefficient % divisor).abs() >= divisor / 2 {
            cents = cents
                .checked_add(self.coefficient.signum())
                .ok_or(NumericOverflow)?;
        }
        i64::try_from(cents).map_err(|_| NumericOverflow)
    }
}

fn power_of_ten(scale: u32) -> Result<i128, CursorPlatformReportError> {
    10_i128
        .checked_pow(scale)
        .ok_or(CursorPlatformReportError::NumericOverflow)
}

fn integral(number: &Number) -> Result<i64, CursorPlatformReportError> {
    let decimal = Decimal::parse(number)?;
    let divisor = power_of_ten(decimal.scale)?;
    if decimal.coefficient % divisor != 0 {
        return Err(CursorPlatformReportError::InvalidReport);
    }
    i64::try_from(decimal.coefficient / divisor)
        .map_err(|_| CursorPlatformReportError::InvalidReport)
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
    usage_event_pages: Vec<String>,
    request_start_ms: i64,
    end_exclusive_ms: i64,
    today_start_ms: i64,
    week_start_ms: i64,
    month_start_ms: i64,
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
struct RawEventPage {
    usage_events: Vec<RawUsageEvent>,
    total_usage_events_count: Number,
    pagination: RawPagination,
    period: RawPeriod,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawUsageEvent {
    #[serde(default)]
    timestamp: Option<String>,
    #[serde(default)]
    is_chargeable: Option<bool>,
    #[serde(default)]
    charged_cents: Option<Value>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawPagination {
    num_pages: Number,
    current_page: Number,
    page_size: Number,
    has_next_page: bool,
    has_previous_page: bool,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawPeriod {
    start_date: Number,
    end_date: Number,
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    const MONTH: i64 = 1_782_864_000_000;
    const WEEK: i64 = 1_783_900_800_000;
    const TODAY: i64 = 1_784_419_200_000;
    const END: i64 = 1_784_462_400_000;

    fn event(timestamp: i64, cents: &str) -> Value {
        json!({"timestamp": timestamp.to_string(), "isChargeable": true,
            "chargedCents": serde_json::from_str::<Value>(cents).unwrap()})
    }

    fn pages(rows: Vec<Vec<Value>>) -> Vec<Value> {
        let total: usize = rows.iter().map(Vec::len).sum();
        let count = rows.len();
        rows.into_iter()
            .enumerate()
            .map(|(index, rows)| {
                json!({
                    "usageEvents": rows, "totalUsageEventsCount": total,
                    "pagination": {"numPages": count, "currentPage": index + 1,
                        "pageSize": 1000, "hasNextPage": index + 1 < count,
                        "hasPreviousPage": index > 0},
                    "period": {"startDate": MONTH, "endDate": END - 1}
                })
            })
            .collect()
    }

    fn envelope(pages: Vec<Value>) -> Value {
        json!({"accountId": "cursor-team-local", "generatedAt": "2026-07-19T12:00:00Z",
            "requestStartMs": MONTH, "endExclusiveMs": END, "todayStartMs": TODAY,
            "weekStartMs": WEEK, "monthStartMs": MONTH,
            "dailyUsagePages": [include_str!("../../../../fixtures/providers/cursor/daily_usage.json")],
            "usageEventPages": pages.into_iter().map(|page| page.to_string()).collect::<Vec<_>>()})
    }

    fn normalize(report: &Value) -> Result<ProviderSnapshot, CursorPlatformReportError> {
        cursor_platform_snapshot_from_report_json(&report.to_string())
            .map(|value| value.provider_snapshot)
    }

    fn amounts(snapshot: &ProviderSnapshot) -> [Option<i64>; 3] {
        [&snapshot.today, &snapshot.week, &snapshot.month].map(|budget| {
            budget.spent.as_ref().map(|money| {
                assert_eq!(money.currency, "USD");
                money.minor_units
            })
        })
    }

    #[test]
    fn normalizes_extra_paid_calendar_spend_and_preserves_daily_funding() {
        let page: Value = serde_json::from_str(include_str!(
            "../../../../fixtures/providers/cursor/usage_events.json"
        ))
        .unwrap();
        let snapshot = normalize(&envelope(vec![page])).unwrap();
        assert_eq!(amounts(&snapshot), [Some(20), Some(50), Some(4326)]);
        assert_eq!(snapshot.provider, ProviderKind::Cursor);
        assert_eq!(
            snapshot.connection.as_deref(),
            Some(connection::CURSOR_PLATFORM)
        );
        assert_eq!(
            snapshot
                .buckets
                .iter()
                .map(|bucket| bucket.requests)
                .collect::<Vec<_>>(),
            vec![Some(45), Some(64)]
        );
        assert!(snapshot
            .buckets
            .iter()
            .all(|bucket| bucket.model.is_none() && bucket.cost.is_none()));
        assert!(snapshot.model_breakdown.is_empty());
    }

    #[test]
    fn requires_explicit_classification_timestamp_and_chargeable_amounts() {
        let mut included = event(TODAY, "999");
        included["isChargeable"] = json!(false);
        included["chargedCents"] = json!("unused");
        assert_eq!(
            amounts(&normalize(&envelope(pages(vec![vec![included]]))).unwrap()),
            [Some(0); 3]
        );
        for key in ["timestamp", "isChargeable", "chargedCents"] {
            for null in [false, true] {
                let mut row = event(TODAY, "5");
                if null {
                    row[key] = Value::Null;
                } else {
                    row.as_object_mut().unwrap().remove(key);
                }
                let snapshot =
                    normalize(&envelope(pages(vec![vec![event(TODAY, "2"), row]]))).unwrap();
                assert_eq!(amounts(&snapshot), [None; 3], "missing {key}");
            }
        }
        let mut row = event(TODAY, "5");
        row["chargedCents"] = json!("5");
        assert_eq!(
            amounts(&normalize(&envelope(pages(vec![vec![row]]))).unwrap()),
            [None; 3]
        );
        for timestamp in [
            json!(TODAY),
            json!("2026-07-19T00:00:00Z"),
            json!("1784419200000.0"),
            json!(" 1784419200000"),
            json!("999999999999999999999999"),
        ] {
            let mut row = event(TODAY, "1");
            row["timestamp"] = timestamp;
            assert!(normalize(&envelope(pages(vec![vec![row]]))).is_err());
        }
    }

    #[test]
    fn counts_identical_events_across_partial_and_empty_pages() {
        let row = event(TODAY, "0.25");
        let snapshot =
            normalize(&envelope(pages(vec![vec![row.clone()], vec![], vec![row]]))).unwrap();
        assert_eq!(amounts(&snapshot), [Some(1); 3]);
        let snapshot = normalize(&envelope(pages(vec![vec![], vec![]]))).unwrap();
        assert_eq!(amounts(&snapshot), [Some(0); 3]);
    }

    #[test]
    fn validates_page_identity_counts_capacity_flags_and_numeric_echoes() {
        for (pointer, value) in [
            ("/pagination/currentPage", json!(2)),
            ("/pagination/currentPage", json!(0)),
            ("/pagination/numPages", json!(0)),
            ("/pagination/numPages", json!(1.5)),
            ("/pagination/pageSize", json!(100)),
            ("/pagination/hasNextPage", json!(true)),
            ("/pagination/hasPreviousPage", json!(true)),
            ("/pagination/hasNextPage", Value::Null),
            ("/totalUsageEventsCount", json!(-1)),
            ("/totalUsageEventsCount", json!(2)),
            ("/totalUsageEventsCount", json!(0.5)),
            ("/totalUsageEventsCount", json!("1")),
            ("/usageEvents", Value::Null),
            ("/period/startDate", json!(MONTH + 1)),
            ("/period/endDate", json!(END)),
            ("/period/startDate", json!(MONTH.to_string())),
        ] {
            let mut page = pages(vec![vec![event(TODAY, "1")]]).remove(0);
            *page.pointer_mut(pointer).unwrap() = value;
            assert!(normalize(&envelope(vec![page])).is_err(), "{pointer}");
        }
        for key in [
            "usageEvents",
            "totalUsageEventsCount",
            "pagination",
            "period",
        ] {
            let mut page = pages(vec![vec![event(TODAY, "1")]]).remove(0);
            page.as_object_mut().unwrap().remove(key);
            assert!(normalize(&envelope(vec![page])).is_err(), "{key}");
        }
        for key in [
            "numPages",
            "currentPage",
            "pageSize",
            "hasNextPage",
            "hasPreviousPage",
        ] {
            let mut page = pages(vec![vec![event(TODAY, "1")]]).remove(0);
            page["pagination"].as_object_mut().unwrap().remove(key);
            assert!(normalize(&envelope(vec![page])).is_err(), "{key}");
        }
        let mut oversized = pages(vec![vec![event(TODAY, "0"); 1001]]);
        assert!(normalize(&envelope(oversized.clone())).is_err());
        oversized[0]["usageEvents"] = json!([]);
        assert!(normalize(&envelope(oversized)).is_err());
        let mut integral_numbers = pages(vec![vec![event(TODAY, "1")]]);
        integral_numbers[0]["pagination"]["numPages"] = serde_json::from_str("1e0").unwrap();
        integral_numbers[0]["period"]["startDate"] =
            serde_json::from_str("1782864000000.0").unwrap();
        assert!(normalize(&envelope(integral_numbers)).is_ok());
    }

    #[test]
    fn rejects_missing_repeated_unstable_or_post_terminal_pages_and_cap_exhaustion() {
        let valid = pages(vec![vec![event(TODAY, "1")], vec![event(TODAY, "1")]]);
        for index in [0, 1] {
            assert!(normalize(&envelope(vec![valid[index].clone()])).is_err());
        }
        for (pointer, value) in [
            ("/pagination/currentPage", json!(1)),
            ("/pagination/numPages", json!(3)),
            ("/pagination/pageSize", json!(999)),
            ("/totalUsageEventsCount", json!(3)),
            ("/pagination/hasPreviousPage", json!(false)),
        ] {
            let mut changed = valid.clone();
            *changed[1].pointer_mut(pointer).unwrap() = value;
            assert!(normalize(&envelope(changed)).is_err(), "{pointer}");
        }
        let single = pages(vec![vec![]]).remove(0);
        assert!(normalize(&envelope(vec![single.clone(), single])).is_err());
        let mut capped = pages(vec![vec![]; 101]);
        capped.pop();
        assert!(normalize(&envelope(capped)).is_err());
    }

    #[test]
    fn terminal_empty_is_known_zero_but_absent_and_integer_empty_periods_are_unknown() {
        for count in 0..=1 {
            for current in 0..=1 {
                let mut empty = pages(vec![vec![]]).remove(0);
                empty["pagination"]["numPages"] = json!(count);
                empty["pagination"]["currentPage"] = json!(current);
                assert_eq!(
                    amounts(&normalize(&envelope(vec![empty])).unwrap()),
                    [Some(0); 3]
                );
            }
        }
        assert_eq!(amounts(&normalize(&envelope(vec![])).unwrap()), [None; 3]);
        let mut skipped = envelope(vec![]);
        skipped["generatedAt"] = json!("2026-06-01T00:00:00.000500Z");
        for key in [
            "endExclusiveMs",
            "requestStartMs",
            "todayStartMs",
            "weekStartMs",
            "monthStartMs",
        ] {
            skipped[key] = json!(1_780_272_000_000_i64);
        }
        assert_eq!(amounts(&normalize(&skipped).unwrap()), [None; 3]);
        let cutoff = 1_785_542_400_000_i64; // 2026-08-01 00:00 UTC.
        let week = 1_785_110_400_000_i64; // 2026-07-27 00:00 UTC.
        let mut page = pages(vec![vec![]]).remove(0);
        page["period"] = json!({"startDate": week, "endDate": cutoff - 1});
        let mut wider = envelope(vec![page]);
        wider["generatedAt"] = json!("2026-08-01T00:00:00.000500Z");
        wider["endExclusiveMs"] = json!(cutoff);
        wider["todayStartMs"] = json!(cutoff);
        wider["monthStartMs"] = json!(cutoff);
        wider["weekStartMs"] = json!(week);
        wider["requestStartMs"] = json!(week);
        assert_eq!(amounts(&normalize(&wider).unwrap()), [None, Some(0), None]);
        wider["todayStartMs"] = json!(cutoff + 1);
        assert_eq!(amounts(&normalize(&wider).unwrap()), [None, Some(0), None]);

        let monday = 1_784_505_600_000_i64; // 2026-07-20 00:00 UTC.
        let mut page = pages(vec![vec![]]).remove(0);
        page["period"]["endDate"] = json!(monday - 1);
        let mut monday_report = envelope(vec![page]);
        monday_report["generatedAt"] = json!("2026-07-20T00:00:00.000500Z");
        monday_report["endExclusiveMs"] = json!(monday);
        monday_report["todayStartMs"] = json!(monday);
        monday_report["weekStartMs"] = json!(monday);
        assert_eq!(
            amounts(&normalize(&monday_report).unwrap()),
            [None, None, Some(0)]
        );
    }

    #[test]
    fn compares_integer_timestamps_at_each_inclusive_start_and_exclusive_cutoff() {
        let snapshot = normalize(&envelope(pages(vec![vec![
            event(MONTH - 1, "1000"),
            event(MONTH, "1"),
            event(WEEK - 1, "2"),
            event(WEEK, "4"),
            event(TODAY - 1, "8"),
            event(TODAY, "16"),
            event(END - 1, "32"),
            event(END, "1000"),
        ]])))
        .unwrap();
        assert_eq!(amounts(&snapshot), [Some(48), Some(60), Some(63)]);
    }

    #[test]
    fn sums_decimal_lexemes_before_rounding_both_signs_once() {
        for (left, right, expected) in [
            ("0.25", "0.25", 1),
            ("-0.25", "-0.25", -1),
            ("0.24", "0.25", 0),
            ("-0.24", "-0.25", 0),
            ("1.25e-1", "3.75e-1", 1),
            ("-1.25E-1", "-3.75E-1", -1),
            ("2.5e+1", "-2.45e1", 1),
            ("0.49999999999999999999999999999999999999", "0", 0),
            ("0.50000000000000000000000000000000000001", "0", 1),
            ("9223372036854775807", "-9223372036854775807", 0),
        ] {
            let snapshot = normalize(&envelope(pages(vec![vec![
                event(TODAY, left),
                event(TODAY, right),
            ]])))
            .unwrap();
            assert_eq!(amounts(&snapshot), [Some(expected); 3], "{left} + {right}");
        }
        for amount in ["9223372036854775807", "-9223372036854775808"] {
            assert!(normalize(&envelope(pages(vec![vec![event(TODAY, amount)]]))).is_ok());
        }
        for amount in [
            "9223372036854775807.5",
            "-9223372036854775808.5",
            "1e100",
            "1e-100",
        ] {
            assert!(
                matches!(
                    normalize(&envelope(pages(vec![vec![event(TODAY, amount)]]))),
                    Err(CursorPlatformReportError::NumericOverflow)
                ),
                "{amount}"
            );
        }
        let overflow = vec![
            event(TODAY, "170141183460469231731687303715884105727"),
            event(TODAY, "1"),
        ];
        assert!(matches!(
            normalize(&envelope(pages(vec![overflow]))),
            Err(CursorPlatformReportError::NumericOverflow)
        ));
    }

    #[test]
    fn preserves_unknown_funding_counts_and_saturating_canonical_zeros() {
        let mut report = envelope(vec![]);
        report["dailyUsagePages"] = json!([json!({"data": [
            {"day": "2026-07-18", "subscriptionIncludedReqs": 0, "usageBasedReqs": 0, "apiKeyReqs": 0, "composerRequests": 900},
            {"day": "2026-07-19", "subscriptionIncludedReqs": u64::MAX, "usageBasedReqs": 1, "apiKeyReqs": 1}
        ]}).to_string()]);
        let snapshot = normalize(&report).unwrap();
        assert_eq!(
            snapshot
                .buckets
                .iter()
                .map(|bucket| bucket.requests)
                .collect::<Vec<_>>(),
            vec![Some(0), Some(u64::MAX)]
        );
        for field in ["subscriptionIncludedReqs", "usageBasedReqs", "apiKeyReqs"] {
            for null in [false, true] {
                let complete = json!({"day": "2026-07-19", "subscriptionIncludedReqs": 1, "usageBasedReqs": 2, "apiKeyReqs": 3});
                let mut missing = complete.clone();
                if null {
                    missing[field] = Value::Null;
                } else {
                    missing.as_object_mut().unwrap().remove(field);
                }
                report["dailyUsagePages"] = json!([
                    json!({"data": [complete]}).to_string(),
                    json!({"data": [missing]}).to_string()
                ]);
                assert_eq!(
                    normalize(&report).unwrap().buckets[0].requests,
                    None,
                    "{field}"
                );
            }
        }
    }
}
