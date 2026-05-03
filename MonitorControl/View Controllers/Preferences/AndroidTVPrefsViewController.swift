//  Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others

import Cocoa
import Settings
import SimplyCoreAudio

class AndroidTVPrefsViewController: NSViewController, SettingsPane {
  let paneIdentifier = Settings.PaneIdentifier.androidTV
  let paneTitle = NSLocalizedString("Android TV", comment: "Shown in prefs")

  var toolbarItemIcon: NSImage {
    if #available(macOS 11.0, *) {
      return NSImage(systemSymbolName: "tv", accessibilityDescription: "Android TV")!
    }
    return NSImage(named: NSImage.computerName)!
  }

  private let tableView = NSTableView()
  private let scrollView = NSScrollView()
  private let addButton = NSButton()
  private let removeButton = NSButton()

  private var statusCache: [Int: AndroidTVADB.Status] = [:]
  private var pollTimer: Timer?

  override func loadView() {
    self.view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 320))
  }

  override var preferredContentSize: NSSize {
    get { NSSize(width: 600, height: 320) }
    set {}
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    self.buildUI()
  }

  override func viewWillAppear() {
    super.viewWillAppear()
    refreshAllStatuses()
    pollTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
      self?.refreshAllStatuses()
    }
    tableView.reloadData()
  }

  override func viewWillDisappear() {
    super.viewWillDisappear()
    pollTimer?.invalidate()
    pollTimer = nil
  }

  private func buildUI() {
    let statusColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("status"))
    statusColumn.title = NSLocalizedString("Status", comment: "")
    statusColumn.width = 90

    let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
    nameColumn.title = NSLocalizedString("Name", comment: "")
    nameColumn.width = 110

    let hostColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("host"))
    hostColumn.title = NSLocalizedString("IP:Port", comment: "")
    hostColumn.width = 120

    let audioColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("audio"))
    audioColumn.title = NSLocalizedString("macOS Audio Output", comment: "")
    audioColumn.width = 200

    tableView.addTableColumn(statusColumn)
    tableView.addTableColumn(nameColumn)
    tableView.addTableColumn(hostColumn)
    tableView.addTableColumn(audioColumn)
    tableView.delegate = self
    tableView.dataSource = self
    tableView.usesAlternatingRowBackgroundColors = true
    tableView.rowHeight = 30
    tableView.target = self
    tableView.doubleAction = #selector(editSelectedTV)

    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.borderType = .bezelBorder
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(scrollView)

    addButton.title = "+"
    addButton.bezelStyle = .regularSquare
    addButton.action = #selector(addTV)
    addButton.target = self
    addButton.translatesAutoresizingMaskIntoConstraints = false

    removeButton.title = "−"
    removeButton.bezelStyle = .regularSquare
    removeButton.action = #selector(removeTV)
    removeButton.target = self
    removeButton.translatesAutoresizingMaskIntoConstraints = false

    view.addSubview(addButton)
    view.addSubview(removeButton)

    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      scrollView.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -8),
      addButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      addButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
      addButton.widthAnchor.constraint(equalToConstant: 30),
      removeButton.leadingAnchor.constraint(equalTo: addButton.trailingAnchor, constant: 4),
      removeButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
      removeButton.widthAnchor.constraint(equalToConstant: 30),
    ])
  }

  // MARK: - Status polling

  private func refreshAllStatuses() {
    let tvs = DisplayManager.shared.androidTVDisplays
    DispatchQueue.global(qos: .utility).async { [weak self] in
      var newStatuses: [Int: AndroidTVADB.Status] = [:]
      for (idx, tv) in tvs.enumerated() {
        newStatuses[idx] = tv.adb.getStatus()
      }
      DispatchQueue.main.async {
        guard let self = self else { return }
        self.statusCache = newStatuses
        self.tableView.reloadData()
      }
    }
  }

  @objc private func reconnectTV(_ sender: NSButton) {
    let row = sender.tag
    guard row < DisplayManager.shared.androidTVDisplays.count else { return }
    let tv = DisplayManager.shared.androidTVDisplays[row]
    sender.isEnabled = false
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let status = tv.adb.reconnect()
      DispatchQueue.main.async {
        sender.isEnabled = true
        self?.statusCache[row] = status
        self?.tableView.reloadData()
        if status == .unauthorized {
          let alert = NSAlert()
          alert.messageText = NSLocalizedString("TV authorization needed", comment: "")
          alert.informativeText = NSLocalizedString("Check the TV screen and accept the ADB debugging prompt, then click Reconnect again.", comment: "")
          alert.runModal()
        }
      }
    }
  }

  // MARK: - Audio device list

  private func audioOutputDeviceNames() -> [String] {
    let coreAudio = SimplyCoreAudio()
    return coreAudio.allOutputDevices.compactMap { $0.name }.sorted()
  }

  // MARK: - Add / Edit dialog

  private struct TVFormFields {
    let name: String
    let host: String
    let port: Int
    let audioDeviceName: String
  }

  private func presentTVForm(title: String, initial: TVFormFields?, onSave: @escaping (TVFormFields) -> Void) {
    let alert = NSAlert()
    alert.messageText = title
    alert.addButton(withTitle: NSLocalizedString("Save", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))

    let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))

    let nameField = NSTextField(frame: NSRect(x: 100, y: 130, width: 200, height: 22))
    nameField.placeholderString = "My TCL TV"
    nameField.stringValue = initial?.name ?? ""
    let nameLabel = NSTextField(labelWithString: NSLocalizedString("Name:", comment: ""))
    nameLabel.frame = NSRect(x: 0, y: 132, width: 95, height: 18)
    nameLabel.alignment = .right

    let ipField = NSTextField(frame: NSRect(x: 100, y: 100, width: 160, height: 22))
    ipField.placeholderString = "192.168.1.x"
    ipField.stringValue = initial?.host ?? ""
    let ipLabel = NSTextField(labelWithString: NSLocalizedString("IP Address:", comment: ""))
    ipLabel.frame = NSRect(x: 0, y: 102, width: 95, height: 18)
    ipLabel.alignment = .right

    let portField = NSTextField(frame: NSRect(x: 100, y: 70, width: 60, height: 22))
    portField.stringValue = initial.map { String($0.port) } ?? "5555"
    let portLabel = NSTextField(labelWithString: NSLocalizedString("Port:", comment: ""))
    portLabel.frame = NSRect(x: 0, y: 72, width: 95, height: 18)
    portLabel.alignment = .right

    let audioPopup = NSPopUpButton(frame: NSRect(x: 100, y: 40, width: 200, height: 22))
    audioPopup.addItem(withTitle: NSLocalizedString("— Not mapped —", comment: ""))
    audioPopup.menu?.addItem(NSMenuItem.separator())
    for name in audioOutputDeviceNames() {
      audioPopup.addItem(withTitle: name)
    }
    if let initial = initial, !initial.audioDeviceName.isEmpty,
       let item = audioPopup.item(withTitle: initial.audioDeviceName) {
      audioPopup.select(item)
    }
    let audioLabel = NSTextField(labelWithString: NSLocalizedString("Audio Output:", comment: ""))
    audioLabel.frame = NSRect(x: 0, y: 42, width: 95, height: 18)
    audioLabel.alignment = .right

    let testButton = NSButton(frame: NSRect(x: 100, y: 5, width: 130, height: 24))
    testButton.title = NSLocalizedString("Test Connection", comment: "")
    testButton.bezelStyle = .rounded

    let testResult = NSTextField(labelWithString: "")
    testResult.frame = NSRect(x: 235, y: 8, width: 80, height: 18)
    testResult.font = NSFont.systemFont(ofSize: 11)

    testButton.target = TestConnectionAction.shared
    testButton.action = #selector(TestConnectionAction.run(_:))
    let action = TestConnectionAction(ipField: ipField, portField: portField, button: testButton, result: testResult)
    TestConnectionAction.current = action

    container.addSubview(nameLabel); container.addSubview(nameField)
    container.addSubview(ipLabel); container.addSubview(ipField)
    container.addSubview(portLabel); container.addSubview(portField)
    container.addSubview(audioLabel); container.addSubview(audioPopup)
    container.addSubview(testButton); container.addSubview(testResult)
    alert.accessoryView = container

    guard let window = self.view.window else { return }
    alert.beginSheetModal(for: window) { response in
      TestConnectionAction.current = nil
      guard response == .alertFirstButtonReturn else { return }
      let name = nameField.stringValue.isEmpty ? "Android TV" : nameField.stringValue
      let host = ipField.stringValue
      guard !host.isEmpty else { return }
      let port = Int(portField.stringValue) ?? 5555
      let selectedAudio = audioPopup.indexOfSelectedItem <= 1 ? "" : (audioPopup.selectedItem?.title ?? "")
      onSave(TVFormFields(name: name, host: host, port: port, audioDeviceName: selectedAudio))
    }
  }

  @objc private func addTV() {
    presentTVForm(title: NSLocalizedString("Add Android TV", comment: ""), initial: nil) { fields in
      DisplayManager.shared.addAndroidTV(name: fields.name, host: fields.host, port: fields.port, audioDeviceName: fields.audioDeviceName)
      self.tableView.reloadData()
      app.updateMenusAndKeys()
      self.refreshAllStatuses()
    }
  }

  @objc private func editSelectedTV() {
    let row = tableView.clickedRow
    guard row >= 0, row < DisplayManager.shared.androidTVDisplays.count else { return }
    let tv = DisplayManager.shared.androidTVDisplays[row]
    let initial = TVFormFields(name: tv.tvName, host: tv.adb.host, port: tv.adb.port, audioDeviceName: tv.audioDeviceName)
    presentTVForm(title: NSLocalizedString("Edit Android TV", comment: ""), initial: initial) { fields in
      DisplayManager.shared.updateAndroidTV(at: row, name: fields.name, host: fields.host, port: fields.port, audioDeviceName: fields.audioDeviceName)
      self.tableView.reloadData()
      app.updateMenusAndKeys()
      self.refreshAllStatuses()
    }
  }

  @objc private func removeTV() {
    let row = tableView.selectedRow
    guard row >= 0 else { return }
    DisplayManager.shared.removeAndroidTV(at: row)
    statusCache.removeValue(forKey: row)
    tableView.reloadData()
    app.updateMenusAndKeys()
  }

  @objc private func audioDeviceChanged(_ sender: NSPopUpButton) {
    let row = sender.tag
    guard row < DisplayManager.shared.androidTVDisplays.count else { return }
    let selected = sender.indexOfSelectedItem <= 1 ? "" : (sender.selectedItem?.title ?? "")
    DisplayManager.shared.androidTVDisplays[row].audioDeviceName = selected
    DisplayManager.shared.saveAndroidTVs()
    app.mediaKeyTap.updateMediaKeyTap()
  }
}

