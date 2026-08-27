import Foundation

/// Reads the OAuth token Claude Code stores on this Mac.
///
/// Nibble only does this after the user explicitly asks it to. The read goes
/// through Apple's `security` tool rather than the Security framework: Claude
/// Code writes the item with that same tool, so its ACL already trusts it, and
/// the read is silent. Calling `SecItemCopyMatching` ourselves put Nibble's own
/// ad-hoc signature in front of the ACL instead, which meant a macOS approval
/// prompt after every rebuild and every token rotation — grants could never
/// stick. Nothing is persisted: the token is held in memory for the life of
/// the process and re-read when the server rejects it, so it follows Claude
/// Code's rotation without Nibble ever writing, refreshing, or storing a
/// credential of its own.
public final class ClaudeCodeCredentials {
    public enum LookupError: Error, LocalizedError, Equatable {
        case notSignedIn
        case accessDenied
        case keychain(Int32)

        public var errorDescription: String? {
            switch self {
            case .notSignedIn:
                return "No Claude Code login found on this Mac. Run `claude` and sign in first."
            case .accessDenied:
                return "The login keychain is locked. Unlock it in Keychain Access and try again."
            case .keychain(let code):
                return "Keychain read failed (security exited with code \(code))."
            }
        }
    }

    static let keychainService = "Claude Code-credentials"

    let fallbackURL: URL
    let useKeychain: Bool
    let securityTool: URL

    /// Guards `cached`, and incidentally keeps two concurrent reads from
    /// spawning two processes.
    private let lock = NSLock()
    private var cached: String?

    public init(
        fallbackURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json"),
        useKeychain: Bool = true,
        securityTool: URL = URL(fileURLWithPath: "/usr/bin/security")
    ) {
        self.fallbackURL = fallbackURL
        self.useKeychain = useKeychain
        self.securityTool = securityTool
    }

    /// Extracts the access token from Claude Code's credential JSON.
    public static func accessToken(fromJSON data: Data) -> String? {
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let token = (root?["claudeAiOauth"] as? [String: Any])?["accessToken"] as? String
        return (token?.isEmpty ?? true) ? nil : token
    }

    /// The token, read once and then remembered, so each poll doesn't spawn
    /// a process. Pass `reload: true` after a 401 to pick up a token Claude
    /// Code has rotated underneath us.
    public func readToken(reload: Bool = false) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        if !reload, let cached { return cached }
        let token = try load()
        cached = token
        return token
    }

    private func load() throws -> String {
        if useKeychain {
            switch keychainToken() {
            case .success(let token):
                return token
            case .failure(.notSignedIn):
                break  // fall through to the JSON file
            case .failure(let error):
                throw error
            }
        }
        if let data = try? Data(contentsOf: fallbackURL),
           let token = Self.accessToken(fromJSON: data) {
            return token
        }
        throw LookupError.notSignedIn
    }

    private func keychainToken() -> Result<String, LookupError> {
        let process = Process()
        process.executableURL = securityTool
        process.arguments = ["find-generic-password", "-s", Self.keychainService, "-w"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return .failure(.keychain(-1))
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        // The tool exits with the OSStatus truncated to a byte:
        // -25300 errSecItemNotFound → 44, -25308 errSecInteractionNotAllowed
        // → 36, -25293 errSecAuthFailed → 51, -128 errSecUserCanceled → 128.
        switch process.terminationStatus {
        case 0:
            guard let token = Self.accessToken(fromJSON: data) else {
                return .failure(.notSignedIn)
            }
            return .success(token)
        case 44:
            return .failure(.notSignedIn)
        case 36, 51, 128:
            return .failure(.accessDenied)
        default:
            return .failure(.keychain(process.terminationStatus))
        }
    }
}
