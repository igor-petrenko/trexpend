import Foundation

nonisolated enum MoneyPresentation {
    static func number(_ value: Decimal, places: Int, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = places
        formatter.maximumFractionDigits = places
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? NSDecimalNumber(decimal: value).stringValue
    }

    static func month(_ month: CalendarMonth, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = LocalDateTime.calendar(in: .gmt)
        formatter.timeZone = .gmt
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        guard let date = formatter.calendar.date(from: month.start.components) else { return month.start.calendarDay }
        return formatter.string(from: date)
    }
}