// Helper class to act as the target/action for the "Test Connection" button.
// Lives across the modal lifecycle without retaining the view controller.
private class TestConnectionAction: NSObject {
  static let shared = TestConnectionAction()
  static weak var current: TestConnectionAction?

  weak var ipField: NSTextField?
  weak var portField: NSTextField?
  weak var button: NSButton?
  weak var result: NSTextField?

  override init() { super.init() }

  init(ipField: NSTextField, portField: NSTextField, button: NSButton, result: NSTextField) {
    self.ipField = ipField; self.portField = portField; self.button = button; self.result = result
    super.init()
  }

  @objc func run(_: NSButton) {
    guard let action = TestConnectionAction.current,
          let ip = action.ipField?.stringValue, !ip.isEmpty,
          let portStr = action.portField?.stringValue,
          let port = Int(portStr) else { return }
    action.button?.isEnabled = false
    action.result?.stringValue = NSLocalizedString("Testing…", comment: "")
    action.result?.textColor = .secondaryLabelColor

    DispatchQueue.global(qos: .userInitiated).async {
      let probe = AndroidTVADB(host: ip, port: port)
      let status = probe.reconnect()
      DispatchQueue.main.async {
        action.button?.isEnabled = true
        switch status {
        case .connected:
          action.result?.stringValue = NSLocalizedString("✓ Connected", comment: "")
          action.result?.textColor = .systemGreen
        case .unauthorized:
          action.result?.stringValue = NSLocalizedString("⚠ Authorize on TV", comment: "")
          action.result?.textColor = .systemOrange
        case .disconnected:
          action.result?.stringValue = NSLocalizedString("✗ Failed", comment: "")
          action.result?.textColor = .systemRed
        }
      }
    }
  }
}

