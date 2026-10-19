import Foundation
import SwiftUI

@MainActor
final class RouterModel: ObservableObject {
    @Published private(set) var apps: [AudioApp] = []
    @Published private(set) var outputs: [OutputOption] = []
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var connecting: Set<String> = []   // Bluetooth option ids being connected
    /// App id -> output option id. Apps without an entry use the system default output.
    @Published private(set) var assignments: [String: String]

    private var routes: [String: Route] = [:]
    private var timer: Timer?
    private let bluetooth = BluetoothConnector()
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
        let newOutputs = BluetoothAudio.outputOptions(devices: AudioSystem.outputDevices(),
                                                      bluetooth: BluetoothAudio.pairedAudioDevices())
        if newOutputs != outputs { outputs = newOutputs }
        let newApps = AudioSystem.routableApps(excludingPID: getpid())
        if newApps != apps { apps = newApps }
        sync()
    }

    func setOutput(_ optionID: String?, for app: AudioApp) {
        assignments[app.id] = optionID
        UserDefaults.standard.set(assignments, forKey: defaultsKey)
        if let option = optionID.flatMap(option(for:)), !option.isConnected {
            connect(option)
        }
        sync()
    }

    func option(for id: String) -> OutputOption? {
        outputs.first { $0.id == id || $0.deviceUID == id }
    }

    func connect(_ option: OutputOption) {
        guard let address = option.bluetoothAddress, !connecting.contains(option.id) else { return }
        connecting.insert(option.id)
        bluetooth.connect(address: address) { [weak self] success in
            Task { @MainActor in
                guard let self else { return }
                self.connecting.remove(option.id)
                if !success {
                    for (app, assigned) in self.assignments where assigned == option.id {
                        self.errors[app] = "Couldn't connect to \(option.name). Is it on and in range?"
                    }
                }
                self.refresh()
            }
        }
    }

    /// Creates, rebuilds or removes routes so they match the current assignments.
    private func sync() {
        let appsByID = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
        let deviceUID: (String) -> String? = { [self] appID in
            assignments[appID].flatMap(option(for:))?.deviceUID
        }

        for (id, route) in routes {
            guard let app = appsByID[id],
                  route.deviceUID == deviceUID(id),
                  route.processObjects == app.processObjects else {
                routes[id] = nil   // tears down the tap; the app falls back to the default output
                continue
            }
        }

        for app in apps where routes[app.id] == nil {
            // An app with no audio processes yet gets routed as soon as it starts playing.
            guard !app.processObjects.isEmpty, let uid = deviceUID(app.id) else { continue }
            do {
                routes[app.id] = try Route(appName: app.name, processObjects: app.processObjects, deviceUID: uid)
                errors[app.id] = nil
            } catch {
                errors[app.id] = "\(error)"
            }
        }
    }
}
