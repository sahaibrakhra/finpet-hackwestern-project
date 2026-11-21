import Foundation

struct ReviewSchedule: Codable {
    var due: Date
    var level = 0
    var missed: [Int] = []
    var round = 0

    static func first(after date: Date, missed: [Int], calendar: Calendar) -> Self {
        Self(due: futureDay(1, after: date, calendar: calendar), missed: missed)
    }

    func next(after date: Date, missed: [Int], calendar: Calendar) -> Self {
        let intervals = [1, 3, 7, 14, 30]
        let nextLevel = missed.isEmpty ? min(level + 1, intervals.count - 1) : max(0, level - 1)
        let interval = missed.isEmpty ? intervals[nextLevel] : 1
        return Self(due: Self.futureDay(interval, after: date, calendar: calendar),
                    level: nextLevel, missed: missed, round: round + 1)
    }

    func questions(total: Int) -> [Int] {
        guard total > 0 else { return [] }
        let priority = missed.filter { (0..<total).contains($0) }
        let rotation = (0..<total).map { ($0 + round * 2) % total }
        var seen = Set<Int>()
        return Array((priority + rotation).filter { seen.insert($0).inserted }.prefix(3))
    }

    private static func futureDay(_ days: Int, after date: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: days, to: today) ?? date
    }
}
