import CoreAudio
import Foundation

@MainActor
final class AudioDeviceMonitor: ObservableObject {
    @Published var currentDeviceName: String = ""
    @Published var currentDeviceUID: String = ""

    private nonisolated(unsafe) var listenerBlock: AudioObjectPropertyListenerBlock?

    func startMonitoring() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        listenerBlock = { [weak self] (_, _) in
            Task { @MainActor in
                self?.updateCurrentDevice()
            }
        }

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            listenerBlock!
        )

        updateCurrentDevice()
    }

    private func updateCurrentDevice() {
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        guard status == noErr else { return }

        // Get device name
        if let name = getStringProperty(kAudioObjectPropertyName, from: deviceID) {
            currentDeviceName = name
        }

        // Get device UID
        if let uid = getStringProperty(kAudioDevicePropertyDeviceUID, from: deviceID) {
            currentDeviceUID = uid
        }
    }

    private func getStringProperty(_ selector: AudioObjectPropertySelector, from deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        guard sizeStatus == noErr, dataSize > 0 else { return nil }

        var value: Unmanaged<CFString>?
        var valueSize = dataSize
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &valueSize, &value)
        guard status == noErr, let cfString = value?.takeRetainedValue() else { return nil }
        return cfString as String
    }

    func stopMonitoring() {
        guard let block = listenerBlock else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address, DispatchQueue.main, block
        )
        listenerBlock = nil
    }

    var currentDevice: AudioDevice {
        AudioDevice(uid: currentDeviceUID, name: currentDeviceName)
    }
}
