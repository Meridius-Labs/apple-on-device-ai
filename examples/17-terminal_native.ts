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
