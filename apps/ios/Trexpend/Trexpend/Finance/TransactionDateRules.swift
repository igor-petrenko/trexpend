import Foundation

nonisolated struct OccurrenceDate: Equatable, Sendable {
    let local: LocalDateTime
    let withOffset: String?
}

nonisolated enum TransactionDateRules {
    static func newOccurrence(now: Date, timeZone: TimeZone) throws -> OccurrenceDate {
        let local = try LocalDateTime(instant: now, timeZone: timeZone)
        return try occurrence(local, instant: now, timeZone: timeZone)
    }

    static func changingDay(of original: LocalDateTime, to day: LocalDateTime) throws -> LocalDateTime {
        if original.calendarDay == day.calendarDay { return original }
        return try LocalDateTime(year: day.year, month: day.month, day: day.day)
    }

    static func forSave(original: OccurrenceDate?, editedLocal: LocalDateTime?, now: Date, timeZone: TimeZone) throws -> OccurrenceDate {
        if let editedLocal {
            try validateNotFuture(editedLocal, now: now, timeZone: timeZone)
            return try occurrence(editedLocal, timeZone: timeZone)
        }
        if let original {
            try validateNotFuture(original.local, now: now, timeZone: timeZone)
            return original
        }
        return try newOccurrence(now: now, timeZone: timeZone)
    }

    static func validateNotFuture(_ local: LocalDateTime, now: Date, timeZone: TimeZone) throws {
        let today = try LocalDateTime(instant: now, timeZone: timeZone)
        guard local.calendarDay <= today.calendarDay else { throw FinanceError.futureDate }
    }

    static func occurrence(_ local: LocalDateTime, timeZone: TimeZone) throws -> OccurrenceDate {
        let calendar = LocalDateTime.calendar(in: timeZone)
        guard let approximate = calendar.date(from: local.components),
              let instant = calendar.nextDate(after: approximate.addingTimeInterval(-86_400), matching: local.components,
                                              matchingPolicy: .strict, repeatedTimePolicy: .first),
              LocalDateTime.matches(instant, components: local.components, calendar: calendar) else {
            throw FinanceError.invalidDate
        }
        return try occurrence(local, instant: instant, timeZone: timeZone)
    }

    private static func occurrence(_ local: LocalDateTime, instant: Date, timeZone: TimeZone) throws -> OccurrenceDate {
        let offset = timeZone.secondsFromGMT(for: instant)
        guard offset % 60 == 0 else { throw FinanceError.invalidDate }
        let suffix = String(format: "%@%02d:%02d", offset < 0 ? "-" : "+", abs(offset) / 3600, (abs(offset) % 3600) / 60)
        return OccurrenceDate(local: local, withOffset: local.storage + suffix)
    }

    static func technicalTimestamp(_ instant: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .gmt
        return formatter.string(from: instant)
    }
}
