//  Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others

import Cocoa
import Foundation
import os.log

class AndroidTVDisplay: Display {
  let adb: AndroidTVADB
  var tvName: String
  var audioDeviceName: String = ""
  var macAddress: String = ""  // WiFi MAC — stable hardware ID used to find TV after IP changes
  var maxVolume: Int { AndroidTVADB.maxVolume }

  static let syntheticIDBase: CGDirectDisplayID = 0xADB0

  init(host: String, port: Int = 5555, name: String, index: Int = 0) {
    self.adb = AndroidTVADB(host: host, port: port)
    self.tvName = name
    let syntheticID = AndroidTVDisplay.syntheticIDBase + CGDirectDisplayID(index)
    super.init(syntheticID, name: name, vendorNumber: nil, modelNumber: nil, serialNumber: nil, isVirtual: true, isDummy: true)
    self.connectAndLearnMAC()
  }

  private func connectAndLearnMAC() {
    adb.connect(macAddress: macAddress.isEmpty ? nil : macAddress) { [weak self] newIP in
      guard let self = self else { return }
      // IP changed — persist it
      self.adb.host = newIP
      DisplayManager.shared.updateAndroidTVHost(display: self, newHost: newIP)
    }
    // After connecting, read and store MAC if we don't have it yet
    if macAddress.isEmpty {
      DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 2) { [weak self] in
        guard let self = self else { return }
        if let mac = self.adb.readMACAddress(), !mac.isEmpty {
          self.macAddress = mac
          DisplayManager.shared.saveAndroidTVs()
          os_log("AndroidTVDisplay: learned MAC %{public}@ for %{public}@", type: .info, mac, self.tvName)
        }
      }
    }
  }

  // Volume as 0.0–1.0
  func getVolumeFraction() -> Float {
    guard let raw = adb.getVolume() else {
      return readPrefAsFloat(for: .audioSpeakerVolume)
    }
    let fraction = Float(raw) / Float(maxVolume)
    savePref(fraction, for: .audioSpeakerVolume)
    return fraction
  }

  func setVolumeFraction(_ fraction: Float) {
    let level = Int((fraction * Float(maxVolume)).rounded())
    adb.setVolume(level)
    savePref(fraction, for: .audioSpeakerVolume)
    if let slider = sliderHandler[.audioSpeakerVolume] {
      DispatchQueue.main.async {
        slider.setValue(fraction, displayID: self.identifier)
      }
    }
  }

  func stepVolume(isUp: Bool) {
    let current = readPrefAsFloat(for: .audioSpeakerVolume)
    let step: Float = 1.0 / Float(maxVolume)
    let newValue = min(max(0, current + (isUp ? step : -step)), 1)
    savePref(newValue, for: .audioSpeakerVolume)
    if let slider = sliderHandler[.audioSpeakerVolume] {
      DispatchQueue.main.async { slider.setValue(newValue, displayID: self.identifier) }
    }
    adb.sendKeyEvent(isUp ? "KEYCODE_VOLUME_UP" : "KEYCODE_VOLUME_DOWN")
  }
}
