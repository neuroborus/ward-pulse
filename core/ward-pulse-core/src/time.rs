use std::cmp::Ordering;

use serde::{Deserialize, Serialize};

/// UTC instant with canonical numeric fractional seconds.
///
/// Numeric `YYYY-MM-DDTHH:MM:SS[.digits]Z` values retain nonzero fractions, with
/// trailing zeros removed. Whole seconds and all-zero fractions are equivalent.
/// Ordering compares seconds, then fractional digits padded with zeros, so a
/// positive fraction follows its whole second regardless of the input width.
/// Microsecond precision is supported end to end within Dart/native timestamp
/// representability; longer fractions are retained here without that guarantee.
///
/// The format recognizer does not validate calendars or accept additional zones.
/// Recognized UTC values sort before opaque values; opaque values sort as text.
///
/// Construction remains infallible. Outside recognized forms, legacy removal
/// of a dotted suffix before `Z` and other input pass-through remain unchanged.
/// See `docs/product/PROVIDER_NOTES.md` (Boundary) for the trade-off and where
/// to reject if a provider ever breaks the format.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(transparent)]
pub struct DateTimeUtc(String);

impl DateTimeUtc {
    pub fn new(value: impl Into<String>) -> Self {
        Self(canonicalize(value.into()))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// Recognizes only the existing numeric UTC shape, without calendar parsing.
fn numeric_utc_parts(value: &str) -> Option<(&str, &str)> {
    let body = value.strip_suffix('Z')?;
    let seconds = body.get(..19)?;
    for (index, byte) in seconds.bytes().enumerate() {
        let valid = match index {
            4 | 7 => byte == b'-',
            10 => byte == b'T',
            13 | 16 => byte == b':',
            _ => byte.is_ascii_digit(),
        };
        if !valid {
            return None;
        }
    }
    let suffix = &body[19..];
    let fraction = if suffix.is_empty() {
        ""
    } else {
        let digits = suffix.strip_prefix('.')?;
        if digits.is_empty() || !digits.bytes().all(|byte| byte.is_ascii_digit()) {
            return None;
        }
        digits
    };
    Some((seconds, fraction))
}

fn canonicalize(value: String) -> String {
    if let Some((seconds, fraction)) = numeric_utc_parts(&value) {
        if fraction.is_empty() {
            return value;
        }
        let fraction = fraction.trim_end_matches('0');
        return if fraction.is_empty() {
            format!("{seconds}Z")
        } else {
            format!("{seconds}.{fraction}Z")
        };
    }
    // Preserve normalization of unrecognized inputs from before fractions were retained.
    let Some(body) = value.strip_suffix('Z') else {
        return value;
    };
    let Some((seconds, _fraction)) = body.split_once('.') else {
        return value;
    };
    format!("{seconds}Z")
}

impl Ord for DateTimeUtc {
    fn cmp(&self, other: &Self) -> Ordering {
        match (numeric_utc_parts(&self.0), numeric_utc_parts(&other.0)) {
            (Some((left_seconds, left)), Some((right_seconds, right))) => {
                left_seconds.cmp(right_seconds).then_with(|| {
                    for index in 0..left.len().max(right.len()) {
                        let order = left
                            .as_bytes()
                            .get(index)
                            .unwrap_or(&b'0')
                            .cmp(right.as_bytes().get(index).unwrap_or(&b'0'));
                        if order != Ordering::Equal {
                            return order;
                        }
                    }
                    Ordering::Equal
                })
            }
            (Some(_), None) => Ordering::Less,
            (None, Some(_)) => Ordering::Greater,
            (None, None) => self.0.cmp(&other.0),
        }
    }
}

impl PartialOrd for DateTimeUtc {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
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
    fn equivalent_fractions_have_one_spelling() {
        for (input, canonical) in [
            ("2026-08-01T10:00:00.000Z", "2026-08-01T10:00:00Z"),
            ("2026-08-01T10:00:00.100000Z", "2026-08-01T10:00:00.1Z"),
            ("2026-08-01T10:00:00.123400Z", "2026-08-01T10:00:00.1234Z"),
        ] {
            let value = DateTimeUtc::from(input);
            let expected = DateTimeUtc::from(canonical);
            assert_eq!(value.as_str(), canonical);
            assert_eq!(value, expected);
            assert_eq!(value.cmp(&expected), Ordering::Equal);
        }
    }

    #[test]
    fn canonicalizes_on_deserialize_not_only_on_construction() {
        for input in [
            "2026-08-01T10:00:00.123456Z",
            "2026-08-01T10:00:00.100000Z",
            "2026-08-01T10:00:00.000Z",
        ] {
            let parsed: DateTimeUtc =
                serde_json::from_str(&serde_json::to_string(input).unwrap()).unwrap();
            let constructed = DateTimeUtc::new(input.to_owned());
            assert_eq!(parsed, constructed);
            assert_eq!(
                serde_json::to_string(&parsed).unwrap(),
                serde_json::to_string(constructed.as_str()).unwrap()
            );
        }
        assert_eq!(
            DateTimeUtc::from("2026-08-01T10:00:00.123456Z").as_str(),
            "2026-08-01T10:00:00.123456Z"
        );
    }

    #[test]
    fn orders_fractions_and_second_boundaries_chronologically() {
        let ordered = [
            "2026-08-01T09:59:59.999999Z",
            "2026-08-01T10:00:00Z",
            "2026-08-01T10:00:00.000001Z",
            "2026-08-01T10:00:00.09Z",
            "2026-08-01T10:00:00.100Z",
            "2026-08-01T10:00:00.11Z",
            "2026-08-01T10:00:00.800Z",
            "2026-08-01T10:00:01Z",
        ]
        .map(DateTimeUtc::from);
        for pair in ordered.windows(2) {
            assert!(pair[0] < pair[1]);
        }
    }

    #[test]
    fn preserves_legacy_handling_outside_numeric_utc_forms() {
        for (input, expected) in [
            ("2026-08-01", "2026-08-01"),
            (
                "2026-08-01T10:00:00.123+01:00",
                "2026-08-01T10:00:00.123+01:00",
            ),
            ("opaque.fractionZ", "opaqueZ"),
            ("2026-08-01T10:00:00.invalidZ", "2026-08-01T10:00:00Z"),
            ("é.123Z", "éZ"),
        ] {
            let parsed: DateTimeUtc =
                serde_json::from_str(&serde_json::to_string(input).unwrap()).unwrap();
            assert_eq!(parsed.as_str(), expected);
            assert_eq!(DateTimeUtc::from(input), parsed);
        }
    }

    #[test]
    fn equality_and_total_order_are_consistent_including_opaque_values() {
        let values = [
            "2026-08-01T10:00:00Z",
            "2026-08-01T10:00:00.000Z",
            "2026-08-01T10:00:00.1Z",
            "2026-08-01T10:00:00.100000Z",
            "2026-08-01T10:00:00.11Z",
            "2026-08-01T10:00:01Z",
            "",
            "2026-08-01",
            "opaque",
        ]
        .map(DateTimeUtc::from);
        assert!(values[5] < values[6]);
        assert!(values[6] < values[7] && values[7] < values[8]);
        for a in &values {
            for b in &values {
                assert_eq!(a == b, a.cmp(b) == Ordering::Equal);
                assert_eq!(a.partial_cmp(b), Some(a.cmp(b)));
                assert_eq!(a.cmp(b), b.cmp(a).reverse());
                for c in &values {
                    if a <= b && b <= c {
                        assert!(a <= c);
                    }
                }
            }
        }
    }
}
