import Foundation
import FoundationModels

struct Guardrails {
  static var developerProvided: LanguageModelSession.Guardrails {
    var guardrails = LanguageModelSession.Guardrails.default

    withUnsafeMutablePointer(to: &guardrails) { ptr in
      let rawPtr = UnsafeMutableRawPointer(ptr)
      let boolPtr = rawPtr.assumingMemoryBound(to: Bool.self)
      boolPtr.pointee = false
    }

    return guardrails
  }
}

// Now you can define the final ToolCall mirror.
public struct ToolCallMirror {
  // Inferred to be at offset 0x0
  public var id: String

  // Inferred to be at offset 0x10
  public var toolName: String

  // Inferred to start at offset 0x20
  public var arguments: GeneratedContent  // This struct is 40 bytes
}

// To perform the final transmutation:
func createUnsafeToolCall(id: String, toolName: String, arguments: GeneratedContent)
  -> FoundationModels.Transcript.ToolCall
{
  let mirror = ToolCallMirror(id: id, toolName: toolName, arguments: arguments)

  // This assumes the total size and alignment of ToolCallMirror matches the real one.
  // Size of ToolCall = 16 (id) + 16 (name) + 40 (arguments) = 72 bytes.
  return unsafeBitCast(mirror, to: FoundationModels.Transcript.ToolCall.self)
}

@available(macOS 26.0, *)
struct WebSearchTool: Tool {
  let name = "web_search"
  let description = "Use this tool when you need to search the web for information on any topic"

  @Generable
  struct Arguments {
    @Guide(description: "The search query")
    var query: String
  }

  func call(arguments: Arguments) async throws -> ToolOutput {
    print("🔧 SWIFT TOOL CALLED: web_search(query: \"\(arguments.query)\")")

    let mockResults: [String: String] = [
      "quantum computing":
        "Quantum computing uses quantum mechanics for computation.",
      "AI developments":
        "Recent AI advances: Large Language Models (GPT-4)",
    ]

    let query = arguments.query.lowercased()
    var result = "No specific information found."

    for (key, value) in mockResults {
      if query.contains(key) {
        result = value
        break
      }
    }

    return ToolOutput(result)
  }
}

@available(macOS 26.0, *)
struct SummarizeTool: Tool {
  let name = "summarize_text"
  let description = "Use this tool to summarize given text to make it shorter"

  @Generable
  struct Arguments {
    @Guide(description: "The text to summarize")
    var text: String
  }

  func call(arguments: Arguments) async throws -> ToolOutput {
    print("🔧 SWIFT TOOL CALLED: summarize_text(text length: \(arguments.text.count))")

    let words = arguments.text.split(separator: " ")
    let summary = words.prefix(20).joined(separator: " ")

    return ToolOutput(summary)
  }
}

// MARK: - Debug Logging

private func debugPrintTranscript(_ transcript: Transcript) {
  print("\n=== DEBUG: TRANSCRIPT SENT TO APPLE INTELLIGENCE ===")
  print("Transcript Entries (\(transcript.entries.count)):")

  for (index, entry) in transcript.entries.enumerated() {
    print("  [\(index)] \(describeTranscriptEntry(entry))")
  }
  print("=== END DEBUG TRANSCRIPT ===\n")
}

private func describeTranscriptEntry(_ entry: Transcript.Entry) -> String {
  switch entry {
  case .instructions(let instructions):
    let toolNames = instructions.toolDefinitions.map { $0.name }.joined(separator: ", ")
    let content = instructions.segments.compactMap { segment in
      if case .text(let textSegment) = segment {
        return textSegment.content
      }
      return nil
    }.joined(separator: " ")
    return "INSTRUCTIONS: '\(content)' | Tools: [\(toolNames)]"

  case .prompt(let prompt):
    let content = prompt.segments.compactMap { segment in
      if case .text(let textSegment) = segment {
        return textSegment.content
      }
      return nil
    }.joined(separator: " ")
    return "PROMPT: '\(content)'"

  case .response(let response):
    let content = response.segments.compactMap { segment in
      if case .text(let textSegment) = segment {
        return textSegment.content
      }
      return nil
    }.joined(separator: " ")
    return "RESPONSE: '\(content)'"

  case .toolOutput(let toolOutput):
    let content = toolOutput.segments.compactMap { segment in
      if case .text(let textSegment) = segment {
        return textSegment.content
      }
      return nil
    }.joined(separator: " ")
    return "TOOL_OUTPUT [\(toolOutput.toolName)]: '\(content)'"

  case .toolCalls(let toolCalls):
    let content = toolCalls.map { call in
      return "\(call.toolName) (\(call.arguments))"
    }
    return "TOOL_CALLS: [\(content.joined(separator: ", "))]"

  @unknown default:
    return "UNKNOWN_ENTRY"
  }
}

@available(macOS 26.0, *)
func runDirectTest() async {
  print("🚀 Testing Apple Intelligence Directly with Swift (Correct API)")
  print("============================================================\n")

  // Check availability
  let model = SystemLanguageModel.default
  guard case .available = model.availability else {
    print("❌ Apple Intelligence not available")
    return
  }

  // Create session with tools and instructions (Apple's way)
  let session = LanguageModelSession(
    guardrails: Guardrails.developerProvided,
    tools: [WebSearchTool(), SummarizeTool()],
    instructions:
      "You are a helpful assistant with access to web search and text processing tools. Use the appropriate tools when asked."
  )

  // Test conversations
  let conversations = [
    "Search the web for information about quantum computing",
    "Can you summarize that information?",
    "Search the web for AI developments",
  ]

  for userMessage in conversations {
    print("👤 User: \(userMessage)")
    print("🤖 Apple Intelligence: ", terminator: "")

    do {
      // Get response using Apple's simple API
      let response = try await session.respond(to: userMessage)
      let responseText = response.content
      print(responseText)

    } catch {
      print("❌ Error: \(error)")
    }

    print("\n" + String(repeating: "─", count: 50) + "\n")
  }

  print("🔍 Transcript:")
  // log the transcript
  debugPrintTranscript(session.transcript)

  print("✅ Direct Swift test completed")
}

// Main execution
if #available(macOS 26.0, *) {
  Task {
    await runDirectTest()
    exit(0)
  }
  RunLoop.main.run()
} else {
  print("❌ macOS 26.0+ required for Apple Intelligence")
  exit(1)
}
