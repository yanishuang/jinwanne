import Foundation
#if os(iOS)
import Combine
import StoreKit
#endif

enum InterfaceLanguage: String {
    case chinese = "zh-Hans"
    case english = "en"

    // Storefront uses ISO 3166-1 alpha-3; device region uses alpha-2.
    static func resolve(storefront: String?, deviceRegion: String?) -> Self {
        if let storefront, !storefront.isEmpty {
            return storefront.uppercased() == "CHN" ? .chinese : .english
        }
        return deviceRegion?.uppercased() == "CN" ? .chinese : .english
    }
}

enum L10n {
    static let preferenceKey = "jinwanne.interfaceLanguage"
    static var language: InterfaceLanguage {
        UserDefaults.standard.string(forKey: preferenceKey).flatMap(InterfaceLanguage.init(rawValue:))
            ?? .resolve(storefront: nil, deviceRegion: Locale.current.region?.identifier)
    }
    static var isChinese: Bool { language == .chinese }
    static var locale: Locale { Locale(identifier: isChinese ? "zh_CN" : "en_US") }
    static func text(_ chinese: String, _ english: String) -> String { isChinese ? chinese : english }
    static var privacyURL: URL { URL(string: "https://jinwanne.woaizhuzhu.com" + (isChinese ? "/privacy" : "/en/privacy"))! }
    static var supportURL: URL { URL(string: "https://jinwanne.woaizhuzhu.com" + (isChinese ? "/support" : "/en/support"))! }

    static func errorMessage(_ error: Error) -> String {
        if let error = error as? APIClientError { return error.localizedDescription }
        if let error = error as? URLError {
            if error.code == .timedOut { return text("连接超时，请稍后重试。", "The connection timed out. Please try again.") }
            if error.code == .cancelled { return text("请求已取消，请重试。", "The request was cancelled. Please try again.") }
            return text("暂时无法连接服务器，请检查网络后重试。", "Couldn't reach the server. Check your connection and try again.")
        }
        return text("操作失败，请稍后重试。", "Something went wrong. Please try again.")
    }
}

#if os(iOS)
@MainActor
final class AppLanguage: ObservableObject {
    @Published private(set) var language: InterfaceLanguage
    @Published private(set) var isReady = false
    private let storefrontKey = "jinwanne.lastStorefrontCountry"

    init() {
        let defaults = UserDefaults.standard
        let storefront = SKPaymentQueue.default().storefront?.countryCode
            ?? defaults.string(forKey: "jinwanne.lastStorefrontCountry")
        if let storefront { defaults.set(storefront, forKey: storefrontKey) }
        language = .resolve(storefront: storefront, deviceRegion: Locale.current.region?.identifier)
        #if DEBUG
        if let testCountry = ProcessInfo.processInfo.environment["JINWANNE_TEST_STOREFRONT"] {
            language = .resolve(storefront: testCountry, deviceRegion: nil)
        }
        #endif
        defaults.set(language.rawValue, forKey: L10n.preferenceKey)
    }

    func prepare() async {
        guard !isReady else { return }
        defer { isReady = true }
        #if DEBUG
        if ProcessInfo.processInfo.environment["JINWANNE_TEST_STOREFRONT"] != nil { return }
        #endif
        // Resolve the store before the first account request, without making an
        // unavailable App Store block this free app. Fall back after 3 seconds.
        await withCheckedContinuation { continuation in
            var resumed = false
            Task {
                let storefront = await Storefront.current
                guard !Task.isCancelled else { return }
                if let storefront { apply(storefront.countryCode) }
                if !resumed { resumed = true; continuation.resume() }
            }
            Task {
                try? await Task.sleep(for: .seconds(3))
                if !resumed {
                    resumed = true
                    // Keep the lookup alive so a slow store response can still
                    // correct the fallback without blocking the first screen.
                    continuation.resume()
                }
            }
        }
    }

    func observeStorefront() async {
        #if DEBUG
        if ProcessInfo.processInfo.environment["JINWANNE_TEST_STOREFRONT"] != nil { return }
        #endif
        for await storefront in Storefront.updates {
            guard !Task.isCancelled else { return }
            apply(storefront.countryCode)
        }
    }

    func refreshDeviceRegion() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["JINWANNE_TEST_STOREFRONT"] != nil { return }
        #endif
        let storefront = SKPaymentQueue.default().storefront?.countryCode
            ?? UserDefaults.standard.string(forKey: storefrontKey)
        apply(storefront)
    }

    private func apply(_ storefront: String?) {
        if let storefront { UserDefaults.standard.set(storefront, forKey: storefrontKey) }
        let selected = InterfaceLanguage.resolve(storefront: storefront, deviceRegion: Locale.current.region?.identifier)
        UserDefaults.standard.set(selected.rawValue, forKey: L10n.preferenceKey)
        if language != selected { language = selected }
    }
}
#endif