extension AndroidTVPrefsViewController: NSTableViewDataSource, NSTableViewDelegate {
  func numberOfRows(in _: NSTableView) -> Int {
    DisplayManager.shared.androidTVDisplays.count
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let tv = DisplayManager.shared.androidTVDisplays[row]
    switch tableColumn?.identifier.rawValue {
    case "status":
      let container = NSView()
      let dot = NSImageView()
      let status = statusCache[row] ?? .disconnected
      let color: NSColor
      let label: String
      switch status {
      case .connected: color = .systemGreen; label = NSLocalizedString("Connected", comment: "")
      case .unauthorized: color = .systemOrange; label = NSLocalizedString("Unauthorized", comment: "")
      case .disconnected: color = .systemRed; label = NSLocalizedString("Offline", comment: "")
      }
      if #available(macOS 11.0, *) {
        let cfg = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        dot.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: label)?.withSymbolConfiguration(cfg)
      } else {
        dot.image = NSImage(named: NSImage.statusAvailableName)
      }
      dot.contentTintColor = color
      dot.frame = NSRect(x: 4, y: 8, width: 12, height: 12)

      let textLabel = NSTextField(labelWithString: label)
      textLabel.font = NSFont.systemFont(ofSize: 11)
      textLabel.frame = NSRect(x: 20, y: 6, width: 50, height: 16)

