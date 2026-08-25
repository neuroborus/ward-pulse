use crate::model::Money;

/// Projects a period total from the fraction of that period already elapsed.
///
/// Returns `None` for a non-finite or non-positive fraction. A fraction above
/// `1.0` is not rejected and projects below `spent`, so clamp before calling.
///
/// Nothing calls this yet, and that is not an oversight. The core deliberately
/// carries no date arithmetic — [`crate::time::DateTimeUtc`] is text — so it
/// cannot work out how much of a period has passed. The fraction has to arrive
/// from a shell that owns a clock, which makes wiring this a contract change
/// rather than a local edit. `docs/DEVELOPMENT_PLAN.md` (Technology direction)
/// keeps projection logic in scope for the core.
pub fn project_linear(spent: &Money, elapsed_fraction: f64) -> Option<Money> {
    if !elapsed_fraction.is_finite() || elapsed_fraction <= 0.0 {
        return None;
    }

    Some(Money::minor_units(
        (spent.minor_units as f64 / elapsed_fraction).round() as i64,
        spent.currency.clone(),
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn usd(cents: i64) -> Money {
        Money::minor_units(cents, "USD")
    }

    #[test]
    fn projects_minor_units_linearly() {
        let projected = project_linear(&usd(1_250), 0.25);

        assert_eq!(projected, Some(usd(5_000)));
    }

    #[test]
    fn rejects_invalid_elapsed_fraction() {
        assert_eq!(project_linear(&usd(1_250), 0.0), None);
        assert_eq!(project_linear(&usd(1_250), f64::NAN), None);
    }
}
