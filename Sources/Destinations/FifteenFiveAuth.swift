import AppKit
import AuthenticationServices
import CryptoKit
import Foundation

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
    static let callbackScheme = "capture"
    static let redirectURI = "capture://oauth/15five"

    /// Who the connection acts for, from `whoami`; empty when signed out.
    static let accountKey = "fifteenFive.account"

    enum AuthError: Error, CustomStringConvertible {
        case notSignedIn
        case http(Int, String)
        case badResponse(String)
        case cancelled

        var description: String {
            switch self {
            case .notSignedIn: "Not signed in to 15Five"
            case .http(let code, let body): "15Five HTTP \(code): \(body.prefix(200))"
            case .badResponse(let detail): "Unexpected 15Five response: \(detail)"
            case .cancelled: "Sign-in cancelled"
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

    static func register() async throws -> String {
        var request = URLRequest(url: FifteenFive.registerURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_name": "Capture",
            "redirect_uris": [FifteenFive.redirectURI],
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

/// The interactive half: registers a client, opens the 15Five login in the
/// browser sheet, and exchanges the code for tokens.
@MainActor
final class FifteenFiveSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func run() async throws {
        let clientId = try await FifteenFiveOAuth.register()
        let verifier = FifteenFiveOAuth.randomBase64URL(bytes: 32)
        let challenge = FifteenFiveOAuth.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = FifteenFiveOAuth.randomBase64URL(bytes: 16)

        var components = URLComponents(url: FifteenFive.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: clientId),
            .init(name: "redirect_uri", value: FifteenFive.redirectURI),
            .init(name: "scope", value: FifteenFive.scope),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "resource", value: FifteenFive.resource),
        ]

        let callback = try await authorize(components.url!)
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state else {
            throw FifteenFive.AuthError.badResponse("state mismatch")
        }
        if let error = items.first(where: { $0.name == "error" })?.value {
            throw FifteenFive.AuthError.badResponse(error)
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw FifteenFive.AuthError.badResponse("no code in callback")
        }

        let token = try await FifteenFiveOAuth.token([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": FifteenFive.redirectURI,
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
    }

    private func authorize(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callback: .customScheme(FifteenFive.callbackScheme)
            ) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: FifteenFive.AuthError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? FifteenFive.AuthError.cancelled)
                }
            }
            session.presentationContextProvider = self
            self.session = session
            session.start()
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible } ?? NSWindow()
        }
    }
}
