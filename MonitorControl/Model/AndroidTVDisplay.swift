//  Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others

import Cocoa
import Foundation
import os.log

class AndroidTVDisplay: Display {
  let adb: AndroidTVADB
  var tvName: String
  // 0–15 internally, exposed as 0.0–1.0 to the UI
  static let maxVolume: Int = 15
  // Synthetic display IDs start here to avoid colliding with real displays
  static let syntheticIDBase: CGDirectDisplayID = 0xADB0

  init(host: String, port: Int = 5555, name: String, index: Int = 0) {
    self.adb = AndroidTVADB(host: host, port: port)
    self.tvName = name
    let syntheticID = AndroidTVDisplay.syntheticIDBase + CGDirectDisplayID(index)
    super.init(syntheticID, name: name, vendorNumber: nil, modelNumber: nil, serialNumber: nil, isVirtual: true, isDummy: true)
    self.adb.connect()
  }

  // Volume as 0.0–1.0
  func getVolumeFraction() -> Float {
    guard let raw = adb.getVolume() else {
      return readPrefAsFloat(for: .audioSpeakerVolume)
    }
    let fraction = Float(raw) / Float(AndroidTVDisplay.maxVolume)
    savePref(fraction, for: .audioSpeakerVolume)
    return fraction
  }

  func setVolumeFraction(_ fraction: Float) {
    let level = Int((fraction * Float(AndroidTVDisplay.maxVolume)).rounded())
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
    let step: Float = 1.0 / Float(AndroidTVDisplay.maxVolume)
    let newValue = min(max(0, current + (isUp ? step : -step)), 1)
    setVolumeFraction(newValue)
  }

  // Brightness is not meaningfully controllable on Android TV — base class handles dummy no-op via isDummy=true
}
