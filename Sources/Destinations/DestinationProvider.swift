import Foundation

/// A system Capture can file into. Every provider's destinations merge into
/// one picker list; the provider owns how a capture is written.
enum ProviderID: String, Codable, Sendable, CaseIterable {
    case bear, fifteenFive

    var displayName: String {
        switch self {
        case .bear: "Bear"
        case .fifteenFive: "15Five"
        }
    }

    private var enabledKey: String { "destination.\(rawValue).enabled" }

    /// Bear is on unless switched off; anything needing a sign-in starts off.
    nonisolated var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? (self == .bear)
    }

    nonisolated func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
    }
}

protocol DestinationProvider: Sendable {
    var id: ProviderID { get }
    func listDestinations() async throws -> [Destination]
    /// Writes `text` verbatim. `datetime` is the capture's own timestamp
    /// (`yyyy-MM-dd HH:mm`); `requestID` lets a retried write land once.
    func file(text: String, datetime: String, to destination: Destination, requestID: UUID) async throws
}
