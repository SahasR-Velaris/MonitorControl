//  Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others

import Foundation
import os.log

class AndroidTVADB {
  let host: String
  let port: Int

  private var adbPath: String {
    let candidates = ["/opt/homebrew/bin/adb", "/usr/local/bin/adb", "/usr/bin/adb"]
    return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? "adb"
  }

  init(host: String, port: Int = 5555) {
    self.host = host
    self.port = port
  }

  @discardableResult
  private func run(_ args: [String]) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: adbPath)
    process.arguments = ["-s", "\(host):\(port)"] + args
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    do {
      try process.run()
      process.waitUntilExit()
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
      os_log("AndroidTVADB run error: %{public}@", type: .error, error.localizedDescription)
      return nil
    }
  }

  func connect() {
    DispatchQueue.global(qos: .background).async {
      let connectProcess = Process()
      connectProcess.executableURL = URL(fileURLWithPath: self.adbPath)
      connectProcess.arguments = ["connect", "\(self.host):\(self.port)"]
      connectProcess.standardOutput = Pipe()
      connectProcess.standardError = Pipe()
      try? connectProcess.run()
      connectProcess.waitUntilExit()
      os_log("AndroidTVADB connected to %{public}@:%{public}d", type: .info, self.host, self.port)
    }
  }

  // Returns volume 0–15, nil on failure
  func getVolume() -> Int? {
    guard let output = run(["shell", "media", "volume", "--get", "--stream", "3"]) else { return nil }
    // Output: "volume is N" or "Current volume: N"
    let parts = output.components(separatedBy: .whitespaces)
    if let last = parts.last, let value = Int(last) {
      return value
    }
    return nil
  }

  // Sets absolute volume 0–15
  func setVolume(_ level: Int) {
    let clamped = max(0, min(15, level))
    DispatchQueue.global(qos: .userInteractive).async {
      self.run(["shell", "media", "volume", "--set", String(clamped), "--stream", "3"])
    }
  }

  func sendKeyEvent(_ keycode: String) {
    DispatchQueue.global(qos: .userInteractive).async {
      self.run(["shell", "input", "keyevent", keycode])
    }
  }

  func volumeUp() { sendKeyEvent("KEYCODE_VOLUME_UP") }
  func volumeDown() { sendKeyEvent("KEYCODE_VOLUME_DOWN") }
  func mute() { sendKeyEvent("KEYCODE_VOLUME_MUTE") }

  func isConnected() -> Bool {
    guard let output = run(["get-state"]) else { return false }
    return output.contains("device")
  }
}
