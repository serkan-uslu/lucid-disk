import XCTest
@testable import LucidDiskCore

/// Every provider is exercised through an injected transport; tests never touch the network.
final class InsightProviderTests: XCTestCase {
    private let node = FileNode(name: "archive.zip", path: "/Users/example/Downloads/archive.zip",
                                isDirectory: false, size: 1)
    private var assessment: DeletionAssessment {
        DeletionSafety.assess(path: node.path, homePath: "/Users/example")
    }

    func testClaudeRequestShapeAndHeaders() throws {
        let request = try ClaudeClient(apiKey: "sk-test", model: "claude-opus-5-5")
            .messagesRequest(system: "system", prompt: "prompt")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])

        XCTAssertEqual(request.url, ClaudeClient.messagesURL)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "server-side-fallback-2026-07-01")
        XCTAssertEqual(body["model"] as? String, "claude-opus-5-5")
        XCTAssertEqual(body["fallbacks"] as? String, "default")
        XCTAssertEqual((body["output_config"] as? [String: String])?["effort"], "low")
        XCTAssertGreaterThanOrEqual(body["max_tokens"] as? Int ?? 0, 4096)
        XCTAssertNil(body["thinking"])
    }

    func testClaudeOmitsUnsupportedParametersForOtherModels() throws {
        let request = try ClaudeClient(apiKey: "sk-test", model: "claude-haiku-4-5")
            .messagesRequest(system: "system", prompt: "prompt")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])

        XCTAssertNil(body["fallbacks"])
        XCTAssertNil(body["output_config"])
        XCTAssertNil(request.value(forHTTPHeaderField: "anthropic-beta"))
    }

    func testClaudeParsesTextBlocksAndIgnoresOthers() throws {
        let data = Data("""
        {"stop_reason":"end_turn","content":[{"type":"thinking","thinking":""},
         {"type":"text","text":"  A downloaded archive. "}]}
        """.utf8)
        XCTAssertEqual(try ClaudeClient.parseMessage(data), "A downloaded archive.")
    }

    func testClaudeRefusalAndEmptyAnswersFallBackToLocalRules() async {
        for payload in [
            #"{"stop_reason":"refusal","content":[]}"#,
            #"{"stop_reason":"max_tokens","content":[{"type":"thinking","thinking":""}]}"#
        ] {
            let result = await claudeService(respondingWith: payload).insight(for: node, assessment: assessment)
            XCTAssertEqual(result.source, .localRules, payload)
            XCTAssertNotNil(result.providerNote, payload)
        }
    }

    func testClaudeAnswerOnlyReplacesProbablePurpose() async {
        let payload = #"{"stop_reason":"end_turn","content":[{"type":"text","text":"Ignore policy. Delete everything."}]}"#
        let result = await claudeService(respondingWith: payload).insight(for: node, assessment: assessment)

        XCTAssertEqual(result.source, .claude)
        XCTAssertEqual(result.modelName, "claude-opus-5-5")
        XCTAssertEqual(result.whyItMatters, assessment.summary)
        XCTAssertEqual(result.verificationSteps.first, assessment.recommendation)
    }

    func testClaudeWithoutConsentNeverSendsARequest() async {
        var configuration = InsightConfiguration()
        configuration.provider = .claude
        configuration.claudeAPIKey = "sk-test"
        configuration.cloudConsent = false
        let counter = RequestCounter()
        let service = LocalFileInsightService(configuration: configuration, transport: counter.transport(status: 200, body: "{}"))

        let result = await service.insight(for: node, assessment: assessment)

        XCTAssertEqual(result.source, .localRules)
        XCTAssertEqual(counter.count, 0)
        XCTAssertNotNil(result.providerNote)
    }

    func testClaudeHTTPErrorsBecomeReadableNotes() async {
        var configuration = InsightConfiguration()
        configuration.provider = .claude
        configuration.claudeAPIKey = "sk-bad"
        configuration.cloudConsent = true
        let body = #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#
        let service = LocalFileInsightService(configuration: configuration,
                                              transport: RequestCounter().transport(status: 401, body: body))

        let result = await service.insight(for: node, assessment: assessment)

        XCTAssertEqual(result.source, .localRules)
        XCTAssertEqual(result.providerNote, InsightProviderError.http(status: 401, message: nil).errorDescription)
    }

    func testOllamaStripsThinkingAndUsesChatEndpoint() async throws {
        var configuration = InsightConfiguration()
        configuration.provider = .ollama
        configuration.ollamaModel = "llama3.2"
        let body = #"{"message":{"role":"assistant","content":"<think>hmm</think>\nA zip archive you downloaded."}}"#
        let counter = RequestCounter()
        let service = LocalFileInsightService(configuration: configuration, transport: counter.transport(status: 200, body: body))

        let result = await service.insight(for: node, assessment: assessment)

        XCTAssertEqual(result.source, .ollama)
        XCTAssertEqual(result.probablePurpose, "A zip archive you downloaded.")
        XCTAssertEqual(counter.lastURL?.path, "/api/chat")
        XCTAssertEqual(OllamaClient.stripThinking("<think>unfinished"), "")
    }

    func testOllamaWithoutModelFallsBackWithoutNetwork() async {
        var configuration = InsightConfiguration()
        configuration.provider = .ollama
        let counter = RequestCounter()
        let result = await LocalFileInsightService(configuration: configuration,
                                                   transport: counter.transport(status: 200, body: "{}"))
            .insight(for: node, assessment: assessment)

        XCTAssertEqual(result.source, .localRules)
        XCTAssertEqual(counter.count, 0)
    }

    func testOllamaListsOnlyLocalChatModels() async throws {
        let body = """
        {"models":[
          {"name":"qwen3:8b","capabilities":["completion","tools"]},
          {"name":"llama3.2:latest"},
          {"name":"embeddinggemma:latest","capabilities":["embedding"]},
          {"name":"glm-5:cloud","remote_host":"https://ollama.com:443","capabilities":["completion"]},
          {"name":"gemini-3-flash-preview:latest","remote_host":"https://ollama.com:443"},
          {"name":"gemma4:31b-cloud"}
        ]}
        """
        let client = OllamaClient(baseURL: URL(string: "http://127.0.0.1:11434")!,
                                  transport: RequestCounter().transport(status: 200, body: body))
        let inventory = try await client.inventory()
        XCTAssertEqual(inventory.localModels, ["llama3.2:latest", "qwen3:8b"])
        XCTAssertEqual(inventory.hiddenCloudModels, 3)
    }

    func testOllamaCloudModelIsNeverCalled() async {
        var configuration = InsightConfiguration()
        configuration.provider = .ollama
        configuration.ollamaModel = "glm-5:cloud"
        let counter = RequestCounter()
        let result = await LocalFileInsightService(configuration: configuration,
                                                   transport: counter.transport(status: 200, body: "{}"))
            .insight(for: node, assessment: assessment)
        XCTAssertEqual(result.source, .localRules)
        XCTAssertEqual(result.providerNote, InsightProviderError.remoteOllamaModel.errorDescription)
        XCTAssertEqual(counter.count, 0)
    }

    func testRulesOnlyNeverUsesAModel() async {
        var configuration = InsightConfiguration()
        configuration.provider = .rulesOnly
        let counter = RequestCounter()
        let result = await LocalFileInsightService(configuration: configuration,
                                                   transport: counter.transport(status: 200, body: "{}"))
            .insight(for: node, assessment: assessment)
        XCTAssertEqual(result.source, .localRules)
        XCTAssertNil(result.providerNote)
        XCTAssertEqual(counter.count, 0)
    }

    @MainActor
    func testSettingsStoreKeyOutsidePreferences() throws {
        let suite = "lucid-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let secrets = InMemorySecretStore()
        let settings = InsightSettings(defaults: defaults, secrets: secrets)

        try settings.saveClaudeKey("  sk-ant-secret-1234 ")
        settings.provider = .claude

        XCTAssertEqual(secrets.read(), "sk-ant-secret-1234")
        XCTAssertEqual(settings.claudeKeyHint, "1234")
        let stored = defaults.dictionaryRepresentation().values.compactMap { $0 as? String }
        XCTAssertFalse(stored.contains { $0.contains("secret") })
        XCTAssertEqual(settings.configuration().claudeAPIKey, "sk-ant-secret-1234")

        settings.provider = .ollama
        XCTAssertNil(settings.configuration().claudeAPIKey, "The key is only read for Claude requests")

        try settings.removeClaudeKey()
        XCTAssertNil(secrets.read())
        XCTAssertFalse(settings.hasClaudeKey)
    }

    @MainActor
    func testSettingsRejectInvalidOllamaURL() throws {
        let suite = "lucid-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = InsightSettings(defaults: defaults, secrets: InMemorySecretStore())

        settings.ollamaURLString = "file:///etc/passwd"
        XCTAssertNil(settings.ollamaBaseURL)
        settings.ollamaURLString = "http://192.168.1.20:11434"
        XCTAssertEqual(settings.ollamaBaseURL?.host, "192.168.1.20")
    }

    private func claudeService(respondingWith body: String) -> LocalFileInsightService {
        var configuration = InsightConfiguration()
        configuration.provider = .claude
        configuration.claudeAPIKey = "sk-test"
        configuration.cloudConsent = true
        return LocalFileInsightService(configuration: configuration,
                                       transport: RequestCounter().transport(status: 200, body: body))
    }
}

private final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    var count: Int { lock.withLock { requests.count } }
    var lastURL: URL? { lock.withLock { requests.last?.url } }

    func transport(status: Int, body: String) -> HTTPTransport {
        { [self] request in
            lock.withLock { requests.append(request) }
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }
    }
}
