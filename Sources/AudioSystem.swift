import AppKit
import CoreAudio
import Darwin

/// Prefix used for the UIDs of the aggregate devices this app creates, so we can hide them.
let routerDevicePrefix = "AudioRouter-"

/// The only apps shown in the router, in display order. Everything else uses the system default output.
let routableBundleIDs = ["com.apple.Safari", "com.google.Chrome", "com.brave.Browser", "com.spotify.client"]

/// Returns the app macOS holds responsible for a process (e.g. Safari for its WebKit GPU process).
@_silgen_name("responsibility_get_pid_responsible_for_pid")
private func responsibility_get_pid_responsible_for_pid(_ pid: pid_t) -> pid_t

struct OutputDevice: Identifiable, Hashable {
    let id: String          // device UID (stable across reboots)
    let objectID: AudioObjectID
    let name: String
    let isBluetooth: Bool
}

/// An application that currently has audio sessions. Browsers and Electron apps play
/// audio from helper processes, so all processes inside the same .app bundle are grouped.
struct AudioApp: Identifiable, Equatable {
    let id: String          // bundle identifier of the top-level .app (or a fallback)
    let name: String
    let bundleURL: URL?
    var processObjects: [AudioObjectID]
    var isPlaying: Bool
}

enum AudioSystem {
    static func outputDevices() -> [OutputDevice] {
        let ids = (try? AudioObjectID.system.objectIDs(kAudioHardwarePropertyDevices)) ?? []
        return ids.compactMap { id -> OutputDevice? in
            guard let streams = try? id.objectIDs(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput),
                  !streams.isEmpty,
                  let uid = try? id.string(kAudioDevicePropertyDeviceUID),
                  !uid.hasPrefix(routerDevicePrefix) else { return nil }
            let name = (try? id.string(kAudioObjectPropertyName)) ?? uid
            let transport = (try? id.value(kAudioDevicePropertyTransportType, default: UInt32(0))) ?? 0
            let isBluetooth = transport == kAudioDeviceTransportTypeBluetooth
                || transport == kAudioDeviceTransportTypeBluetoothLE
            return OutputDevice(id: uid, objectID: id, name: name, isBluetooth: isBluetooth)
        }
    }

    /// The routable apps that are installed, with their current audio processes (if any).
    static func routableApps(excludingPID ownPID: pid_t) -> [AudioApp] {
        let active = Dictionary(audioApps(excludingPID: ownPID).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return routableBundleIDs.compactMap { bundleID in
            if let app = active[bundleID] { return app }
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
            return AudioApp(id: bundleID, name: url.deletingPathExtension().lastPathComponent,
                            bundleURL: url, processObjects: [], isPlaying: false)
        }
    }

    static func audioApps(excludingPID ownPID: pid_t) -> [AudioApp] {
        let objects = (try? AudioObjectID.system.objectIDs(kAudioHardwarePropertyProcessObjectList)) ?? []
        var groups: [String: AudioApp] = [:]

        for object in objects {
            guard let pid = try? object.value(kAudioProcessPropertyPID, default: pid_t(0)),
                  pid > 0, pid != ownPID else { continue }
            let bundleID = try? object.string(kAudioProcessPropertyBundleID)
            let owner = owningApp(pid: pid, bundleID: bundleID)
            let playing = ((try? object.value(kAudioProcessPropertyIsRunningOutput, default: UInt32(0))) ?? 0) != 0

            groups[owner.key, default: AudioApp(id: owner.key, name: owner.name, bundleURL: owner.url,
                                                processObjects: [], isPlaying: false)]
                .processObjects.append(object)
            if playing { groups[owner.key]?.isPlaying = true }
        }

        return groups.values
            .map { var app = $0; app.processObjects.sort(); return app }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func executablePath(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    /// Resolves the outermost .app bundle of the process macOS holds responsible for `pid`,
    /// e.g. ".../Brave Browser.app/.../Brave Browser Helper.app/..." -> "Brave Browser".
    private static func owningApp(pid: pid_t, bundleID: String?) -> (key: String, name: String, url: URL?) {
        let responsible = responsibility_get_pid_responsible_for_pid(pid)
        let path = (responsible > 0 ? executablePath(pid: responsible) : nil) ?? executablePath(pid: pid)
        if let path, let range = path.range(of: ".app/") {
            let appPath = String(path[..<range.lowerBound]) + ".app"
            let url = URL(fileURLWithPath: appPath)
            let key = Bundle(url: url)?.bundleIdentifier ?? appPath
            let name = url.deletingPathExtension().lastPathComponent
            return (key, name, url)
        }
        let name = bundleID ?? path.map { ($0 as NSString).lastPathComponent } ?? "Process \(pid)"
        return (bundleID ?? "pid:\(pid)", name, nil)
    }
}
