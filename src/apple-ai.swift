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

        // Signal completion to streaming coordinator for early termination
        await StreamingCoordinator.shared.toolCompleted()

        // Return placeholder output to allow generation to continue naturally
        return ToolOutput("Tool call executed")
    }
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

// MARK: - Streaming Coordinator for Early Termination

@available(macOS 26.0, *)
private actor StreamingCoordinator {
    static let shared = StreamingCoordinator()

    private var expectedToolCount: Int = 0
    private var completedToolCount: Int = 0
    private var shouldStopAfterTools: Bool = false
    private var allToolsCompleted: Bool = false

    func reset(expectedTools: Int, stopAfterToolCalls: Bool) {
        expectedToolCount = expectedTools
        completedToolCount = 0
        shouldStopAfterTools = stopAfterToolCalls
        allToolsCompleted = false
    }

    func toolCompleted() {
        completedToolCount += 1
        if completedToolCount >= expectedToolCount {
            allToolsCompleted = true
        }
    }

    func shouldTerminateStream() -> Bool {
        return shouldStopAfterTools && allToolsCompleted
    }

    func hasToolsToExecute() -> Bool {
        return expectedToolCount > 0
    }
}

// C callback that receives tool results (for compatibility with JS side)
@_cdecl("apple_ai_tool_result_callback")
public func appleAIToolResultCallback(_ toolID: UInt64, _ resultJson: UnsafePointer<CChar>) {
    // In natural completion mode, we don't need to resume anything
    // This callback exists for JS compatibility but doesn't affect Swift execution
    _ = String(cString: resultJson)
}

// MARK: - Unified Generation Function

