import SwiftUI

struct LeaderboardView: View {
    @EnvironmentObject private var model: AppModel
    @State private var metric: Outcome = .declined
    @State private var period: RankingPeriod = .month
    @State private var ranking: RankingResponse?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var showJoinConfirmation = false
    @State private var requestID = UUID()

    private var taskKey: String {
        "\(metric.rawValue)-\(period.rawValue)-\(model.recordsRevision)-\(model.session?.profile.participating == true)-\(model.session?.profile.alias ?? "")"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("原来，\n不止我一个。")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(AppPalette.ink)
                    Text("只晒天数，不晒家事。")
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.muted)
                }
                .padding(.top, 22)

                participationCard

                VStack(spacing: 12) {
                    Picker("榜单类型", selection: $metric) {
                        Text("改天再说 · 拒绝榜").tag(Outcome.declined)
                        Text("今晚有戏 · 成功榜").tag(Outcome.success)
                    }
                    .pickerStyle(.segmented)
                    Picker("统计时间", selection: $period) {
                        ForEach(RankingPeriod.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                if loading && ranking == nil {
                    ProgressView("正在翻小本本…")
                        .tint(AppPalette.blue)
                        .frame(maxWidth: .infinity, minHeight: 150)
                } else if let errorMessage {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("榜单暂时没连上", systemImage: "wifi.exclamationmark")
                            .font(.headline)
                        Text(errorMessage).font(.caption).foregroundStyle(AppPalette.muted)
                        Button("再试一次") { Task { await load() } }
                            .frame(minHeight: 44)
                    }
                } else if let ranking {
                    if ranking.rows.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 30))
                                .foregroundStyle(AppPalette.blue)
                            Text("这一页，等个同道中人。")
                                .font(.title3.weight(.semibold))
                            Text("当前时段还没有公开的\(metric == .success ? "成功" : "被拒绝")记录。私人记录不会自动上榜，换个榜单或时段也可以看看。")
                                .font(.subheadline)
                                .lineSpacing(4)
                                .foregroundStyle(AppPalette.muted)
                        }
                        .padding(.vertical, 20)
                    } else {
                        rankingList(ranking)
                    }
                    Text("\(ranking.total) 人参与此榜 · 一天只记一个结果")
                        .font(.caption)
                        .foregroundStyle(AppPalette.muted)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Color.white)
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
        .refreshable {
            await model.refresh()
            await load()
        }
        .confirmationDialog("和同道中人一起上榜？", isPresented: $showJoinConfirmation, titleVisibility: .visible) {
            Button("同意并上榜") { Task { _ = await model.updateProfile(participating: true) } }
            Button("先记给自己", role: .cancel) {}
        } message: {
            Text("公开你的用户名和成功、被拒绝的汇总天数，不公开具体日期与备注。不要使用真实姓名或联系方式；可随时在设置中退出。")
        }
    }

    private var participationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Label(model.session?.profile.participating == true ? "已开启匿名排行" : "你的小本本，还没公开", systemImage: model.session?.profile.participating == true ? "person.crop.circle.badge.checkmark" : "lock")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppPalette.ink)
                Spacer(minLength: 0)
            }
            if let diary = model.diary {
                Text("本月已保存 \(diary.stats.total) 天 · 成功 \(diary.stats.success) / 被拒绝 \(diary.stats.declined)")
                    .font(.caption)
                    .foregroundStyle(AppPalette.blue)
            }
            if model.session?.profile.participating == true {
                Text(ranking?.mine.map { "这个榜里，你是第 \($0.rank) 名 · \($0.days) 天" } ?? "已开启。选中时段有对应结果，就会出现在榜上。")
                    .font(.caption)
                    .foregroundStyle(AppPalette.muted)
                NavigationLink("修改用户名或退出", destination: SettingsView())
                    .font(.subheadline.weight(.medium))
                    .frame(minHeight: 34)
            } else {
                Text("记录默认只留给自己。上榜后才会公开用户名和汇总天数。")
                    .font(.caption)
                    .foregroundStyle(AppPalette.muted)
                Button("我也来匿名上榜") { showJoinConfirmation = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppPalette.blue)
                    .frame(minHeight: 40)
                    .disabled(!model.canSave)
                    .accessibilityIdentifier("joinLeaderboard")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func rankingList(_ data: RankingResponse) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("排名").frame(width: 42, alignment: .leading)
                Text("同道中人")
                Spacer()
                Text("天数")
            }
            .font(.caption)
            .foregroundStyle(AppPalette.muted)
            .padding(.bottom, 14)
            ForEach(data.rows) { row in
                HStack(spacing: 8) {
                    Text(String(format: "%02d", row.rank))
                        .font(.title3.monospacedDigit())
                        .frame(width: 34, alignment: .leading)
                    Text(row.alias).font(.subheadline).lineLimit(2)
                    if row.isMe { Text("我").font(.caption2).foregroundStyle(AppPalette.blue) }
                    Spacer(minLength: 6)
                    Text("\(row.days)")
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(AppPalette.blue)
                }
                .padding(.vertical, 18)
                .padding(.horizontal, 8)
                .background(row.isMe ? AppPalette.blue.opacity(0.05) : .clear)
                Divider()
            }
        }
    }

    private func load() async {
        let id = UUID()
        requestID = id
        let requestedMetric = metric
        let requestedPeriod = period
        loading = true
        errorMessage = nil
        ranking = nil
        do {
            let response = try await APIClient.shared.ranking(metric: requestedMetric, period: requestedPeriod)
            guard !Task.isCancelled, requestID == id else { return }
            ranking = response
        } catch {
            guard !Task.isCancelled, requestID == id else { return }
            errorMessage = error.localizedDescription
        }
        if requestID == id { loading = false }
    }
}
