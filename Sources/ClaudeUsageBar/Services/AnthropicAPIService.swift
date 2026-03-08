import Foundation
import CryptoKit
import AppKit
import UserNotifications

@MainActor
final class AuthService: ObservableObject {
    @Published var usage: UsageResponse?
    @Published var lastError: String?
    @Published var lastUpdated: Date?
    @Published var isAuthenticated = false
    @Published var isAwaitingCode = false
    @Published var recentlyReset = false

    private var timer: Timer?
    private var resetFlashTimer: Timer?
    private var previous5hPct: Double = 0
    private let usageEndpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private let pollingInterval: TimeInterval = 300

    // OAuth PKCE
    private let clientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private let redirectUri = "https://console.anthropic.com/oauth/code/callback"
    private let tokenEndpoint = URL(string: "https://console.anthropic.com/v1/oauth/token")!
    private var codeVerifier: String?
    private var oauthState: String?

    // Token file storage
    private static var tokenFileURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/claude-usage-bar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("token")
    }

    var pct5h: Double { (usage?.fiveHour?.utilization ?? 0) / 100.0 }
    var pct7d: Double { (usage?.sevenDay?.utilization ?? 0) / 100.0 }

    var reset5h: Date? { usage?.fiveHour?.resetsAtDate }
    var reset7d: Date? { usage?.sevenDay?.resetsAtDate }

    init() {
        isAuthenticated = loadToken() != nil
    }

    func requestNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else {
            print("Skipping notification permission: no bundle identifier (running via swift run?)")
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                print("Notification permission error: \(error)")
            }
            print("Notification permission granted: \(granted)")
        }
    }

    // MARK: - Polling

    func startPolling() {
        guard isAuthenticated else { return }
        Task { await fetchUsage(force: true) }
        timer?.invalidate()
        let t = Timer(timeInterval: pollingInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isAuthenticated else { return }
                Task { await self.fetchUsage(force: true) }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: - OAuth PKCE Flow

    func startOAuthFlow() {
        let verifier = generateRandomString()
        let challenge = generateCodeChallenge(from: verifier)
        let state = generateRandomString()

        codeVerifier = verifier
        oauthState = state

        var components = URLComponents(string: "https://claude.ai/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "scope", value: "user:profile user:inference"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]

        if let url = components.url {
            NSWorkspace.shared.open(url)
            isAwaitingCode = true
        }
    }

    func submitOAuthCode(_ rawCode: String) async {
        let parts = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "#", maxSplits: 1)
        let code = String(parts[0])

        if parts.count > 1 {
            let returnedState = String(parts[1])
            guard returnedState == oauthState else {
                lastError = "OAuth state mismatch"
                isAwaitingCode = false
                codeVerifier = nil
                oauthState = nil
                return
            }
        }

        guard let verifier = codeVerifier else {
            lastError = "No pending OAuth flow"
            isAwaitingCode = false
            return
        }

        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "state": oauthState ?? "",
            "client_id": clientId,
            "redirect_uri": redirectUri,
            "code_verifier": verifier,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                lastError = "Token exchange failed"
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accessToken = json["access_token"] as? String else {
                lastError = "Could not parse token"
                return
            }

            saveToken(accessToken)
            isAuthenticated = true
            isAwaitingCode = false
            lastError = nil
            codeVerifier = nil
            oauthState = nil
            startPolling()
        } catch {
            lastError = "Token exchange error: \(error.localizedDescription)"
        }
    }

    func signOut() {
        deleteToken()
        isAuthenticated = false
        usage = nil
        lastError = nil
        lastUpdated = nil
        timer?.invalidate()
    }

    // MARK: - Fetch Usage

    private static let minFetchInterval: TimeInterval = 120

    func fetchUsage(force: Bool = false) async {
        // Skip if fetched recently (unless forced by timer)
        if !force, let last = lastUpdated, Date().timeIntervalSince(last) < Self.minFetchInterval {
            return
        }

        guard let token = loadToken() else {
            lastError = "Not signed in"
            isAuthenticated = false
            return
        }

        var request = URLRequest(url: usageEndpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                lastError = "Invalid response"
                return
            }
            if http.statusCode == 401 {
                lastError = "Session expired — sign in again"
                signOut()
                return
            }
            if http.statusCode == 429 {
                // Silently ignore rate limit if we already have data
                if usage != nil { return }
                lastError = "Rate limited — try again later"
                return
            }
            guard http.statusCode == 200 else {
                lastError = "HTTP \(http.statusCode)"
                return
            }
            let newUsage = try JSONDecoder().decode(UsageResponse.self, from: data)
            let new5hPct = newUsage.fiveHour?.usedPercentage ?? 0

            // Detect 5h reset: was high (>=50%), now low
            if previous5hPct >= 50 && new5hPct < 10 {
                sendResetNotification()
                showResetFlash()
            }
            previous5hPct = new5hPct

            usage = newUsage
            lastError = nil
            lastUpdated = Date()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Reset Notification

    private func sendResetNotification() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "Claude Usage Reset"
        content.body = "5-hour usage limit has been reset!"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "5h-reset-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func showResetFlash() {
        recentlyReset = true
        resetFlashTimer?.invalidate()
        resetFlashTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.recentlyReset = false
            }
        }
    }

    // MARK: - PKCE Helpers

    private func generateRandomString() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncoded()
    }

    // MARK: - Token Storage

    private func saveToken(_ token: String) {
        let url = Self.tokenFileURL
        try? Data(token.utf8).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func loadToken() -> String? {
        guard let data = try? Data(contentsOf: Self.tokenFileURL) else { return nil }
        let token = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return token?.isEmpty == false ? token : nil
    }

    private func deleteToken() {
        try? FileManager.default.removeItem(at: Self.tokenFileURL)
    }
}

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
