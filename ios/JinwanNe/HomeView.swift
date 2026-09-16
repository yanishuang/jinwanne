import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var choosing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let session = model.session {
                    Label(session.today.chineseDayLabel, systemImage: "moon")
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.muted)
                        .padding(.top, 28)
                        .padding(.bottom, 46)
                    homeAction
                } else {
                    Text("今晚呢？")
                        .font(.system(size: 46, weight: .bold))
                        .foregroundStyle(AppPalette.ink)
                        .padding(.top, 72)
                    if model.isLoading {
                        ProgressView("正在找回你的小本本…")
                            .tint(AppPalette.blue)
                            .padding(.top, 28)
                    } else {
                        Text("连接后，就能记下今晚。")
                            .foregroundStyle(AppPalette.muted)
                            .padding(.vertical, 24)
                        Button("重新连接") { Task { await model.retry() } }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                }
                Spacer(minLength: 44)
                NavigationLink(destination: HistoryView()) {
                    HStack {
                        Label("我的小本本", systemImage: "book.closed")
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
                    Text("自嘲归自嘲，亲密要双方都想。")
                    Link("浙ICP备2026018883号-4A", destination: URL(string: "https://beian.miit.gov.cn/")!)
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
        .navigationTitle("今晚呢")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "slider.horizontal.3").foregroundStyle(AppPalette.ink)
                }
                .accessibilityLabel("设置")
            }
        }
    }

    @ViewBuilder
    private var homeAction: some View {
        if choosing {
            VStack(alignment: .leading, spacing: 0) {
                Text("后来呢？")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(AppPalette.ink)
                Text("有戏没戏，都给今晚一个交代。")
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.muted)
                    .padding(.top, 14)
                    .padding(.bottom, 34)
                HStack(spacing: 12) {
                    outcomeButton(.success)
                    outcomeButton(.declined)
                }
                Text(model.isSaving ? "正在保存到云端…" : "选一个结果，立即保存。同一天只算一天。")
                    .font(.caption)
                    .foregroundStyle(AppPalette.muted)
                    .padding(.top, 18)
                    .accessibilityIdentifier("saveExplanation")
                Button("还没结果，先等等") { choosing = false }
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
                Text(entry.outcome == .success ? "今晚有戏。" : "改天，也行。")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(AppPalette.ink)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                Text(entry.outcome == .success ? "今天的小本本，值得画颗星。" : "申请已读。今晚先睡个好觉。")
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.muted)
                    .padding(.top, 14)
                Label("\(entry.outcome.title) · 已保存到云端", systemImage: "checkmark.icloud")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppPalette.blue)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(AppPalette.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 28)
                    .accessibilityIdentifier("recordSaved")
                Text("今天再改结果，也只记 1 天。")
                    .font(.caption)
                    .foregroundStyle(AppPalette.muted)
                    .padding(.top, 12)
                if let warning = model.refreshWarning {
                    Text(warning).font(.caption).foregroundStyle(AppPalette.muted).padding(.top, 10)
                }
                Button("改一下结果") { choosing = true }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppPalette.blue)
                    .frame(minHeight: 44)
                    .padding(.top, 18)
                if model.session?.profile.participating == false {
                    Text("这笔只记给自己。想上榜？去「排行榜」开启。")
                        .font(.caption)
                        .foregroundStyle(AppPalette.muted)
                        .padding(.top, 12)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text("今晚呢？")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(AppPalette.ink)
                Text("问问看。")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(AppPalette.blue)
                Text("一句话的事，\n有时得攒一天勇气。")
                    .font(.system(size: 18))
                    .lineSpacing(5)
                    .foregroundStyle(AppPalette.muted)
                    .padding(.top, 22)
                    .padding(.bottom, 38)
                Button {
                    choosing = true
                } label: {
                    HStack {
                        Text("今晚发起了")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }.padding(.horizontal, 22)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!model.canSave)
                .accessibilityIdentifier("startTonight")
                Text("下一步选结果，选完才保存。")
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
                Text(outcome.title).font(.system(size: 24, weight: .semibold))
                Text(filled ? "今晚有戏" : "改天再说").font(.caption)
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
