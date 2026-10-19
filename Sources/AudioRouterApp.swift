import AppKit
import SwiftUI

@main
struct AudioRouterApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @StateObject private var model = RouterModel()

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
        let failures = PlaybackPauser.pauseAll()
        if !failures.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Some audio couldn't be paused"
            alert.informativeText = failures.joined(separator: "\n\n")
            alert.addButton(withTitle: "Quit Anyway")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
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

            Divider()
            HStack {
                Button("Refresh") { model.refresh() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 360)
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
