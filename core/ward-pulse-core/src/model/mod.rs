use crate::time::DateTimeUtc;

pub type AccountId = String;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ProviderKind {
    OpenAi,
    Codex,
    Claude,
    Cursor,
    Mock,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ProviderStatus {
    Ok,
    Warning,
    Error,
    RateLimited,
    AuthRequired,
    Stale,
    Unknown,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BudgetPeriod {
    Today,
    Week,
    Month,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CurrencyCode(String);

impl CurrencyCode {
    pub fn new(value: impl Into<String>) -> Self {
        Self(value.into())
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl From<&str> for CurrencyCode {
    fn from(value: &str) -> Self {
        Self::new(value)
    }
}

impl From<String> for CurrencyCode {
    fn from(value: String) -> Self {
        Self::new(value)
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Money {
    pub minor_units: i64,
    pub currency: CurrencyCode,
}

impl Money {
    pub fn minor_units(minor_units: i64, currency: impl Into<CurrencyCode>) -> Self {
        Self {
            minor_units,
            currency: currency.into(),
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct BudgetPolicy {
    pub daily_limit: Option<Money>,
    pub weekly_limit: Option<Money>,
    pub monthly_limit: Option<Money>,
    pub warn_at_percent: u8,
}

#[derive(Clone, Debug, PartialEq)]
pub struct BudgetState {
    pub period: BudgetPeriod,
    pub spent: Option<Money>,
    pub limit: Option<Money>,
    pub remaining: Option<Money>,
    pub used_percent: Option<f64>,
    pub projected_total: Option<Money>,
    pub status: ProviderStatus,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ProviderAccount {
    pub id: AccountId,
    pub provider: ProviderKind,
    pub display_name: String,
    pub workspace_name: Option<String>,
    pub masked_credential: Option<String>,
    pub enabled: bool,
    pub budget: Option<BudgetPolicy>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct UsageBucket {
    pub start_at: DateTimeUtc,
    pub end_at: DateTimeUtc,
    pub cost: Option<Money>,
    pub input_tokens: Option<u64>,
    pub output_tokens: Option<u64>,
    pub cached_tokens: Option<u64>,
    pub requests: Option<u64>,
    pub model: Option<String>,
    pub project: Option<String>,
    pub user: Option<String>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CreditSource {
    Provider,
    Promo,
    Manual,
    Unknown,
}

#[derive(Clone, Debug, PartialEq)]
pub struct CreditState {
    pub remaining: Option<Money>,
    pub granted: Option<Money>,
    pub expires_at: Option<DateTimeUtc>,
    pub source: CreditSource,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ModelUsage {
    pub model: String,
    pub cost: Option<Money>,
    pub input_tokens: Option<u64>,
    pub output_tokens: Option<u64>,
    pub requests: Option<u64>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ProviderErrorSummary {
    pub code: String,
    pub message: String,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ProviderSnapshot {
    pub account_id: AccountId,
    pub provider: ProviderKind,
    pub status: ProviderStatus,
    pub today: BudgetState,
    pub week: BudgetState,
    pub month: BudgetState,
    pub credits: Vec<CreditState>,
    pub buckets: Vec<UsageBucket>,
    pub model_breakdown: Vec<ModelUsage>,
    pub last_successful_sync_at: Option<DateTimeUtc>,
    pub last_error: Option<ProviderErrorSummary>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AlertSeverity {
    Info,
    Warning,
    Error,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Alert {
    pub severity: AlertSeverity,
    pub message: String,
}

#[derive(Clone, Debug, PartialEq)]
pub struct WatchSummary {
    pub today_used_percent: Option<f64>,
    pub week_used_percent: Option<f64>,
    pub status: ProviderStatus,
}

#[derive(Clone, Debug, PartialEq)]
pub struct DashboardSnapshot {
    pub generated_at: DateTimeUtc,
    pub overall_status: ProviderStatus,
    pub accounts: Vec<ProviderSnapshot>,
    pub today_total: BudgetState,
    pub week_total: BudgetState,
    pub month_total: BudgetState,
    pub alerts: Vec<Alert>,
    pub watch_summary: WatchSummary,
}