      let reconnect = NSButton(frame: NSRect(x: 70, y: 4, width: 18, height: 20))
      reconnect.bezelStyle = .recessed
      reconnect.isBordered = false
      reconnect.tag = row
      reconnect.target = self
      reconnect.action = #selector(reconnectTV(_:))
      reconnect.toolTip = NSLocalizedString("Reconnect ADB", comment: "")
      if #available(macOS 11.0, *) {
        reconnect.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reconnect")
      } else {
        reconnect.title = "↻"
      }

      container.addSubview(dot)
      container.addSubview(textLabel)
      container.addSubview(reconnect)
      return container

    case "name":
      let cell = NSTextField()
      cell.isBordered = false
      cell.backgroundColor = .clear
      cell.isEditable = false
      cell.stringValue = tv.tvName
      return cell
    case "host":
      let cell = NSTextField()
      cell.isBordered = false
      cell.backgroundColor = .clear
      cell.isEditable = false
      cell.stringValue = "\(tv.adb.host):\(tv.adb.port)"
      return cell
    case "audio":
      let popup = NSPopUpButton()
      popup.tag = row
      popup.target = self
      popup.action = #selector(audioDeviceChanged(_:))
      popup.addItem(withTitle: NSLocalizedString("— Not mapped —", comment: ""))
      popup.menu?.addItem(NSMenuItem.separator())
      for name in audioOutputDeviceNames() {
        popup.addItem(withTitle: name)
      }
      if !tv.audioDeviceName.isEmpty, let item = popup.item(withTitle: tv.audioDeviceName) {
        popup.select(item)
      }
      return popup
    default:
      return nil
    }
  }
}
