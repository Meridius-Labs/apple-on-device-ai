import Foundation
import FoundationModels

// MARK: - C-compatible data structures

@available(macOS 26.0, *)

@_cdecl("apple_ai_init")
public func appleAIInit() -> Bool {
    // Initialize and return success status
    return true
}

@_cdecl("apple_ai_check_availability")
public func appleAICheckAvailability() -> Int32 {
    let model = SystemLanguageModel.default
    let availability = model.availability

    switch availability {
    case .available:
        return 1  // Available
    case .unavailable(let reason):
        switch reason {
        case .deviceNotEligible:
            return -1  // Device not eligible
        case .appleIntelligenceNotEnabled:
            return -2  // Apple Intelligence not enabled
        case .modelNotReady:
            return -3  // Model not ready
        @unknown default:
            return -99  // Unknown error
        }
    @unknown default:
        return -99  // Unknown error
    }
}

@_cdecl("apple_ai_get_availability_reason")
public func appleAIGetAvailabilityReason() -> UnsafeMutablePointer<CChar>? {
    let model = SystemLanguageModel.default
    let availability = model.availability

    switch availability {
    case .available:
        return strdup("Model is available")
    case .unavailable(let reason):
        let reasonString: String
        switch reason {
        case .deviceNotEligible:
            reasonString =
                "Device not eligible for Apple Intelligence. Supported devices: iPhone 15 Pro/Pro Max or newer, iPad with M1 chip or newer, Mac with Apple Silicon"
        case .appleIntelligenceNotEnabled:
            reasonString =
                "Apple Intelligence not enabled. Enable it in Settings > Apple Intelligence & Siri"
        case .modelNotReady:
            reasonString =
                "AI model not ready. Models are downloaded automatically based on network status, battery level, and system load. Please wait and try again later."
        @unknown default:
            reasonString = "Unknown availability issue"
        }
        return strdup(reasonString)
    @unknown default:
        return strdup("Unknown availability status")
    }
}

@_cdecl("apple_ai_get_supported_languages_count")
public func appleAIGetSupportedLanguagesCount() -> Int32 {
    let model = SystemLanguageModel.default
    return Int32(Array(model.supportedLanguages).count)
}

@_cdecl("apple_ai_get_supported_language")
public func appleAIGetSupportedLanguage(index: Int32) -> UnsafeMutablePointer<CChar>? {
    let model = SystemLanguageModel.default
    let languagesArray = Array(model.supportedLanguages)

    guard index >= 0 && index < Int32(languagesArray.count) else {
        return nil
    }

    let language = languagesArray[Int(index)]
    let locale = Locale(identifier: language.maximalIdentifier)

    // Get the display name in the current locale
    if let displayName = locale.localizedString(forIdentifier: language.maximalIdentifier) {
        return strdup(displayName)
    }

    // Fallback to language code if display name is not available
    if let languageCode = language.languageCode?.identifier {
        return strdup(languageCode)
    }

    return strdup("Unknown")
}

@_cdecl("apple_ai_generate_response")
public func appleAIGenerateResponse(
    prompt: UnsafePointer<CChar>,
    temperature: Double,
    maxTokens: Int32
) -> UnsafeMutablePointer<CChar>? {
    let promptString = String(cString: prompt)

    // Use semaphore to convert async to sync
    let semaphore = DispatchSemaphore(value: 0)
    var result: String = "Error: No response"

    Task {
        do {
            let model = SystemLanguageModel.default

            // Check availability first
            let availability = model.availability
            guard case .available = availability else {
                result = "Error: Apple Intelligence not available"
                semaphore.signal()
                return
            }

            // Create session
            let session = LanguageModelSession()

            // Create generation options
            var options = GenerationOptions()
            if temperature > 0 {
                options = GenerationOptions(
                    temperature: temperature,
                    maximumResponseTokens: maxTokens > 0 ? Int(maxTokens) : nil)
            } else if maxTokens > 0 {
                options = GenerationOptions(maximumResponseTokens: Int(maxTokens))
            }

            // Generate response
            let response = try await session.respond(to: promptString, options: options)
            result = response.content

        } catch {
            result = "Error: \(error.localizedDescription)"
        }

        semaphore.signal()
    }

    // Wait for async operation to complete
    semaphore.wait()

    return strdup(result)
}

