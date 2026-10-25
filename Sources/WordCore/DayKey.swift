import Foundation

/// A single calendar day, stored as an integer offset from 1970-01-01.
///
/// Keeping days as integers means time zones and DST only matter at the moment
/// a `Date` is converted; everything after that (sorting, scheduling, JSON) is
/// plain integer arithmetic and therefore reproducible in tests.
public struct DayKey: Hashable, Comparable, Codable, CustomStringConvertible, Sendable {
    /// Days since 1970-01-01, in the calendar that produced this key.
    public let raw: Int

    public init(raw: Int) {
        self.raw = raw
    }

    public init(containing date: Date, calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: date)
        let epoch = calendar.startOfDay(for: DayKey.epochDate(calendar: calendar))
        self.raw = calendar.dateComponents([.day], from: epoch, to: start).day ?? 0
    }

    public static func today(calendar: Calendar = .current, now: Date = Date()) -> DayKey {
        DayKey(containing: now, calendar: calendar)
    }

    public func date(calendar: Calendar = .current) -> Date {
        let base = calendar.startOfDay(for: DayKey.epochDate(calendar: calendar))
        return calendar.date(byAdding: .day, value: raw, to: base) ?? base
    }

    public func adding(_ days: Int, calendar: Calendar = .current) -> DayKey {
        guard days != 0 else { return self }
        let origin = date(calendar: calendar)
        let shifted = calendar.date(byAdding: .day, value: days, to: origin)
            ?? origin.addingTimeInterval(TimeInterval(days) * 86_400)
        return DayKey(containing: shifted, calendar: calendar)
    }

    public func components(calendar: Calendar = .current) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .weekday], from: date(calendar: calendar))
    }

    /// `yyyy-MM-dd`, independent of the device locale.
    public func isoString(calendar: Calendar = .current) -> String {
        let parts = components(calendar: calendar)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public var description: String { isoString() }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        lhs.raw < rhs.raw
    }

    private static func epochDate(calendar: Calendar) -> Date {
        var parts = DateComponents()
        parts.year = 1970
        parts.month = 1
        parts.day = 1
        return calendar.date(from: parts) ?? Date(timeIntervalSince1970: 0)
    }

    // MARK: - Codable (a bare integer keeps the on-disk JSON small and readable)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.raw = try container.decode(Int.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }
}
