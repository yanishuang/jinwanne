import SwiftUI

struct LeaderboardView: View {
    @EnvironmentObject private var model: AppModel
    @State private var metric: Outcome = .success
    @State private var period: RankingPeriod = .month
    @State private var ranking: RankingResponse?
    @State private var loading = false
    @State private var errorMessage: String?

    private var taskKey: String {
        "\(metric.rawValue)-\(period.rawValue)-\(model.session?.profile.participating == true)-\(model.session?.profile.alias ?? "")"
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("匿名上榜，只看天数。")
                .font(.subheadline)
                .foregroundStyle(AppPalette.muted)
                .padding(.bottom, 22)

            Picker("榜单类型", selection: $metric) {
                Text("成功榜").tag(Outcome.success)
                Text("失败榜").tag(Outcome.declined)
            }
            .pickerStyle(.segmented)

            Picker("统计时间", selection: $period) {
                ForEach(RankingPeriod.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 18)

            if loading {
                Spacer()
                ProgressView("正在读取排行榜…").tint(AppPalette.blue)
                Spacer()
            } else if let errorMessage {
                Spacer()
                ContentUnavailableView("暂时无法读取", systemImage: "wifi.exclamationmark", description: Text(errorMessage))
                Button("重试") { Task { await load() } }.foregroundStyle(AppPalette.blue)
                Spacer()
            } else if let ranking, ranking.rows.isEmpty {
                Spacer()
                ContentUnavailableView("暂时还没有人上榜", systemImage: "chart.bar", description: Text("有对应记录并主动参与后，就会出现在这里。"))
                participationLink(ranking)
                Spacer()
            } else if let ranking {
                rankingList(ranking)
            }
        }
        .padding(.horizontal, 24)
        .navigationTitle("排行榜")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "slider.horizontal.3").foregroundStyle(AppPalette.ink)
                }
                .accessibilityLabel("设置")
            }
        }
        .task(id: taskKey) { await load() }
    }

    @ViewBuilder
    private func rankingList(_ data: RankingResponse) -> some View {
        HStack {
            Text("排名").frame(width: 48, alignment: .leading)
            Text("用户名")
            Spacer()
            Text("天数")
        }
        .font(.caption)
        .foregroundStyle(AppPalette.muted)
        .padding(.vertical, 12)

        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(data.rows) { row in
                    HStack(spacing: 0) {
                        Text(String(format: "%02d", row.rank))
                            .font(.title3.monospacedDigit())
                            .frame(width: 48, alignment: .leading)
                        Text(row.alias)
                            .font(.subheadline)
                            .lineLimit(2)
                        if row.isMe { Text("我").font(.caption2).foregroundStyle(AppPalette.blue) }
                        Spacer(minLength: 8)
                        Text("\(row.days)")
                            .font(.title3.monospacedDigit())
                            .foregroundStyle(AppPalette.blue)
                    }
                    .padding(.vertical, 17)
                    .padding(.horizontal, row.isMe ? 8 : 0)
                    .background(row.isMe ? AppPalette.blue.opacity(0.04) : .clear)
                    Divider()
                }
            }
        }
        participationLink(data)
    }

    private func participationLink(_ data: RankingResponse) -> some View {
        HStack {
            Text(model.session?.profile.participating == true
                 ? data.mine.map { "我的排名：第 \($0.rank) 名 · \($0.days) 天" } ?? "已参与 · 暂无对应记录"
                 : "我还没有参与排行")
                .font(.caption)
                .foregroundStyle(AppPalette.muted)
            Spacer()
            NavigationLink(model.session?.profile.participating == true ? "管理" : "匿名参与", destination: SettingsView())
                .font(.footnote.weight(.medium))
                .foregroundStyle(AppPalette.blue)
        }
        .padding(.vertical, 16)
    }

    private func load() async {
        guard model.session != nil else { return }
        loading = true
        errorMessage = nil
        do { ranking = try await APIClient.shared.ranking(metric: metric, period: period) }
        catch { errorMessage = error.localizedDescription }
        loading = false
    }
}
