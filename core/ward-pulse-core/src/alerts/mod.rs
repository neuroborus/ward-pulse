use crate::model::{
    Alert, AlertSeverity, AllowanceSource, AllowanceState, BudgetState, ProviderKind,
    ProviderStatus,
};

pub fn alerts_for_budget_state(label: &str, state: &BudgetState) -> Vec<Alert> {
    match state.status {
        ProviderStatus::Error => vec![Alert {
            severity: AlertSeverity::Error,
            message: format!("{label} budget has been reached."),
        }],
        ProviderStatus::Warning => vec![Alert {
            severity: AlertSeverity::Warning,
            message: format!("{label} budget is above the warning threshold."),
        }],
        _ => Vec::new(),
    }
}

/// Purchased meters (Extra usage, on-demand, …) are not watch rings — warn here.
pub fn alerts_for_purchased_allowance(
    provider: ProviderKind,
    allowance: &AllowanceState,
) -> Vec<Alert> {
    if allowance.source != AllowanceSource::Purchased {
        return Vec::new();
    }
    let provider_label = match provider {
        ProviderKind::OpenAi => "OpenAI",
        ProviderKind::Codex => "Codex",
        ProviderKind::Claude => "Claude",
        ProviderKind::Cursor => "Cursor",
        ProviderKind::Mock => "Mock",
    };
    match allowance.status {
        ProviderStatus::Error | ProviderStatus::RateLimited => vec![Alert {
            severity: AlertSeverity::Error,
            message: format!("{provider_label} {} has been exhausted.", allowance.label),
        }],
        ProviderStatus::Warning => vec![Alert {
            severity: AlertSeverity::Warning,
            message: format!(
                "{provider_label} {} is above the warning threshold.",
                allowance.label
            ),
        }],
        _ => Vec::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{Quantity, QuantityUnit};

    fn purchased(status: ProviderStatus) -> AllowanceState {
        AllowanceState {
            id: "claude-extra-usage".to_string(),
            source: AllowanceSource::Purchased,
            label: "Extra usage".to_string(),
            used_percent: Some(84.0),
            used: None,
            limit: None,
            remaining: Some(Quantity {
                value: "15.10".to_string(),
                unit: QuantityUnit::Credits,
            }),
            unlimited: false,
            window_minutes: None,
            resets_at: None,
            status,
        }
    }

    #[test]
    fn warns_on_purchased_allowance_threshold() {
        let alerts = alerts_for_purchased_allowance(
            ProviderKind::Claude,
            &purchased(ProviderStatus::Warning),
        );
        assert_eq!(alerts.len(), 1);
        assert_eq!(alerts[0].severity, AlertSeverity::Warning);
        assert!(alerts[0].message.contains("Extra usage"));
    }

    #[test]
    fn ignores_plan_allowances() {
        let mut plan = purchased(ProviderStatus::Warning);
        plan.source = AllowanceSource::Plan;
        plan.id = "claude-five-hour".to_string();
        plan.label = "5-hour session".to_string();
        assert!(alerts_for_purchased_allowance(ProviderKind::Claude, &plan).is_empty());
    }
}