@_cdecl("apple_ai_generate_response_with_history")
public func appleAIGenerateResponseWithHistory(
    messagesJson: UnsafePointer<CChar>,
    temperature: Double,
    maxTokens: Int32
) -> UnsafeMutablePointer<CChar>? {
    let messagesJsonString = String(cString: messagesJson)

    // Use semaphore to convert async to sync
    let semaphore = DispatchSemaphore(value: 0)
    var result: String = "Error: No response"

    Task {
        do {
            // Use shared conversation preparation logic
            let context = try prepareConversationContext(
                messagesJsonString: messagesJsonString,
                temperature: temperature,
                maxTokens: maxTokens
            )

            // Create session with conversation history
            let transcript = Transcript(entries: context.transcriptEntries)
            let session = LanguageModelSession(transcript: transcript)

            // Generate response using the current prompt with history
            let response = try await session.respond(
                to: context.currentPrompt, options: context.options)
            result = response.content

        } catch let error as ConversationError {
            switch error {
            case .intelligenceUnavailable(let reason):
                result = "Error: Apple Intelligence not available - \(reason)"
            case .invalidJSON(let reason):
                result = "Error: \(reason)"
            case .noMessages:
                result = "Error: No messages provided"
            }
        } catch {
            result = "Error: \(error.localizedDescription)"
        }

        semaphore.signal()
    }

    // Wait for async operation to complete
    semaphore.wait()

    return strdup(result)
}

@_cdecl("apple_ai_free_string")
public func appleAIFreeString(ptr: UnsafeMutablePointer<CChar>?) {
    if let ptr = ptr {
        free(ptr)
    }
}

// MARK: - Helper functions

/// Centralized conversation preparation logic used by all message-based functions
private struct ConversationContext {
    let currentPrompt: String
    let transcriptEntries: [Transcript.Entry]
    let options: GenerationOptions
}

private enum ConversationError: Error {
    case intelligenceUnavailable(String)
    case invalidJSON(String)
    case noMessages
}

private func prepareConversationContext(
    messagesJsonString: String,
    temperature: Double,
    maxTokens: Int32
) throws -> ConversationContext {
    // Check availability first
    let model = SystemLanguageModel.default
    let availability = model.availability
    guard case .available = availability else {
        let reason: String
        switch availability {
        case .available:
            reason = "Available"  // This case will never be reached due to guard
        case .unavailable(let unavailableReason):
            switch unavailableReason {
            case .deviceNotEligible:
                reason = "Device not eligible for Apple Intelligence"
            case .appleIntelligenceNotEnabled:
                reason = "Apple Intelligence not enabled"
            case .modelNotReady:
                reason = "AI model not ready"
            @unknown default:
                reason = "Unknown availability issue"
            }
        @unknown default:
            reason = "Unknown availability status"
        }
        throw ConversationError.intelligenceUnavailable(reason)
    }

    // Parse messages from JSON
    guard let messagesData = messagesJsonString.data(using: .utf8) else {
        throw ConversationError.invalidJSON("Invalid JSON data")
    }

    let messages = try JSONDecoder().decode([ChatMessage].self, from: messagesData)
    guard !messages.isEmpty else {
        throw ConversationError.noMessages
    }

    // Determine conversation context based on message types
    let lastMessage = messages.last!
    let currentPrompt: String
    let previousMessages: [ChatMessage]

    if lastMessage.role == "tool" {
        // If last message is a tool result, include ALL messages in context and use empty prompt
        currentPrompt = ""
        previousMessages = messages
    } else {
        // Otherwise use the last message content as prompt and previous as context
        currentPrompt = lastMessage.content ?? ""
        previousMessages = messages.count > 1 ? Array(messages.dropLast()) : []
    }

    let transcriptEntries = convertMessagesToTranscript(previousMessages)

    // Create generation options
    var options = GenerationOptions()
    if temperature > 0 {
        options.temperature = temperature
        if maxTokens > 0 {
            options.maximumResponseTokens = Int(maxTokens)
        }
    } else if maxTokens > 0 {
        options.maximumResponseTokens = Int(maxTokens)
    }

    return ConversationContext(
        currentPrompt: currentPrompt,
        transcriptEntries: transcriptEntries,
        options: options
    )
}

private struct ChatMessage: Codable {
    let role: String
    let content: String?  // Made optional to support OpenAI format with tool calls
    let name: String?
    let tool_call_id: String?  // OpenAI-compatible snake_case
    let tool_calls: [[String: Any]]?  // OpenAI-compatible tool calls array

