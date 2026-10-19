import AppKit

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
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error {
                let name = app.localizedName ?? bundleID
                failures.append("\(name): \(hint(for: bundleID, error: error))")
            }
        }
        return failures
    }

    private static func hint(for bundleID: String, error: NSDictionary) -> String {
        if error[NSAppleScript.errorNumber] as? Int == -1743 {
            return "Allow Audio Router to control it in System Settings → Privacy & Security → Automation."
        }
        switch bundleID {
        case "com.apple.Safari":
            return "Turn on Develop → Allow JavaScript from Apple Events (enable the Develop menu in Settings → Advanced)."
        case "com.google.Chrome", "com.brave.Browser":
            return "Turn on View → Developer → Allow JavaScript from Apple Events."
        default:
            return error[NSAppleScript.errorMessage] as? String ?? "Unknown error."
        }
    }
}
