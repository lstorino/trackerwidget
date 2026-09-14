import SwiftUI
import Combine
import ServiceManagement

@main
enum TrackerPanel {
  @MainActor
  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // menu-bar app, no Dock icon
    app.run()
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var panel: NSPanel!
  private var statusItem: NSStatusItem!
  private let viewModel = PanelViewModel()

  func applicationDidFinishLaunching(_ notification: Notification) {
    let hosting = NSHostingView(rootView: PanelContent(viewModel: viewModel))

    let size = NSSize(width: 360, height: 560)
    hosting.frame = NSRect(origin: .zero, size: size)

    panel = NSPanel(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable],
      backing: .buffered,
      defer: false
    )
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.isMovableByWindowBackground = true
    // Desktop-widget layer semantics: under working windows, never hides.
    panel.level = .normal
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true
    panel.contentView = hosting
    panel.center()
    panel.orderFrontRegardless()

    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let button = statusItem.button {
      button.image = NSImage(systemSymbolName: "square.grid.2x2.fill",
                             accessibilityDescription: "Price Trackers")
    }
    let menu = NSMenu()
    menu.addItem(NSMenuItem(title: "Show / Hide Panel", action: #selector(togglePanel), keyEquivalent: ""))
    menu.addItem(NSMenuItem(title: "Refresh Now", action: #selector(refresh), keyEquivalent: "r"))
    let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    menu.addItem(loginItem)
    menu.addItem(.separator())
    menu.addItem(NSMenuItem(title: "Quit Price Trackers", action: #selector(NSApplication.terminate), keyEquivalent: "q"))
    statusItem.menu = menu

    viewModel.refreshAll()
  }

  @objc private func togglePanel() {
    if panel.isVisible {
      panel.orderOut(nil)
    } else {
      panel.orderFrontRegardless()
    }
  }

  @objc private func refresh() {
    viewModel.refreshAll()
  }

  @objc private func toggleLaunchAtLogin() {
    let service = SMAppService.mainApp
    do {
      if service.status == .enabled {
        try service.unregister()
      } else {
        try service.register()
      }
    } catch {
      NSLog("[TrackerWidget] launch-at-login toggle failed: \(error.localizedDescription)")
    }
    if let item = statusItem.menu?.items.first(where: { $0.action == #selector(toggleLaunchAtLogin) }) {
      item.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
  }
}
