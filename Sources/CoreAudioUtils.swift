import CoreAudio
import Foundation

struct CoreAudioError: Error, CustomStringConvertible {
    let status: OSStatus
    let context: String
    var description: String { "\(context) failed (OSStatus \(status))" }
}

func check(_ status: OSStatus, _ context: @autoclosure () -> String) throws {
    guard status == noErr else { throw CoreAudioError(status: status, context: context()) }
}

extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = AudioObjectID(kAudioObjectUnknown)

    private func address(_ selector: AudioObjectPropertySelector,
                         _ scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    /// Reads a fixed-size property value.
    func value<T>(_ selector: AudioObjectPropertySelector,
                  scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                  default defaultValue: T) throws -> T {
        var addr = address(selector, scope)
        var size = UInt32(MemoryLayout<T>.size)
        var value = defaultValue
        let status = withUnsafeMutableBytes(of: &value) {
            AudioObjectGetPropertyData(self, &addr, 0, nil, &size, $0.baseAddress!)
        }
        try check(status, "Read property \(selector)")
        return value
    }

    /// Reads a property that is an array of AudioObjectIDs.
    func objectIDs(_ selector: AudioObjectPropertySelector,
                   scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> [AudioObjectID] {
        var addr = address(selector, scope)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(self, &addr, 0, nil, &size), "Read size of \(selector)")
        let count = Int(size) / MemoryLayout<AudioObjectID>.stride
        guard count > 0 else { return [] }
        var ids = [AudioObjectID](repeating: .unknown, count: count)
        try check(AudioObjectGetPropertyData(self, &addr, 0, nil, &size, &ids), "Read property \(selector)")
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.stride))
    }

    /// Reads a CFString property.
    func string(_ selector: AudioObjectPropertySelector,
                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> String {
        var addr = address(selector, scope)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var ref: Unmanaged<CFString>?
        try check(AudioObjectGetPropertyData(self, &addr, 0, nil, &size, &ref), "Read property \(selector)")
        guard let ref else { throw CoreAudioError(status: -1, context: "Read property \(selector)") }
        return ref.takeRetainedValue() as String
    }
}
