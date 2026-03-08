import Testing
import Foundation
@testable import ClaudeUsageBar

@Suite("UsageBucket Tests")
struct UsageBucketTests {

    @Test("usedPercentage returns utilization when present")
    func usedPercentageWithValue() {
        let bucket = UsageBucket(utilization: 75.5, resetsAt: nil)
        #expect(bucket.usedPercentage == 75.5)
    }

    @Test("usedPercentage returns 0 when utilization is nil")
    func usedPercentageNil() {
        let bucket = UsageBucket(utilization: nil, resetsAt: nil)
        #expect(bucket.usedPercentage == 0)
    }

    @Test("resetsAtDate parses ISO8601 with fractional seconds")
    func resetsAtDateFractional() {
        let bucket = UsageBucket(utilization: 50, resetsAt: "2026-03-08T15:30:00.000Z")
        #expect(bucket.resetsAtDate != nil)

        let components = Calendar.current.dateComponents(
            in: TimeZone(identifier: "UTC")!,
            from: bucket.resetsAtDate!
        )
        #expect(components.hour == 15)
        #expect(components.minute == 30)
    }

    @Test("resetsAtDate parses ISO8601 without fractional seconds")
    func resetsAtDateNoFractional() {
        let bucket = UsageBucket(utilization: 50, resetsAt: "2026-03-08T15:30:00Z")
        #expect(bucket.resetsAtDate != nil)
    }

    @Test("resetsAtDate returns nil for empty string")
    func resetsAtDateEmpty() {
        let bucket = UsageBucket(utilization: 50, resetsAt: "")
        #expect(bucket.resetsAtDate == nil)
    }

    @Test("resetsAtDate returns nil when resetsAt is nil")
    func resetsAtDateNil() {
        let bucket = UsageBucket(utilization: 50, resetsAt: nil)
        #expect(bucket.resetsAtDate == nil)
    }

    @Test("timeUntilReset returns 0 for past date")
    func timeUntilResetPast() {
        let bucket = UsageBucket(utilization: 50, resetsAt: "2020-01-01T00:00:00Z")
        #expect(bucket.timeUntilReset == 0)
    }

    @Test("timeUntilReset returns positive for future date")
    func timeUntilResetFuture() {
        let bucket = UsageBucket(utilization: 50, resetsAt: "2099-01-01T00:00:00Z")
        #expect(bucket.timeUntilReset > 0)
    }
}

@Suite("ExtraUsage Tests")
struct ExtraUsageTests {

    @Test("usedCreditsAmount converts cents to dollars")
    func creditsConversion() {
        let extra = ExtraUsage(isEnabled: true, utilization: 50, usedCredits: 1234, monthlyLimit: 5000)
        #expect(extra.usedCreditsAmount == 12.34)
    }

    @Test("monthlyLimitAmount converts cents to dollars")
    func limitConversion() {
        let extra = ExtraUsage(isEnabled: true, utilization: 50, usedCredits: 100, monthlyLimit: 10000)
        #expect(extra.monthlyLimitAmount == 100.0)
    }

    @Test("usedCreditsAmount returns nil when nil")
    func creditsNil() {
        let extra = ExtraUsage(isEnabled: false, utilization: nil, usedCredits: nil, monthlyLimit: nil)
        #expect(extra.usedCreditsAmount == nil)
        #expect(extra.monthlyLimitAmount == nil)
    }
}

@Suite("UsageResponse JSON Decoding")
struct UsageResponseDecodingTests {

    @Test("Decodes full response with five_hour and seven_day")
    func decodeFull() throws {
        let json = """
        {
            "five_hour": {"utilization": 20.5, "resets_at": "2026-03-08T22:00:00Z"},
            "seven_day": {"utilization": 43.0, "resets_at": "2026-03-15T00:00:00Z"}
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(UsageResponse.self, from: json)
        #expect(response.fiveHour?.utilization == 20.5)
        #expect(response.sevenDay?.utilization == 43.0)
        #expect(response.extraUsage == nil)
    }

    @Test("Decodes response with extra_usage")
    func decodeWithExtra() throws {
        let json = """
        {
            "five_hour": {"utilization": 10},
            "seven_day": {"utilization": 30},
            "extra_usage": {
                "is_enabled": true,
                "utilization": 25.0,
                "used_credits": 500,
                "monthly_limit": 2000
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(UsageResponse.self, from: json)
        #expect(response.extraUsage?.isEnabled == true)
        #expect(response.extraUsage?.usedCreditsAmount == 5.0)
        #expect(response.extraUsage?.monthlyLimitAmount == 20.0)
    }

    @Test("Decodes response with null buckets")
    func decodeNulls() throws {
        let json = """
        {}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(UsageResponse.self, from: json)
        #expect(response.fiveHour == nil)
        #expect(response.sevenDay == nil)
    }
}

@Suite("Base64URL Encoding")
struct Base64URLTests {

    @Test("Encodes to URL-safe base64 without padding")
    func urlSafeEncoding() {
        // Bytes that produce +, /, and = in standard base64
        let data = Data([0xfb, 0xff, 0xfe])
        let encoded = data.base64URLEncoded()
        #expect(!encoded.contains("+"))
        #expect(!encoded.contains("/"))
        #expect(!encoded.contains("="))
        #expect(encoded.contains("-") || encoded.contains("_"))
    }

    @Test("Empty data returns empty string")
    func emptyData() {
        let data = Data()
        #expect(data.base64URLEncoded() == "")
    }
}
