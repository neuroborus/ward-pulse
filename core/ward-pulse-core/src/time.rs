#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DateTimeUtc(String);

impl DateTimeUtc {
    pub fn new(value: impl Into<String>) -> Self {
        Self(value.into())
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl From<&str> for DateTimeUtc {
    fn from(value: &str) -> Self {
        Self::new(value)
    }
}

impl From<String> for DateTimeUtc {
    fn from(value: String) -> Self {
        Self::new(value)
    }
}
