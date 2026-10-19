import CoreAudio
import Foundation

/// Sends one app's audio to a specific output device.
///
/// How it works (macOS 14.2+ Core Audio process taps):
/// 1. A process tap captures the app's audio and *mutes* it on the normal output.
/// 2. A private aggregate device combines that tap with the chosen output device.
/// 3. An IO callback copies the tapped audio into the output device's buffers.
final class Route {
    let deviceUID: String
    let processObjects: [AudioObjectID]

    private var tapID = AudioObjectID.unknown
    private var aggregateID = AudioObjectID.unknown
    private var ioProcID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "AudioRouter.io", qos: .userInteractive)
    /// Read by the IO callback; a single aligned Float, so plain reads/writes are safe enough here.
    private let gain = UnsafeMutablePointer<Float>.allocate(capacity: 1)

    /// Software volume applied to the app's audio (used when the device has no volume control).
    var softwareGain: Float {
        get { gain.pointee }
        set { gain.pointee = newValue }
    }

    init(appName: String, processObjects: [AudioObjectID], deviceUID: String) throws {
        self.deviceUID = deviceUID
        self.processObjects = processObjects
        gain.initialize(to: 1)
        do {
            try start(appName: appName)
        } catch {
            stop()
            throw error
        }
    }

    deinit {
        stop()
        gain.deallocate()
    }

    private func start(appName: String) throws {
        let tap = CATapDescription(stereoMixdownOfProcesses: processObjects)
        tap.uuid = UUID()
        tap.name = "Audio Router – \(appName)"
        tap.isPrivate = true
        tap.muteBehavior = .muted
        try check(AudioHardwareCreateProcessTap(tap, &tapID), "Create process tap")

        let format = try tapID.value(kAudioTapPropertyFormat, default: AudioStreamBasicDescription())
        let tapChannels = Int(format.mChannelsPerFrame)
        let gain = self.gain

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Audio Router – \(appName)",
            kAudioAggregateDeviceUIDKey: routerDevicePrefix + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: deviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: deviceUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: tap.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        try check(AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID),
                  "Create aggregate device")

        try check(AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, queue) { _, input, _, output, _ in
            Route.render(input: input, output: output, tapChannels: tapChannels, gain: gain.pointee)
        }, "Create IO callback")
        try check(AudioDeviceStart(aggregateID, ioProcID), "Start output device")
    }

    private func stop() {
        if aggregateID != .unknown {
            if let ioProcID {
                AudioDeviceStop(aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != .unknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        ioProcID = nil
        aggregateID = .unknown
        tapID = .unknown
    }

    // MARK: - Real-time rendering (no allocations or locks below)

    private typealias Channel = (samples: UnsafeMutablePointer<Float>, stride: Int, frames: Int)

    /// Finds channel `index` (counting across buffers, starting at buffer `first`).
    @inline(__always)
    private static func channel(_ list: UnsafeMutableAudioBufferListPointer, first: Int, _ index: Int) -> Channel? {
        var remaining = index
        var b = first
        while b < list.count {
            let buffer = list[b]
            let count = Int(buffer.mNumberChannels)
            if remaining < count {
                guard let data = buffer.mData else { return nil }
                let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * count)
                return (data.assumingMemoryBound(to: Float.self) + remaining, count, frames)
            }
            remaining -= count
            b += 1
        }
        return nil
    }

    private static func render(input: UnsafePointer<AudioBufferList>,
                               output: UnsafeMutablePointer<AudioBufferList>,
                               tapChannels: Int,
                               gain: Float) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)

        var outChannels = 0
        for buffer in outputs {
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
            outChannels += Int(buffer.mNumberChannels)
        }

        // The tap's buffers come after any input streams of the output device itself.
        var firstTap = inputs.count
        var needed = tapChannels
        while needed > 0 && firstTap > 0 {
            firstTap -= 1
            needed -= Int(inputs[firstTap].mNumberChannels)
        }
        guard tapChannels > 0, needed <= 0 else { return }

        // Mono output device: mix the stereo tap down.
        if outChannels == 1, tapChannels >= 2,
           let dst = channel(outputs, first: 0, 0),
           let l = channel(inputs, first: firstTap, 0),
           let r = channel(inputs, first: firstTap, 1) {
            for f in 0..<min(dst.frames, l.frames, r.frames) {
                dst.samples[f * dst.stride] = 0.5 * gain * (l.samples[f * l.stride] + r.samples[f * r.stride])
            }
            return
        }

        for d in 0..<outChannels {
            // Channel d gets tap channel d; a mono tap feeds both left and right. Extra channels stay silent.
            let s = d < tapChannels ? d : (tapChannels == 1 && d == 1 ? 0 : -1)
            guard s >= 0,
                  let dst = channel(outputs, first: 0, d),
                  let src = channel(inputs, first: firstTap, s) else { continue }
            for f in 0..<min(dst.frames, src.frames) {
                dst.samples[f * dst.stride] = gain * src.samples[f * src.stride]
            }
        }
    }
}
