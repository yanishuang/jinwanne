import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var session: SessionResponse?
    @Published private(set) var diary: DiaryResponse?
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    var todayEntry: Entry? {
        guard let today = session?.today else { return nil }
        return diary?.records.first { $0.date == today }
    }

    func bootstrap() async {
        guard session == nil, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            let opened = try await APIClient.shared.openSession()
            session = opened
            try await loadCurrentMonth()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func retry() async {
        session = nil
        diary = nil
        await bootstrap()
    }

    func loadCurrentMonth() async throws {
        guard let today = session?.today else { return }
        diary = try await APIClient.shared.records(month: String(today.prefix(7)))
    }

    @discardableResult
    func saveToday(_ outcome: Outcome) async -> Bool {
        guard let today = session?.today, !isSaving else { return false }
        isSaving = true
        errorMessage = nil
        do {
            try await APIClient.shared.save(date: today, outcome: outcome, note: todayEntry?.note ?? "")
            try await loadCurrentMonth()
            isSaving = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
            return false
        }
    }

    func updateProfile(participating: Bool) async -> Bool {
        guard let current = session, !isSaving else { return false }
        isSaving = true
        errorMessage = nil
        do {
            let profile = try await APIClient.shared.setParticipation(participating)
            session = SessionResponse(profile: profile, today: current.today, timezone: current.timezone)
            isSaving = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
            return false
        }
    }

    func updateAlias(_ alias: String) async -> Bool {
        guard let current = session, !isSaving else { return false }
        isSaving = true
        errorMessage = nil
        do {
            let profile = try await APIClient.shared.setAlias(alias)
            session = SessionResponse(profile: profile, today: current.today, timezone: current.timezone)
            isSaving = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
            return false
        }
    }

    func eraseAccount() async -> Bool {
        isSaving = true
        do {
            try await APIClient.shared.deleteAccount()
            session = nil
            diary = nil
            isSaving = false
            await bootstrap()
            return true
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
            return false
        }
    }
}
