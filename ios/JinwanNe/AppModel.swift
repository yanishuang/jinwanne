import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var session: SessionResponse?
    @Published private(set) var diary: DiaryResponse?
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var lastSavedAt: Date?
    @Published private(set) var recordsRevision = 0
    @Published private(set) var refreshWarning: String?
    @Published var errorMessage: String?

    private let api: any JournalAPI
    private let now: () -> Date
    private var loadedMonth: String?
    private var latestDiaryLoad = UUID()

    init(api: any JournalAPI = APIClient.shared, now: @escaping () -> Date = Date.init) {
        self.api = api
        self.now = now
    }

    var canSave: Bool { session != nil && !isSaving && !isLoading }

    func clearPresentationMessages() {
        errorMessage = nil
        refreshWarning = nil
    }

    var todayEntry: Entry? {
        guard let today = session?.today else { return nil }
        return diary?.records.first { $0.date == today }
    }

    func bootstrap() async {
        guard session == nil else { return }
        await refresh()
    }

    func refresh() async {
        guard !isLoading, !isSaving else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            acceptSession(try await api.openSession())
            try await loadCurrentMonth()
        } catch {
            errorMessage = L10n.errorMessage(error)
        }
    }

    func retry() async {
        await refresh()
    }

    func loadCurrentMonth() async throws {
        guard let today = session?.today else { return }
        let month = String(today.prefix(7))
        let requestID = UUID()
        latestDiaryLoad = requestID
        let revision = recordsRevision
        let updated = try await api.records(month: month)
        // A slower read must not replace a newer save or a later month's records.
        guard latestDiaryLoad == requestID,
              recordsRevision == revision,
              session.map({ String($0.today.prefix(7)) }) == month else { return }
        diary = updated
        loadedMonth = month
        recordsRevision += 1
        refreshWarning = nil
    }

    @discardableResult
    func saveToday(_ outcome: Outcome) async -> Bool {
        guard canSave else { return false }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        refreshWarning = nil
        do {
            try await updateDayBeforeSaving()
            guard let today = session?.today else { return false }
            // Read before a write if startup/rollover could not load this month,
            // so changing a result never silently erases an existing note.
            if loadedMonth != String(today.prefix(7)) { try await loadCurrentMonth() }
            guard loadedMonth == String(today.prefix(7)), diary != nil else {
                throw APIClientError.server(L10n.text("本月记录还未读取完成，请稍后再试。", "This month’s records haven’t loaded yet. Please try again."))
            }
            let note = todayEntry?.note ?? ""
            try await api.save(date: today, outcome: outcome, note: note)
            let savedAt = now()
            lastSavedAt = savedAt
            applyConfirmedSave(date: today, outcome: outcome, note: note, savedAt: savedAt)
            await refreshAfterConfirmedChange(date: today, deleted: false)
            return true
        } catch {
            errorMessage = L10n.errorMessage(error)
            return false
        }
    }

    @discardableResult
    func changeRecord(date: String, outcome: Outcome, note: String) async -> Bool {
        guard canSave else { return false }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        refreshWarning = nil
        do {
            try await api.save(date: date, outcome: outcome, note: note)
            let savedAt = now()
            if date == session?.today { lastSavedAt = savedAt }
            applyConfirmedSave(date: date, outcome: outcome, note: note, savedAt: savedAt)
            await refreshAfterConfirmedChange(date: date, deleted: false)
            return true
        } catch {
            errorMessage = L10n.errorMessage(error)
            return false
        }
    }

    @discardableResult
    func deleteRecord(date: String) async -> Bool {
        guard canSave else { return false }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        refreshWarning = nil
        do {
            try await api.delete(date: date)
            if date == session?.today { lastSavedAt = nil }
            recordsRevision += 1
            if loadedMonth == String(date.prefix(7)), let diary {
                replaceDiaryRecords(diary.records.filter { $0.date != date })
            }
            await refreshAfterConfirmedChange(date: date, deleted: true)
            return true
        } catch {
            errorMessage = L10n.errorMessage(error)
            return false
        }
    }

    func updateProfile(participating: Bool) async -> Bool {
        guard let current = session, canSave else { return false }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        do {
            let profile = try await api.setParticipation(participating)
            session = SessionResponse(profile: profile, today: current.today, timezone: current.timezone)
            return true
        } catch {
            errorMessage = L10n.errorMessage(error)
            return false
        }
    }

    func updateAlias(_ alias: String) async -> Bool {
        guard let current = session, canSave else { return false }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        do {
            let profile = try await api.setAlias(alias)
            session = SessionResponse(profile: profile, today: current.today, timezone: current.timezone)
            return true
        } catch {
            errorMessage = L10n.errorMessage(error)
            return false
        }
    }

    func eraseAccount() async -> Bool {
        guard canSave else { return false }
        isSaving = true
        errorMessage = nil
        do {
            try await api.deleteAccount()
            session = nil
            diary = nil
            loadedMonth = nil
            lastSavedAt = nil
            refreshWarning = nil
            recordsRevision += 1
            isSaving = false
            await bootstrap()
            return true
        } catch {
            errorMessage = L10n.errorMessage(error)
            isSaving = false
            return false
        }
    }

    private func acceptSession(_ opened: SessionResponse) {
        // The server may return a new anonymous identity when a credential expires.
        // A changed unique alias is a conservative cache boundary: remote renames
        // only cause a reload, while old identity notes can never enter a new save.
        let identityMayHaveChanged = session.map { $0.profile.alias != opened.profile.alias } ?? false
        session = opened
        if identityMayHaveChanged {
            recordsRevision += 1
            lastSavedAt = nil
            refreshWarning = nil
        }
        if identityMayHaveChanged || loadedMonth != String(opened.today.prefix(7)) {
            diary = nil
            loadedMonth = nil
        }
    }

    private func updateDayBeforeSaving() async throws {
        guard let current = session else { return }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: current.timezone) ?? TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        if formatter.string(from: now()) != current.today {
            // Use the server's date after midnight, never a stale launch date.
            acceptSession(try await api.openSession())
            try await loadCurrentMonth()
        }
    }

    private func applyConfirmedSave(date: String, outcome: Outcome, note: String, savedAt: Date) {
        recordsRevision += 1
        // History may edit any month. Never mix it into the home month's diary.
        guard loadedMonth == String(date.prefix(7)), let diary else { return }
        var records = diary.records.filter { $0.date != date }
        records.append(Entry(date: date, outcome: outcome, note: note, updatedAt: ISO8601DateFormatter().string(from: savedAt)))
        records.sort { $0.date > $1.date }
        replaceDiaryRecords(records)
    }

    private func replaceDiaryRecords(_ records: [Entry]) {
        let success = records.filter { $0.outcome == .success }.count
        diary = DiaryResponse(records: records, stats: RecordStats(success: success, declined: records.count - success, total: records.count))
    }

    private func refreshAfterConfirmedChange(date: String, deleted: Bool) async {
        guard session.map({ String($0.today.prefix(7)) }) == String(date.prefix(7)) else { return }
        do {
            try await loadCurrentMonth()
        } catch {
            // The mutation is already confirmed. A failed GET is not a failed write.
            refreshWarning = deleted
                ? L10n.text("记录已从服务器删除，统计暂未刷新。下拉刷新可重试。", "Deleted from the server. Totals haven’t refreshed yet. Pull down to retry.")
                : L10n.text("记录已保存到服务器，统计暂未刷新。下拉刷新可重试。", "Saved to the server. Totals haven’t refreshed yet. Pull down to retry.")
        }
    }
}
