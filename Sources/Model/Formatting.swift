import CryptoKit
import Foundation

struct ScannedCode: Equatable, Sendable {
    var payload: String
    var symbology: String
}

enum CodeHash {
    static func hash(_ code: ScannedCode) -> String {
        let digest = SHA256.hash(data: Data("\(code.symbology)|\(code.payload)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum Weekdays {
    /// Calendar weekdays in the order the user's locale starts the week.
    static var ordered: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    static func letter(_ day: Int) -> String { Calendar.current.veryShortStandaloneWeekdaySymbols[day - 1] }
    static func short(_ day: Int) -> String { Calendar.current.shortStandaloneWeekdaySymbols[day - 1] }
    static func name(_ day: Int) -> String { Calendar.current.standaloneWeekdaySymbols[day - 1] }

    static func summary(_ days: [Int]) -> String {
        let set = Set(days)
        if set.isEmpty { return "Once" }
        if set.count == 7 { return "Every day" }
        if set == [2, 3, 4, 5, 6] { return "Weekdays" }
        if set == [1, 7] { return "Weekends" }
        return ordered.filter(set.contains).map(short).joined(separator: ", ")
    }

    static func localeWeekday(_ day: Int) -> Locale.Weekday? {
        let all: [Locale.Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        return all.indices.contains(day - 1) ? all[day - 1] : nil
    }
}

enum Clock {
    static var uses12Hour: Bool {
        (DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "").contains("a")
    }

    /// "6:30" and "AM" separately, so the period can be set smaller next to the time.
    static func parts(hour: Int, minute: Int) -> (time: String, period: String?) {
        if uses12Hour {
            let displayHour = hour % 12 == 0 ? 12 : hour % 12
            let period = hour < 12 ? Calendar.current.amSymbol : Calendar.current.pmSymbol
            return (String(format: "%d:%02d", displayHour, minute), period)
        }
        return (String(format: "%02d:%02d", hour, minute), nil)
    }

    static func parts(_ date: Date) -> (time: String, period: String?) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return parts(hour: c.hour ?? 0, minute: c.minute ?? 0)
    }

    static func string(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

enum NextAlarm {
    static func date(for alarm: AlarmSnapshot, after now: Date) -> Date? {
        let calendar = Calendar.current
        if alarm.weekdays.isEmpty {
            return calendar.nextDate(after: now, matching: DateComponents(hour: alarm.hour, minute: alarm.minute),
                                     matchingPolicy: .nextTime)
        }
        return alarm.weekdays.compactMap { day in
            calendar.nextDate(after: now, matching: DateComponents(hour: alarm.hour, minute: alarm.minute, weekday: day),
                              matchingPolicy: .nextTime)
        }.min()
    }

    /// The most recent time this alarm was due to ring, at or before `now`.
    static func previousDate(for alarm: AlarmSnapshot, before now: Date) -> Date? {
        let calendar = Calendar.current
        for daysBack in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: -daysBack, to: now),
                  let date = calendar.date(bySettingHour: alarm.hour, minute: alarm.minute, second: 0, of: day),
                  date <= now else { continue }
            if alarm.weekdays.isEmpty || alarm.weekdays.contains(calendar.component(.weekday, from: date)) {
                return date
            }
        }
        return nil
    }

    static func summary(for alarms: [AlarmSnapshot], now: Date) -> String {
        let next = alarms.filter(\.isEnabled).compactMap { date(for: $0, after: now) }.min()
        guard let next else { return alarms.isEmpty ? "Add an alarm to get started" : "No alarms on" }
        let minutes = Int((next.timeIntervalSince(now) / 60).rounded(.up))
        if minutes >= 24 * 60 {
            return "Next alarm \(next.formatted(.dateTime.weekday(.wide).hour().minute()))"
        }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "Next alarm in \(rest) min" }
        if rest == 0 { return "Next alarm in \(hours) hr" }
        return "Next alarm in \(hours) hr \(rest) min"
    }
}
