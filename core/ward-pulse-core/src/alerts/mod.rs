use crate::model::{Alert, AlertSeverity, BudgetState, ProviderStatus};

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
