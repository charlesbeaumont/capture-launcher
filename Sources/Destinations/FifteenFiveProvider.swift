import Foundation

/// 15Five 1-on-1 agendas over the 15Five MCP server. One destination per
/// person Charles has 1-on-1s with; filing adds the capture as a talking
/// point, which starts an undated 1-on-1 when none is upcoming.
struct FifteenFiveProvider: DestinationProvider {
    let mcp: any MCPToolCaller
    var id: ProviderID { .fifteenFive }

    static let listTool = "list_one_on_one_counterparts"
    static let talkingPointTool = "add_one_on_one_talking_point"

    func listDestinations() async throws -> [Destination] {
        // Argument names are undocumented; keep the live schemas next to the
        // routing log so a changed tool is diagnosable.
        if let tools = try? await mcp.listTools() {
            Self.log("15five-tools.json", tools.value)
        }
        let result = try await mcp.callTool(name: Self.listTool, arguments: MCPJSON(value: [String: Any]()))
        Self.log("15five-counterparts.json", result.value)
        return Self.destinations(from: result.value)
    }

    func file(text: String, datetime: String, to destination: Destination, requestID: UUID) async throws {
        guard let ref = destination.ref else { throw MCPError.tool("no 15Five person for \(destination.title)") }
        let tools = try await mcp.listTools().objects
        guard let schema = tools.first(where: { $0["name"] as? String == Self.talkingPointTool })?["inputSchema"] as? [String: Any] else {
            throw MCPError.tool("\(Self.talkingPointTool) is not offered; is Updates switched on in 15Five?")
        }
        let arguments = try Self.talkingPointArguments(schema: schema, person: ref, text: text, requestID: requestID)
        _ = try await mcp.callTool(name: Self.talkingPointTool, arguments: MCPJSON(value: arguments))
    }

    // MARK: - Pure, testable

    /// Maps the tool's own schema onto person, text and request id.
    nonisolated static func talkingPointArguments(
        schema: [String: Any], person: String, text: String, requestID: UUID
    ) throws -> [String: Any] {
        let properties = schema["properties"] as? [String: [String: Any]] ?? [:]
        let required = Set(schema["required"] as? [String] ?? [])
        let names = Array(properties.keys)

        func pick(_ match: (String) -> Bool) -> String? {
            names.filter { match($0.lowercased()) }.sorted { $0.count < $1.count }.first
        }
        let personKey = pick { $0.contains("counterpart") }
            ?? pick { ($0.contains("user") || $0.contains("person") || $0.contains("participant")
                       || $0.contains("employee") || $0.contains("report")) && $0.contains("id") }
        let textKey = pick { ["text", "title", "content", "body", "talking_point", "description"].contains($0) }
            ?? pick { $0.contains("text") || $0.contains("title") || $0.contains("content") }
        let requestKey = pick { $0.contains("request") || $0.contains("idempotency") }

        guard let personKey, let textKey else {
            throw MCPError.tool("can't map \(talkingPointTool) arguments: \(names.sorted())")
        }
        var arguments: [String: Any] = [textKey: text]
        let personType = properties[personKey]?["type"] as? String
        arguments[personKey] = personType == "integer" ? (Int(person) as Any? ?? person) : person
        if let requestKey { arguments[requestKey] = requestID.uuidString }

        let unmapped = required.subtracting(arguments.keys)
        guard unmapped.isEmpty else {
            throw MCPError.tool("\(talkingPointTool) also requires \(unmapped.sorted())")
        }
        return arguments
    }

    /// Finds the list of people in whatever shape the tool returns.
    nonisolated static func destinations(from value: Any) -> [Destination] {
        guard let rows = firstObjectArray(in: value) else { return [] }
        return rows.compactMap { row -> Destination? in
            let person = ["counterpart", "user", "person", "employee"]
                .lazy.compactMap { row[$0] as? [String: Any] }.first ?? row
            guard let id = firstValue(person, ["id", "user_id", "counterpart_id", "person_id", "employee_id"]) ?? firstValue(row, ["counterpart_id", "user_id", "id"]),
                  let name = name(of: person) ?? name(of: row) else { return nil }
            let next = row.first { $0.key.lowercased().contains("next") }.flatMap { date(from: $0.value) }
            return Destination(provider: .fifteenFive, ref: id, title: name, kind: .oneOnOne, lastModified: next)
        }
        .sorted { $0.title < $1.title }
    }

    nonisolated private static func firstObjectArray(in value: Any) -> [[String: Any]]? {
        if let rows = value as? [[String: Any]] { return rows }
        if let dict = value as? [String: Any] {
            for key in dict.keys.sorted() {
                if let rows = firstObjectArray(in: dict[key]!) { return rows }
            }
        }
        return nil
    }

    nonisolated private static func firstValue(_ dict: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let s = dict[key] as? String, !s.isEmpty { return s }
            if let n = dict[key] as? NSNumber { return n.stringValue }
        }
        return nil
    }

    nonisolated private static func name(of dict: [String: Any]) -> String? {
        if let name = firstValue(dict, ["full_name", "name", "display_name"]) { return name }
        let parts = [firstValue(dict, ["first_name"]), firstValue(dict, ["last_name"])].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    nonisolated private static func date(from value: Any) -> Date? {
        if let dict = value as? [String: Any] {
            return dict.values.lazy.compactMap { date(from: $0) }.first
        }
        guard let text = value as? String else { return nil }
        let full = ISO8601DateFormatter()
        if let d = full.date(from: text) { return d }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        return day.date(from: String(text.prefix(10)))
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
