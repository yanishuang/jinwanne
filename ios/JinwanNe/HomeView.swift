import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var choosing = false

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                if model.isLoading && model.session == nil {
                    ProgressView("正在打开…")
                        .tint(AppPalette.blue)
                } else if let session = model.session {
                    Text(session.today.chineseDayLabel)
                        .font(.footnote)
                        .tracking(0.5)
                        .foregroundStyle(AppPalette.muted)
                        .padding(.bottom, 28)
                    homeAction
                } else {
                    Button("重新连接") { Task { await model.retry() } }
                        .buttonStyle(PrimaryButtonStyle())
                }
                Spacer()
                VStack(spacing: 5) {
                    Text("私人记录 · 双方自愿")
                    Link("浙ICP备2026018883号-4A", destination: URL(string: "https://beian.miit.gov.cn/")!)
                }
                .font(.caption2)
                .tracking(0.4)
                .foregroundStyle(AppPalette.muted.opacity(0.75))
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 30)
        }
        .navigationTitle("今晚呢")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(AppPalette.ink)
                }
                .accessibilityLabel("设置")
            }
        }
    }

    @ViewBuilder
    private var homeAction: some View {
        if choosing {
            VStack(spacing: 24) {
                Text("结果怎么样？")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(AppPalette.ink)
                HStack(spacing: 14) {
                    outcomeButton(.success, filled: true)
                    outcomeButton(.declined, filled: false)
                }
                Button("返回") { choosing = false }
                    .font(.footnote)
                    .foregroundStyle(AppPalette.muted)
                    .frame(minHeight: 44)
            }
        } else if let entry = model.todayEntry {
            VStack(spacing: 16) {
                Image(systemName: entry.outcome == .success ? "checkmark" : "minus")
                    .font(.system(size: 27, weight: .medium))
                    .foregroundStyle(AppPalette.blue)
                    .frame(width: 64, height: 64)
                    .background(AppPalette.blue.opacity(0.08), in: Circle())
                Text("今晚\(entry.outcome.title)")
                    .font(.system(size: 29, weight: .semibold))
                    .foregroundStyle(AppPalette.blue)
                Text("已记下，今天不重复计数。")
                    .font(.footnote)
                    .foregroundStyle(AppPalette.muted)
                Button("修改结果") { choosing = true }
                    .font(.footnote)
                    .foregroundStyle(AppPalette.muted)
                    .frame(minHeight: 44)
            }
        } else {
            Button("今晚发起了") { choosing = true }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    private func outcomeButton(_ outcome: Outcome, filled: Bool) -> some View {
        Button {
            Task {
                if await model.saveToday(outcome) { choosing = false }
            }
        } label: {
            Group {
                if model.isSaving { ProgressView().tint(filled ? .white : AppPalette.blue) }
                else { Text(outcome.title) }
            }
            .font(.system(size: 21, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 64)
        }
        .foregroundStyle(filled ? Color.white : AppPalette.blue)
        .background(filled ? AppPalette.blue : Color.white)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(filled ? AppPalette.blue : AppPalette.blue.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .disabled(model.isSaving)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(configuration.isPressed ? AppPalette.blue.opacity(0.82) : AppPalette.blue)
            .clipShape(RoundedRectangle(cornerRadius: 13))
    }
}
