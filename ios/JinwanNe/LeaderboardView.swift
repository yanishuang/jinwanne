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
                    Text(L10n.text("原来，\n不止我一个。", "Oh. It’s not\njust me."))
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(AppPalette.ink)
                    Text(L10n.text("只晒天数，不晒家事。", "Share the count. Keep the stories."))
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.muted)
                }
                .padding(.top, 22)

                participationCard

                VStack(spacing: 12) {
                    Picker(L10n.text("榜单类型", "Leaderboard type"), selection: $metric) {
                        Text(L10n.text("改天再说 · 拒绝榜", "Rain checks")).tag(Outcome.declined)
                        Text(L10n.text("今晚有戏 · 成功榜", "Yes nights")).tag(Outcome.success)
                    }
                    .pickerStyle(.segmented)
                    Picker(L10n.text("统计时间", "Time period"), selection: $period) {
                        ForEach(RankingPeriod.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                if loading && ranking == nil {
                    ProgressView(L10n.text("正在翻小本本…", "Turning the pages…"))
                        .tint(AppPalette.blue)
                        .frame(maxWidth: .infinity, minHeight: 150)
                } else if let errorMessage {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(L10n.text("榜单暂时没连上", "The board is out of reach"), systemImage: "wifi.exclamationmark")
                            .font(.headline)
                        Text(errorMessage).font(.caption).foregroundStyle(AppPalette.muted)
                        Button(L10n.text("再试一次", "Try again")) { Task { await load() } }
                            .frame(minHeight: 44)
                    }
                } else if let ranking {
                    if ranking.rows.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 30))
                                .foregroundStyle(AppPalette.blue)
                            Text(L10n.text("这一页，等个同道中人。", "Waiting for a kindred spirit."))
                                .font(.title3.weight(.semibold))
                            Text(L10n.text("当前时段还没有公开的\(metric == .success ? "成功" : "被拒绝")记录。私人记录不会自动上榜，换个榜单或时段也可以看看。", "No public \(metric == .success ? "yes nights" : "rain checks") for this period yet. Private entries never join automatically. Try another board or time period."))
                                .font(.subheadline)
                                .lineSpacing(4)
                                .foregroundStyle(AppPalette.muted)
                        }
                        .padding(.vertical, 20)
                    } else {
                        rankingList(ranking)
                    }
                    Text(L10n.text("\(ranking.total) 人参与此榜 · 一天只记一个结果", "\(ranking.total) on this board · One result per day"))
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
        .navigationTitle(L10n.text("排行榜", "Leaderboard"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "slider.horizontal.3").foregroundStyle(AppPalette.ink)
                }
                .accessibilityLabel(L10n.text("设置", "Settings"))
            }
        }
        .task(id: taskKey) { await load() }
        .refreshable {
            await model.refresh()
            await load()
        }
        .confirmationDialog(L10n.text("和同道中人一起上榜？", "Join the kindred spirits?"), isPresented: $showJoinConfirmation, titleVisibility: .visible) {
            Button(L10n.text("同意并上榜", "Agree and join")) { Task { _ = await model.updateProfile(participating: true) } }
            Button(L10n.text("先记给自己", "Keep it private"), role: .cancel) {}
        } message: {
            Text(L10n.text("公开你的用户名和成功、被拒绝的汇总天数，不公开具体日期与备注。不要使用真实姓名或联系方式；可随时在设置中退出。", "Your username and totals for yes nights and rain checks will be public. Dates and notes stay off the board. Don’t use your real name or contact details. You can leave in Settings anytime."))
        }
    }

    private var participationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Label(model.session?.profile.participating == true ? L10n.text("已开启匿名排行", "You’ve joined the board") : L10n.text("你的小本本，还没公开", "Your diary stays off the board"), systemImage: model.session?.profile.participating == true ? "person.crop.circle.badge.checkmark" : "lock")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppPalette.ink)
                Spacer(minLength: 0)
            }
            if let diary = model.diary {
                Text(L10n.text("本月已保存 \(diary.stats.total) 天 · 成功 \(diary.stats.success) / 被拒绝 \(diary.stats.declined)", "This month: \(diary.stats.total) saved · \(diary.stats.success) yes / \(diary.stats.declined) not tonight"))
                    .font(.caption)
                    .foregroundStyle(AppPalette.blue)
            }
            if model.session?.profile.participating == true {
                Text(ranking?.mine.map { L10n.text("这个榜里，你是第 \($0.rank) 名 · \($0.days) 天", "Your rank: \($0.rank) · \($0.days) \($0.days == 1 ? "day" : "days")") } ?? L10n.text("已开启。选中时段有对应结果，就会出现在榜上。", "You’re in. Matching results for this period will appear here."))
                    .font(.caption)
                    .foregroundStyle(AppPalette.muted)
                NavigationLink(L10n.text("修改用户名或退出", "Change username or leave"), destination: SettingsView())
                    .font(.subheadline.weight(.medium))
                    .frame(minHeight: 34)
            } else {
                Text(L10n.text("记录默认只留给自己。上榜后才会公开用户名和汇总天数。", "Entries stay off the board by default. Joining makes your username and totals public."))
                    .font(.caption)
                    .foregroundStyle(AppPalette.muted)
                Button(L10n.text("我也来匿名上榜", "Count me in")) { showJoinConfirmation = true }
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
                Text(L10n.text("排名", "Rank")).frame(width: 42, alignment: .leading)
                Text(L10n.text("同道中人", "Kindred spirits"))
                Spacer()
                Text(L10n.text("天数", "Days"))
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
                    if row.isMe { Text(L10n.text("我", "Me")).font(.caption2).foregroundStyle(AppPalette.blue) }
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
            errorMessage = L10n.errorMessage(error)
        }
        if requestID == id { loading = false }
    }
}
