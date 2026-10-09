import Foundation

public enum AgentCommand: Sendable {
    case pair
    case listen
}

public enum ConfigurationError: Error, CustomStringConvertible, Equatable {
    case missing(String)
    case invalidServerURL

    public var description: String {
        switch self {
        case .missing(let name):
            return "Environment variable \(name) is required."
        case .invalidServerURL:
            return "RAMBU_SERVER_URL must be an absolute http or https URL."
        }
    }
}

public struct AgentConfiguration: Sendable {
    public let serverURL: URL
    public let puckToken: String?

    public init(environment: [String: String], command: AgentCommand) throws {
        guard let rawURL = environment["RAMBU_SERVER_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawURL.isEmpty else {
            throw ConfigurationError.missing("RAMBU_SERVER_URL")
        }
        guard let serverURL = URL(string: rawURL),
              let scheme = serverURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              serverURL.host != nil else {
            throw ConfigurationError.invalidServerURL
        }
        let token = environment["RAMBU_PUCK_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if command == .listen && (token?.isEmpty != false) {
            throw ConfigurationError.missing("RAMBU_PUCK_TOKEN")
        }
        self.serverURL = serverURL
        self.puckToken = token?.isEmpty == false ? token : nil
    }
}
