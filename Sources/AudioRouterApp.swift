import AppKit
import SwiftUI

@main
struct AudioRouterApp: App {
    @StateObject private var model = RouterModel()

    var body: some Scene {
        MenuBarExtra("Audio Router", systemImage: "hifispeaker.2") {
            RouterView().environmentObject(model)
        }
        .menuBarExtraStyle(.window)
    }
}

struct RouterView: View {
    @EnvironmentObject private var model: RouterModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Audio Router").font(.headline)

            if model.apps.isEmpty {
                Text("No apps are using audio yet. Start playing something and it will show up here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.apps) { app in
                AppRow(app: app)
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
    }
}

private struct AppRow: View {
    @EnvironmentObject private var model: RouterModel
    let app: AudioApp

    private var icon: NSImage {
        if let url = app.bundleURL { return NSWorkspace.shared.icon(forFile: url.path) }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }

    private var selection: Binding<String> {
        Binding(
            get: { model.assignments[app.id] ?? "" },
            set: { model.setDevice($0.isEmpty ? nil : $0, for: app) }
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
                    ForEach(model.devices) { device in
                        Text(device.name).tag(device.id)
                    }
                    if let uid = model.assignments[app.id], model.deviceName(for: uid) == nil {
                        Text("Disconnected device").tag(uid)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }
            if let error = model.errors[app.id] {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }
}