    init(
        role: String,
        content: String? = nil,
        name: String? = nil,
        tool_call_id: String? = nil,
        tool_calls: [[String: Any]]? = nil
    ) {
        self.role = role
        self.content = content
        self.name = name
        self.tool_call_id = tool_call_id
        self.tool_calls = tool_calls
    }

    // Custom encoding/decoding to handle the dynamic tool_calls array
    enum CodingKeys: String, CodingKey {
        case role, content, name, tool_call_id, tool_calls
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(String.self, forKey: .role)
        content = try container.decodeIfPresent(String.self, forKey: .content)  // Made optional
        name = try container.decodeIfPresent(String.self, forKey: .name)
        tool_call_id = try container.decodeIfPresent(String.self, forKey: .tool_call_id)
        tool_calls = nil  // Will be handled separately in conversion
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(tool_call_id, forKey: .tool_call_id)
        // tool_calls encoding would need custom handling
    }
}

private func convertMessagesToTranscript(_ messages: [ChatMessage]) -> [Transcript.Entry] {
    var entries: [Transcript.Entry] = []

    for message in messages {
        switch message.role.lowercased() {
        case "system":
            entries.append(.instructions(createInstructions(from: message)))
        case "user":
            entries.append(.prompt(createPrompt(from: message)))
        case "assistant":
            entries.append(createAssistantEntry(from: message))
        case "tool":
            // Handle tool messages that may return multiple entries
            let toolEntries = createToolOutputEntry(from: message)
            entries.append(contentsOf: toolEntries)
        default:
            entries.append(.prompt(createPrompt(from: message)))  // Fallback to user prompt
        }
    }

    return entries
}

private func createInstructions(from message: ChatMessage) -> Transcript.Instructions {
    let textSegment = Transcript.TextSegment(content: message.content ?? "")
    return Transcript.Instructions(
        segments: [.text(textSegment)],
        toolDefinitions: []
    )
}

private func createPrompt(from message: ChatMessage) -> Transcript.Prompt {
    let textSegment = Transcript.TextSegment(content: message.content ?? "")
    return Transcript.Prompt(segments: [.text(textSegment)])
}

private func createAssistantEntry(from message: ChatMessage) -> Transcript.Entry {
    // Check if this is an assistant message with tool calls
    if let content = message.content,
        let toolCallsData = content.data(using: .utf8),
        let toolCalls = try? JSONSerialization.jsonObject(with: toolCallsData) as? [[String: Any]],
        !toolCalls.isEmpty,
        toolCalls.allSatisfy({ call in
            if let function = call["function"] as? [String: Any] {
                return function["name"] != nil
            }
            return false
        })
    {
        // Convert OpenAI tool calls to readable format
        let summary = convertOpenAIToolCallsToText(toolCalls)
        return .response(
            Transcript.Response(
                assetIDs: [], segments: [.text(Transcript.TextSegment(content: summary))]))
    }

    return .response(createResponse(from: message))
}

private func convertOpenAIToolCallsToText(_ toolCalls: [[String: Any]]) -> String {
    let calls = toolCalls.compactMap { call -> String? in
        guard let function = call["function"] as? [String: Any],
            let name = function["name"] as? String
        else { return nil }

        if let argsString = function["arguments"] as? String,
            let argsData = argsString.data(using: .utf8),
            let args = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any]
        {
            let argsList = args.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            return "\(name)(\(argsList))"
        }

        return "\(name)()"
    }

    return calls.joined(separator: ", ")
}

private func createResponse(from message: ChatMessage) -> Transcript.Response {
    let textSegment = Transcript.TextSegment(content: message.content ?? "")
    return Transcript.Response(
        assetIDs: [],
        segments: [.text(textSegment)]
    )
}

private func createToolOutputEntry(from message: ChatMessage) -> [Transcript.Entry] {
    // The message should have role "tool" and contain tool_calls array
    guard message.role == "tool" else {
        return []
    }

    // Parse the message content which should contain tool_calls array
    guard let content = message.content,
        let messageData = content.data(using: .utf8),
        let messageObject = try? JSONSerialization.jsonObject(with: messageData) as? [String: Any],
        let toolCalls = messageObject["tool_calls"] as? [[String: Any]]
    else {
        return []
    }

    var entries: [Transcript.Entry] = []

    // Each tool call becomes its own transcript entry
    for toolCall in toolCalls {
        guard let id = toolCall["id"] as? String,
            let toolName = toolCall["toolName"] as? String,
            let segments = toolCall["segments"] as? [[String: Any]]
        else {
            continue
        }

        var transcriptSegments: [Transcript.Segment] = []
        for segment in segments {
            if let type = segment["type"] as? String,
                type == "text",
                let text = segment["text"] as? String
            {
                transcriptSegments.append(.text(Transcript.TextSegment(content: text)))
            }
        }

        let toolOutput = Transcript.ToolOutput(
            id: id,
            toolName: toolName,
            segments: transcriptSegments
        )

        entries.append(.toolOutput(toolOutput))
    }

    return entries
}

