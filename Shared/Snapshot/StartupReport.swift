import Foundation

/// What was tried while opening the store, and what each attempt said.
///
/// This exists because the app is developed without a Mac: when it fails on a device, the only
/// evidence available is whatever the person running it can see. A white screen and a debugger
/// pause is not evidence. A report rendered on the phone, in selectable text, is.
///
/// Foundation-only and free of SwiftData on purpose, so the test bundle can compile it and so that
/// building the report cannot itself be the thing that fails.
struct StartupReport: Sendable, Equatable {

    /// One rung of the ladder and how it went.
    struct Step: Sendable, Equatable {
        let attempt: String
        let failure: String?

        var isSuccess: Bool { failure == nil }
    }

    /// The App Group the build asks for.
    var appGroupIdentifier: String
    /// Whether that group actually resolved to a directory. False means the entitlement is absent,
    /// which is normal for a free Apple ID and fatal to anything naming a group container.
    var appGroupResolved: Bool
    /// Whether the iCloud sync preference was on when the store was opened.
    var cloudSyncRequested: Bool
    var steps: [Step] = []

    mutating func record(_ attempt: String, failure: String? = nil) {
        steps.append(Step(attempt: attempt, failure: failure))
    }

    /// True when some configuration opened. A report can be worth printing either way.
    var didOpen: Bool { steps.contains(where: \.isSuccess) }

    /// Plain text, suitable for the Xcode console and for a screen on the device.
    var text: String {
        var lines = [
            "Tradewind startup report",
            "App Group:      \(appGroupIdentifier)",
            "  resolved:     \(appGroupResolved ? "yes" : "no — entitlement missing")",
            "  iCloud asked: \(cloudSyncRequested ? "yes" : "no")",
            "Attempts:",
        ]
        if steps.isEmpty {
            lines.append("  (none — nothing was considered safe to try)")
        }
        for step in steps {
            if let failure = step.failure {
                lines.append("  \(step.attempt): failed — \(failure)")
            } else {
                lines.append("  \(step.attempt): opened")
            }
        }
        return lines.joined(separator: "\n")
    }
}
