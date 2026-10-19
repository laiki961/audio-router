import Foundation
import IOBluetooth

/// One entry in the output picker. Mirrors the macOS Sound menu: connected devices plus
/// paired Bluetooth audio devices, which get connected when picked.
struct OutputOption: Identifiable, Hashable {
    let id: String               // "bt:<address>" for Bluetooth devices, otherwise the Core Audio device UID
    let name: String
    let deviceUID: String?       // nil while a Bluetooth device isn't connected
    let bluetoothAddress: String?

    var isConnected: Bool { deviceUID != nil }
}

enum BluetoothAudio {
    struct Device {
        let address: String
        let name: String
    }

    private static let audioMajorClass: BluetoothDeviceClassMajor = 0x04  // kBluetoothDeviceClassMajorAudio

    static func pairedAudioDevices() -> [Device] {
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        return paired.compactMap { device in
            guard device.deviceClassMajor == audioMajorClass, let address = device.addressString else { return nil }
            return Device(address: address, name: device.nameOrAddress ?? address)
        }
    }

    /// Lowercase hex digits only, so "AC:90:85-..." style addresses compare equal.
    static func normalize(_ address: String) -> String {
        String(address.lowercased().filter(\.isHexDigit))
    }

    /// Combines Core Audio output devices with paired Bluetooth audio devices.
    static func outputOptions(devices: [OutputDevice], bluetooth: [Device]) -> [OutputOption] {
        var claimed = Set<String>()
        let bluetoothOptions = bluetooth.map { bt -> OutputOption in
            let address = normalize(bt.address)
            // Core Audio's UID for a Bluetooth device contains its address; fall back to the name.
            let match = devices.first { device in
                !claimed.contains(device.id)
                    && (normalize(device.id).contains(address) || (device.isBluetooth && device.name == bt.name))
            }
            if let match { claimed.insert(match.id) }
            return OutputOption(id: "bt:" + address, name: match?.name ?? bt.name,
                                deviceUID: match?.id, bluetoothAddress: bt.address)
        }
        let others = devices
            .filter { !claimed.contains($0.id) }
            .map { OutputOption(id: $0.id, name: $0.name, deviceUID: $0.id, bluetoothAddress: nil) }

        let byName: (OutputOption, OutputOption) -> Bool = {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return (others + bluetoothOptions.filter(\.isConnected)).sorted(by: byName)
            + bluetoothOptions.filter { !$0.isConnected }.sorted(by: byName)
    }
}

/// Connects paired Bluetooth devices asynchronously, like clicking one in the Sound menu.
final class BluetoothConnector: NSObject {
    private var pending: [String: (Bool) -> Void] = [:]

    func connect(address: String, completion: @escaping (Bool) -> Void) {
        guard let device = IOBluetoothDevice(addressString: address) else { return completion(false) }
        if device.isConnected() { return completion(true) }
        pending[address] = completion
        if device.openConnection(self) != kIOReturnSuccess {
            pending.removeValue(forKey: address)?(false)
        }
    }

    @objc(connectionComplete:status:)
    func connectionComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        guard let address = device.addressString else { return }
        let key = pending.keys.first { BluetoothAudio.normalize($0) == BluetoothAudio.normalize(address) } ?? address
        pending.removeValue(forKey: key)?(status == kIOReturnSuccess)
    }
}
