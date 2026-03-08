import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private let service = AuthService()
    private var refreshTimer: Timer?
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.action = #selector(togglePanel)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            updateStatusBarText()
        }

        // Borderless panel instead of NSPopover — no arrow, no gap
        let hostingView = NSHostingView(rootView: PopoverContentView(service: service))
        hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 10)

        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        // Use visual effect view for native menu-bar-style background
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .popover
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 10
        visualEffect.layer?.masksToBounds = true

        let wrapper = NSView()
        wrapper.wantsLayer = true
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(visualEffect)
        wrapper.addSubview(hostingView)

        panel.contentView = wrapper

        NSLayoutConstraint.activate([
            visualEffect.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            visualEffect.topAnchor.constraint(equalTo: wrapper.topAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: wrapper.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])

        // Update status bar text every 30s
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateStatusBarText()
            }
        }

        // Request notification permission after app is fully launched
        service.requestNotificationPermission()

        if service.isAuthenticated {
            service.startPolling()
        }
    }

    private func colorForPct(_ pct: Double) -> NSColor {
        if pct >= 90 { return .systemRed }
        if pct >= 70 { return .systemOrange }
        return .systemGreen
    }

    private func updateStatusBarText() {
        guard let button = statusItem.button else { return }

        if !service.isAuthenticated {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            button.attributedTitle = NSAttributedString(string: "C: --", attributes: attrs)
            return
        }

        guard let usage = service.usage else {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            button.attributedTitle = NSAttributedString(string: "C: ...", attributes: attrs)
            return
        }

        // Flash reset indicator
        if service.recentlyReset {
            let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.systemCyan
            ]
            button.attributedTitle = NSAttributedString(string: "C: RESET!", attributes: attrs)
            return
        }

        let pct5h = usage.fiveHour?.usedPercentage ?? 0
        let pct7d = usage.sevenDay?.usedPercentage ?? 0
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        let dimAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]

        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: "5h:", attributes: dimAttrs))
        result.append(NSAttributedString(string: String(format: "%.0f%%", pct5h), attributes: [
            .font: font,
            .foregroundColor: colorForPct(pct5h)
        ]))
        result.append(NSAttributedString(string: " 7d:", attributes: dimAttrs))
        result.append(NSAttributedString(string: String(format: "%.0f%%", pct7d), attributes: [
            .font: font,
            .foregroundColor: colorForPct(pct7d)
        ]))

        button.attributedTitle = result
    }

    @objc private func togglePanel(_ sender: NSStatusBarButton) {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            showContextMenu(sender)
            return
        }

        if panel.isVisible {
            closePanel()
        } else {
            openPanel(sender)
        }
    }

    private func openPanel(_ button: NSStatusBarButton) {
        // Refresh on open
        if service.isAuthenticated {
            Task { await service.fetchUsage() }
        }

        // Position panel directly below the status bar button
        guard let buttonWindow = button.window else { return }
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)

        // Fit content
        panel.contentView?.layoutSubtreeIfNeeded()
        let contentSize = panel.contentView?.fittingSize ?? NSSize(width: 320, height: 300)
        let panelWidth: CGFloat = 320
        let panelX = screenRect.midX - panelWidth / 2
        let panelY = screenRect.minY - contentSize.height

        panel.setFrame(NSRect(x: panelX, y: panelY, width: panelWidth, height: contentSize.height), display: true)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Close when clicking outside
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanel()
        }
    }

    private func closePanel() {
        panel.orderOut(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func showContextMenu(_ button: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refreshNow), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func refreshNow() {
        Task { await service.fetchUsage() }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
