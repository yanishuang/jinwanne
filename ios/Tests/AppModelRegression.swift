import Foundation

private enum TestError: Error { case offline, failed(String) }

private final class MockAPI: JournalAPI {
    var day = "2026-09-16"
    var profile = Profile(alias: "测试用户", participating: false)
    var entries: [Entry] = []
    var sessionCalls = 0
    var savedDates: [String] = []
    var deletedDates: [String] = []
    var failOpening = false
    var failSaving = false
    var failReading = false
    var failReadingAfterSave = false
    var failDeleting = false
    var failReadingAfterDelete = false
    var readOverride: ((String) async throws -> DiaryResponse)?
    var writeGate: (() async throws -> Void)?

    func openSession() async throws -> SessionResponse {
        sessionCalls += 1
        if failOpening { throw TestError.offline }
        return SessionResponse(profile: profile, today: day, timezone: "Asia/Shanghai")
    }

    func records(month: String) async throws -> DiaryResponse {
        if let readOverride { return try await readOverride(month) }
        if failReading { throw TestError.offline }
        return snapshot(month: month)
    }

    func snapshot(month: String) -> DiaryResponse {
        let records = entries.filter { $0.date.hasPrefix(month) }.sorted { $0.date > $1.date }
        let success = records.filter { $0.outcome == .success }.count
        return DiaryResponse(records: records, stats: RecordStats(success: success, declined: records.count - success, total: records.count))
    }

    func save(date: String, outcome: Outcome, note: String) async throws {
        if failSaving { throw TestError.offline }
        if let writeGate { try await writeGate() }
        savedDates.append(date)
        entries.removeAll { $0.date == date }
        entries.append(Entry(date: date, outcome: outcome, note: note, updatedAt: "2026-09-16T08:00:00Z"))
        if failReadingAfterSave { failReading = true }
    }

    func delete(date: String) async throws {
        if failDeleting { throw TestError.offline }
        if let writeGate { try await writeGate() }
        deletedDates.append(date)
        entries.removeAll { $0.date == date }
        if failReadingAfterDelete { failReading = true }
    }

    func setParticipation(_ participating: Bool) async throws -> Profile {
        profile = Profile(alias: profile.alias, participating: participating)
        return profile
    }

    func setAlias(_ alias: String) async throws -> Profile {
        profile = Profile(alias: alias, participating: profile.participating)
        return profile
    }

    func deleteAccount() async throws { entries = [] }
}

