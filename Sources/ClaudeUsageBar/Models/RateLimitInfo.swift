import Foundation

struct UsageResponse: Codable {
    let fiveHour: UsageBucket?
    let sevenDay: UsageBucket?
    let extraUsage: ExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case extraUsage = "extra_usage"
    }
}

struct UsageBucket: Codable {
    let utilization: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    var resetsAtDate: Date? {
        guard let resetsAt, !resetsAt.isEmpty else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: resetsAt) { return date }

        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: resetsAt)
    }

    var timeUntilReset: TimeInterval {
        max(0, resetsAtDate?.timeIntervalSinceNow ?? 0)
    }

    var usedPercentage: Double {
        utilization ?? 0
    }
}

struct ExtraUsage: Codable {
    let isEnabled: Bool
    let utilization: Double?
    let usedCredits: Double?
    let monthlyLimit: Double?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case utilization
        case usedCredits = "used_credits"
        case monthlyLimit = "monthly_limit"
    }

    var usedCreditsAmount: Double? { usedCredits.map { $0 / 100.0 } }
    var monthlyLimitAmount: Double? { monthlyLimit.map { $0 / 100.0 } }
}