@available(macOS 26.0, *)
@_cdecl("apple_ai_generate_response_stream")
public func appleAIGenerateResponseStream(
    _ prompt: UnsafePointer<CChar>,
    _ temperature: Double,
    _ maxTokens: Int32,
    _ onChunk: (@convention(c) (UnsafePointer<CChar>?) -> Void)
) {
    let promptString = String(cString: prompt)

    Task.detached {
        do {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else {
                emitError("Model unavailable", to: onChunk)
                return
            }

            var options = GenerationOptions()
            if temperature != 0.0 { options.temperature = temperature }
            if maxTokens > 0 { options.maximumResponseTokens = Int(maxTokens) }

            let session = LanguageModelSession(model: model)

            var prev = ""
            for try await cumulative in session.streamResponse(to: promptString, options: options) {
                let delta = String(cumulative.dropFirst(prev.count))
                prev = cumulative
                guard !delta.isEmpty, delta.first != ERROR_SENTINEL else { continue }

                delta.withCString { cStr in
                    onChunk(strdup(cStr))
                }
            }
            onChunk(nil)  // stream finished
        } catch {
            emitError(error.localizedDescription, to: onChunk)
        }
    }
}

// Control-B (0x02) sentinel prefix marks an error string in streaming callbacks
private let ERROR_SENTINEL: Character = "\u{0002}"

@inline(__always)
private func emitError(
    _ message: String, to onChunk: (@convention(c) (UnsafePointer<CChar>?) -> Void)
) {
    let full = String(ERROR_SENTINEL) + message
    full.withCString { cStr in
        onChunk(strdup(cStr))
    }
}

// MARK: - JS Tool Callback Bridge

// Simple async callback - Rust calls this, expects result via separate callback
public typealias JSToolCallback = @convention(c) (
    _ toolID: UInt64, _ argsJson: UnsafePointer<CChar>
) -> Void

private var jsToolCallback: JSToolCallback?

// Expose a C function so Rust can register the async callback
@_cdecl("apple_ai_register_tool_callback")
public func appleAIRegisterToolCallback(_ cb: JSToolCallback?) {
    jsToolCallback = cb
}

// MARK: - Proxy Tool implementation bridging to JS

@available(macOS 26.0, *)
private struct JSArguments: ConvertibleFromGeneratedContent {
    let raw: GeneratedContent
    init(_ content: GeneratedContent) throws {
        self.raw = content
    }
}

@available(macOS 26.0, *)
private struct JSProxyTool: Tool {
    typealias Arguments = JSArguments

    let toolID: UInt64
    let name: String
    let description: String
    let parametersSchema: GenerationSchema

    var parameters: GenerationSchema { parametersSchema }

    func call(arguments: JSArguments) async throws -> ToolOutput {
        guard let cb = jsToolCallback else {
            return ToolOutput("Tool system not available")
        }

        // Serialize arguments and forward to JavaScript for external execution
        let jsonObj = generatedContentToJSON(arguments.raw)
        guard let data = try? JSONSerialization.data(withJSONObject: jsonObj),
            let jsonStr = String(data: data, encoding: .utf8)
        else {
            return ToolOutput("Unable to process tool arguments")
        }

        // Notify JavaScript side for collection and external execution
        jsonStr.withCString { cb(toolID, $0) }

        // Collect this tool call for post-processing
        if let argsDict = jsonObj as? [String: Any] {
            ToolCallCollector.shared.append(id: toolID, name: name, arguments: argsDict)
        } else {
            ToolCallCollector.shared.append(id: toolID, name: name, arguments: [:])
        }

        // Return placeholder output to allow generation to continue naturally
        return ToolOutput("Tool call executed")
    }
}

// MARK: - Updated Tool Calling implementation

