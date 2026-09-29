//
//  AppConfig.swift
//  NutriVision
//

import Foundation

/// Runtime configuration. Values can be overridden from `UserDefaults` (handy
/// for pointing a debug build at a local proxy) and otherwise fall back to the
/// constants below.
nonisolated enum AppConfig {
    /// Base URL of the vision-LLM proxy (see `Proxy/worker.js`). The proxy
    /// holds the model API key so it never ships inside the app. Empty means
    /// cloud estimation is disabled and the on-device classifier is used.
    static var proxyURL: URL? {
        let value = UserDefaults.standard.string(forKey: "proxyURL") ?? defaultProxyURL
        return value.isEmpty ? nil : URL(string: value)
    }
    static let defaultProxyURL = ""

    /// Shared secret sent to the proxy so it can reject other callers. This is
    /// a speed bump, not real auth — pair it with rate limiting on the proxy.
    static var proxyToken: String {
        UserDefaults.standard.string(forKey: "proxyToken") ?? ""
    }

    static let usdaAPIKey = "DEMO_KEY"
}
