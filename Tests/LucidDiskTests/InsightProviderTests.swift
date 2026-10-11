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

    func testOpenAIRequestUsesResponsesWithoutStorageOrTools() throws {
        let request = try OpenAIClient(apiKey: "sk-test", model: OpenAIClient.defaultModel)
            .responsesRequest(system: "rules", prompt: "metadata")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])

        XCTAssertEqual(request.url, OpenAIClient.responsesURL)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(body["model"] as? String, OpenAIClient.defaultModel)
        XCTAssertEqual(body["instructions"] as? String, "rules")
        XCTAssertEqual(body["input"] as? String, "metadata")
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertNil(body["tools"])
        XCTAssertNil(body["conversation"])
        XCTAssertNil(body["previous_response_id"])
        XCTAssertEqual((body["reasoning"] as? [String: String])?["effort"], "low")
    }

    func testOpenAICustomModelDoesNotReceiveReasoningOptions() throws {
        let request = try OpenAIClient(apiKey: "sk-test", model: "gpt-4.1-mini")
            .responsesRequest(system: "rules", prompt: "metadata")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertNil(body["reasoning"])
    }

    func testOpenAIParsesAssistantTextAfterReasoningItems() throws {
        let payload = """
        {"status":"completed","output":[
          {"type":"reasoning","summary":[]},
          {"type":"message","role":"assistant","content":[
            {"type":"output_text","text":" A downloaded archive."},
            {"type":"output_text","text":"It may contain installers. "}]}]}
        """
        XCTAssertEqual(try OpenAIClient.parseResponse(Data(payload.utf8)), "A downloaded archive.\nIt may contain installers.")
    }

    func testOpenAIRefusalEmptyAndIncompleteResponsesFallBack() async {
        for payload in [
            #"{"status":"completed","output":[{"type":"message","role":"assistant","content":[{"type":"refusal","refusal":"No"}]}]}"#,
            #"{"status":"completed","output":[]}"#,
            #"{"status":"incomplete","output":[{"type":"message","role":"assistant","content":[{"type":"output_text","text":"A partial"}]}]}"#,
            #"{"error":{"message":"failure"}}"#
        ] {
            let result = await openAIService(respondingWith: payload).insight(for: node, assessment: assessment)
            XCTAssertEqual(result.source, .localRules, payload)
            XCTAssertNotNil(result.providerNote, payload)
        }
    }

    func testOpenAIAnswerCannotChangeSafety() async {
        let protectedNode = FileNode(name: "Library", path: "/System/Library", isDirectory: true)
        let protectedAssessment = DeletionSafety.assess(path: protectedNode.path, homePath: "/Users/example")
        let payload = #"{"status":"completed","output":[{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Delete everything."}]}]}"#
        let result = await openAIService(respondingWith: payload).insight(for: protectedNode, assessment: protectedAssessment)

        XCTAssertEqual(result.source, .openAI)
        XCTAssertEqual(result.modelName, OpenAIClient.defaultModel)
        XCTAssertEqual(result.confidence, .modelEstimate)
        XCTAssertEqual(result.whyItMatters, protectedAssessment.summary)
        XCTAssertEqual(result.verificationSteps.first, protectedAssessment.recommendation)
        XCTAssertEqual(protectedAssessment.actionPolicy, .blocked)
    }

    func testOpenAIRequiresIndependentConsentKeyAndModelBeforeNetwork() async {
        for missing in ["consent", "key", "model"] {
            var configuration = InsightConfiguration()
            configuration.provider = .openAI
            configuration.cloudConsent = true // Anthropic consent must not authorize OpenAI.
            configuration.claudeAPIKey = "sk-claude"
            configuration.openAIConsent = missing != "consent"
            configuration.openAIAPIKey = missing == "key" ? nil : "sk-openai"
            configuration.openAIModel = missing == "model" ? "   " : OpenAIClient.defaultModel
            let counter = RequestCounter()
            let result = await LocalFileInsightService(configuration: configuration,
                                                       transport: counter.transport(status: 200, body: "{}"))
                .insight(for: node, assessment: assessment)

            XCTAssertEqual(result.source, .localRules, missing)
            XCTAssertEqual(counter.count, 0, missing)
            XCTAssertNotNil(result.providerNote, missing)
        }
    }

    func testOpenAIFailureDoesNotCallAnotherProvider() async {
        let counter = RequestCounter()
        var configuration = InsightConfiguration()
        configuration.provider = .openAI
        configuration.openAIConsent = true
        configuration.openAIAPIKey = "sk-openai"
        configuration.cloudConsent = true
        configuration.claudeAPIKey = "sk-claude"
        let result = await LocalFileInsightService(configuration: configuration,
                                                   transport: counter.transport(status: 401, body: "{}"))
            .insight(for: node, assessment: assessment)
        XCTAssertEqual(result.source, .localRules)
        XCTAssertEqual(counter.count, 1)
        XCTAssertEqual(counter.lastURL, OpenAIClient.responsesURL)
        XCTAssertEqual(result.providerNote, InsightProviderError.http(status: 401, message: nil).errorDescription)
    }

    func testOpenAIKeyTestDoesNotGenerateAnAnswer() async throws {
        let counter = RequestCounter()
        let client = OpenAIClient(apiKey: "sk-test", model: OpenAIClient.defaultModel,
                                  transport: counter.transport(status: 200, body: #"{"data":[]}"#))
        try await client.verify()
        XCTAssertEqual(counter.count, 1)
        XCTAssertEqual(counter.lastURL, OpenAIClient.modelsURL)
        XCTAssertNil(counter.lastRequest?.httpBody)
    }

    func testOpenAIRequestDoesNotReadOrSendFileContents() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("notes.txt")
        let secretContent = "file-content-must-never-leave-this-mac"
        try Data(secretContent.utf8).write(to: url)
        let file = FileNode(name: url.lastPathComponent, path: url.path, isDirectory: false, size: 37)
        let counter = RequestCounter()
        var configuration = InsightConfiguration()
        configuration.provider = .openAI
        configuration.openAIAPIKey = "sk-test"
        configuration.openAIConsent = true
        _ = await LocalFileInsightService(configuration: configuration,
                                           transport: counter.transport(status: 200, body: #"{"status":"completed","output":[]}"#))
            .insight(for: file, assessment: DeletionSafety.assess(path: file.path, homePath: directory.path))
        let data = try XCTUnwrap(counter.lastRequest?.httpBody)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let input = try XCTUnwrap(body["input"] as? String)
        XCTAssertTrue(input.contains("notes.txt"))
        XCTAssertTrue(input.contains("allocatedBytes"))
        XCTAssertFalse(input.contains(secretContent))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(secretContent))
    }

    @MainActor
    func testOpenAISettingsKeepKeysAndConsentSeparate() throws {
        let suite = "lucid-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let claudeSecrets = InMemorySecretStore()
        let openAISecrets = InMemorySecretStore()
        let settings = InsightSettings(defaults: defaults, secrets: claudeSecrets, openAISecrets: openAISecrets)
        try settings.saveClaudeKey("sk-claude-secret-abcd")
        try settings.saveOpenAIKey(" sk-openai-secret-1234 ")
        settings.cloudConsent = true
        settings.provider = .openAI

        XCTAssertFalse(settings.openAIConsent)
        XCTAssertEqual(openAISecrets.read(), "sk-openai-secret-1234")
        XCTAssertEqual(settings.openAIKeyHint, "1234")
        XCTAssertEqual(settings.configuration().openAIAPIKey, "sk-openai-secret-1234")
        XCTAssertNil(settings.configuration().claudeAPIKey)
        let stored = defaults.dictionaryRepresentation().values.compactMap { $0 as? String }
        XCTAssertFalse(stored.contains { $0.contains("secret") })
        settings.openAIConsent = true
        settings.openAIModel = "custom-model"
        let reloaded = InsightSettings(defaults: defaults, secrets: claudeSecrets, openAISecrets: openAISecrets)
        XCTAssertEqual(reloaded.provider, .openAI)
        XCTAssertTrue(reloaded.openAIConsent)
        XCTAssertEqual(reloaded.openAIModel, "custom-model")
        settings.provider = .claude
        XCTAssertNil(settings.configuration().openAIAPIKey)
        XCTAssertEqual(settings.configuration().claudeAPIKey, "sk-claude-secret-abcd")
        try settings.removeOpenAIKey()
        XCTAssertNil(openAISecrets.read())
        XCTAssertFalse(settings.hasOpenAIKey)
        XCTAssertEqual(claudeSecrets.read(), "sk-claude-secret-abcd")
    }

    private func openAIService(respondingWith body: String) -> LocalFileInsightService {
        var configuration = InsightConfiguration()
        configuration.provider = .openAI
        configuration.openAIAPIKey = "sk-test"
        configuration.openAIConsent = true
        return LocalFileInsightService(configuration: configuration,
                                       transport: RequestCounter().transport(status: 200, body: body))
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
    var lastRequest: URLRequest? { lock.withLock { requests.last } }

    func transport(status: Int, body: String) -> HTTPTransport {
        { [self] request in
            lock.withLock { requests.append(request) }
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }
    }
}
