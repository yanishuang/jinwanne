import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var month = ""
    @State private var diary: DiaryResponse?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var deleting: Entry?

    var body: some View {
        List {
            Section {
                Picker("查看月份", selection: $month) {
                    ForEach(availableMonths, id: \.self) { Text(monthLabel($0)).tag($0) }
                }
            }

            if loading {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if let errorMessage {
                ContentUnavailableView("暂时无法读取", systemImage: "wifi.exclamationmark", description: Text(errorMessage))
            } else if let diary {
                Section {
                    HStack {
                        stat(title: "成功天数", value: diary.stats.success)
                        Divider()
                        stat(title: "失败天数", value: diary.stats.declined)
                    }
                    .frame(height: 82)
                }

                Section("每日结果") {
                    if diary.records.isEmpty {
                        Text("这个月还没有记录。")
                            .foregroundStyle(AppPalette.muted)
                    }
                    ForEach(diary.records) { entry in
                        HStack {
                            Text(entry.date.chineseDayLabel).font(.subheadline)
                            Spacer()
                            Text(entry.outcome.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AppPalette.blue)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("删除", role: .destructive) { deleting = entry }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button("成功") { Task { await change(entry, to: .success) } }.tint(AppPalette.blue)
                            Button("失败") { Task { await change(entry, to: .declined) } }.tint(AppPalette.muted)
                        }
                    }
                }
            }
        }
        .navigationTitle("我的记录")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if month.isEmpty { month = model.session.map { String($0.today.prefix(7)) } ?? "" }
        }
        .task(id: month) { if !month.isEmpty { await load() } }
        .alert("删除这一天？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("删除", role: .destructive) {
                guard let deleting else { return }
                Task { await remove(deleting) }
            }
            Button("取消", role: .cancel) { deleting = nil }
        } message: {
            Text("统计和排行榜也会随之更新。")
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
        formatter.dateFormat = "yyyy-MM"
        return (0..<24).compactMap { calendar.date(byAdding: .month, value: -$0, to: start) }.map(formatter.string)
    }

    private func monthLabel(_ value: String) -> String {
        let parts = value.split(separator: "-")
        guard parts.count == 2 else { return value }
        return "\(parts[0]) 年 \(Int(parts[1]) ?? 0) 月"
    }

    private func stat(title: String, value: Int) -> some View {
        VStack(spacing: 7) {
            Text(title).font(.caption).foregroundStyle(AppPalette.muted)
            Text("\(value) 天").font(.title2.weight(.semibold)).foregroundStyle(AppPalette.blue)
        }
        .frame(maxWidth: .infinity)
    }

    private func load() async {
        loading = true
        errorMessage = nil
        do { diary = try await APIClient.shared.records(month: month) }
        catch { errorMessage = error.localizedDescription }
        loading = false
    }

    private func change(_ entry: Entry, to outcome: Outcome) async {
        do {
            try await APIClient.shared.save(date: entry.date, outcome: outcome, note: entry.note)
            await load()
            if month == (model.session.map { String($0.today.prefix(7)) } ?? "") { try? await model.loadCurrentMonth() }
        } catch { errorMessage = error.localizedDescription }
    }

    private func remove(_ entry: Entry) async {
        do {
            try await APIClient.shared.delete(date: entry.date)
            deleting = nil
            await load()
            if month == (model.session.map { String($0.today.prefix(7)) } ?? "") { try? await model.loadCurrentMonth() }
        } catch { errorMessage = error.localizedDescription }
    }
}