@available(macOS 26.0, *)
@_cdecl("apple_ai_generate_response_with_tools")
public func appleAIGenerateResponseWithTools(
    messagesJson: UnsafePointer<CChar>,
    toolsJson: UnsafePointer<CChar>,
    temperature: Double,
    maxTokens: Int32
) -> UnsafeMutablePointer<CChar>? {
    let messagesJsonString = String(cString: messagesJson)
    let toolsJsonString = String(cString: toolsJson)

    let semaphore = DispatchSemaphore(value: 0)
    var result: String = "Error: No response"

    Task {
        do {
            // Use shared conversation preparation logic
            let context = try prepareConversationContext(
                messagesJsonString: messagesJsonString,
                temperature: temperature,
                maxTokens: maxTokens
            )

            // Decode tool definitions (now expect id,name,description,parameters)
            guard let toolsData = toolsJsonString.data(using: .utf8),
                let rawToolsArr = try JSONSerialization.jsonObject(with: toolsData)
                    as? [[String: Any]]
            else {
                result = "Error: Invalid tools JSON"
                semaphore.signal()
                return
            }

            var tools: [any Tool] = []
            for dict in rawToolsArr {
                guard let idNum = dict["id"] as? UInt64,
                    let name = dict["name"] as? String
                else { continue }
                let description = dict["description"] as? String ?? ""
                let paramsSchemaJson = dict["parameters"] as? [String: Any] ?? [:]
                let (root, deps) = buildSchemasFromJson(paramsSchemaJson)
                let genSchema = try GenerationSchema(root: root, dependencies: deps)
                let proxy = JSProxyTool(
                    toolID: idNum, name: name, description: description, parametersSchema: genSchema
                )
                tools.append(proxy)
            }

            // Build final transcript with tools embedded as definitions
            var finalEntries = context.transcriptEntries
            if !tools.isEmpty {
                let instructions = Transcript.Instructions(
                    segments: [],
                    toolDefinitions: tools.map { tool in
                        Transcript.ToolDefinition(
                            name: tool.name, description: tool.description,
                            parameters: tool.parameters)
                    })
                finalEntries.insert(.instructions(instructions), at: 0)
            }

            let transcript = Transcript(entries: finalEntries)
            let session = LanguageModelSession(tools: tools, transcript: transcript)

            // Reset tool call collection
            ToolCallCollector.shared.reset()

            let response = try await session.respond(
                to: context.currentPrompt, options: context.options)

            let text = response.content
            let toolCalls = ToolCallCollector.shared.getAllCalls()

            // Format response with OpenAI-compatible structure
            var json: [String: Any] = [:]

            if !toolCalls.isEmpty {
                // Convert to OpenAI-style tool_calls format
                let formattedCalls = toolCalls.map { call in
                    [
                        "id": call.callId,
                        "type": "function",
                        "function": [
                            "name": call.name,
                            "arguments":
                                (try? String(
                                    data: JSONSerialization.data(withJSONObject: call.arguments),
                                    encoding: .utf8)) ?? "{}",
                        ],
                    ]
                }
                json["text"] = "(awaiting tool execution)"
                json["toolCalls"] = formattedCalls
            } else {
                json["text"] = text
            }

            // Convert to JSON string
            let jsonData = try JSONSerialization.data(withJSONObject: json, options: [])
            result = String(data: jsonData, encoding: .utf8) ?? "Error: Encoding failure"
        } catch let error as ConversationError {
            switch error {
            case .intelligenceUnavailable(let reason):
                result = "Error: Apple Intelligence not available - \(reason)"
            case .invalidJSON(let reason):
                result = "Error: \(reason)"
            case .noMessages:
                result = "Error: No messages provided"
            }
        } catch {
            result = "Error: \(error.localizedDescription)"
        }
        semaphore.signal()
    }

    semaphore.wait()
    return strdup(result)
}

// MARK: - Tool Definition Structure

private struct ToolDefinition: Codable {
    let name: String
    let description: String?
    let parameters: [String: Any]?

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case parameters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)

        // Decode parameters as generic JSON
        if container.contains(.parameters) {
            let parametersValue = try container.decode(AnyCodable.self, forKey: .parameters)
            parameters = parametersValue.value as? [String: Any]
        } else {
            parameters = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)

        if let params = parameters {
            try container.encode(AnyCodable(params), forKey: .parameters)
        }
    }
}

// Helper for decoding arbitrary JSON
private struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}

// MARK: - Structured Object Generation Support (Implementation)

#if canImport(FoundationModels)
    import FoundationModels
#endif