@main
private struct AppModelRegression {
    @MainActor
    static func main() async throws {
        try await check("confirmed save remains successful when refresh fails") {
            let api = MockAPI()
            let instant = date("2026-09-16T08:00:00Z")
            let model = AppModel(api: api, now: { instant })
            await model.bootstrap()
            api.failReadingAfterSave = true
            let success = await model.saveToday(.declined)
            try expect(success, "Confirmed server write was reported as failure")
            try expect(model.todayEntry?.outcome == .declined, "Confirmed record vanished")
            try expect(model.diary?.stats.declined == 1, "Confirmed record was not counted")
            try expect(model.lastSavedAt == instant, "No confirmation timestamp")
            try expect(model.errorMessage == nil && model.refreshWarning != nil, "Refresh warning mixed with save failure")
            api.failReading = false
            api.failReadingAfterSave = false
            await model.refresh()
            try expect(model.refreshWarning == nil, "Refresh warning did not clear after recovery")
        }

        try await check("failed write never appears as saved") {
            let api = MockAPI()
            let model = AppModel(api: api, now: { date("2026-09-16T08:00:00Z") })
            await model.bootstrap()
            api.failSaving = true
            let success = await model.saveToday(.success)
            try expect(!success, "Failed write was reported as successful")
            try expect(model.todayEntry == nil && model.lastSavedAt == nil, "Failed write changed displayed record")
            try expect(model.errorMessage != nil, "No retryable write error")
        }

        try await check("repeated same-day writes count one day and move outcome") {
            let api = MockAPI()
            let model = AppModel(api: api, now: { date("2026-09-16T08:00:00Z") })
            await model.bootstrap()
            for _ in 0..<3 {
                let saved = await model.saveToday(.declined)
                try expect(saved, "Repeated write failed")
            }
            let saved = await model.saveToday(.success)
            try expect(saved, "Outcome edit failed")
            try expect(model.diary?.stats.total == 1 && model.diary?.stats.success == 1 && model.diary?.stats.declined == 0, "Same date was counted multiple times")
        }

        try await check("Shanghai midnight uses new server day and preserves notes") {
            let api = MockAPI()
            api.entries = [Entry(date: "2026-09-16", outcome: .declined, note: "昨天的备注", updatedAt: "")]
            var instant = date("2026-09-16T15:59:00Z")
            let model = AppModel(api: api, now: { instant })
            await model.bootstrap()
            api.day = "2026-09-17"
            api.entries.append(Entry(date: api.day, outcome: .declined, note: "今天已有备注", updatedAt: ""))
            instant = date("2026-09-16T16:01:00Z")
            let saved = await model.saveToday(.success)
            try expect(saved && api.savedDates == ["2026-09-17"], "Rollover overwrote yesterday")
            try expect(api.entries.first { $0.date == "2026-09-16" }?.note == "昨天的备注", "Yesterday changed")
            try expect(model.todayEntry?.note == "今天已有备注", "Rollover dropped an existing note")
            try expect(model.diary?.stats.total == 2, "New day was not counted")
        }

        try await check("month rollover replaces current-month statistics") {
            let api = MockAPI()
            api.day = "2026-09-30"
            api.entries = [Entry(date: api.day, outcome: .declined, note: "", updatedAt: "")]
            var instant = date("2026-09-30T15:59:00Z")
            let model = AppModel(api: api, now: { instant })
            await model.bootstrap()
            api.day = "2026-10-01"
            instant = date("2026-09-30T16:01:00Z")
            let saved = await model.saveToday(.success)
            try expect(saved && model.diary?.stats.total == 1 && model.diary?.stats.declined == 0, "Old month leaked into new month")
        }

        try await check("failed rollover refresh does not write stale date") {
            let api = MockAPI()
            var instant = date("2026-09-16T15:59:00Z")
            let model = AppModel(api: api, now: { instant })
            await model.bootstrap()
            instant = date("2026-09-16T16:01:00Z")
            api.failOpening = true
            let saved = await model.saveToday(.declined)
            try expect(!saved && api.savedDates.isEmpty, "Unverified rollover wrote stale date")
        }

        try await check("retry preserves already-loaded data on connection failure") {
            let api = MockAPI()
            api.entries = [Entry(date: api.day, outcome: .declined, note: "", updatedAt: "")]
            let model = AppModel(api: api, now: { date("2026-09-16T08:00:00Z") })
            await model.bootstrap()
            api.failOpening = true
            await model.retry()
            try expect(model.session != nil && model.todayEntry?.outcome == .declined, "Retry cleared the visible account or data")
            try expect(!model.isLoading && model.errorMessage != nil, "Retry did not finish with an error")
        }

        try await check("startup read failure cannot erase an unread note") {
            let api = MockAPI()
            api.entries = [Entry(date: api.day, outcome: .declined, note: "应保留的备注", updatedAt: "")]
            api.failReading = true
            let model = AppModel(api: api, now: { date("2026-09-16T08:00:00Z") })
            await model.bootstrap()
            let blockedSave = await model.saveToday(.success)
            try expect(!blockedSave && api.savedDates.isEmpty, "Write proceeded without loading prior note")
            api.failReading = false
            let saved = await model.saveToday(.success)
            try expect(saved && model.todayEntry?.note == "应保留的备注", "Recovery erased existing note")
        }

        try await check("slower read cannot overwrite a confirmed newer save") {
            let api = MockAPI()
            let model = AppModel(api: api, now: { date("2026-09-16T08:00:00Z") })
            await model.bootstrap()
            let oldSnapshot = api.snapshot(month: "2026-09")
            var continuation: CheckedContinuation<DiaryResponse, Error>?
            api.readOverride = { _ in
                try await withCheckedThrowingContinuation { continuation = $0 }
            }
            let staleRead = Task { try await model.loadCurrentMonth() }
            while continuation == nil { await Task.yield() }
            api.readOverride = nil
            let saved = await model.saveToday(.declined)
            continuation?.resume(returning: oldSnapshot)
            try await staleRead.value
            try expect(saved && model.todayEntry?.outcome == .declined && model.diary?.stats.total == 1, "Late read erased a newer save")
        }

        try await check("overlapping foreground refreshes share the active load") {
            let api = MockAPI()
            let model = AppModel(api: api, now: { date("2026-09-16T08:00:00Z") })
            await model.bootstrap()
            let calls = api.sessionCalls
            var continuation: CheckedContinuation<DiaryResponse, Error>?
            api.readOverride = { _ in try await withCheckedThrowingContinuation { continuation = $0 } }
            let refreshing = Task { await model.refresh() }
            while continuation == nil { await Task.yield() }
            await model.refresh()
            try expect(api.sessionCalls == calls + 1 && !model.canSave, "Overlapping refresh or conflicting write was allowed")
            continuation?.resume(returning: api.snapshot(month: "2026-09"))
            await refreshing.value
            try expect(model.canSave, "Save remained disabled after refresh")
        }
        try await check("history edit updates home immediately even when refresh fails") {
            let api = MockAPI()
            api.entries = [Entry(date: api.day, outcome: .declined, note: "保留备注", updatedAt: "")]
            let model = AppModel(api: api, now: { date("2026-09-16T08:00:00Z") })
            await model.bootstrap()
            let revision = model.recordsRevision
            api.failReadingAfterSave = true
            let saved = await model.changeRecord(date: api.day, outcome: .success, note: "保留备注")
            try expect(saved && model.todayEntry?.outcome == .success && model.todayEntry?.note == "保留备注", "Confirmed history edit did not update home")
            try expect(model.diary?.stats.success == 1 && model.diary?.stats.declined == 0, "History edit left stale home counts")
            try expect(model.recordsRevision > revision && model.refreshWarning != nil && model.errorMessage == nil, "History edit did not notify views or misreported a failed write")
        }

        try await check("history deletion updates home immediately even when refresh fails") {
            let api = MockAPI()
            api.entries = [Entry(date: api.day, outcome: .declined, note: "", updatedAt: "")]
            let model = AppModel(api: api, now: { date("2026-09-16T08:00:00Z") })
            await model.bootstrap()
            let revision = model.recordsRevision
            api.failReadingAfterDelete = true
            let deleted = await model.deleteRecord(date: api.day)
            try expect(deleted && model.todayEntry == nil && model.diary?.stats.total == 0, "Confirmed history deletion remained visible on home")
            try expect(model.recordsRevision > revision && model.refreshWarning?.contains("删除") == true && model.errorMessage == nil, "Deletion did not invalidate views or misreported a failed write")
        }

        try await check("failed history mutations preserve confirmed records and revisions") {
            let api = MockAPI()
            api.entries = [Entry(date: api.day, outcome: .declined, note: "", updatedAt: "")]
            let model = AppModel(api: api, now: { date("2026-09-16T08:00:00Z") })
            await model.bootstrap()
            let revision = model.recordsRevision
            api.failSaving = true
            let edited = await model.changeRecord(date: api.day, outcome: .success, note: "")
            try expect(!edited && model.todayEntry?.outcome == .declined && model.recordsRevision == revision, "Failed history edit changed confirmed data")
            api.failDeleting = true
            let deleted = await model.deleteRecord(date: api.day)
            try expect(!deleted && model.todayEntry?.outcome == .declined && model.recordsRevision == revision && model.errorMessage != nil, "Failed history deletion removed confirmed data")
        }

        try await check("older-month mutations invalidate rankings without mixing home months") {
            let api = MockAPI()
            api.entries = [Entry(date: api.day, outcome: .success, note: "本月", updatedAt: ""), Entry(date: "2026-08-31", outcome: .success, note: "上月", updatedAt: "")]
            let model = AppModel(api: api, now: { date("2026-09-16T08:00:00Z") })
            await model.bootstrap()
            let revision = model.recordsRevision
            let edited = await model.changeRecord(date: "2026-08-31", outcome: .declined, note: "上月")
            try expect(edited && model.recordsRevision > revision && model.diary?.stats.total == 1 && model.diary?.stats.declined == 0, "Older-month edit contaminated home counts")
            let deleted = await model.deleteRecord(date: "2026-08-31")
            try expect(deleted && model.todayEntry?.note == "本月" && model.diary?.stats.total == 1, "Older-month deletion affected current diary")
        }

        try await check("pending history mutation blocks foreground refresh and other writes") {
            let api = MockAPI()
            let model = AppModel(api: api, now: { date("2026-09-16T08:00:00Z") })
            await model.bootstrap()
            let sessionCalls = api.sessionCalls
            var continuation: CheckedContinuation<Void, Error>?
            api.writeGate = { try await withCheckedThrowingContinuation { continuation = $0 } }
            let editing = Task { await model.changeRecord(date: api.day, outcome: .declined, note: "") }
            while continuation == nil { await Task.yield() }
            await model.refresh()
            let deleted = await model.deleteRecord(date: api.day)
            let saved = await model.saveToday(.success)
            try expect(!deleted && !saved && model.isSaving && !model.canSave && api.sessionCalls == sessionCalls, "History mutation raced refresh or another write")
            continuation?.resume()
            let edited = await editing.value
            try expect(edited && model.canSave && model.todayEntry?.outcome == .declined, "History mutation did not complete")
        }

        try await check("foreground refresh blocks history mutations") {
            let api = MockAPI()
            let model = AppModel(api: api, now: { date("2026-09-16T08:00:00Z") })
            await model.bootstrap()
            var continuation: CheckedContinuation<DiaryResponse, Error>?
            api.readOverride = { _ in try await withCheckedThrowingContinuation { continuation = $0 } }
            let refreshing = Task { await model.refresh() }
            while continuation == nil { await Task.yield() }
            let edited = await model.changeRecord(date: api.day, outcome: .declined, note: "")
            let deleted = await model.deleteRecord(date: api.day)
            try expect(!edited && !deleted && api.savedDates.isEmpty && api.deletedDates.isEmpty, "History mutation bypassed foreground refresh guard")
            continuation?.resume(returning: api.snapshot(month: "2026-09"))
            await refreshing.value
        }
        try await check("changed anonymous identity cannot reuse old diary after failed reload") {
            let api = MockAPI()
            api.entries = [Entry(date: api.day, outcome: .declined, note: "旧身份的私人备注", updatedAt: "")]
            let model = AppModel(api: api, now: { date("2026-09-16T08:00:00Z") })
            await model.bootstrap()
            let revision = model.recordsRevision
            api.profile = Profile(alias: "新匿名用户", participating: false)
            api.entries = []
            api.failReading = true
            await model.refresh()
            try expect(model.session?.profile.alias == "新匿名用户" && model.diary == nil && model.recordsRevision > revision, "Old identity diary survived a new session")
            let blocked = await model.saveToday(.success)
            try expect(!blocked && api.savedDates.isEmpty, "Old notes could be written before new identity loaded")
            api.failReading = false
            let saved = await model.saveToday(.success)
            try expect(saved && model.todayEntry?.note == "", "Old private note leaked into new identity")
        }
        print("17 AppModel regressions passed")
    }

    static func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw TestError.failed(message) }
    }
    @MainActor
    static func check(_ name: String, _ block: () async throws -> Void) async throws {
        try await block()
        print("PASS: \(name)")
    }
}
