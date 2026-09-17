import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var month = ""
    @State private var diary: DiaryResponse?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var deleting: Entry?
    @State private var requestID = UUID()

    private var taskKey: String {
        "\(month)-\(model.recordsRevision)-\(model.session?.profile.alias ?? "")"
    }

    var body: some View {
        List {
            Section {
                Picker(L10n.text("查看月份", "Month"), selection: $month) {
                    ForEach(availableMonths, id: \.self) { Text(monthLabel($0)).tag($0) }
                }
                .disabled(model.isSaving)
            }

            if loading {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if let errorMessage {
                ContentUnavailableView(L10n.text("暂时无法读取", "Couldn’t open your diary"), systemImage: "wifi.exclamationmark", description: Text(errorMessage))
                Button(L10n.text("重新读取", "Try again")) { Task { await load() } }
            } else if let diary {
                Section {
                    HStack {
                        stat(title: L10n.text("成功天数", "Yes nights"), value: diary.stats.success)
                        Divider()
                        stat(title: L10n.text("被拒绝天数", "Rain checks"), value: diary.stats.declined)
                    }
                    .frame(height: 82)
                }

                Section(L10n.text("每日结果", "Day by day")) {
                    if diary.records.isEmpty {
                        Text(L10n.text("小本本还是空的。首页选好结果，这里就有记录了。", "A blank page for now. Pick a result on the home screen to make your first entry."))
                            .foregroundStyle(AppPalette.muted)
                    }
                    ForEach(diary.records) { entry in
                        HStack {
                            Text(entry.date.localizedDayLabel).font(.subheadline)
                            Spacer()
                            Text(entry.outcome.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AppPalette.blue)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(L10n.text("删除", "Delete"), role: .destructive) { deleting = entry }
                                .disabled(!model.canSave)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button(Outcome.success.title) { Task { await change(entry, to: .success) } }
                                .tint(AppPalette.blue)
                                .disabled(!model.canSave)
                            Button(Outcome.declined.title) { Task { await change(entry, to: .declined) } }
                                .tint(AppPalette.muted)
                                .disabled(!model.canSave)
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.text("我的小本本", "My little diary"))
        .refreshable { await load() }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if month.isEmpty { month = model.session.map { String($0.today.prefix(7)) } ?? "" }
        }
        .task(id: taskKey) { await load() }
        .alert(L10n.text("删除这一天？", "Delete this day?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(L10n.text("删除", "Delete"), role: .destructive) {
                guard let deleting else { return }
                Task { await remove(deleting) }
            }
            .disabled(!model.canSave)
            Button(L10n.text("取消", "Cancel"), role: .cancel) { deleting = nil }
        } message: {
            Text(L10n.text("统计和排行榜也会随之更新。", "Your totals and leaderboard position will update too."))
        }
    }

    private var availableMonths: [String] {
        guard let today = model.session?.today else { return [] }
        let pieces = today.split(separator: "-").compactMap { Int($0) }
        guard pieces.count >= 2 else { return [String(today.prefix(7))] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        guard let start = calendar.date(from: DateComponents(year: pieces[0], month: pieces[1], day: 1)) else { return [] }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM"
        return (0..<24).compactMap { calendar.date(byAdding: .month, value: -$0, to: start) }.map(formatter.string)
    }

    private func monthLabel(_ value: String) -> String {
        let parts = value.split(separator: "-")
        guard parts.count == 2 else { return value }
        guard let year = Int(parts[0]), let month = Int(parts[1]), (1...12).contains(month) else { return value }
        if L10n.isChinese { return "\(year) 年 \(month) 月" }
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        return "\(formatter.monthSymbols[month - 1]) \(year)"
    }

    private func stat(title: String, value: Int) -> some View {
        VStack(spacing: 7) {
            Text(title).font(.caption).foregroundStyle(AppPalette.muted)
            Text(L10n.text("\(value) 天", "\(value) \(value == 1 ? "day" : "days")")).font(.title2.weight(.semibold)).foregroundStyle(AppPalette.blue)
        }
        .frame(maxWidth: .infinity)
    }

    private func load() async {
        let id = UUID()
        requestID = id
        let requestedMonth = month
        let revision = model.recordsRevision
        diary = nil
        errorMessage = nil
        guard model.session != nil, !requestedMonth.isEmpty else {
            loading = false
            return
        }
        loading = true
        defer { if requestID == id { loading = false } }
        do {
            let response = try await APIClient.shared.records(month: requestedMonth)
            guard !Task.isCancelled, requestID == id,
                  month == requestedMonth, model.recordsRevision == revision else { return }
            diary = response
        } catch {
            guard !Task.isCancelled, requestID == id,
                  month == requestedMonth, model.recordsRevision == revision else { return }
            errorMessage = L10n.errorMessage(error)
        }
    }

    private func change(_ entry: Entry, to outcome: Outcome) async {
        _ = await model.changeRecord(date: entry.date, outcome: outcome, note: entry.note)
    }

    private func remove(_ entry: Entry) async {
        if await model.deleteRecord(date: entry.date) {
            deleting = nil
        }
    }
}
