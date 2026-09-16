import SwiftUI

enum AppPalette {
    static let blue = Color(red: 21 / 255, green: 81 / 255, blue: 238 / 255)
    static let ink = Color(red: 24 / 255, green: 39 / 255, blue: 61 / 255)
    static let muted = Color(red: 123 / 255, green: 133 / 255, blue: 153 / 255)
    static let surface = Color(red: 244 / 255, green: 246 / 255, blue: 250 / 255)
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            NavigationStack { HomeView() }
                .tabItem { Label("记录", systemImage: "checklist") }
            NavigationStack { LeaderboardView() }
                .tabItem { Label("排行榜", systemImage: "chart.bar") }
        }
        .tint(AppPalette.blue)
        .preferredColorScheme(.light)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
        .overlay(alignment: .top) {
            if let message = model.errorMessage {
                ErrorBanner(message: message) { model.errorMessage = nil }
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.errorMessage)
    }
}

struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle")
            Text(message).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) { Image(systemName: "xmark") }
                .accessibilityLabel("关闭")
        }
        .foregroundStyle(Color(red: 0.61, green: 0.2, blue: 0.2))
        .padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, 16)
    }
}
