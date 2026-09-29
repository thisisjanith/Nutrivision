//
//  ReminderService.swift
//  NutriVision
//

import Foundation
import UserNotifications

nonisolated struct MealReminder: Codable, Equatable, Identifiable, Sendable {
    var type: MealType
    var hour: Int
    var minute: Int
    var enabled: Bool
    var id: String { type.rawValue }

    static let defaults: [MealReminder] = [
        MealReminder(type: .breakfast, hour: 8, minute: 0, enabled: false),
        MealReminder(type: .lunch, hour: 12, minute: 30, enabled: false),
        MealReminder(type: .dinner, hour: 18, minute: 30, enabled: false),
    ]
}

nonisolated enum ReminderService {
    private static let key = "nutrivision.reminders"
    static let identifierPrefix = "nutrivision.reminder."

    static func load() -> [MealReminder] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([MealReminder].self, from: data) else { return MealReminder.defaults }
        return decoded
    }

    static func save(_ reminders: [MealReminder]) {
        if let data = try? JSONEncoder().encode(reminders) { UserDefaults.standard.set(data, forKey: key) }
    }

    /// One repeating daily request per enabled reminder.
    static func requests(for reminders: [MealReminder]) -> [UNNotificationRequest] {
        reminders.filter(\.enabled).map { reminder in
            let content = UNMutableNotificationContent()
            content.title = "Time to log \(reminder.type.title.lowercased())"
            content.body = "A quick scan keeps your day on track."
            content.sound = .default
            var components = DateComponents()
            components.hour = reminder.hour
            components.minute = reminder.minute
            return UNNotificationRequest(
                identifier: identifierPrefix + reminder.type.rawValue,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            )
        }
    }

    /// Replaces all scheduled meal reminders. Asks for permission the first
    /// time something is enabled; returns false if the user declined.
    @discardableResult
    static func apply(_ reminders: [MealReminder]) async -> Bool {
        save(reminders)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: MealType.allCases.map { identifierPrefix + $0.rawValue })
        let active = requests(for: reminders)
        guard !active.isEmpty else { return true }
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return false }
        for request in active { try? await center.add(request) }
        return true
    }
}