@available(macOS 26.0, *)
@_cdecl("apple_ai_generate_response_structured")
public func appleAIGenerateResponseStructured(
    prompt: UnsafePointer<CChar>,
    schemaJson: UnsafePointer<CChar>,
    temperature: Double,
    maxTokens: Int32
) -> UnsafeMutablePointer<CChar>? {
    let promptString = String(cString: prompt)
    let schemaJsonString = String(cString: schemaJson)

    // Use semaphore to convert async to sync
    let semaphore = DispatchSemaphore(value: 0)
    var result: String = "Error: No response"

    Task {
        do {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else {
                result = "Error: Apple Intelligence not available"
                semaphore.signal()
                return
            }

            // Parse JSON Schema into dictionary
            guard let data = schemaJsonString.data(using: .utf8),
                let jsonObj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                result = "Error: Invalid JSON Schema"
                semaphore.signal()
                return
            }

            // Build schema(s) from JSON Schema, including definitions
            let (rootSchema, deps) = buildSchemasFromJson(jsonObj)
            let generationSchema = try GenerationSchema(root: rootSchema, dependencies: deps)

            // Create generation options
            var options = GenerationOptions()
            if temperature > 0 {
                options.temperature = temperature
            }
            if maxTokens > 0 {
                options.maximumResponseTokens = Int(maxTokens)
            }

            // Start session
            let session = LanguageModelSession(model: model)
            let response = try await session.respond(
                to: promptString,
                schema: generationSchema,
                includeSchemaInPrompt: true,
                options: options
            )

            let generatedContent = response.content

            // Convert GeneratedContent to JSON-compatible structure
            let objectJson: Any = generatedContentToJSON(generatedContent)

            // Provide textual fallback as well
            let textRepresentation = String(describing: generatedContent)

            let json: [String: Any] = [
                "text": textRepresentation,
                "object": objectJson,
            ]

            // Convert to JSON string
            let jsonData = try JSONSerialization.data(withJSONObject: json, options: [])
            result = String(data: jsonData, encoding: .utf8) ?? "Error: Encoding failure"
        } catch {
            result = "Error: \(error.localizedDescription)"
        }
        semaphore.signal()
    }

    semaphore.wait()
    return strdup(result)
}

@available(macOS 26.0, *)
private func convertJSONSchemaToDynamic(_ dict: [String: Any], name: String? = nil)
    -> DynamicGenerationSchema
{
    // Handle references (not fully implemented)
    if let ref = dict["$ref"] as? String {
        return .init(referenceTo: ref)
    }

    if let anyOf = dict["anyOf"] as? [[String: Any]] {
        // Detect simple string enum union
        var stringChoices: [String] = []
        var dynamicChoices: [DynamicGenerationSchema] = []
        for choice in anyOf {
            if let enums = choice["enum"] as? [String], enums.count == 1 {
                stringChoices.append(enums[0])
            } else {
                dynamicChoices.append(convertJSONSchemaToDynamic(choice))
            }
        }
        if !stringChoices.isEmpty && dynamicChoices.isEmpty {
            return .init(
                name: name ?? UUID().uuidString, description: dict["description"] as? String,
                anyOf: stringChoices)
        } else {
            let choices =
                dynamicChoices.isEmpty
                ? anyOf.map { convertJSONSchemaToDynamic($0) } : dynamicChoices
            return .init(
                name: name ?? UUID().uuidString, description: dict["description"] as? String,
                anyOf: choices)
        }
    }

    // Enum handling
    if let enums = dict["enum"] as? [String] {
        return .init(
            name: name ?? UUID().uuidString, description: dict["description"] as? String,
            anyOf: enums)
    }

    guard let type = dict["type"] as? String else {
        // Fallback to string
        return .init(type: String.self)
    }

    switch type {
    case "string":
        return .init(type: String.self)
    case "number":
        return .init(type: Double.self)
    case "integer":
        return .init(type: Int.self)
    case "boolean":
        return .init(type: Bool.self)
    case "array":
        if let items = dict["items"] as? [String: Any] {
            let itemSchema = convertJSONSchemaToDynamic(items)
            let min = dict["minItems"] as? Int
            let max = dict["maxItems"] as? Int
            return .init(arrayOf: itemSchema, minimumElements: min, maximumElements: max)
        } else {
            // Unknown items, fallback
            return .init(arrayOf: .init(type: String.self))
        }
    case "object":
        let required = (dict["required"] as? [String]) ?? []
        var props: [DynamicGenerationSchema.Property] = []
        if let properties = dict["properties"] as? [String: Any] {
            for (propName, subSchemaAny) in properties {
                guard let subSchemaDict = subSchemaAny as? [String: Any] else { continue }
                let subSchema = convertJSONSchemaToDynamic(subSchemaDict, name: propName)
                let isOptional = !required.contains(propName)
                let prop = DynamicGenerationSchema.Property(
                    name: propName, description: subSchemaDict["description"] as? String,
                    schema: subSchema, isOptional: isOptional)
                props.append(prop)
            }
        }
        return .init(
            name: name ?? "Object", description: dict["description"] as? String, properties: props)
    default:
        return .init(type: String.self)
    }
}

