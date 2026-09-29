//
//  Log.swift
//  NutriVision
//

import os
import MetricKit

nonisolated enum Log {
    private static let subsystem = "com.nutrivision"
    static let scanner = Logger(subsystem: subsystem, category: "scanner")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let storage = Logger(subsystem: subsystem, category: "storage")
    static let health = Logger(subsystem: subsystem, category: "health")
    static let app = Logger(subsystem: subsystem, category: "app")

    /// Signposts around per-frame work show up in Instruments' Points of
    /// Interest track, giving per-frame latency without extra tooling.
    static let signposter = OSSignposter(subsystem: subsystem, category: "frame")
}

/// Crash and hang reporting through MetricKit: iOS delivers diagnostics from
/// the previous session, which are logged (and visible in Xcode Organizer)
/// without any third-party SDK.
final class DiagnosticsSubscriber: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = DiagnosticsSubscriber()

    func start() { MXMetricManager.shared.add(self) }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let crashes = payload.crashDiagnostics?.count ?? 0
            let hangs = payload.hangDiagnostics?.count ?? 0
            Log.app.error("MetricKit diagnostics: \(crashes) crashes, \(hangs) hangs")
        }
    }
}
