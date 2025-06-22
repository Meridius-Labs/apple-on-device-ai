import { appleAISDK, chat, type ChatMessage } from "../src";
import { zodToJsonSchema } from "zod-to-json-schema";
import type { JSONSchema7 } from "json-schema";

import { z } from "zod";

async function main() {
  console.log("MacOS 26 Local AI Chat - Text Processing & Search\n");

  // Start with system message
  let messages: ChatMessage[] = [
    {
      role: "system",
      content: `You are a helpful assistant with access to web search and text processing tools. Use the appropriate tools when asked.`,
    },
  ];

  const questions = [
    "Search the web for information about quantum computing",
    "Can you summarize that information?",
    "Make that summary shorter and more concise",
    "Search for recent AI developments",
    "Compare that with the quantum computing info",
    "Create a bullet point list from all this information",
  ];

  //   const tools = {
  //     web_search: tool({
  //       description:
  //         "Use this tool when you need to search the web for information on any topic",
  //       inputSchema: z.object({
  //         query: z.string().describe("The search query"),
  //         num_results: z
  //           .number()
  //           .optional()
  //           .describe("Number of results to return"),
  //       }),
  //       async execute(input) {
  //         console.log("[TS] TOOL CALLED", "Web Search", input);

  //         // Mock search results based on query
  //         const mockResults = {
  //           "quantum computing": `Quantum computing is a revolutionary technology that uses quantum mechanical phenomena like superposition and entanglement to process information. Key developments include IBM's quantum processors, Google's quantum supremacy achievement, and advances in quantum error correction. Major applications include cryptography, drug discovery, and financial modeling.`,

  //           "AI developments": `Recent AI developments include GPT-4 and other large language models, advances in computer vision, breakthrough in protein folding with AlphaFold, autonomous vehicles progress, and AI-assisted scientific research. Notable companies include OpenAI, Google DeepMind, Anthropic, and Microsoft.`,

  //           "recent AI": `Latest AI breakthroughs: multimodal AI systems that can process text, images, and audio; AI coding assistants like GitHub Copilot; advances in robotics with Boston Dynamics and Tesla; AI drug discovery accelerating pharmaceutical research; and ethical AI frameworks being developed globally.`,
  //         };

  //         // Find best match for the query
  //         const query = (input.query || "").toLowerCase();
  //         let result = "No specific information found for this query.";

  //         for (const [key, value] of Object.entries(mockResults)) {
  //           if (
  //             query.includes(key) ||
  //             key.includes((query || "").split(" ")[0] || "")
  //           ) {
  //             result = value;
  //             break;
  //           }
  //         }

  //         return `Search Results for "${
  //           input.query || "your search"
  //         }":\n\n${result}`;
  //       },
  //     }),

  //     summarize_text: tool({
  //       description:
  //         "Summarize any given text to make it shorter while keeping key information",
  //       inputSchema: z.object({
  //         text: z.string().describe("The text to summarize"),
  //         length: z
  //           .enum(["short", "medium", "long"])
  //           .optional()
  //           .describe("Desired summary length"),
  //       }),
  //       async execute(input) {
  //         console.log("[TS] TOOL CALLED", "Summarize Text", {
  //           textLength: input.text.length,
  //           length: input.length,
  //         });

  //         const text = input.text;
  //         const words = text.split(" ");

  //         // Mock summarization by taking key sentences and reducing length
  //         if (words.length <= 20) {
  //           return `Summary: ${text}`;
  //         }

  //         const targetLength =
  //           input.length === "short" ? 30 : input.length === "medium" ? 50 : 80;
  //         const summary = words.slice(0, targetLength).join(" ");

  //         return `Summary (${input.length || "medium"} length): ${summary}...`;
  //       },
  //     }),

  //     make_concise: tool({
  //       description:
  //         "Make text more concise and remove unnecessary words while preserving meaning",
  //       inputSchema: z.object({
  //         text: z.string().describe("The text to make more concise"),
  //       }),
  //       async execute(input) {
  //         console.log("[TS] TOOL CALLED", "Make Concise", {
  //           textLength: input.text.length,
  //         });

  //         // Mock concise version by removing common filler words and shortening
  //         const text = input.text
  //           .replace(/\b(very|really|quite|rather|extremely|incredibly)\b/g, "")
  //           .replace(/\b(that|which)\b/g, "")
  //           .replace(/\s+/g, " ")
  //           .trim();

  //         const words = text.split(" ");
  //         const conciseText = words
  //           .slice(0, Math.floor(words.length * 0.7))
  //           .join(" ");

  //         return `Concise version: ${conciseText}`;
  //       },
  //     }),

  //     create_bullet_points: tool({
  //       description: "Convert text into a bullet point list format",
  //       inputSchema: z.object({
  //         text: z.string().describe("The text to convert to bullet points"),
  //         max_points: z
  //           .number()
  //           .optional()
  //           .describe("Maximum number of bullet points"),
  //       }),
  //       async execute(input) {
  //         console.log("[TS] TOOL CALLED", "Create Bullet Points", {
  //           textLength: input.text.length,
  //           maxPoints: input.max_points,
  //         });

  //         // Mock bullet point creation
  //         const sentences = input.text
  //           .split(/[.!?]+/)
  //           .filter((s) => s.trim().length > 10);
  //         const maxPoints = input.max_points || 5;
  //         const points = sentences.slice(0, maxPoints);

  //         const bulletList = points
  //           .map((point, i) => `• ${point.trim()}`)
  //           .join("\n");

  //         return `Bullet Points:\n${bulletList}`;
  //       },
  //     }),

  //     compare_topics: tool({
  //       description: "Compare two different topics or pieces of information",
  //       inputSchema: z.object({
  //         topic1: z.string().describe("First topic or information to compare"),
  //         topic2: z.string().describe("Second topic or information to compare"),
  //       }),
  //       async execute(input) {
  //         console.log("[TS] TOOL CALLED", "Compare Topics", input);

  //         return `Comparison between "${input.topic1}" and "${input.topic2}":

  // Similarities:
  // • Both are cutting-edge technology fields
  // • Both require significant research and development
  // • Both have transformative potential for society

  // Differences:
  // • ${input.topic1}: Focuses on specific technological approach and applications
  // • ${input.topic2}: Has different implementation methods and use cases
  // • Timeline and maturity levels may vary between the two fields`;
  //       },
  //     }),
  //   };

  for (const question of questions) {
    console.log(`> ${question}`);

    // Add user message to conversation
    messages.push({ role: "user", content: question });

    try {
      // Use streamText with the full conversation - this properly handles tool calls
      const result = chat({
        messages: messages,
        stream: true,
        stopAfterToolCalls: false,
        tools: [
          {
            name: "web_search",
            description:
              "Use this tool when you need to search the web for information on any topic",
            jsonSchema: zodToJsonSchema(
              z.object({
                query: z.string().describe("The search query"),
              })
            ) as JSONSchema7,
            handler: async (args: Record<string, unknown>) => {
              console.log("🔍 TOOL CALLED", "Web Search", args);
              return "Web Search Result";
            },
          },
          {
            name: "summarize_text",
            description:
              "Use this tool to summarize given text to make it shorter",
            jsonSchema: zodToJsonSchema(
              z.object({
                text: z.string().describe("The text to summarize"),
              })
            ) as JSONSchema7,
            handler: async (args: Record<string, unknown>) => {
              const parsedArgs = {
                text: args.text as string,
              };
              console.log("🔍 TOOL CALLED", "Summarize Text", parsedArgs);
              return `Summarized text: ${parsedArgs.text.slice(0, 100)}...`;
            },
          },
        ],
      });

      // Collect the complete response including tool calls
      let assistantResponse = "";

      console.log("");
      for await (const chunk of result) {
        assistantResponse += chunk;
        process.stdout.write(chunk);
      }
      messages.push({ role: "assistant", content: assistantResponse });
      console.log("");

      // Add assistant response to conversation
    } catch (error) {
      console.error("Error:", error);
      // On error, still add a placeholder response to keep conversation going
      messages.push({
        role: "assistant",
        content: "I encountered an error processing your request.",
      });
    }

    console.log("\n");
  }
}

if (require.main === module) {
  main().catch(console.error);
}
