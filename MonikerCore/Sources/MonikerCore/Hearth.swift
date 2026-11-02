import Foundation

// Hearth (github.com/seckinbeduk/hearth) runs a local model on your Mac and serves it with an
// OpenAI-compatible API. Apps that can't use Apple Intelligence, or prefer a bigger model, use it
// through this client. Each request names the app, so Hearth's "Who's using it" shows who used what.

/// Which model does the work.
public enum Engine: String, Sendable, CaseIterable, Codable {
    /// Apple Intelligence, on-device.
    case apple
    /// Hearth's local model.
    case hearth
    /// Apple Intelligence when it's available, Hearth otherwise.
    case auto
}

public enum HearthError: Error, LocalizedError, Equatable {
    case notRunning
    case server(String)
    case badReply

    public var errorDescription: String? {
        switch self {
        case .notRunning: "Hearth isn't running. Start it from the menu bar, or get it at github.com/seckinbeduk/hearth."
        case .server(let message): "Hearth: \(message)"
        case .badReply: "Hearth's model didn't give a usable answer. Try again, or pick a larger model in Hearth."
        }
    }
}

public struct HearthClient: Sendable {
    public let baseURL: URL
    public let appName: String
    public let appVersion: String
    /// The model Hearth is serving, if it said.
    public let model: String?
    /// What to ask Hearth for: "hearth" (its local model) or "apple-intelligence" (Apple's, through Hearth).
    public var requestedModel: String

    public init(baseURL: URL, appName: String, appVersion: String, model: String? = nil, requestedModel: String = "hearth") {
        self.baseURL = baseURL
        self.appName = appName
        self.appVersion = appVersion
        self.model = model
        self.requestedModel = requestedModel
    }

    /// "mlx-community/Qwen3-8B-4bit" or "Apple Intelligence via Hearth", for logs and status lines.
    public var servingDescription: String {
        requestedModel.lowercased().hasPrefix("apple") ? "Apple Intelligence via Hearth" : (model ?? "no model loaded")
    }

    /// Hearth's preferred port is 8800; if that's taken it uses one of the next nine.
    static func candidatePorts() -> [Int] {
        var ports = Array(8800...8809)
        if let preferred = CFPreferencesCopyAppValue("hearth.port" as CFString, "io.github.seckinbeduk.hearth" as CFString) as? Int,
           preferred > 0 {
            ports.removeAll { $0 == preferred }
            ports.insert(preferred, at: 0)
        }
        return ports
    }

    /// Finds a running Hearth on this Mac, or nil.
    public static func discover(appName: String, appVersion: String, requestedModel: String = "hearth") async -> HearthClient? {
        for port in candidatePorts() {
            guard let base = URL(string: "http://127.0.0.1:\(port)") else { continue }
            var request = URLRequest(url: base.appendingPathComponent("health"))
            request.timeoutInterval = 0.5
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let health = try? JSONDecoder().decode(Health.self, from: data),
                  health.server == "Hearth" else { continue }
            return HearthClient(baseURL: base, appName: appName, appVersion: appVersion, model: health.model,
                                requestedModel: requestedModel)
        }
        return nil
    }

    struct Health: Decodable {
        let status: String?
        let model: String?
        let server: String?
    }

    /// One chat completion, not streamed. Returns the text with any thinking removed.
    /// With a `schema` (JSON Schema), Hearth answers Apple Intelligence requests through guided
    /// generation, so the reply always matches; local models get the schema as an instruction.
    public func chat(system: String, user: String, maxTokens: Int, temperature: Double = 0.3,
                     schema: [String: Any]? = nil, schemaName: String = "Response") async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("\(appName)/\(appVersion) (macOS)", forHTTPHeaderField: "User-Agent")
        request.setValue(appName, forHTTPHeaderField: "X-Title")
        var body: [String: Any] = [
            "model": requestedModel,
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
            "max_tokens": maxTokens,
            "temperature": temperature,
            "stream": false,
        ]
        if let schema {
            body["response_format"] = ["type": "json_schema",
                                       "json_schema": ["name": schemaName, "schema": schema, "strict": true]]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw HearthError.notRunning
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let message = (try? JSONDecoder().decode(ErrorReply.self, from: data))?.error.message
            throw HearthError.server(message ?? "request failed (\(status))")
        }
        guard let reply = try? JSONDecoder().decode(ChatReply.self, from: data),
              let content = reply.choices.first?.message.content else { throw HearthError.badReply }
        return JSONReply.removeThinking(content)
    }

    struct ChatReply: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]
    }

    struct ErrorReply: Decodable {
        struct Detail: Decodable { let message: String }
        let error: Detail
    }
}

/// Pulls a JSON object out of a model's reply, however it was wrapped.
public enum JSONReply {
    public static func decode<T: Decodable>(_ type: T.Type, from text: String) -> T? {
        let text = removeThinking(text)
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        return try? JSONDecoder().decode(T.self, from: Data(text[start...end].utf8))
    }

    /// Drops a `<think>…</think>` block some local models emit before answering.
    public static func removeThinking(_ text: String) -> String {
        guard let close = text.range(of: "</think>") else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        return String(text[close.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Moniker's namer, served by Hearth. The reply is JSON in text; FileNamer cleans it up as usual.
public struct HearthNamer: NamingModel {
    let client: HearthClient

    public init(client: HearthClient) {
        self.client = client
    }

    public func suggest(instructions: String, prompt: String) async throws -> NameIdea {
        let system = instructions + """


        Reply with only a JSON object, no other text:
        {"title": "...", "tags": ["..."]}
        """
        let reply = try await client.chat(system: system, user: prompt, maxTokens: 150,
                                          schema: Self.schema, schemaName: "FileName")
        guard let idea = JSONReply.decode(Reply.self, from: reply), let title = idea.title, !title.isEmpty else {
            throw HearthError.badReply
        }
        return NameIdea(title: title, tags: idea.tags ?? [])
    }

    /// The same shape as the @Generable type used with Apple Intelligence directly.
    static var schema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "title": ["type": "string",
                          "description": "A short, specific title: 2 to 6 words in Title Case, no date, no file extension"],
                "tags": ["type": "array", "items": ["type": "string"], "maxItems": 3,
                         "description": "Up to three lowercase one-word topics"],
            ],
            "required": ["title", "tags"],
        ]
    }

    struct Reply: Decodable {
        var title: String?
        var tags: [String]?
    }
}
