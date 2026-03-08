# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

macOS menu bar app that displays Claude Pro/Max subscription usage (5-hour and 7-day windows) in the system status bar. Uses OAuth PKCE authentication — no API key needed, zero token cost.

## Build & Run

```bash
swift build              # Debug build
swift build -c release   # Release build
swift run                # Build and run
pkill ClaudeUsageBar; swift run  # Restart
```

## Architecture

**AppKit-based menu bar app** using `NSApplication.setActivationPolicy(.accessory)` to hide the Dock icon. SwiftUI views hosted via NSHostingController.

- `main.swift` — Entry point, sets up NSApplication + Edit menu (required for Cmd+V in popover)
- `AppDelegate.swift` — NSStatusItem + NSPopover, left-click=popover, right-click=context menu
- `Services/AnthropicAPIService.swift` — OAuth PKCE flow + usage polling via `AuthService`
  - OAuth: browser login → code+state paste → token exchange
  - Usage endpoint: `POST https://api.anthropic.com/api/oauth/usage` with `anthropic-beta: oauth-2025-04-20`
  - Token stored in `~/.config/claude-usage-bar/token` (file, 0600 permissions)
- `Views/PopoverContentView.swift` — Main popover: sign-in flow or usage display
- `Views/UsageRowView.swift` — Single usage bucket row (progress bar + percentage + reset countdown)
- `Models/RateLimitInfo.swift` — `UsageResponse` with `five_hour`, `seven_day`, `extra_usage` buckets

**Data flow**: Timer (60s) → `api.anthropic.com/api/oauth/usage` → `UsageResponse` → status bar text + SwiftUI popover

## Key Details

- OAuth client ID: `9d1c250a-e61b-44d9-88ed-5944d1962f5e` (Anthropic public OAuth client)
- Status bar color: green (<70%), orange (70-90%), red (>90%)
- `@MainActor` on AppDelegate and AuthService for thread safety
