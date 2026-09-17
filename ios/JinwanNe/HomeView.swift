import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var choosing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let session = model.session {
                    Label(session.today.localizedDayLabel, systemImage: "moon")
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.muted)
                        .padding(.top, 28)
                        .padding(.bottom, 46)
                    homeAction
                } else {
                    Text(L10n.text("今晚呢？", "Tonight?"))
                        .font(.system(size: 46, weight: .bold))
                        .foregroundStyle(AppPalette.ink)
                        .padding(.top, 72)
                    if model.isLoading {
                        ProgressView(L10n.text("正在找回你的小本本…", "Opening your little diary…"))
                            .tint(AppPalette.blue)
                            .padding(.top, 28)
                    } else {
                        Text(L10n.text("连接后，就能记下今晚。", "Connect to jot down how tonight went."))
                            .foregroundStyle(AppPalette.muted)
                            .padding(.vertical, 24)
                        Button(L10n.text("重新连接", "Reconnect")) { Task { await model.retry() } }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                }
                Spacer(minLength: 44)
                NavigationLink(destination: HistoryView()) {
                    HStack {
                        Label(L10n.text("我的小本本", "My little diary"), systemImage: "book.closed")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppPalette.ink)
                    .padding(.vertical, 20)
                }
                .disabled(model.session == nil)
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("自嘲归自嘲，亲密要双方都想。", "Laugh at yourself. Respect each other. Always mutual."))
                    if L10n.isChinese {
                        Link("浙ICP备2026018883号-4A", destination: URL(string: "https://beian.miit.gov.cn/")!)
                    }
                }
                .font(.caption)
                .foregroundStyle(AppPalette.muted)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: 520, minHeight: 640, alignment: .topLeading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.white)
        .refreshable { await model.refresh() }
        .navigationTitle(L10n.text("今晚呢", "Maybe Tonight"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "slider.horizontal.3").foregroundStyle(AppPalette.ink)
                }
                .accessibilityLabel(L10n.text("设置", "Settings"))
            }
        }
    }

    @ViewBuilder
    private var homeAction: some View {
        if choosing {
            VStack(alignment: .leading, spacing: 0) {
                Text(L10n.text("后来呢？", "And then?"))
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(AppPalette.ink)
                Text(L10n.text("有戏没戏，都给今晚一个交代。", "A yes or a rain check. Either way, that was tonight."))
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.muted)
                    .padding(.top, 14)
                    .padding(.bottom, 34)
                HStack(spacing: 12) {
                    outcomeButton(.success)
                    outcomeButton(.declined)
                }
                Text(model.isSaving ? L10n.text("正在保存到云端…", "Saving to the cloud…") : L10n.text("选一个结果，立即保存。同一天只算一天。", "Tap a result to save it. One day, one entry."))
                    .font(.caption)
                    .foregroundStyle(AppPalette.muted)
                    .padding(.top, 18)
                    .accessibilityIdentifier("saveExplanation")
                Button(L10n.text("还没结果，先等等", "Still waiting? Come back later")) { choosing = false }
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.muted)
                    .frame(minHeight: 44)
                    .padding(.top, 20)
                    .disabled(model.isSaving)
            }
        } else if let entry = model.todayEntry {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: entry.outcome == .success ? "sparkles" : "moon.zzz")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(AppPalette.blue)
                    .padding(.bottom, 24)
                Text(entry.outcome == .success ? L10n.text("今晚有戏。", "It’s a yes.") : L10n.text("改天，也行。", "Rain check. Okay."))
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(AppPalette.ink)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                Text(entry.outcome == .success ? L10n.text("今天的小本本，值得画颗星。", "Tonight earns a little star in the diary.") : L10n.text("申请已读。今晚先睡个好觉。", "Message received. A good night’s sleep it is."))
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.muted)
                    .padding(.top, 14)
                Label(L10n.text("\(entry.outcome.title) · 已保存到云端", "\(entry.outcome.title) · Saved to the cloud"), systemImage: "checkmark.icloud")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppPalette.blue)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(AppPalette.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 28)
                    .accessibilityIdentifier("recordSaved")
                Text(L10n.text("今天再改结果，也只记 1 天。", "Changing today’s result still counts as one day."))
                    .font(.caption)
                    .foregroundStyle(AppPalette.muted)
                    .padding(.top, 12)
                if let warning = model.refreshWarning {
                    Text(warning).font(.caption).foregroundStyle(AppPalette.muted).padding(.top, 10)
                }
                Button(L10n.text("改一下结果", "Change the result")) { choosing = true }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppPalette.blue)
                    .frame(minHeight: 44)
                    .padding(.top, 18)
                if model.session?.profile.participating == false {
                    Text(L10n.text("这笔只记给自己。想上榜？去「排行榜」开启。", "This stays off the board. Want to join? Open Leaderboard."))
                        .font(.caption)
                        .foregroundStyle(AppPalette.muted)
                        .padding(.top, 12)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text(L10n.text("今晚呢？", "Tonight?"))
                    .font(.system(size: 52, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(AppPalette.ink)
                Text(L10n.text("问问看。", "Worth asking."))
                    .font(.system(size: 52, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(AppPalette.blue)
                Text(L10n.text("一句话的事，\n有时得攒一天勇气。", "One little question.\nSometimes, a whole day’s courage."))
                    .font(.system(size: 18))
                    .lineSpacing(5)
                    .foregroundStyle(AppPalette.muted)
                    .padding(.top, 22)
                    .padding(.bottom, 38)
                Button {
                    choosing = true
                } label: {
                    HStack {
                        Text(L10n.text("今晚发起了", "I asked tonight"))
                        Spacer()
                        Image(systemName: "arrow.right")
                    }.padding(.horizontal, 22)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!model.canSave)
                .accessibilityIdentifier("startTonight")
                Text(L10n.text("下一步选结果，选完才保存。", "Next, pick the result. That’s when it saves."))
                    .font(.caption)
                    .foregroundStyle(AppPalette.muted)
                    .padding(.top, 14)
            }
        }
    }

    private func outcomeButton(_ outcome: Outcome) -> some View {
        let filled = outcome == .success
        return Button {
            Task {
                if await model.saveToday(outcome) { choosing = false }
            }
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: filled ? "sparkles" : "moon.zzz")
                    .font(.system(size: 25))
                Text(outcome.title)
                    .font(.system(size: L10n.isChinese ? 24 : 22, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(filled ? L10n.text("今晚有戏", "A little spark") : L10n.text("改天再说", "A rain check")).font(.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
            .padding(20)
        }
        .foregroundStyle(filled ? Color.white : AppPalette.blue)
        .background(filled ? AppPalette.blue : AppPalette.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
        .disabled(!model.canSave)
        .accessibilityIdentifier(filled ? "outcomeSuccess" : "outcomeDeclined")
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 66)
            .background(configuration.isPressed ? AppPalette.blue.opacity(0.82) : AppPalette.blue)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
