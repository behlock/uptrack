import CoreAudio
import Foundation

@MainActor
final class AudioDeviceMonitor {
    private(set) var currentDevice = AudioDevice(uid: "", name: "")

    /// nonisolated(unsafe) is required because AudioObjectAddPropertyListenerBlock captures
    /// this block outside of Swift's concurrency model. Safe because the block is only set/cleared
    /// from @MainActor methods and dispatched on DispatchQueue.main.
    private nonisolated(unsafe) var listenerBlock: AudioObjectPropertyListenerBlock?

    private static func defaultOutputAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    /// Idempotent: calling this while already monitoring is a no-op, so a listener
    /// can never be registered twice.
    func startMonitoring() {
        guard listenerBlock == nil else { return }

        var address = Self.defaultOutputAddress()
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.updateCurrentDevice()
            }
        }
        listenerBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )

        updateCurrentDevice()
    }

    func stopMonitoring() {
        guard let block = listenerBlock else { return }
        var address = Self.defaultOutputAddress()
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address, DispatchQueue.main, block
        )
        listenerBlock = nil
    }

    private func updateCurrentDevice() {
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = Self.defaultOutputAddress()

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        guard status == noErr else { return }

        currentDevice = AudioDevice(
            uid: getStringProperty(kAudioDevicePropertyDeviceUID, from: deviceID) ?? currentDevice.uid,
            name: getStringProperty(kAudioObjectPropertyName, from: deviceID) ?? currentDevice.name
        )
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
}
