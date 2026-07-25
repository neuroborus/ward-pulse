//! Shared allowance helpers for percent-reported plan providers.

use ward_pulse_core::model::{AllowanceState, ProviderStatus, Quantity, QuantityUnit};

/// Maps a reported utilization percentage to a provider status.
///
/// An unreported percentage stays `Unknown`: a provider that says nothing about
/// utilization must not be shown as healthy.
pub(crate) fn percent_status(used_percent: Option<f64>) -> ProviderStatus {
    let Some(used_percent) = used_percent else {
        return ProviderStatus::Unknown;
    };
    if used_percent >= 100.0 {
        ProviderStatus::RateLimited
    } else if used_percent >= 80.0 {
        ProviderStatus::Warning
    } else {
        ProviderStatus::Ok
    }
}

/// Formats a provider amount reported in minor currency units as credits.
pub(crate) fn credits_from_cents(cents: f64) -> Quantity {
    Quantity {
        value: format!("{:.2}", cents / 100.0),
        unit: QuantityUnit::Credits,
    }
}

/// Most severe allowance status, or `Unknown` when nothing was reported.
pub(crate) fn worst_status(allowances: &[AllowanceState]) -> ProviderStatus {
    allowances
        .iter()
        .map(|allowance| allowance.status)
        .max_by_key(severity)
        .unwrap_or(ProviderStatus::Unknown)
}

fn severity(status: &ProviderStatus) -> u8 {
    match status {
        ProviderStatus::Error | ProviderStatus::AuthRequired => 5,
        ProviderStatus::RateLimited => 4,
        ProviderStatus::Warning => 3,
        ProviderStatus::Stale => 2,
        ProviderStatus::Ok => 1,
        ProviderStatus::Unknown => 0,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn maps_reported_percentages_to_status() {
        assert_eq!(percent_status(Some(0.0)), ProviderStatus::Ok);
        assert_eq!(percent_status(Some(80.0)), ProviderStatus::Warning);
        assert_eq!(percent_status(Some(100.0)), ProviderStatus::RateLimited);
    }

    #[test]
    fn keeps_an_unreported_percentage_unknown() {
        assert_eq!(percent_status(None), ProviderStatus::Unknown);
    }

    #[test]
    fn formats_minor_units_as_credits() {
        assert_eq!(
            credits_from_cents(1234.0),
            Quantity {
                value: "12.34".to_string(),
                unit: QuantityUnit::Credits,
            }
        );
    }
}
