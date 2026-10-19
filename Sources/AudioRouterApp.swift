import AppKit
import SwiftUI

@main
struct AudioRouterApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @StateObject private var model = RouterModel()

    init() {
        // Runs before the model is created, so a second copy never touches any audio.
        Self.exitIfAlreadyRunning()
    }

    /// Only one Audio Router may run at a time (two copies would both try to route the same apps).
    /// The copy launched later explains where the running one is and quits.
    private static func exitIfAlreadyRunning() {
        let me = NSRunningApplication.current
        guard let bundleID = Bundle.main.bundleIdentifier,
              let other = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first(where: {
                  // Tie-break on PID, so two copies launched at the same moment don't both quit.
                  $0 != me && ($0.launchDate ?? .distantPast, $0.processIdentifier)
                      < (me.launchDate ?? .distantFuture, me.processIdentifier)
              }) else { return }

        let alert = NSAlert()
        alert.messageText = "Audio Router is already running"
        alert.informativeText = "Click the speaker icon in the menu bar to use it."
        if let path = other.bundleURL?.path, path != Bundle.main.bundlePath {
            alert.informativeText += "\n\nThe running copy is at:\n\(path)"
        }
        alert.addButton(withTitle: "OK")
        NSApplication.shared.activate()
        alert.window.level = .floating
        alert.runModal()
        exit(0)
    }

    var body: some Scene {
        MenuBarExtra("Audio Router", systemImage: "hifispeaker.2") {
            RouterView().environmentObject(model)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Pause playback before quitting, while the routes still hold the audio; otherwise it would
    /// jump to the default output once the taps go away.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        log.notice("Quit requested; pausing playback")
        let failures = PlaybackPauser.pauseAll()
        if !failures.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Some audio couldn't be paused"
            alert.informativeText = failures.joined(separator: "\n\n")
            alert.addButton(withTitle: "Quit Anyway")
            alert.addButton(withTitle: "Cancel")
            // Audio Router has no Dock icon, so bring the alert in front of other apps' windows.
            NSApp.activate()
            alert.window.level = .floating
            if alert.runModal() != .alertFirstButtonReturn { return .terminateCancel }
        }
        return .terminateNow
    }
}

struct RouterView: View {
    @EnvironmentObject private var model: RouterModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Audio Router").font(.headline)

            if model.apps.isEmpty {
                Text("Safari, Chrome, Brave or Spotify isn't installed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.apps) { app in
                AppRow(app: app)
            }

            Text("All other apps use the system default output.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !model.pauseProblems.isEmpty {
                Divider()
                PauseWarning()
            }

            Divider()
            HStack {
                Button("Refresh") { model.refresh() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 360)
        .onAppear { model.checkPauseReadiness() }
    }
}

/// Explains which browsers will keep playing when Audio Router quits, and how to fix it.
private struct PauseWarning: View {
    @EnvironmentObject private var model: RouterModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("These won't pause when you quit", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
            ForEach(model.pauseProblems.sorted(by: { $0.key < $1.key }), id: \.key) { bundleID, hint in
                let name = model.apps.first { $0.id == bundleID }?.name ?? bundleID
                Text("**\(name):** \(hint)")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Check Again") { model.checkPauseReadiness() }
                .controlSize(.small)
        }
    }
}

private struct AppRow: View {
    @EnvironmentObject private var model: RouterModel
    let app: AudioApp

    private var icon: NSImage {
        if let url = app.bundleURL { return NSWorkspace.shared.icon(forFile: url.path) }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }

    private var assigned: OutputOption? {
        model.assignments[app.id].flatMap(model.option(for:))
    }

    private var selection: Binding<String> {
        Binding(
            get: { assigned?.id ?? model.assignments[app.id] ?? "" },
            set: { model.setOutput($0.isEmpty ? nil : $0, for: app) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                Text(app.name).lineLimit(1)
                if app.isPlaying {
                    Image(systemName: "waveform").foregroundStyle(.green).help("Playing")
                }
                Spacer()
                Picker("", selection: selection) {
                    Text("System default").tag("")
                    Divider()
                    ForEach(model.outputs.filter(\.isConnected)) { output in
                        Text(output.name).tag(output.id)
                    }
                    let disconnected = model.outputs.filter { !$0.isConnected }
                    if !disconnected.isEmpty {
                        Divider()
                        Section("Bluetooth – connects when picked") {
                            ForEach(disconnected) { output in
                                Text(output.name).tag(output.id)
                            }
                        }
                    }
                    if let id = model.assignments[app.id], assigned == nil {
                        Text("Unavailable device").tag(id)
                    }
                }
                .labelsHidden()
                .frame(width: 170)
            }
            if let output = assigned, output.isConnected, let volume = model.volume(for: app) {
                HStack(spacing: 6) {
                    Image(systemName: "speaker.fill")
                    Slider(value: Binding(get: { Double(volume) },
                                          set: { model.setVolume(Float($0), for: app) }),
                           in: 0...1)
                    Image(systemName: "speaker.wave.3.fill")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 28)
                .help("\(output.name) volume")
            }
            if let output = assigned, !output.isConnected {
                HStack(spacing: 6) {
                    if model.connecting.contains(output.id) {
                        ProgressView().controlSize(.small)
                        Text("Connecting to \(output.name)…")
                    } else {
                        Text("\(output.name) isn't connected.")
                        Button("Connect") { model.connect(output) }.controlSize(.small)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if let error = model.errors[app.id] {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }
}
