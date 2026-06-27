use crate::model::Money;

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
