//  Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others

import Cocoa
import Settings

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
    self.view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 300))
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    self.buildUI()
  }

  private func buildUI() {
    let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
    nameColumn.title = NSLocalizedString("Name", comment: "")
    nameColumn.width = 140

    let hostColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("host"))
    hostColumn.title = NSLocalizedString("IP Address", comment: "")
    hostColumn.width = 140

    let portColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("port"))
    portColumn.title = NSLocalizedString("Port", comment: "")
    portColumn.width = 60

    tableView.addTableColumn(nameColumn)
    tableView.addTableColumn(hostColumn)
    tableView.addTableColumn(portColumn)
    tableView.delegate = self
    tableView.dataSource = self
    tableView.usesAlternatingRowBackgroundColors = true

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

  @objc private func addTV() {
    let alert = NSAlert()
    alert.messageText = NSLocalizedString("Add Android TV", comment: "")
    alert.addButton(withTitle: NSLocalizedString("Add", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))

    let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 90))

    let nameField = NSTextField(frame: NSRect(x: 80, y: 60, width: 200, height: 22))
    nameField.placeholderString = "My TCL TV"
    let nameLabel = NSTextField(labelWithString: NSLocalizedString("Name:", comment: ""))
    nameLabel.frame = NSRect(x: 0, y: 62, width: 75, height: 18)
    nameLabel.alignment = .right

    let ipField = NSTextField(frame: NSRect(x: 80, y: 30, width: 160, height: 22))
    ipField.placeholderString = "192.168.1.x"
    let ipLabel = NSTextField(labelWithString: NSLocalizedString("IP Address:", comment: ""))
    ipLabel.frame = NSRect(x: 0, y: 32, width: 75, height: 18)
    ipLabel.alignment = .right

    let portField = NSTextField(frame: NSRect(x: 80, y: 0, width: 60, height: 22))
    portField.stringValue = "5555"
    let portLabel = NSTextField(labelWithString: NSLocalizedString("Port:", comment: ""))
    portLabel.frame = NSRect(x: 0, y: 2, width: 75, height: 18)
    portLabel.alignment = .right

    container.addSubview(nameLabel)
    container.addSubview(nameField)
    container.addSubview(ipLabel)
    container.addSubview(ipField)
    container.addSubview(portLabel)
    container.addSubview(portField)
    alert.accessoryView = container

    guard let window = self.view.window else { return }
    alert.beginSheetModal(for: window) { response in
      guard response == .alertFirstButtonReturn else { return }
      let name = nameField.stringValue.isEmpty ? "Android TV" : nameField.stringValue
      let host = ipField.stringValue
      let port = Int(portField.stringValue) ?? 5555
      guard !host.isEmpty else { return }
      DisplayManager.shared.addAndroidTV(name: name, host: host, port: port)
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
}

extension AndroidTVPrefsViewController: NSTableViewDataSource, NSTableViewDelegate {
  func numberOfRows(in _: NSTableView) -> Int {
    DisplayManager.shared.androidTVDisplays.count
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let tv = DisplayManager.shared.androidTVDisplays[row]
    let cell = NSTextField()
    cell.isBordered = false
    cell.backgroundColor = .clear
    switch tableColumn?.identifier.rawValue {
    case "name": cell.stringValue = tv.tvName
    case "host": cell.stringValue = tv.adb.host
    case "port": cell.stringValue = String(tv.adb.port)
    default: break
    }
    return cell
  }
}
