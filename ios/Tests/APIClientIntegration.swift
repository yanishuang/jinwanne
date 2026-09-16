import Foundation

private enum IntegrationFailure: Error { case failed(String) }

@main
private struct APIClientIntegration {
    static func main() async throws {
        guard let address = CommandLine.arguments.dropFirst().first, let url = URL(string: address), url.host == "127.0.0.1" else {
            throw IntegrationFailure.failed("Tests require an isolated localhost server")
        }
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let api = APIClient(baseURL: url, session: session)
        let opened = try await api.openSession()
        try expect(!opened.profile.participating, "New identity must remain private")
        let month = String(opened.today.prefix(7))
        try await api.save(date: opened.today, outcome: .declined, note: "isolated test note")
        try await api.save(date: opened.today, outcome: .declined, note: "isolated test note")
        var diary = try await api.records(month: month)
        try expect(diary.stats.declined == 1 && diary.stats.total == 1, "Repeated taps should count one server day")
        let privateRanking = try await api.ranking(metric: .declined, period: .month)
        try expect(privateRanking.rows.isEmpty, "Private records leaked to public ranking")
        _ = try await api.setParticipation(true)
        let ranking = try await api.ranking(metric: .declined, period: .month)
        try expect(ranking.mine?.days == 1 && ranking.rows.count == 1, "Participation did not reveal the saved record")
        try await api.save(date: opened.today, outcome: .success, note: "isolated test note")
        diary = try await api.records(month: month)
        try expect(diary.stats.success == 1 && diary.stats.declined == 0 && diary.stats.total == 1, "Server edit did not move counts")
        let newConfig = URLSessionConfiguration.ephemeral
        newConfig.httpShouldSetCookies = true
        newConfig.httpCookieStorage = config.httpCookieStorage
        let recreatedSession = URLSession(configuration: newConfig)
        defer { recreatedSession.invalidateAndCancel() }
        let recreatedAPI = APIClient(baseURL: url, session: recreatedSession)
        let reopened = try await recreatedAPI.openSession()
        try expect(reopened.profile.alias == opened.profile.alias && reopened.profile.participating, "Recreated client lost the existing cookie identity")
        let recoveredDiary = try await recreatedAPI.records(month: month)
        try expect(recoveredDiary.stats.success == 1 && recoveredDiary.records.first?.note == "isolated test note", "Recreated client lost server records")
        do {
            _ = try await recreatedAPI.records(month: "invalid")
            throw IntegrationFailure.failed("Invalid request was accepted")
        } catch APIClientError.server(let message) {
            try expect(message.contains("月份"), "API did not preserve server validation error")
        }
        try await api.deleteAccount()
        let afterDelete = try await api.ranking(metric: .success, period: .month)
        try expect(afterDelete.rows.isEmpty, "Test account deletion left public records")
        print("PASS: real URLSession cookie identity, private save, repeated-day count, opt-in ranking, outcome edit, recreated client, server errors, and account cleanup")
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw IntegrationFailure.failed(message) }
    }
}
