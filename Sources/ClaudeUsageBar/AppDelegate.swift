import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let service = AuthService()
    private var refreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            updateStatusBarText()
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 300)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PopoverContentView(service: service)
        )

        // Update status bar text every 30s
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateStatusBarText()
            }
        }

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
            .foregroundColor: NSColor.secondaryLabelColor
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

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            showContextMenu(sender)
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Refresh on open
            if service.isAuthenticated {
                Task { await service.fetchUsage() }
            }
            popover.show(relativeTo: .zero, of: sender, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKey()
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
