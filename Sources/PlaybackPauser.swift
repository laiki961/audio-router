import AppKit
import os

let log = Logger(subsystem: "com.nikkiip.AudioRouter", category: "app")

/// Pauses playback in the routable apps (used on quit, so audio doesn't jump to the default output).
enum PlaybackPauser {
    /// Pauses every <video>/<audio> element; on the Spotify web player, presses its pause button
    /// (its audio element isn't always in the page).
    private static let pauseJavaScript = """
        document.querySelectorAll('video,audio').forEach(function (m) { m.pause(); });\
        var b = document.querySelector('[data-testid=control-button-playpause]');\
        if (b && b.getAttribute('aria-label') === 'Pause') { b.click(); }
        """

    private static func chromiumScript(_ bundleID: String) -> String {
        """
        tell application id "\(bundleID)"
            repeat with w in windows
                repeat with t in tabs of w
                    tell t to execute javascript "\(pauseJavaScript)"
                end repeat
            end repeat
        end tell
        """
    }

    private static let scripts: [String: String] = [
        "com.apple.Safari": """
            tell application id "com.apple.Safari"
                repeat with w in windows
                    repeat with t in tabs of w
                        do JavaScript "\(pauseJavaScript)" in t
                    end repeat
                end repeat
            end tell
            """,
        "com.google.Chrome": chromiumScript("com.google.Chrome"),
        "com.brave.Browser": chromiumScript("com.brave.Browser"),
        "com.spotify.client": #"tell application id "com.spotify.client" to pause"#,
    ]

    /// Pauses all running routable apps. Returns a message for each app that couldn't be paused.
    static func pauseAll() -> [String] {
        var failures: [String] = []
        for bundleID in routableBundleIDs {
            // Only talk to running apps; `tell application` would launch the others.
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
                  let source = scripts[bundleID] else { continue }
            var error: NSDictionary?
            log.notice("Pausing \(bundleID, privacy: .public)")
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error {
                log.error("Pause failed for \(bundleID, privacy: .public): \(error, privacy: .public)")
                let name = app.localizedName ?? bundleID
                let number = error[NSAppleScript.errorNumber] as? Int
                let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error."
                failures.append("\(name): \(hint(for: bundleID, errorNumber: number, message: message))")
            }
        }
        return failures
    }

    // MARK: - Checking ahead of time

    /// Runs a harmless script in the front tab of each running browser to find out, before quitting,
    /// whether pausing will work. Returns bundle ID -> how to fix it. Browsers with no open
    /// windows can't be checked and are left out.
    static func checkReadiness() async -> [String: String] {
        let checks: [String: String] = [
            "com.apple.Safari": """
                tell application id "com.apple.Safari"
                    if (count of documents) > 0 then do JavaScript "1" in front document
                end tell
                """,
            "com.google.Chrome": chromiumCheck("com.google.Chrome"),
            "com.brave.Browser": chromiumCheck("com.brave.Browser"),
        ]
        return await withTaskGroup(of: (String, String?).self) { group in
            for (bundleID, source) in checks
            where !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
                group.addTask { (bundleID, await problem(running: source, for: bundleID)) }
            }
            var problems: [String: String] = [:]
            for await (bundleID, problem) in group {
                if let problem { problems[bundleID] = problem }
            }
            return problems
        }
    }

    private static func chromiumCheck(_ bundleID: String) -> String {
        """
        tell application id "\(bundleID)"
            if (count of windows) > 0 then execute active tab of front window javascript "1"
        end tell
        """
    }

    /// Runs `source` with osascript (off the main thread; macOS still attributes the
    /// Automation permission to Audio Router) and returns a fix-it hint if it failed.
    private static func problem(running source: String, for bundleID: String) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            let stderr = Pipe()
            process.standardError = stderr
            process.standardOutput = FileHandle.nullDevice
            process.terminationHandler = { process in
                guard process.terminationStatus != 0 else { return continuation.resume(returning: nil) }
                let output = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                // osascript errors end with "(<number>)".
                let number = output.range(of: #"\((-?\d+)\)\s*$"#, options: .regularExpression)
                    .flatMap { Int(output[$0].filter { $0.isNumber || $0 == "-" }) }
                log.error("Pause check failed for \(bundleID, privacy: .public): \(output, privacy: .public)")
                continuation.resume(returning: hint(for: bundleID, errorNumber: number, message: output))
            }
            do { try process.run() } catch { continuation.resume(returning: nil) }
        }
    }

    private static func hint(for bundleID: String, errorNumber: Int?, message: String) -> String {
        if errorNumber == -1743 {
            return "Allow Audio Router to control it in System Settings → Privacy & Security → Automation."
        }
        switch bundleID {
        case "com.apple.Safari":
            return "Turn on Develop → Allow JavaScript from Apple Events (enable the Develop menu in Settings → Advanced)."
        case "com.google.Chrome", "com.brave.Browser":
            return "Turn on View → Developer → Allow JavaScript from Apple Events."
        default:
            return message
        }
    }
}
