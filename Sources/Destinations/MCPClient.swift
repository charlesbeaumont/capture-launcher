import Foundation

/// Calls one MCP tool and returns its result. A seam so a destination can
/// later swap the native client for another transport (e.g. `claude -p`).
protocol MCPToolCaller: Sendable {
    func listTools() async throws -> MCPJSON
    func callTool(name: String, arguments: MCPJSON) async throws -> MCPToolResult
}

/// JSON from JSONSerialization crossing actor boundaries. Never mutated
/// after creation, so sharing it is safe.
struct MCPJSON: @unchecked Sendable {
    let value: Any
    var objects: [[String: Any]] { value as? [[String: Any]] ?? [] }
}

struct MCPToolResult: @unchecked Sendable {
    /// `structuredContent` when the server sends it, else the first text
    /// block parsed as JSON, else the raw text.
    let value: Any
    let text: String
}

enum MCPError: Error, CustomStringConvertible {
    case http(Int, String)
    case rpc(String)
    case tool(String)

    var description: String {
        switch self {
        case .http(let code, let body): "MCP HTTP \(code): \(body.prefix(200))"
        case .rpc(let message): "MCP error: \(message)"
        case .tool(let message): "MCP tool error: \(message.prefix(300))"
        }
    }
}

/// Minimal Streamable HTTP MCP client: `initialize`, `tools/list`,
/// `tools/call`. Responses may come back as JSON or as an SSE stream.
actor NativeMCPClient: MCPToolCaller {
    private let endpoint: URL
    private let token: @Sendable (_ forceRefresh: Bool) async throws -> String
    private var sessionId: String?
    private var initialized = false
    private var nextId = 1

    init(endpoint: URL, token: @escaping @Sendable (_ forceRefresh: Bool) async throws -> String) {
        self.endpoint = endpoint
        self.token = token
    }

    func reset() {
        sessionId = nil
        initialized = false
    }

    func listTools() async throws -> MCPJSON {
        try await ensureInitialized()
        let result = try await rpc("tools/list", params: [:])
        return MCPJSON(value: result["tools"] as? [[String: Any]] ?? [])
    }

    func callTool(name: String, arguments: MCPJSON) async throws -> MCPToolResult {
        try await ensureInitialized()
        let result = try await rpc("tools/call", params: ["name": name, "arguments": arguments.value])
        let blocks = result["content"] as? [[String: Any]] ?? []
        let text = blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
        if result["isError"] as? Bool == true { throw MCPError.tool(text) }
        if let structured = result["structuredContent"] {
            return MCPToolResult(value: structured, text: text)
        }
        let parsed = (try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])) ?? text
        return MCPToolResult(value: parsed, text: text)
    }

    private func ensureInitialized() async throws {
        guard !initialized else { return }
        _ = try await rpc("initialize", params: [
            "protocolVersion": "2025-06-18",
            "capabilities": [:] as [String: Any],
            "clientInfo": ["name": "Capture", "version": "1"],
        ])
        try await notify("notifications/initialized")
        initialized = true
    }

    private func rpc(_ method: String, params: [String: Any]) async throws -> [String: Any] {
        let id = nextId
        nextId += 1
        let body: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
        let message = try await send(body, expectingId: id)
        if let error = message["error"] as? [String: Any] {
            throw MCPError.rpc(error["message"] as? String ?? "\(error)")
        }
        return message["result"] as? [String: Any] ?? [:]
    }

    private func notify(_ method: String) async throws {
        _ = try await send(["jsonrpc": "2.0", "method": method], expectingId: nil)
    }

    /// One retry on 401 with a refreshed token, and on 404 with a fresh
    /// session (the server forgot ours).
    private func send(_ body: [String: Any], expectingId id: Int?, retried: Bool = false) async throws -> [String: Any] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("2025-06-18", forHTTPHeaderField: "MCP-Protocol-Version")
        request.setValue("Bearer \(try await token(retried))", forHTTPHeaderField: "Authorization")
        if let sessionId { request.setValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        if let session = http?.value(forHTTPHeaderField: "Mcp-Session-Id") { sessionId = session }

        if !retried, status == 401 {
            return try await send(body, expectingId: id, retried: true)
        }
        if !retried, status == 404, sessionId != nil, body["method"] as? String != "initialize" {
            reset()
            try await ensureInitialized()
            return try await send(body, expectingId: id, retried: true)
        }
        guard (200..<300).contains(status) else {
            throw MCPError.http(status, String(decoding: data, as: UTF8.self))
        }
        guard let id else { return [:] }

        let contentType = http?.value(forHTTPHeaderField: "Content-Type") ?? ""
        let messages = contentType.contains("text/event-stream")
            ? Self.sseMessages(data)
            : [(try? JSONSerialization.jsonObject(with: data)) as? [String: Any]].compactMap { $0 }
        guard let match = messages.first(where: { ($0["id"] as? Int) == id }) else {
            throw MCPError.rpc("no response for request \(id)")
        }
        return match
    }

    nonisolated static func sseMessages(_ data: Data) -> [[String: Any]] {
        String(decoding: data, as: UTF8.self)
            .components(separatedBy: "\n\n")
            .compactMap { event in
                let payload = event.split(separator: "\n")
                    .filter { $0.hasPrefix("data:") }
                    .map { $0.dropFirst(5).trimmingCharacters(in: .whitespaces) }
                    .joined(separator: "\n")
                guard !payload.isEmpty else { return nil }
                return (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any]
            }
    }
}
