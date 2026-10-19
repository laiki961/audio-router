# Audio Router

A small macOS menu bar app that sends each app's audio to a different output device.
For example, Spotify in Brave plays on an external speaker while course videos in another
browser play on the built-in speakers.

Requires macOS 14.4 or later. It uses Core Audio process taps, so you don't need to install an audio driver.

## Build

```sh
xcode-select --install   # once, if you don't have the Command Line Tools
./build.sh
open build/AudioRouter.app
```

## Use

1. Start playing audio in each app so it shows up in the list.
2. Click the speaker icon in the menu bar and pick an output device for each app.
3. The first time, macOS asks for **System Audio Recording** permission. Allow it
   (System Settings → Privacy & Security → Screen & System Audio Recording).

Apps left on "System default" follow the normal macOS output. Set both browsers explicitly
if you don't want them to move when the default output changes (connecting a Bluetooth
speaker often makes it the default).

Assignments are saved and come back the next time you launch the app. If the device an app
is assigned to disconnects, that app falls back to the default output.

## How it works

For each routed app, Audio Router:

1. creates a muted process tap on all of the app's audio processes (browsers play audio from helper processes);
2. creates a private aggregate device that combines the tap with the chosen output device;
3. copies the tapped audio to that device in a real-time IO callback.
