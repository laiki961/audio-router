import CoreAudio
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
    /// Device UID -> hardware volume (0...1), for devices that apps are routed to.
    @Published private(set) var deviceVolumes: [String: Float] = [:]
    /// App id -> software volume, used when the app's device has no volume control.
    @Published private(set) var softwareGains: [String: Float] = [:]

    private var deviceIDs: [String: AudioObjectID] = [:]

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
        let devices = AudioSystem.outputDevices()
        deviceIDs = Dictionary(devices.map { ($0.id, $0.objectID) }, uniquingKeysWith: { a, _ in a })
        let newOutputs = BluetoothAudio.outputOptions(devices: devices,
                                                      bluetooth: BluetoothAudio.pairedAudioDevices())
        if newOutputs != outputs { outputs = newOutputs }
        let newApps = AudioSystem.routableApps(excludingPID: getpid())
        if newApps != apps { apps = newApps }
        sync()
        refreshVolumes()
    }

    /// The volume shown for an app routed to a specific device, or nil if it uses the system default.
    func volume(for app: AudioApp) -> Float? {
        guard let uid = deviceUID(for: app.id) else { return nil }
        return deviceVolumes[uid] ?? softwareGains[app.id] ?? 1
    }

    func setVolume(_ volume: Float, for app: AudioApp) {
        guard let uid = deviceUID(for: app.id) else { return }
        if let device = deviceIDs[uid], deviceVolumes[uid] != nil {
            DeviceVolume.set(device, volume)
            deviceVolumes[uid] = volume
        } else {
            softwareGains[app.id] = volume
            routes[app.id]?.softwareGain = volume
        }
    }

    /// Picks up volume changes made elsewhere (Sound menu, the speaker's own buttons).
    private func refreshVolumes() {
        var volumes: [String: Float] = [:]
        for app in apps {
            guard let uid = deviceUID(for: app.id), let device = deviceIDs[uid],
                  let volume = DeviceVolume.get(device) else { continue }
            volumes[uid] = volume
        }
        if volumes != deviceVolumes { deviceVolumes = volumes }
    }

    private func deviceUID(for appID: String) -> String? {
        assignments[appID].flatMap(option(for:))?.deviceUID
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
        for (id, route) in routes {
            guard let app = appsByID[id],
                  route.deviceUID == deviceUID(for: id),
                  route.processObjects == app.processObjects else {
                routes[id] = nil   // tears down the tap; the app falls back to the default output
                continue
            }
        }

        for app in apps where routes[app.id] == nil {
            // An app with no audio processes yet gets routed as soon as it starts playing.
            guard !app.processObjects.isEmpty, let uid = deviceUID(for: app.id) else { continue }
            do {
                let route = try Route(appName: app.name, processObjects: app.processObjects, deviceUID: uid)
                route.softwareGain = softwareGains[app.id] ?? 1
                routes[app.id] = route
                errors[app.id] = nil
            } catch {
                errors[app.id] = "\(error)"
            }
        }
    }
}
