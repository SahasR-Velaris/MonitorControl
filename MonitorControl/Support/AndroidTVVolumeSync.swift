//  Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others

import AudioToolbox
import CoreAudio
import Foundation
import os.log

// Observes macOS default audio output changes and system volume changes.
// When the output is a mapped Android TV:
//   - re-configures MediaKeyTap so volume keys are intercepted
//   - mirrors system volume changes to the TV via ADB (for devices that support virtual main volume)
class AndroidTVVolumeSync {
  static let shared = AndroidTVVolumeSync()

  private var monitoredDeviceID: AudioObjectID = kAudioObjectUnknown
  private var lastSentVolume: Float32 = -1

  init() {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: 0
    )
    AudioObjectAddPropertyListenerBlock(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      DispatchQueue.main
    ) { [weak self] _, _ in
      self?.onDefaultDeviceChanged()
    }
    onDefaultDeviceChanged()
  }

  func onDefaultDeviceChanged() {
    monitoredDeviceID = kAudioObjectUnknown
    lastSentVolume = -1

    guard let deviceID = defaultOutputDeviceID() else {
      os_log("AndroidTVVolumeSync: no default output device", type: .info)
      return
    }
    monitoredDeviceID = deviceID

    let name = deviceName(for: deviceID) ?? "<unknown>"
    os_log("AndroidTVVolumeSync: default output → %{public}@ (id %u)", type: .info, name, deviceID)

    // Log all mapped TVs so we can see if the name matches
    for tv in DisplayManager.shared.androidTVDisplays {
      os_log("AndroidTVVolumeSync:   mapped TV '%{public}@' → audioDeviceName='%{public}@' match=%{public}@",
             type: .info, tv.tvName, tv.audioDeviceName,
             tv.audioDeviceName == name ? "YES" : "NO")
    }

    // Re-configure MediaKeyTap now that audio output has changed — this is the key call
    // that keeps volume keys in the tap when a mapped TV is the output.
    app.mediaKeyTap.updateMediaKeyTap()

    // Also attach a volume-property listener (works for Bluetooth/AirPlay TVs that support
    // kAudioHardwareServiceDeviceProperty_VirtualMainVolume).
    var addr = AudioObjectPropertyAddress(
      mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: 0
    )
    AudioObjectAddPropertyListenerBlock(deviceID, &addr, DispatchQueue.global(qos: .userInteractive)) { [weak self] _, _ in
      self?.handleVolumeChange(on: deviceID)
    }
  }

  private func defaultOutputDeviceID() -> AudioObjectID? {
    var deviceID = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: 0
    )
    let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
    guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
    return deviceID
  }

  private func deviceName(for deviceID: AudioObjectID) -> String? {
    var name: Unmanaged<CFString>? = nil
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioObjectPropertyName,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: 0
    )
    let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)
    guard status == noErr, let ref = name else { return nil }
    return ref.takeRetainedValue() as String
  }

  private func currentVolume(for deviceID: AudioObjectID) -> Float32? {
    var volume: Float32 = 0
    var size = UInt32(MemoryLayout<Float32>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: 0
    )
    let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
    return status == noErr ? volume : nil
  }

  private func handleVolumeChange(on deviceID: AudioObjectID) {
    guard deviceID == monitoredDeviceID else { return }
    guard let volume = currentVolume(for: deviceID) else { return }
    guard abs(volume - lastSentVolume) > 0.005 else { return }
    lastSentVolume = volume
    guard let name = deviceName(for: deviceID) else { return }
    for tv in DisplayManager.shared.androidTVDisplays where !tv.audioDeviceName.isEmpty {
      if tv.audioDeviceName == name {
        os_log("AndroidTVVolumeSync: system volume %.2f → %{public}@", type: .info, volume, tv.tvName)
        tv.setVolumeFraction(volume)
        return
      }
    }
  }
}