@available(macOS 26.0, *)
private func generatedContentToJSON(_ content: GeneratedContent) -> Any {
    // Try object
    if let dict = try? content.properties() {
        var result: [String: Any] = [:]
        for (k, v) in dict {
            result[k] = generatedContentToJSON(v)
        }
        return result
    }

    // Try array
    if let arr = try? content.elements() {
        return arr.map { generatedContentToJSON($0) }
    }

    // Try basic scalar types
    if let str = try? content.value(String.self) { return str }
    if let intVal = try? content.value(Int.self) { return intVal }
    if let dbl = try? content.value(Double.self) { return dbl }
    if let boolVal = try? content.value(Bool.self) { return boolVal }

    // Fallback to description
    return String(describing: content)
}

@available(macOS 26.0, *)
private func buildSchemasFromJson(_ json: [String: Any]) -> (
    DynamicGenerationSchema, [DynamicGenerationSchema]
) {
    var dependencies: [DynamicGenerationSchema] = []
    var rootNameFromRef: String? = nil
    if let ref = json["$ref"] as? String, ref.hasPrefix("#/definitions/") {
        rootNameFromRef = String(ref.dropFirst("#/definitions/".count))
    }

    if let defs = json["definitions"] as? [String: Any] {
        for (name, subAny) in defs {
            if let subDict = subAny as? [String: Any] {
                if let rootNameFromRef, name == rootNameFromRef { continue }
                let depSchema = convertJSONSchemaToDynamic(subDict, name: name)
                dependencies.append(depSchema)
            }
        }
    }

    // Determine root schema
    if let rootNameFromRef = rootNameFromRef {
        let name = rootNameFromRef
        if let defs = json["definitions"] as? [String: Any],
            let rootDef = defs[name] as? [String: Any]
        {
            let rootSchema = convertJSONSchemaToDynamic(rootDef, name: name)
            return (rootSchema, dependencies)
        }
    }

    // Fallback
    let root = convertJSONSchemaToDynamic(json, name: json["title"] as? String)
    return (root, dependencies)
}

