//  Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others

import Foundation
import os.log

class AndroidTVADB {
  var host: String  // mutable — updated automatically when IP changes
  let port: Int

  private var adbPath: String {
    let candidates = ["/opt/homebrew/bin/adb", "/usr/local/bin/adb", "/usr/bin/adb"]
    return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? "adb"
  }

  init(host: String, port: Int = 5555) {
    self.host = host
    self.port = port
  }

  // MARK: - Process helpers

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

  @discardableResult
  private func runDirect(_ args: [String]) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: adbPath)
    process.arguments = args
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    do {
      try process.run()
      process.waitUntilExit()
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    } catch { return nil }
  }

  // MARK: - Connection & auto-reconnect

  // Reads the WiFi MAC address from the connected TV — stable hardware identifier
  func readMACAddress() -> String? {
    guard let output = run(["shell", "cat", "/sys/class/net/wlan0/address"]) else { return nil }
    let mac = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard mac.count == 17 else { return nil }
    return mac
  }

  // Scans the local ARP table for a device with the given MAC, returns its IP if found
  static func findIPByMAC(_ mac: String) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
    process.arguments = ["-a"]
    let pipe = Pipe()
    process.standardOutput = pipe
    try? process.run()
    process.waitUntilExit()
    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    for line in output.components(separatedBy: "\n") {
      let normalizedLine = line.lowercased()
      let normalizedMAC = mac.lowercased()
      if normalizedLine.contains(normalizedMAC) {
        // Line format: "hostname (192.168.1.x) at aa:bb:cc:dd:ee:ff ..."
        if let start = normalizedLine.range(of: "("),
           let end = normalizedLine.range(of: ")"),
           start.upperBound < end.lowerBound {
          return String(normalizedLine[start.upperBound ..< end.lowerBound])
        }
      }
    }
    return nil
  }

  // Connects to the TV. If connection fails and macAddress is known, scans ARP to find new IP.
  // Calls onIPUpdated(newIP) if the IP changed so the caller can persist it.
  func connect(macAddress: String? = nil, onIPUpdated: ((String) -> Void)? = nil) {
    DispatchQueue.global(qos: .background).async {
      self.runDirect(["connect", "\(self.host):\(self.port)"])
      if self.isConnected() {
        os_log("AndroidTVADB connected to %{public}@:%{public}d", type: .info, self.host, self.port)
        return
      }
      // Connection failed — try to find TV by MAC address
      guard let mac = macAddress, !mac.isEmpty else { return }
      os_log("AndroidTVADB: connection failed, scanning ARP for MAC %{public}@", type: .info, mac)
      // Refresh ARP table by pinging broadcast
      let ping = Process()
      ping.executableURL = URL(fileURLWithPath: "/sbin/ping")
      ping.arguments = ["-c", "1", "-b", "192.168.1.255"]
      try? ping.run(); ping.waitUntilExit()

      if let newIP = AndroidTVADB.findIPByMAC(mac) {
        os_log("AndroidTVADB: found TV at new IP %{public}@", type: .info, newIP)
        self.host = newIP
        self.runDirect(["connect", "\(newIP):\(self.port)"])
        onIPUpdated?(newIP)
      }
    }
  }

  func isConnected() -> Bool {
    guard let output = runDirect(["get-state", "-s", "\(host):\(port)"]) else { return false }
    return output.contains("device")
  }

  // MARK: - Volume

  static let maxVolume: Int = 100

  func getVolume() -> Int? {
    guard let output = run(["shell", "settings", "get", "system", "volume_music_speaker"]) else { return nil }
    return Int(output)
  }

  private var pendingVolumeWork: DispatchWorkItem?
  private var lastSentVolume: Int?

  func setVolume(_ level: Int) {
    let target = max(0, min(AndroidTVADB.maxVolume, level))
    pendingVolumeWork?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self = self else { return }
      let current = self.lastSentVolume ?? self.getVolume() ?? target
      self.lastSentVolume = target
      let delta = target - current
      guard delta != 0 else { return }
      let keycode = delta > 0 ? "KEYCODE_VOLUME_UP" : "KEYCODE_VOLUME_DOWN"
      let keys = Array(repeating: keycode, count: abs(delta)).joined(separator: " ")
      self.run(["shell", "input", "keyevent", keys])
    }
    pendingVolumeWork = work
    DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.15, execute: work)
  }

  func sendKeyEvent(_ keycode: String) {
    DispatchQueue.global(qos: .userInteractive).async {
      self.run(["shell", "input", "keyevent", keycode])
    }
  }

  func mute() { sendKeyEvent("KEYCODE_VOLUME_MUTE") }
}
