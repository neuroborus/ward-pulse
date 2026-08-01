use serde::{Deserialize, Serialize};

/// RFC 3339 instant in UTC, canonicalized to whole seconds.
///
/// Values reach the core in two shapes: the phone builds `generatedAt` with Dart
/// `toIso8601String`, which always writes milliseconds, while provider payloads
/// and adapter-built bucket bounds carry whole seconds. Ordering compares these
/// as text, and `.` sorts before `Z`, so `…:00.000Z` would rank below the very
/// same instant written `…:00Z`. Dropping sub-second precision on the way in
/// keeps one shape, so text order matches chronological order.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(transparent)]
pub struct DateTimeUtc(String);

impl DateTimeUtc {
    pub fn new(value: impl Into<String>) -> Self {
        Self(whole_seconds(value.into()))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// Drops a fractional-seconds part from a UTC instant, leaving other input as is.
fn whole_seconds(value: String) -> String {
    let Some(body) = value.strip_suffix('Z') else {
        return value;
    };
    let Some((seconds, _fraction)) = body.split_once('.') else {
        return value;
    };
    format!("{seconds}Z")
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

impl<'de> Deserialize<'de> for DateTimeUtc {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        String::deserialize(deserializer).map(Self::new)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn drops_sub_second_precision_so_one_instant_has_one_spelling() {
        assert_eq!(
            DateTimeUtc::from("2026-08-01T10:00:00.000Z"),
            DateTimeUtc::from("2026-08-01T10:00:00Z")
        );
    }

    #[test]
    fn canonicalizes_on_deserialize_not_only_on_construction() {
        let parsed: DateTimeUtc = serde_json::from_str(r#""2026-08-01T10:00:00.123Z""#).unwrap();

        assert_eq!(parsed.as_str(), "2026-08-01T10:00:00Z");
    }

    #[test]
    fn text_order_matches_chronological_order_across_input_shapes() {
        let earlier = DateTimeUtc::from("2026-08-01T10:00:00.000Z");
        let later = DateTimeUtc::from("2026-08-01T10:00:01Z");

        assert!(earlier.as_str() < later.as_str());
    }

    #[test]
    fn leaves_unrecognized_input_untouched() {
        assert_eq!(DateTimeUtc::from("2026-08-01").as_str(), "2026-08-01");
    }
}
