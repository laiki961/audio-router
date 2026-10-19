import Foundation
import SwiftUI

@MainActor
final class RouterModel: ObservableObject {
    @Published private(set) var apps: [AudioApp] = []
    @Published private(set) var devices: [OutputDevice] = []
    @Published private(set) var errors: [String: String] = [:]
    /// App id -> output device UID. Apps without an entry use the system default output.
    @Published private(set) var assignments: [String: String]

    private var routes: [String: Route] = [:]
    private var timer: Timer?
    private let defaultsKey = "assignments"

    init() {
        assignments = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
        refresh()
        // Apps start/stop audio helper processes and devices come and go, so re-scan regularly.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        let newDevices = AudioSystem.outputDevices()
        if newDevices != devices { devices = newDevices }
        let newApps = AudioSystem.audioApps(excludingPID: getpid())
        if newApps != apps { apps = newApps }
        sync()
    }

    func setDevice(_ deviceUID: String?, for app: AudioApp) {
        assignments[app.id] = deviceUID
        UserDefaults.standard.set(assignments, forKey: defaultsKey)
        sync()
    }

    func deviceName(for uid: String) -> String? {
        devices.first { $0.id == uid }?.name
    }

    /// Creates, rebuilds or removes routes so they match the current assignments.
    private func sync() {
        let available = Set(devices.map(\.id))
        let appsByID = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })

        for (id, route) in routes {
            guard let app = appsByID[id],
                  let uid = assignments[id], available.contains(uid),
                  route.deviceUID == uid,
                  route.processObjects == app.processObjects else {
                routes[id] = nil   // tears down the tap; the app falls back to the default output
                continue
            }
        }

        for app in apps where routes[app.id] == nil {
            guard let uid = assignments[app.id], available.contains(uid) else {
                errors[app.id] = nil
                continue
            }
            do {
                routes[app.id] = try Route(appName: app.name, processObjects: app.processObjects, deviceUID: uid)
                errors[app.id] = nil
            } catch {
                errors[app.id] = "\(error)"
            }
        }
    }
}
