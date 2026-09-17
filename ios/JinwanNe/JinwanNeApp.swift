import SwiftUI

@main
struct JinwanNeApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var language = AppLanguage()

    var body: some Scene {
        WindowGroup {
            Group {
                if language.isReady {
                    RootView().id(language.language.rawValue)
                } else {
                    ProgressView(L10n.text("正在打开小本本…", "Opening your little diary…"))
                }
            }
                .environmentObject(model)
                .environment(\.locale, L10n.locale)
                .task {
                    await language.prepare()
                    await model.bootstrap()
                }
                .task { await language.observeStorefront() }
                .onChange(of: language.language) { _, _ in model.clearPresentationMessages() }
                .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
                    language.refreshDeviceRegion()
                }
        }
    }
}