/// Generates a streaming response from Apple Intelligence with optional tool-calling support.
///
/// This C-compatible wrapper bridges the Swift async streaming API to a C callback.
/// It performs the following high-level steps:
/// 1. Converts the incoming C strings (messages and tools) into Swift `String`s.
/// 2. Deserializes the chat history and tool definitions from JSON.
/// 3. Creates `JSProxyTool` instances for each supplied tool and embeds them, along with the
///    prior conversation, into a `LanguageModelSession` transcript.
/// 4. Streams the assistant's response; every incremental delta is duplicated with `strdup` and
///    passed to the `onChunk` callback so that the Rust/JS side can consume it without threading
///    issues.
/// 5. Signals completion by invoking the callback with `nil`, or propagates errors by sending a
///    string prefixed by the ASCII Control-B (0x02) sentinel defined by `ERROR_SENTINEL`.
///
/// - Parameters:
///   - messagesJson: A JSON-encoded array of chat messages (`[{"role":"user","content":"..."}, …]`).
///   - toolsJson:    A JSON-encoded array describing tools (`[{"id":1,"name":"weather",…}]`).
///   - temperature:  Sampling temperature; `0` uses the model default.
///   - maxTokens:    Maximum number of tokens to generate (≤ 0 means the model default).
///   - onChunk:      Callback invoked with each UTF-8 text delta; receives `nil` when streaming ends.
///
@available(macOS 26.0, *)
@_cdecl("apple_ai_generate_response_with_tools_stream")
public func appleAIGenerateResponseWithToolsStream(
    messagesJson: UnsafePointer<CChar>,
    toolsJson: UnsafePointer<CChar>,
    temperature: Double,
    maxTokens: Int32,
    onChunk: (@convention(c) (UnsafePointer<CChar>?) -> Void)
) {
    let messagesJsonString = String(cString: messagesJson)  // Convert C strings to Swift Strings
    let toolsJsonString = String(cString: toolsJson)

    Task.detached {
        do {
            // Use shared conversation preparation logic
            let context = try prepareConversationContext(
                messagesJsonString: messagesJsonString,
                temperature: temperature,
                maxTokens: maxTokens
            )

            // 3. ----- Tool Definitions -----------------------------------------------------
            // Deserialize tool definitions that the assistant may invoke.
            guard let toolsData = toolsJsonString.data(using: .utf8),
                let rawArr = try JSONSerialization.jsonObject(with: toolsData) as? [[String: Any]]
            else {
                emitError("Invalid tools JSON", to: onChunk)
                return
            }
            var tools: [any Tool] = []
            for dict in rawArr {
                // Each element must contain at least an `id` and a `name`.
                guard let id = dict["id"] as? UInt64,
                    let name = dict["name"] as? String
                else { continue }
                let description = dict["description"] as? String ?? ""
                let paramsJson = dict["parameters"] as? [String: Any] ?? [:]
                // Convert JSON Schema → GenerationSchema so the model understands the arguments.
                let (root, deps) = buildSchemasFromJson(paramsJson)
                let gs = try GenerationSchema(root: root, dependencies: deps)
                // Wrap each tool with a JS proxy that delegates execution back to JavaScript.
                tools.append(
                    JSProxyTool(
                        toolID: id, name: name, description: description, parametersSchema: gs))
            }

            // 4. ----- Build Transcript & Session -------------------------------------------
            var entries = context.transcriptEntries
            if !tools.isEmpty {
                // Prepend an instruction containing the available tool signatures.
                let instr = Transcript.Instructions(
                    segments: [],
                    toolDefinitions: tools.map { t in
                        Transcript.ToolDefinition(
                            name: t.name, description: t.description, parameters: t.parameters)
                    })
                entries.insert(.instructions(instr), at: 0)
            }
            let transcript = Transcript(entries: entries)
            let session = LanguageModelSession(tools: tools, transcript: transcript)

            // 5. ----- Streaming Loop -------------------------------------------------------
            // Reset tool call collection for streaming
            ToolCallCollector.shared.reset()

            var prev = ""  // cumulative text we have seen so far
            for try await cumulative in session.streamResponse(
                to: context.currentPrompt, options: context.options)
            {
                // Compute the incremental delta (only send what is new)
                let delta = String(cumulative.dropFirst(prev.count))
                prev = cumulative
                guard !delta.isEmpty else { continue }

                delta.withCString { cStr in
                    onChunk(strdup(cStr))  // pass ownership of the strdup'ed buffer to caller
                }
            }

            // Signal completion
            onChunk(nil)
        } catch let error as ConversationError {
            switch error {
            case .intelligenceUnavailable(let reason):
                emitError("Apple Intelligence not available - \(reason)", to: onChunk)
            case .invalidJSON(let reason):
                emitError(reason, to: onChunk)
            case .noMessages:
                emitError("No messages", to: onChunk)
            }
        } catch {
            emitError(error.localizedDescription, to: onChunk)
        }
    }
}

// MARK: - Tool Call Collection for Natural Completion

@available(macOS 26.0, *)
private class ToolCallCollector {
    static let shared = ToolCallCollector()
    private let queue = DispatchQueue(label: "tool.call.collector")
    private var calls: [ToolCallRecord] = []

    struct ToolCallRecord {
        let id: UInt64
        let name: String
        let arguments: [String: Any]
        let callId: String
    }

    func reset() {
        queue.sync { calls.removeAll() }
    }

    func append(id: UInt64, name: String, arguments: [String: Any]) {
        let callId = "call_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))"
        let record = ToolCallRecord(id: id, name: name, arguments: arguments, callId: callId)
        queue.sync { calls.append(record) }
    }

    func getAllCalls() -> [ToolCallRecord] {
        queue.sync { calls }
    }
}

// C callback that receives tool results (for compatibility with JS side)
@_cdecl("apple_ai_tool_result_callback")
public func appleAIToolResultCallback(_ toolID: UInt64, _ resultJson: UnsafePointer<CChar>) {
    // In natural completion mode, we don't need to resume anything
    // This callback exists for JS compatibility but doesn't affect Swift execution
    _ = String(cString: resultJson)
}
