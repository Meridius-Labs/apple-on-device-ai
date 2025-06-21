import Foundation
import FoundationModels

@available(macOS 26.0, *)
struct WebSearchTool: Tool {
  let name = "web_search"
  let description = "Search the web for information on any topic"

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

    let searchResult = GeneratedContent(properties: [
      "query": arguments.query,
      "result": result,
    ])

    return ToolOutput(searchResult)
  }
}

@available(macOS 26.0, *)
struct SummarizeTool: Tool {
  let name = "summarize_text"
  let description = "Summarize given text to make it shorter"

  @Generable
  struct Arguments {
    @Guide(description: "The text to summarize")
    var text: String
  }

  func call(arguments: Arguments) async throws -> ToolOutput {
    print("🔧 SWIFT TOOL CALLED: summarize_text(text length: \(arguments.text.count))")

    let words = arguments.text.split(separator: " ")
    let summary = words.prefix(20).joined(separator: " ")

    let summaryResult = GeneratedContent(properties: [
      "original_length": arguments.text.count,
      "summary": "\(summary)...",
    ])

    return ToolOutput(summaryResult)
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
    tools: [WebSearchTool(), SummarizeTool()],
    instructions:
      "You are a helpful assistant with access to web search and text processing tools. Use tools when requested by the user."
  )

  // Test conversations
  let conversations = [
    "Search for information about quantum computing",
    "Can you summarize that information?",
    "Search for AI developments",
    "Compare quantum computing with AI",
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
  // log the transcript
  print(session.transcript)

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
