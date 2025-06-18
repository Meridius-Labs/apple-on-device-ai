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
        return 1 // Available
    case .unavailable(let reason):
        switch reason {
        case .deviceNotEligible:
            return -1 // Device not eligible
        case .appleIntelligenceNotEnabled:
            return -2 // Apple Intelligence not enabled
        case .modelNotReady:
            return -3 // Model not ready
        @unknown default:
            return -99 // Unknown error
        }
    @unknown default:
        return -99 // Unknown error
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
            reasonString = "Device not eligible for Apple Intelligence. Supported devices: iPhone 15 Pro/Pro Max or newer, iPad with M1 chip or newer, Mac with Apple Silicon"
        case .appleIntelligenceNotEnabled:
            reasonString = "Apple Intelligence not enabled. Enable it in Settings > Apple Intelligence & Siri"
        case .modelNotReady:
            reasonString = "AI model not ready. Models are downloaded automatically based on network status, battery level, and system load. Please wait and try again later."
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
                options = GenerationOptions(temperature: temperature, maximumResponseTokens: maxTokens > 0 ? Int(maxTokens) : nil)
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
            let model = SystemLanguageModel.default
            
            // Check availability first
            let availability = model.availability
            guard case .available = availability else {
                result = "Error: Apple Intelligence not available"
                semaphore.signal()
                return
            }
            
            // Parse messages from JSON
            guard let messagesData = messagesJsonString.data(using: .utf8) else {
                result = "Error: Invalid JSON data"
                semaphore.signal()
                return
            }
            
            let messages = try JSONDecoder().decode([ChatMessage].self, from: messagesData)
            
            guard !messages.isEmpty else {
                result = "Error: No messages provided"
                semaphore.signal()
                return
            }
            
            // Get the last message as the current prompt
            let lastMessage = messages.last!
            let currentPrompt = lastMessage.content
            
            // Convert previous messages to transcript for conversation context
            let previousMessages = messages.count > 1 ? Array(messages.dropLast()) : []
            let transcriptEntries = convertMessagesToTranscript(previousMessages)
            
            // Create session with conversation history
            let transcript = Transcript(entries: transcriptEntries)
            let session = LanguageModelSession(transcript: transcript)
            
            // Create generation options
            var options = GenerationOptions()
            if temperature > 0 {
                options = GenerationOptions(temperature: temperature, maximumResponseTokens: maxTokens > 0 ? Int(maxTokens) : nil)
            } else if maxTokens > 0 {
                options = GenerationOptions(maximumResponseTokens: Int(maxTokens))
            }
            
            // Generate response using the current prompt with history
            let response = try await session.respond(to: currentPrompt, options: options)
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

@_cdecl("apple_ai_free_string")
public func appleAIFreeString(ptr: UnsafeMutablePointer<CChar>?) {
    if let ptr = ptr {
        free(ptr)
    }
}

// MARK: - Helper functions

private struct ChatMessage: Codable {
    let role: String
    let content: String
    let name: String?
    
    init(role: String, content: String, name: String? = nil) {
        self.role = role
        self.content = content
        self.name = name
    }
}

private func convertMessagesToTranscript(_ messages: [ChatMessage]) -> [Transcript.Entry] {
    var entries: [Transcript.Entry] = []
    
    // Process all messages in order
    for message in messages {
        let textSegment = Transcript.TextSegment(content: message.content)
        
        switch message.role.lowercased() {
        case "system":
            // Convert system messages to instructions
            let instructions = Transcript.Instructions(
                segments: [.text(textSegment)],
                toolDefinitions: []
            )
            entries.append(.instructions(instructions))
            
        case "user":
            // Convert user messages to prompts
            let prompt = Transcript.Prompt(
                segments: [.text(textSegment)]
            )
            entries.append(.prompt(prompt))
            
        case "assistant":
            // Convert assistant messages to responses
            let response = Transcript.Response(
                assetIDs: [],
                segments: [.text(textSegment)]
            )
            entries.append(.response(response))
            
        default:
            // Treat unknown roles as user messages
            let prompt = Transcript.Prompt(
                segments: [.text(textSegment)]
            )
            entries.append(.prompt(prompt))
        }
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
            onChunk(nil)        // stream finished
        } catch {
            emitError(error.localizedDescription, to: onChunk)
        }
    }
}

// Control-B (0x02) sentinel prefix marks an error string in streaming callbacks
private let ERROR_SENTINEL: Character = "\u{0002}"

@inline(__always)
private func emitError(_ message: String, to onChunk: (@convention(c) (UnsafePointer<CChar>?) -> Void)) {
    let full = String(ERROR_SENTINEL) + message
    full.withCString { cStr in
        onChunk(strdup(cStr))
    }
}

