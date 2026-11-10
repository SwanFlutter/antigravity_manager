//! Time helpers of the Google adapter.
//!
//! The crate parses exactly one timestamp shape (RFC 3339) and formats one
//! reset label. Both are small enough to keep here, so the adapter needs no
//! date-time dependency.

use std::time::{SystemTime, UNIX_EPOCH};

/// The current time in milliseconds since the Unix epoch.
pub fn now_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|value| value.as_millis() as i64)
        .unwrap_or(0)
}

/// Parses an RFC 3339 timestamp into milliseconds since the Unix epoch.
///
/// Google answers with UTC timestamps such as `2026-01-02T03:04:05.123Z` and
/// with numeric offsets such as `2026-01-02T03:04:05+02:00`. A missing
/// offset is read as UTC. Anything else yields `None`.
pub fn parse_rfc3339_millis(input: &str) -> Option<i64> {
    let text = input.trim();
    if text.is_empty() {
        return None;
    }

    let separator = text.find(['T', 't', ' '])?;
    let (date_part, rest) = text.split_at(separator);
    let time_part = rest[1..].trim();

    let mut date_fields = date_part.split('-');
    let year: i64 = date_fields.next()?.parse().ok()?;
    let month: i64 = date_fields.next()?.parse().ok()?;
    let day: i64 = date_fields.next()?.parse().ok()?;
    if date_fields.next().is_some() || !(1..=12).contains(&month) || !(1..=31).contains(&day) {
        return None;
    }

    let (clock_part, offset_seconds) = split_offset(time_part)?;

    let mut clock_fields = clock_part.split(':');
    let hour: i64 = clock_fields.next()?.parse().ok()?;
    let minute: i64 = clock_fields.next()?.parse().ok()?;
    let seconds_field = clock_fields.next()?;
    if clock_fields.next().is_some() {
        return None;
    }

    let (seconds_text, fraction_text) = match seconds_field.split_once('.') {
        Some((seconds, fraction)) => (seconds, fraction),
        None => (seconds_field, ""),
    };
    let seconds: i64 = seconds_text.parse().ok()?;

    let fraction_millis = parse_fraction(fraction_text);
    if !(0..=23).contains(&hour) || !(0..=59).contains(&minute) || !(0..=60).contains(&seconds) {
        return None;
    }

    let days = days_from_civil(year, month, day);
    let epoch_seconds = days * 86_400 + hour * 3_600 + minute * 60 + seconds - offset_seconds;
    Some(epoch_seconds * 1_000 + fraction_millis)
}

/// Splits the clock of a timestamp from its offset.
///
/// The clock is `HH:MM:SS` with an optional fraction, the offset is `Z`, a
/// numeric offset such as `+02:00` or nothing at all. A missing offset is
/// read as UTC.
fn split_offset(time_part: &str) -> Option<(&str, i64)> {
    let time_part = time_part.trim();

    if let Some(stripped) = time_part.strip_suffix('Z').or_else(|| time_part.strip_suffix('z')) {
        return Some((stripped, 0));
    }

    // The sign of an offset can only follow the clock, so the search starts
    // behind the first character.
    let offset_start = time_part
        .char_indices()
        .skip(1)
        .find(|(_, character)| *character == '+' || *character == '-')
        .map(|(index, _)| index);

    match offset_start {
        Some(index) => Some((&time_part[..index], parse_offset(&time_part[index..])?)),
        None => Some((time_part, 0)),
    }
}

/// Reads the fractional part of a timestamp, for example `.123456`.
fn parse_fraction(text: &str) -> i64 {
    let digits: String = text
        .trim_start_matches('.')
        .chars()
        .filter(|c| c.is_ascii_digit())
        .take(3)
        .collect();
    if digits.is_empty() {
        return 0;
    }
    let padded = format!("{digits:0<3}");
    padded.parse().unwrap_or(0)
}

/// Reads a numeric UTC offset such as `+02:00` or `-0530` in seconds.
fn parse_offset(text: &str) -> Option<i64> {
    let mut chars = text.chars();
    let sign = match chars.next()? {
        '+' => 1,
        '-' => -1,
        _ => return None,
    };
    let rest: String = chars.collect();
    let digits: String = rest.chars().filter(|c| c.is_ascii_digit()).collect();
    if digits.len() < 2 {
        return None;
    }
    let hours: i64 = digits[..2].parse().ok()?;
    let minutes: i64 = if digits.len() >= 4 {
        digits[2..4].parse().ok()?
    } else {
        0
    };
    Some(sign * (hours * 3_600 + minutes * 60))
}

/// The number of days between the Unix epoch and the given civil date.
///
/// This is the standard "days from civil" algorithm: it works for the whole
/// proleptic Gregorian calendar without any lookup table.
fn days_from_civil(year: i64, month: i64, day: i64) -> i64 {
    let year = year - i64::from(month <= 2);
    let era = if year >= 0 { year } else { year - 399 } / 400;
    let year_of_era = year - era * 400;
    let month_position = (month + if month > 2 { -3 } else { 9 }) as i64;
    let day_of_year = (153 * month_position + 2) / 5 + day - 1;
    let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    era * 146_097 + day_of_era - 719_468
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_utc_timestamps() {
        assert_eq!(parse_rfc3339_millis("1970-01-01T00:00:00Z"), Some(0));
        assert_eq!(
            parse_rfc3339_millis("2026-01-02T03:04:05Z"),
            Some(1_767_323_045_000)
        );
    }

    #[test]
    fn parses_fractional_seconds() {
        assert_eq!(
            parse_rfc3339_millis("2026-01-02T03:04:05.250Z"),
            Some(1_767_323_045_250)
        );
        // More than three digits are truncated, not rounded.
        assert_eq!(
            parse_rfc3339_millis("2026-01-02T03:04:05.123456Z"),
            Some(1_767_323_045_123)
        );
    }

    #[test]
    fn parses_numeric_offsets() {
        assert_eq!(
            parse_rfc3339_millis("2026-01-02T05:04:05+02:00"),
            Some(1_767_323_045_000)
        );
        assert_eq!(
            parse_rfc3339_millis("2026-01-01T23:04:05-02:00"),
            Some(1_767_315_845_000)
        );
    }

    #[test]
    fn rejects_garbage() {
        assert_eq!(parse_rfc3339_millis(""), None);
        assert_eq!(parse_rfc3339_millis("not a date"), None);
        assert_eq!(parse_rfc3339_millis("2026-13-02T03:04:05Z"), None);
    }
}
