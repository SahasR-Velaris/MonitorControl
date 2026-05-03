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

  override func loadView() {
    self.view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 320))
  }

  override var preferredContentSize: NSSize {
    get { NSSize(width: 520, height: 320) }
    set {}
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    self.buildUI()
  }

  override func viewWillAppear() {
    super.viewWillAppear()
    tableView.reloadData()
  }

  private func buildUI() {
    let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
    nameColumn.title = NSLocalizedString("Name", comment: "")
    nameColumn.width = 120

    let hostColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("host"))
    hostColumn.title = NSLocalizedString("IP:Port", comment: "")
    hostColumn.width = 130

    let audioColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("audio"))
    audioColumn.title = NSLocalizedString("macOS Audio Output", comment: "")
    audioColumn.width = 200

    tableView.addTableColumn(nameColumn)
    tableView.addTableColumn(hostColumn)
    tableView.addTableColumn(audioColumn)
    tableView.delegate = self
    tableView.dataSource = self
    tableView.usesAlternatingRowBackgroundColors = true
    tableView.rowHeight = 28

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

  private func audioOutputDeviceNames() -> [String] {
    let coreAudio = SimplyCoreAudio()
    return coreAudio.allOutputDevices.compactMap { $0.name }.sorted()
  }

  @objc private func addTV() {
    let alert = NSAlert()
    alert.messageText = NSLocalizedString("Add Android TV", comment: "")
    alert.addButton(withTitle: NSLocalizedString("Add", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))

    let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))

    let nameField = NSTextField(frame: NSRect(x: 90, y: 90, width: 200, height: 22))
    nameField.placeholderString = "My TCL TV"
    let nameLabel = NSTextField(labelWithString: NSLocalizedString("Name:", comment: ""))
    nameLabel.frame = NSRect(x: 0, y: 92, width: 85, height: 18)
    nameLabel.alignment = .right

    let ipField = NSTextField(frame: NSRect(x: 90, y: 60, width: 160, height: 22))
    ipField.placeholderString = "192.168.1.x"
    let ipLabel = NSTextField(labelWithString: NSLocalizedString("IP Address:", comment: ""))
    ipLabel.frame = NSRect(x: 0, y: 62, width: 85, height: 18)
    ipLabel.alignment = .right

    let portField = NSTextField(frame: NSRect(x: 90, y: 30, width: 60, height: 22))
    portField.stringValue = "5555"
    let portLabel = NSTextField(labelWithString: NSLocalizedString("Port:", comment: ""))
    portLabel.frame = NSRect(x: 0, y: 32, width: 85, height: 18)
    portLabel.alignment = .right

    let audioPopup = NSPopUpButton(frame: NSRect(x: 90, y: 0, width: 200, height: 22))
    audioPopup.addItem(withTitle: NSLocalizedString("— Not mapped —", comment: ""))
    audioPopup.menu?.addItem(NSMenuItem.separator())
    for name in audioOutputDeviceNames() {
      audioPopup.addItem(withTitle: name)
    }
    let audioLabel = NSTextField(labelWithString: NSLocalizedString("Audio Output:", comment: ""))
    audioLabel.frame = NSRect(x: 0, y: 2, width: 85, height: 18)
    audioLabel.alignment = .right

    container.addSubview(nameLabel); container.addSubview(nameField)
    container.addSubview(ipLabel); container.addSubview(ipField)
    container.addSubview(portLabel); container.addSubview(portField)
    container.addSubview(audioLabel); container.addSubview(audioPopup)
    alert.accessoryView = container

    guard let window = self.view.window else { return }
    alert.beginSheetModal(for: window) { response in
      guard response == .alertFirstButtonReturn else { return }
      let name = nameField.stringValue.isEmpty ? "Android TV" : nameField.stringValue
      let host = ipField.stringValue
      let port = Int(portField.stringValue) ?? 5555
      guard !host.isEmpty else { return }
      let selectedAudio = audioPopup.indexOfSelectedItem <= 1 ? "" : (audioPopup.selectedItem?.title ?? "")
      DisplayManager.shared.addAndroidTV(name: name, host: host, port: port, audioDeviceName: selectedAudio)
      self.tableView.reloadData()
      app.updateMenusAndKeys()
    }
  }

  @objc private func removeTV() {
    let row = tableView.selectedRow
    guard row >= 0 else { return }
    DisplayManager.shared.removeAndroidTV(at: row)
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

extension AndroidTVPrefsViewController: NSTableViewDataSource, NSTableViewDelegate {
  func numberOfRows(in _: NSTableView) -> Int {
    DisplayManager.shared.androidTVDisplays.count
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let tv = DisplayManager.shared.androidTVDisplays[row]
    switch tableColumn?.identifier.rawValue {
    case "name":
      let cell = NSTextField()
      cell.isBordered = false
      cell.backgroundColor = .clear
      cell.stringValue = tv.tvName
      return cell
    case "host":
      let cell = NSTextField()
      cell.isBordered = false
      cell.backgroundColor = .clear
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
