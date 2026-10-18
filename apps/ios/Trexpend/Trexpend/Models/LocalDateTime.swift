import Foundation

nonisolated struct LocalDateTime: Equatable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int
    let hour: Int
    let minute: Int
    let second: Int

    init(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0, second: Int = 0) throws {
        guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day),
              (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else {
            throw FinanceError.invalidDate
        }
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.second = second
        let calendar = Self.calendar(in: .gmt)
        guard let instant = calendar.date(from: components), Self.matches(instant, components: components, calendar: calendar) else {
            throw FinanceError.invalidDate
        }
    }

    init(storage: String) throws {
        guard storage.count == 19,
              storage.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$"#, options: .regularExpression) != nil else {
            throw FinanceError.invalidDate
        }
        let numbers = storage.split(whereSeparator: { "-T:".contains($0) }).compactMap { Int($0) }
        guard numbers.count == 6 else { throw FinanceError.invalidDate }
        try self.init(year: numbers[0], month: numbers[1], day: numbers[2], hour: numbers[3], minute: numbers[4], second: numbers[5])
    }

    init(instant: Date, timeZone: TimeZone) throws {
        let values = Self.calendar(in: timeZone).dateComponents([.year, .month, .day, .hour, .minute, .second], from: instant)
        guard let year = values.year, let month = values.month, let day = values.day,
              let hour = values.hour, let minute = values.minute, let second = values.second else {
            throw FinanceError.invalidDate
        }
        try self.init(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
    }

    var storage: String {
        String(format: "%04d-%02d-%02dT%02d:%02d:%02d", year, month, day, hour, minute, second)
    }

    var calendarDay: String { String(storage.prefix(10)) }

    var components: DateComponents {
        DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.storage < rhs.storage }

    static func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        return calendar
    }

    static func matches(_ instant: Date, components: DateComponents, calendar: Calendar) -> Bool {
        let values = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: instant)
        return values.year == components.year && values.month == components.month && values.day == components.day
            && values.hour == components.hour && values.minute == components.minute && values.second == components.second
    }
}

nonisolated struct CalendarMonth: Equatable, Sendable {
    let start: LocalDateTime
    let end: LocalDateTime

    init(year: Int, month: Int) throws {
        start = try LocalDateTime(year: year, month: month, day: 1)
        end = try LocalDateTime(year: month == 12 ? year + 1 : year, month: month == 12 ? 1 : month + 1, day: 1)
    }

    func contains(_ date: LocalDateTime) -> Bool { date >= start && date < end }
}
