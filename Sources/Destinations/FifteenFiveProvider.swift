import Foundation

/// 15Five 1-on-1 agendas over the 15Five MCP server, its only write path for
/// talking points. Called as a plain API with the exact tool contract: one
/// destination per 1-on-1 person, and filing adds one talking point to the
/// pair's current 1-on-1 (started if none exists).
struct FifteenFiveProvider: DestinationProvider {
    let mcp: any MCPToolCaller
    var id: ProviderID { .fifteenFive }

    static let listTool = "list_one_on_one_counterparts"
    static let talkingPointTool = "add_one_on_one_talking_point"

    func listDestinations() async throws -> [Destination] {
        // Diagnostic only: if 15Five changes a tool, the live schema is here.
        if let tools = try? await mcp.listTools() {
            Self.log("15five-tools.json", tools.value)
        }
        var people: [Counterpart] = []
        var offset = 0
        while true {
            let result = try await mcp.callTool(
                name: Self.listTool,
                arguments: MCPJSON(value: ["params": ["limit": 100, "offset": offset]])
            )
            let page = try Self.decode(CounterpartsPage.self, from: result, tool: Self.listTool)
            people += page.counterparts ?? []
            guard page.hasMore == true, let next = page.nextOffset, next > offset else { break }
            offset = next
        }
        return Self.destinations(from: people)
    }

    func file(text: String, datetime: String, to destination: Destination, requestID: UUID) async throws {
        guard let ref = destination.ref, let userId = Int(ref) else {
            throw MCPError.tool("no 15Five user id for \(destination.title)")
        }
        let result = try await mcp.callTool(
            name: Self.talkingPointTool,
            arguments: MCPJSON(value: Self.talkingPointArguments(userId: userId, text: text, requestID: requestID))
        )
        let receipt = try Self.decode(TalkingPointReceipt.self, from: result, tool: Self.talkingPointTool).receipt
        guard receipt.applied || receipt.replay == true else {
            throw MCPError.tool("\(Self.talkingPointTool) did not apply: \(receipt.summary)")
        }
    }

    // MARK: - Contract (from the live tools/list schema, 2026-10-14)

    struct Counterpart: Decodable {
        let userId: Int
        let name: String
        let nextMeetingDate: String?
    }

    struct CounterpartsPage: Decodable {
        /// Defaults to empty in the schema, so it may be omitted.
        let counterparts: [Counterpart]?
        let hasMore: Bool?
        let nextOffset: Int?
    }

    struct TalkingPointReceipt: Decodable {
        struct Receipt: Decodable {
            let applied: Bool
            let replay: Bool?
            let summary: String
        }
        let receipt: Receipt
    }

    nonisolated static func talkingPointArguments(userId: Int, text: String, requestID: UUID) -> [String: Any] {
        ["params": ["with_user_id": userId, "description": text, "request_id": requestID.uuidString]]
    }

    /// One row per person, ranked by their next 1-on-1 date.
    nonisolated static func destinations(from people: [Counterpart]) -> [Destination] {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        return people.map {
            Destination(provider: .fifteenFive, ref: String($0.userId), title: $0.name,
                        kind: .oneOnOne, lastModified: $0.nextMeetingDate.flatMap(day.date(from:)))
        }
    }

    nonisolated static func decode<T: Decodable>(_ type: T.Type, from result: MCPToolResult, tool: String) throws -> T {
        guard JSONSerialization.isValidJSONObject(result.value),
              let data = try? JSONSerialization.data(withJSONObject: result.value) else {
            throw MCPError.tool("\(tool) returned no JSON: \(result.text.prefix(200))")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw MCPError.tool("\(tool) response changed shape: \(error)")
        }
    }

    nonisolated private static func log(_ file: String, _ value: Any) {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Capture/\(file)")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        else { return }
        try? data.write(to: url, options: .atomic)
    }
}