// MARK: - Tool Calling Support

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
            
            // Parse messages from JSON
            guard let messagesData = messagesJsonString.data(using: .utf8) else {
                result = "Error: Invalid messages JSON data"
                semaphore.signal()
                return
            }
            
            let messages = try JSONDecoder().decode([ChatMessage].self, from: messagesData)
            
            // Parse tools from JSON
            guard let toolsData = toolsJsonString.data(using: .utf8) else {
                result = "Error: Invalid tools JSON data"
                semaphore.signal()
                return
            }
            
            let toolDefinitions = try JSONDecoder().decode([ToolDefinition].self, from: toolsData)
            
            // Get the last message as the current prompt
            let lastMessage = messages.last!
            let currentPrompt = lastMessage.content
            
            // Convert previous messages to transcript for conversation context
            let previousMessages = messages.count > 1 ? Array(messages.dropLast()) : []
            let transcriptEntries = convertMessagesToTranscript(previousMessages)
            
            // Create instructions with tool definitions
            var instructionSegments: [Transcript.Segment] = []
            if !toolDefinitions.isEmpty {
                // Create tool definitions compatible with Apple's API
                var toolDescriptions = "You have access to the following tools:\n\n"
                for tool in toolDefinitions {
                    toolDescriptions += "Tool: \(tool.name)\n"
                    if let desc = tool.description {
                        toolDescriptions += "Description: \(desc)\n"
                    }
                    toolDescriptions += "\n"
                }
                
                let textSegment = Transcript.TextSegment(content: toolDescriptions)
                instructionSegments.append(.text(textSegment))
            }
            
            // Add tool definitions to transcript if tools are provided
            var finalTranscriptEntries = transcriptEntries
            if !toolDefinitions.isEmpty {
                // For now, we'll just add instructions about tools
                // In a real implementation, we'd need to properly integrate with Apple's Tool API
                let instructions = Transcript.Instructions(
                    segments: instructionSegments,
                    toolDefinitions: [] // Empty for now - requires proper Tool objects
                )
                finalTranscriptEntries.insert(.instructions(instructions), at: 0)
            }
            
            // Create session with conversation history
            let transcript = Transcript(entries: finalTranscriptEntries)
            let session = LanguageModelSession(transcript: transcript)
            
            // Create generation options
            var options = GenerationOptions()
            if temperature > 0 {
                options = GenerationOptions(temperature: temperature, maximumResponseTokens: maxTokens > 0 ? Int(maxTokens) : nil)
            } else if maxTokens > 0 {
                options = GenerationOptions(maximumResponseTokens: Int(maxTokens))
            }
            
            // Generate response - for now without native tool support
            let response = try await session.respond(to: currentPrompt, options: options)
            
            // Create response JSON
            var responseDict: [String: Any] = [:]
            responseDict["text"] = response.content
            responseDict["toolCalls"] = [] // Empty for now
            
            // Convert to JSON string
            let jsonData = try JSONSerialization.data(withJSONObject: responseDict, options: [])
            result = String(data: jsonData, encoding: .utf8) ?? "Error: Failed to encode response"
            
        } catch {
            result = "Error: \(error.localizedDescription)"
        }
        
        semaphore.signal()
    }
    
    // Wait for async operation to complete
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
                  let jsonObj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
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
                "object": objectJson
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
private func convertJSONSchemaToDynamic(_ dict: [String: Any], name: String? = nil) -> DynamicGenerationSchema {
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
            return .init(name: name ?? UUID().uuidString, description: dict["description"] as? String, anyOf: stringChoices)
        } else {
            let choices = dynamicChoices.isEmpty ? anyOf.map { convertJSONSchemaToDynamic($0) } : dynamicChoices
            return .init(name: name ?? UUID().uuidString, description: dict["description"] as? String, anyOf: choices)
        }
    }

    // Enum handling
    if let enums = dict["enum"] as? [String] {
        return .init(name: name ?? UUID().uuidString, description: dict["description"] as? String, anyOf: enums)
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
                let prop = DynamicGenerationSchema.Property(name: propName, description: subSchemaDict["description"] as? String, schema: subSchema, isOptional: isOptional)
                props.append(prop)
            }
        }
        return .init(name: name ?? "Object", description: dict["description"] as? String, properties: props)
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
private func buildSchemasFromJson(_ json: [String: Any]) -> (DynamicGenerationSchema, [DynamicGenerationSchema]) {
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
        if let defs = json["definitions"] as? [String: Any], let rootDef = defs[name] as? [String: Any] {
            let rootSchema = convertJSONSchemaToDynamic(rootDef, name: name)
            return (rootSchema, dependencies)
        }
    }

    // Fallback
    let root = convertJSONSchemaToDynamic(json, name: json["title"] as? String)
    return (root, dependencies)
} 