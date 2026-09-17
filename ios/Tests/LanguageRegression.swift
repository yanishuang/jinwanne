import Foundation

@main
struct LanguageRegression {
    static func main() throws {
        let cases: [(String?, String?, InterfaceLanguage)] = [
            ("CHN", "US", .chinese), ("USA", "CN", .english), ("HKG", "CN", .english),
            ("TWN", "CN", .english), ("GBR", "CN", .english), (nil, "CN", .chinese),
            (nil, "US", .english), (nil, "HK", .english), (nil, "TW", .english),
            (nil, nil, .english), ("chn", "US", .chinese), ("", "CN", .chinese)
        ]
        for (store, region, expected) in cases {
            precondition(InterfaceLanguage.resolve(storefront: store, deviceRegion: region) == expected)
        }
        let saved = UserDefaults.standard.string(forKey: L10n.preferenceKey)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: L10n.preferenceKey) }
            else { UserDefaults.standard.removeObject(forKey: L10n.preferenceKey) }
        }
        UserDefaults.standard.set("en", forKey: L10n.preferenceKey)
        precondition(Outcome.declined.title == "Not tonight")
        precondition(RankingPeriod.month.title == "Month")
        precondition("2026-09-17".localizedDayLabel == "Thu, Sep 17")
        precondition(L10n.privacyURL.path == "/en/privacy")
        precondition(L10n.errorMessage(URLError(.timedOut)).contains("timed out"))
        precondition(APIClientError.server("旧服务端错误").localizedDescription == "Something went wrong. Please try again.")
        UserDefaults.standard.set("zh-Hans", forKey: L10n.preferenceKey)
        precondition(Outcome.declined.title == "失败")
        precondition(L10n.privacyURL.path == "/privacy")
        precondition("2026-09-17".localizedDayLabel.contains("9 月 17 日"))
        print("PASS: 12 country-policy cases, bilingual dates, outcomes, URLs, and network errors")
    }
}
