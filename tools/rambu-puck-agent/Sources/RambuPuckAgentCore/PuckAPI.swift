import Foundation

public enum PuckRiskLevel: String, Decodable, Equatable, Sendable {
    case low
    case needsReview = "needs_review"
    case highRisk = "high_risk"
}

public struct PuckAssessment: Decodable, Sendable {
    public let riskLevel: PuckRiskLevel
    public let recommendedAction: String

    public init(riskLevel: PuckRiskLevel, recommendedAction: String) {
        self.riskLevel = riskLevel
        self.recommendedAction = recommendedAction
    }
}

public struct ProtectionSession: Decodable, Sendable {
    public let id: String
    public let status: String
    public let endRequested: Bool
    public let nextSequence: Int
    public let maskedTranscript: String
    public let assessment: PuckAssessment?
}

public struct PuckWarning: Equatable, Sendable {
    public let title: String
    public let recommendedAction: String
}

public struct PuckWarningGate: Sendable {
    private var highestSeverity = 0

    public init() {}

    public mutating func warning(for assessment: PuckAssessment?) -> PuckWarning? {
        guard let assessment else { return nil }
        let severity: Int
        let title: String
        switch assessment.riskLevel {
        case .low:
            return nil
        case .needsReview:
            severity = 1
            title = "Telepon mencurigakan"
        case .highRisk:
            severity = 2
            title = "Terindikasi penipuan"
        }
        guard severity > highestSeverity else { return nil }
        highestSeverity = severity
        return PuckWarning(
            title: title,
            recommendedAction: assessment.recommendedAction
        )
    }
}

public struct PairedPuck: Decodable, Sendable {
    public let puckID: String
    public let familyID: String
    public let displayName: String
    public let accessToken: String

    private enum CodingKeys: String, CodingKey {
        case puckID = "puckId"
        case familyID = "familyId"
        case displayName
        case accessToken
    }
}

public enum PuckAPIError: Error, CustomStringConvertible, Equatable {
    case missingToken
    case transport(String)
    case server(status: Int, detail: String)
    case invalidResponse

    public var description: String {
        switch self {
        case .missingToken:
            return "RAMBU_PUCK_TOKEN is required for this request."
        case .transport(let detail):
            return "Network request failed: \(detail)"
        case .server(let status, let detail):
            return "HTTP \(status): \(detail)"
        case .invalidResponse:
            return "Server returned an invalid response."
        }
    }
}

public typealias HTTPTransport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

public struct PuckAPI: Sendable {
    private let serverURL: URL
    private let token: String?
    private let retryDelaysNanoseconds: [UInt64]
    private let transport: HTTPTransport
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(
        serverURL: URL,
        token: String?,
        retryDelaysNanoseconds: [UInt64] = [250_000_000, 750_000_000],
        transport: @escaping HTTPTransport = { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw PuckAPIError.invalidResponse
            }
            return (data, http)
        }
    ) {
        self.serverURL = serverURL
        self.token = token
        self.retryDelaysNanoseconds = retryDelaysNanoseconds
        self.transport = transport
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    public func pair(code: String, displayName: String) async throws -> PairedPuck {
        struct Body: Encodable { let code: String; let displayName: String }
        var request = URLRequest(url: endpoint("api", "pucks", "pair"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(Body(code: code, displayName: displayName))
        let (data, response) = try await send(request)
        try requireSuccess(response, data: data)
        return try decode(PairedPuck.self, from: data)
    }

    public func activeSession() async throws -> ProtectionSession? {
        var request = try authenticatedRequest(endpoint("api", "pucks", "sessions", "active"))
        request.httpMethod = "GET"
        let (data, response) = try await send(request)
        if response.statusCode == 404 { return nil }
        try requireSuccess(response, data: data)
        return try decode(ProtectionSession.self, from: data)
    }

    public func createSession(callID: UUID, startedAt: Date) async throws -> ProtectionSession {
        struct Body: Encodable {
            let callID: UUID
            let startedAt: Date
            let channel: String
            let title: String
            let callerDetail: String
        }
        var request = try authenticatedRequest(endpoint("api", "pucks", "sessions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(Body(
            callID: callID,
            startedAt: startedAt,
            channel: "whatsapp",
            title: "Panggilan WhatsApp terdeteksi",
            callerDetail: "Kontak WhatsApp"
        ))
        let (data, response) = try await send(request)
        try requireSuccess(response, data: data)
        return try decode(ProtectionSession.self, from: data)
    }

    public func startOrJoinSession(callID: UUID, startedAt: Date) async throws -> ProtectionSession {
        if let active = try await activeSession() {
            return active
        }
        do {
            return try await createSession(callID: callID, startedAt: startedAt)
        } catch let error as PuckAPIError {
            guard case .server(status: 409, detail: _) = error,
                  let active = try await activeSession() else {
                throw error
            }
            return active
        }
    }

    public func uploadChunk(
        sessionID: String,
        sequence: Int,
        final: Bool,
        wav: Data
    ) async throws -> ProtectionSession {
        var request = try authenticatedRequest(
            endpoint("api", "pucks", "sessions", sessionID, "chunks")
        )
        request.httpMethod = "POST"
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.setValue(String(sequence), forHTTPHeaderField: "X-Rambu-Sequence")
        request.setValue(final ? "true" : "false", forHTTPHeaderField: "X-Rambu-Final")
        request.httpBody = wav
        let (data, response) = try await send(request)
        try requireSuccess(response, data: data)
        return try decode(ProtectionSession.self, from: data)
    }

    private func authenticatedRequest(_ url: URL) throws -> URLRequest {
        guard let token, !token.isEmpty else { throw PuckAPIError.missingToken }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func endpoint(_ components: String...) -> URL {
        components.reduce(serverURL) { url, component in
            url.appendingPathComponent(component)
        }
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let attempts = retryDelaysNanoseconds.count + 1
        for attempt in 0..<attempts {
            do {
                let result = try await transport(request)
                if (500...599).contains(result.1.statusCode), attempt < attempts - 1 {
                    try await pause(afterAttempt: attempt)
                    continue
                }
                return result
            } catch {
                if error is CancellationError { throw error }
                if attempt < attempts - 1 {
                    try await pause(afterAttempt: attempt)
                    continue
                }
                if let apiError = error as? PuckAPIError { throw apiError }
                throw PuckAPIError.transport(error.localizedDescription)
            }
        }
        throw PuckAPIError.invalidResponse
    }

    private func pause(afterAttempt attempt: Int) async throws {
        let delay = retryDelaysNanoseconds[attempt]
        if delay > 0 { try await Task.sleep(nanoseconds: delay) }
    }

    private func requireSuccess(_ response: HTTPURLResponse, data: Data) throws {
        guard (200...299).contains(response.statusCode) else {
            throw PuckAPIError.server(
                status: response.statusCode,
                detail: Self.serverDetail(from: data)
            )
        }
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw PuckAPIError.invalidResponse
        }
    }

    private static func serverDetail(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let detail = object["detail"] else {
            return String(data: data, encoding: .utf8) ?? "Unknown server error."
        }
        if let text = detail as? String { return text }
        if let dictionary = detail as? [String: Any], let message = dictionary["message"] as? String {
            return message
        }
        return "Unknown server error."
    }
}
