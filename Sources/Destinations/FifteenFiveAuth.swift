import AppKit
import CryptoKit
import Foundation
import Network

/// OAuth for the 15Five MCP server, as advertised at
/// `https://my.15five.com/.well-known/oauth-authorization-server`: dynamic
/// client registration, authorization code + PKCE S256, public client,
/// refresh tokens, scope `mcp:tools`.
enum FifteenFive {
    static let mcpEndpoint = URL(string: "https://my.15five.com/mcp")!
    static let resource = "https://my.15five.com/mcp"
    static let registerURL = URL(string: "https://my.15five.com/o/register")!
    static let authorizeURL = URL(string: "https://my.15five.com/o/authorize/")!
    static let tokenURL = URL(string: "https://my.15five.com/o/token/")!
    static let revokeURL = URL(string: "https://my.15five.com/o/revoke_token/")!
    static let scope = "mcp:tools"

    /// Who the connection acts for, from `whoami`; empty when signed out.
    static let accountKey = "fifteenFive.account"

    enum AuthError: Error, CustomStringConvertible {
        case notSignedIn
        case http(Int, String)
        case badResponse(String)
        case cancelled
        case timedOut

        var description: String {
            switch self {
            case .notSignedIn: "Not signed in to 15Five"
            case .http(let code, let body): "15Five HTTP \(code): \(body.prefix(200))"
            case .badResponse(let detail): "Unexpected 15Five response: \(detail)"
            case .cancelled: "Sign-in cancelled"
            case .timedOut: "Sign-in timed out; try again"
            }
        }
    }
}

/// Stored in the Keychain as one JSON item.
struct FifteenFiveCredentials: Codable, Sendable {
    var clientId: String
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
}

/// Serialises token reads and refreshes so concurrent calls never race two
/// refreshes with one single-use refresh token.
actor FifteenFiveTokens {
    static let shared = FifteenFiveTokens()

    private let service = "com.charlesbeaumont.Capture.15five"
    private let account = "credentials"

    var isSignedIn: Bool { load() != nil }

    func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard var creds = load() else { throw FifteenFive.AuthError.notSignedIn }
        if forceRefresh || creds.expiresAt < Date().addingTimeInterval(60) {
            guard let refresh = creds.refreshToken else { throw FifteenFive.AuthError.notSignedIn }
            let token = try await FifteenFiveOAuth.token([
                "grant_type": "refresh_token",
                "refresh_token": refresh,
                "client_id": creds.clientId,
                "resource": FifteenFive.resource,
            ])
            creds.accessToken = token.accessToken
            creds.refreshToken = token.refreshToken ?? refresh
            creds.expiresAt = token.expiresAt
            save(creds)
        }
        return creds.accessToken
    }

    func store(_ creds: FifteenFiveCredentials) { save(creds) }

    func clear() {
        SecItemDelete(query() as CFDictionary)
    }

    private func query() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private func load() -> FifteenFiveCredentials? {
        var q = query()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(FifteenFiveCredentials.self, from: data)
    }

    private func save(_ creds: FifteenFiveCredentials) {
        guard let data = try? JSONEncoder().encode(creds) else { return }
        SecItemDelete(query() as CFDictionary)
        var q = query()
        q[kSecValueData as String] = data
        SecItemAdd(q as CFDictionary, nil)
    }
}

enum FifteenFiveOAuth {
    struct Token {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date
    }

    static func token(_ form: [String: String]) async throws -> Token {
        var request = URLRequest(url: FifteenFive.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(formEncode(form).utf8)
        let json = try await jsonObject(for: request)
        guard let access = json["access_token"] as? String else {
            throw FifteenFive.AuthError.badResponse("no access_token")
        }
        let lifetime = (json["expires_in"] as? Double) ?? 3600
        return Token(accessToken: access,
                     refreshToken: json["refresh_token"] as? String,
                     expiresAt: Date().addingTimeInterval(lifetime))
    }

    static func register(redirectURI: String) async throws -> String {
        var request = URLRequest(url: FifteenFive.registerURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_name": "Capture",
            "redirect_uris": [redirectURI],
            "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"],
            "token_endpoint_auth_method": "none",
            "scope": FifteenFive.scope,
        ])
        let json = try await jsonObject(for: request)
        guard let clientId = json["client_id"] as? String else {
            throw FifteenFive.AuthError.badResponse("registration returned no client_id")
        }
        return clientId
    }

    static func jsonObject(for request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw FifteenFive.AuthError.http(status, String(decoding: data, as: UTF8.self))
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FifteenFive.AuthError.badResponse("not a JSON object")
        }
        return json
    }

    static func formEncode(_ form: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return form.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&")
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func randomBase64URL(bytes: Int) -> String {
        var buffer = [UInt8](repeating: 0, count: bytes)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes, &buffer)
        return base64URL(Data(buffer))
    }
}

