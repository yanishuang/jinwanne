import Foundation

enum Outcome: String, Codable, CaseIterable, Identifiable {
    case success
    case declined

    var id: String { rawValue }
    var title: String { self == .success ? "成功" : "失败" }
}

struct Profile: Codable, Equatable {
    let alias: String
    let participating: Bool
}

struct SessionResponse: Codable {
    let profile: Profile
    let today: String
    let timezone: String
}

struct Entry: Codable, Identifiable, Equatable {
    var id: String { date }
    let date: String
    let outcome: Outcome
    let note: String
    let updatedAt: String
}

struct RecordStats: Codable {
    let success: Int
    let declined: Int
    let total: Int
}

struct DiaryResponse: Codable {
    let records: [Entry]
    let stats: RecordStats
}

struct RankRow: Codable, Identifiable {
    var id: String { alias }
    let alias: String
    let rank: Int
    let days: Int
    let isMe: Bool
}

struct RankingResponse: Codable {
    let rows: [RankRow]
    let mine: RankRow?
    let total: Int
    let start: String
    let end: String
    let updatedAt: String
}

struct ProfileResponse: Codable { let profile: Profile }
struct EmptyResponse: Codable { let ok: Bool }
struct ErrorResponse: Codable { let error: String }

enum RankingPeriod: String, CaseIterable, Identifiable {
    case month, year, all
    var id: String { rawValue }
    var title: String {
        switch self { case .month: "本月"; case .year: "今年"; case .all: "全部" }
    }
}

extension String {
    var chineseDayLabel: String {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "Asia/Shanghai")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: self) else { return self }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = parser.timeZone
        formatter.dateFormat = "M 月 d 日 · EEEE"
        return formatter.string(from: date)
    }
}
