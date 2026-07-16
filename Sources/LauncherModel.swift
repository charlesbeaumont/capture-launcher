import Foundation
import Observation

/// Stage machine driving the launcher. All transitions are synchronous and
/// in-memory; Bear work happens behind them via CaptureRouter (optimistic).
@MainActor
@Observable
final class LauncherModel {
    enum Mode { case capture, triage }

    enum Stage: Equatable {
        case loading      // triage only: reading the inbox (a few ms)
        case compose      // editing the thought (prefilled in triage)
        case route        // destination picker below the dimmed text
        case done         // triage only: "inbox clear" flash
    }

    let mode: Mode
    private let store: DestinationStore
    private let router: CaptureRouter
    private let bear: BearCLI
    /// Hides the panel. The model decides when; the delegate does the hiding.
    private let onFinish: () -> Void

    private(set) var stage: Stage
    var composeText: String = ""
    var query: String = "" {
        didSet { if query != oldValue { refilter() } }
    }
    private(set) var selectionIndex = 0
    private(set) var ranked: [RankedDestination] = []
    private(set) var lastFilterMS: Double = 0
    private(set) var hint: String?

    // Triage session (immutable snapshot).
    private(set) var entries: [InboxEntry] = []
    private(set) var currentIndex = 0

    init(
        mode: Mode,
        store: DestinationStore,
        router: CaptureRouter,
        bear: BearCLI,
        onFinish: @escaping () -> Void
    ) {
        self.mode = mode
        self.store = store
        self.router = router
        self.bear = bear
        self.onFinish = onFinish
        self.stage = mode == .capture ? .compose : .loading
        if mode == .triage { loadTriageSession() }
    }

    // MARK: - Derived display state

    var counterText: String? {
        guard mode == .triage, !entries.isEmpty, currentIndex < entries.count else { return nil }
        return "\(currentIndex + 1)/\(entries.count)"
    }

    var bannerText: String {
        composeText.isEmpty ? "(empty)" : composeText
    }

    var composePlaceholder: String {
        mode == .capture ? "Capture a thought…" : "(empty)"
    }

    var queryPlaceholder: String {
        let fallback: String
        switch mode {
        case .capture: fallback = "enter → inbox"
        case .triage: fallback = store.generalReference != nil ? "enter → general reference" : "enter → skip"
        }
        return "route to…  \(fallback)"
    }

    var hintText: String {
        if let hint { return hint }
        switch (mode, stage) {
        case (.capture, .route): return "↩ route · esc back"
        case (.triage, .compose): return "↩ route · ⇥ skip · ⌘⌫ discard · esc exit"
        case (.triage, .route): return "↩ file · ⇥ skip · ⌘⌫ discard · esc back"
        default: return ""
        }
    }

    /// Empty-query default row: Inbox when capturing, general reference in triage.
    private var pinnedDestination: Destination? {
        switch mode {
        case .capture: .inbox
        case .triage: store.generalReference
        }
    }

    // MARK: - Stage transitions

    func submitCompose() {
        let trimmed = composeText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .capture:
            guard !trimmed.isEmpty else {
                onFinish()
                return
            }
        case .triage:
            break // empty entries can still be routed/discarded
        }
        beginRouting()
    }

    private func beginRouting() {
        query = ""
        hint = nil
        refilter()
        stage = .route
    }

    func submitRoute() {
        guard selectionIndex < ranked.count else {
            if mode == .triage { advance() }
            return
        }
        let destination = ranked[selectionIndex].destination
        let text = composeText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch mode {
        case .capture:
            if destination.kind == .inbox {
                router.captureToInbox(text: text)
            } else {
                router.file(text: text, to: destination)
            }
            onFinish()
        case .triage:
            let entry = entries[currentIndex]
            router.triageRoute(entry: entry, editedText: text, to: destination)
            advance()
        }
    }

    /// Route stage with no rows at all (triage without a general reference
    /// and an empty query): fall back to skip.
    var routeHasRows: Bool { !ranked.isEmpty }

    func escape() {
        switch stage {
        case .route:
            stage = .compose
        case .compose, .loading, .done:
            onFinish()
        }
    }

    func skip() {
        guard mode == .triage else { return }
        advance()
    }

    func discard() {
        guard mode == .triage, currentIndex < entries.count else { return }
        router.triageDiscard(entry: entries[currentIndex])
        advance()
    }

    func moveSelection(_ delta: Int) {
        guard !ranked.isEmpty else { return }
        selectionIndex = max(0, min(ranked.count - 1, selectionIndex + delta))
    }

    func refilter() {
        let start = CFAbsoluteTimeGetCurrent()
        ranked = DestinationRanker.rank(
            indexed: store.indexed,
            query: query,
            usageIndex: store.usageIndex,
            pinned: pinnedDestination
        )
        lastFilterMS = (CFAbsoluteTimeGetCurrent() - start) * 1000
        selectionIndex = 0
    }

    // MARK: - Triage session

    private func loadTriageSession() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let content = try await bear.readNote(id: DestinationStore.inboxNoteId).content
                let parsed = InboxParser.parse(content)
                self.entries = parsed
                if parsed.isEmpty {
                    self.finishTriage()
                } else {
                    self.currentIndex = 0
                    self.composeText = parsed[0].body
                    self.stage = .compose
                }
            } catch {
                Notify.failure("Could not read the Inbox note: \(error)")
                self.onFinish()
            }
        }
    }

    private func advance() {
        hint = nil
        currentIndex += 1
        guard currentIndex < entries.count else {
            finishTriage()
            return
        }
        composeText = entries[currentIndex].body
        query = ""
        stage = .compose
    }

    private func finishTriage() {
        stage = .done
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            self?.onFinish()
        }
    }
}
