import Foundation

struct RetentionPolicyTests {
    static func run() throws {
        try testDisabledPolicyDoesNotExpireSessions()
        try testPolicyExpiresSessionsOlderThanConfiguredDays()
        try testRetentionDaysAreClamped()
    }

    private static func testDisabledPolicyDoesNotExpireSessions() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let session = TranscriptSession(
            createdAt: now.addingTimeInterval(-90 * 24 * 60 * 60),
            audioURL: URL(fileURLWithPath: "/tmp/old.wav"),
            model: .v3
        )
        let policy = RetentionPolicy(target: .off, days: 30)

        try expect(!policy.isExpired(session, now: now), "Expected disabled retention policy to keep old sessions")
    }

    private static func testPolicyExpiresSessionsOlderThanConfiguredDays() throws {
        let now = Date(timeIntervalSince1970: 20_000)
        let policy = RetentionPolicy(target: .recordingsAndTranscripts, days: 7)
        let expired = TranscriptSession(
            createdAt: now.addingTimeInterval(-8 * 24 * 60 * 60),
            audioURL: URL(fileURLWithPath: "/tmp/expired.wav"),
            model: .v3
        )
        let retained = TranscriptSession(
            createdAt: now.addingTimeInterval(-6 * 24 * 60 * 60),
            audioURL: URL(fileURLWithPath: "/tmp/retained.wav"),
            model: .v3
        )

        try expect(policy.isExpired(expired, now: now), "Expected session older than policy to expire")
        try expect(!policy.isExpired(retained, now: now), "Expected session inside policy window to be retained")
    }

    private static func testRetentionDaysAreClamped() throws {
        try expectEqual(RetentionPolicy(target: .recordings, days: 0).days, 1)
        try expectEqual(RetentionPolicy(target: .recordings, days: 500).days, 365)
    }
}