@available(macOS 26.0, *)
@_cdecl("apple_ai_generate_unified")
public func appleAIGenerateUnified(
    messagesJson: UnsafePointer<CChar>,
    toolsJson: UnsafePointer<CChar>?,
    schemaJson: UnsafePointer<CChar>?,
    temperature: Double,
    maxTokens: Int32,
    stream: Bool,
    stopAfterToolCalls: Bool,  // New parameter - controls early termination behavior
    onChunk: (@convention(c) (UnsafePointer<CChar>?) -> Void)?
) -> UnsafeMutablePointer<CChar>? {
    let messagesJsonString = String(cString: messagesJson)
    let toolsJsonString = toolsJson.map { String(cString: $0) }
    let schemaJsonString = schemaJson.map { String(cString: $0) }

    // Validate streaming parameters
    if stream && onChunk == nil {
        return strdup("Error: Streaming requested but no callback provided")
    }

    // For non-streaming mode, use a semaphore
    if !stream {
        let semaphore = DispatchSemaphore(value: 0)
        var result: String = "Error: No response"

        Task {
            do {
                // Parse messages and prepare context
                let context = try prepareConversationContext(
                    messagesJsonString: messagesJsonString,
                    temperature: temperature,
                    maxTokens: maxTokens
                )

                // Determine operation mode based on provided parameters
                if let toolsStr = toolsJsonString, !toolsStr.isEmpty {
                    // Tools mode - takes precedence over schema
                    result = try await handleToolsMode(
                        context: context,
                        toolsJsonString: toolsStr,
                        streaming: false,
                        stopAfterToolCalls: stopAfterToolCalls,
                        onChunk: nil
                    )
                } else if let schemaStr = schemaJsonString, !schemaStr.isEmpty {
                    // Structured generation mode
                    result = try await handleStructuredMode(
                        context: context,
                        schemaJsonString: schemaStr
                    )
                } else {
                    // Basic generation mode
                    result = try await handleBasicMode(context: context)
                }
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
    } else {
        // Streaming mode
        Task.detached {
            do {
                // Parse messages and prepare context
                let context = try prepareConversationContext(
                    messagesJsonString: messagesJsonString,
                    temperature: temperature,
                    maxTokens: maxTokens
                )

                // Determine operation mode and stream
                if let toolsStr = toolsJsonString, !toolsStr.isEmpty {
                    // Tools mode with streaming
                    _ = try await handleToolsMode(
                        context: context,
                        toolsJsonString: toolsStr,
                        streaming: true,
                        stopAfterToolCalls: stopAfterToolCalls,
                        onChunk: onChunk
                    )
                } else if let schemaStr = schemaJsonString, !schemaStr.isEmpty {
                    // Structured generation doesn't support streaming
                    emitError("Structured generation does not support streaming", to: onChunk!)
                } else {
                    // Basic generation with streaming
                    try await handleBasicModeStream(
                        context: context,
                        onChunk: onChunk!
                    )
                }
            } catch let error as ConversationError {
                switch error {
                case .intelligenceUnavailable(let reason):
                    emitError("Apple Intelligence not available - \(reason)", to: onChunk!)
                case .invalidJSON(let reason):
                    emitError(reason, to: onChunk!)
                case .noMessages:
                    emitError("No messages", to: onChunk!)
                }
            } catch {
                emitError(error.localizedDescription, to: onChunk!)
            }
        }
        return nil  // Streaming returns immediately
    }
}

// MARK: - Helper functions for unified generation

@available(macOS 26.0, *)
private func handleBasicMode(context: ConversationContext) async throws -> String {
    let transcript = Transcript(entries: context.transcriptEntries)
    let session = LanguageModelSession(transcript: transcript)
    let response = try await session.respond(to: context.currentPrompt, options: context.options)

    // Return as JSON for consistency
    let json: [String: Any] = ["text": response.content]
    let jsonData = try JSONSerialization.data(withJSONObject: json, options: [])
    return String(data: jsonData, encoding: .utf8) ?? "Error: Encoding failure"
}

@available(macOS 26.0, *)
private func handleBasicModeStream(
    context: ConversationContext,
    onChunk: @convention(c) (UnsafePointer<CChar>?) -> Void
) async throws {
    let transcript = Transcript(entries: context.transcriptEntries)
    let session = LanguageModelSession(transcript: transcript)

    var prev = ""
    for try await cumulative in session.streamResponse(
        to: context.currentPrompt, options: context.options)
    {
        let delta = String(cumulative.dropFirst(prev.count))
        prev = cumulative
        guard !delta.isEmpty else { continue }

        delta.withCString { cStr in
            onChunk(strdup(cStr))
        }
    }
    onChunk(nil)  // Signal end of stream
}

@available(macOS 26.0, *)
private func handleStructuredMode(
    context: ConversationContext,
    schemaJsonString: String
) async throws -> String {
    // Parse JSON Schema
    guard let data = schemaJsonString.data(using: .utf8),
        let jsonObj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        throw ConversationError.invalidJSON("Invalid JSON Schema")
    }

    // Build schema from JSON
    let (rootSchema, deps) = buildSchemasFromJson(jsonObj)
    let generationSchema = try GenerationSchema(root: rootSchema, dependencies: deps)

    // Create session without tools (structured generation doesn't use tools constructor)
    let transcript = Transcript(entries: context.transcriptEntries)
    let session = LanguageModelSession(transcript: transcript)

    // Generate structured response
    let response = try await session.respond(
        to: context.currentPrompt,
        schema: generationSchema,
        includeSchemaInPrompt: true,
        options: context.options
    )

    let generatedContent = response.content
    let objectJson = generatedContentToJSON(generatedContent)
    let textRepresentation = String(describing: generatedContent)

    let json: [String: Any] = [
        "text": textRepresentation,
        "object": objectJson,
    ]

    let jsonData = try JSONSerialization.data(withJSONObject: json, options: [])
    return String(data: jsonData, encoding: .utf8) ?? "Error: Encoding failure"
}

@available(macOS 26.0, *)
private func handleToolsMode(
    context: ConversationContext,
    toolsJsonString: String,
    streaming: Bool,
    stopAfterToolCalls: Bool,  // New parameter
    onChunk: (@convention(c) (UnsafePointer<CChar>?) -> Void)?
) async throws -> String {
    // Parse tools
    guard let toolsData = toolsJsonString.data(using: .utf8),
        let rawToolsArr = try JSONSerialization.jsonObject(with: toolsData) as? [[String: Any]]
    else {
        throw ConversationError.invalidJSON("Invalid tools JSON")
    }

    // Build tools
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

    // Build transcript with tools
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

    if !streaming {
        // Non-streaming with tools
        let response = try await session.respond(
            to: context.currentPrompt, options: context.options
        )

        let text = response.content
        let toolCalls = ToolCallCollector.shared.getAllCalls()

        var json: [String: Any] = [:]

        if !toolCalls.isEmpty {
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

        let jsonData = try JSONSerialization.data(withJSONObject: json, options: [])
        return String(data: jsonData, encoding: .utf8) ?? "Error: Encoding failure"
    } else {
        // Streaming with tools
        guard let onChunk = onChunk else {
            throw ConversationError.invalidJSON("No callback provided for streaming")
        }

        // Initialize coordination with configurable early termination
        await StreamingCoordinator.shared.reset(
            expectedTools: tools.count,
            stopAfterToolCalls: stopAfterToolCalls  // Use the parameter
        )

        var prev = ""
        for try await cumulative in session.streamResponse(
            to: context.currentPrompt, options: context.options
        ) {
            // Check for early termination only if enabled
            if stopAfterToolCalls {
                let shouldTerminate = await StreamingCoordinator.shared.shouldTerminateStream()
                if shouldTerminate {
                    break
                }
            }

            let delta = String(cumulative.dropFirst(prev.count))
            prev = cumulative
            guard !delta.isEmpty else { continue }

            delta.withCString { cStr in
                onChunk(strdup(cStr))
            }
        }

        // Signal completion
        onChunk(nil)
        return ""  // Not used in streaming mode
    }
}