/// The interactive half, as a desktop app does OAuth (RFC 8252): listen on a
/// loopback port, register a client with that exact redirect, open the
/// 15Five login in the default browser, and exchange the returned code.
/// 15Five rejects custom-scheme redirects such as `capture://`.
@MainActor
final class FifteenFiveSignIn {
    func run() async throws {
        let listener = try LoopbackCallback()
        defer { listener.stop() }
        let redirectURI = "http://127.0.0.1:\(try await listener.start())/callback"

        let clientId = try await FifteenFiveOAuth.register(redirectURI: redirectURI)
        let verifier = FifteenFiveOAuth.randomBase64URL(bytes: 32)
        let challenge = FifteenFiveOAuth.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = FifteenFiveOAuth.randomBase64URL(bytes: 16)

        var components = URLComponents(url: FifteenFive.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: clientId),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "scope", value: FifteenFive.scope),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "resource", value: FifteenFive.resource),
        ]
        NSWorkspace.shared.open(components.url!)

        let items = try await listener.awaitCallback(timeout: 300)
        guard items["state"] == state else {
            throw FifteenFive.AuthError.badResponse("state mismatch")
        }
        if let error = items["error"] {
            throw error == "access_denied" ? FifteenFive.AuthError.cancelled : FifteenFive.AuthError.badResponse(error)
        }
        guard let code = items["code"] else {
            throw FifteenFive.AuthError.badResponse("no code in callback")
        }

        let token = try await FifteenFiveOAuth.token([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientId,
            "code_verifier": verifier,
            "resource": FifteenFive.resource,
        ])
        await FifteenFiveTokens.shared.store(FifteenFiveCredentials(
            clientId: clientId,
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiresAt: token.expiresAt
        ))
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// One-shot HTTP listener on 127.0.0.1 for the OAuth redirect. Answers the
/// browser with a short page and hands back the query parameters.
final class LoopbackCallback: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "capture.oauth.loopback")
    // Both touched only on `queue`.
    private var continuation: CheckedContinuation<[String: String], Error>?
    private var startResumed = false

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    /// Starts listening and returns the port the OS picked.
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (ready: CheckedContinuation<UInt16, Error>) in
            listener.stateUpdateHandler = { [self] state in
                guard !startResumed else { return }
                switch state {
                case .ready:
                    startResumed = true
                    ready.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error):
                    startResumed = true
                    ready.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
            listener.start(queue: queue)
        }
    }

    func awaitCallback(timeout: TimeInterval) async throws -> [String: String] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.continuation = continuation
                self.queue.asyncAfter(deadline: .now() + timeout) {
                    self.finish(.failure(FifteenFive.AuthError.timedOut))
                }
            }
        }
    }

    func stop() { listener.cancel() }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            let request = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
            // "GET /callback?code=…&state=… HTTP/1.1"
            let target = request.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            guard target.hasPrefix("/callback") else {
                connection.send(content: Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8),
                                completion: .contentProcessed { _ in connection.cancel() })
                return
            }
            let page = "<html><body style=\"font:16px -apple-system;padding:3em\">Capture is connected to 15Five. You can close this tab.</body></html>"
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(page.utf8.count)\r\nConnection: close\r\n\r\n\(page)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            var items: [String: String] = [:]
            for item in URLComponents(string: "http://127.0.0.1\(target)")?.queryItems ?? [] {
                items[item.name] = item.value
            }
            self?.finish(.success(items))
        }
    }

    private func finish(_ result: Result<[String: String], Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}
