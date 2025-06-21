import { streamText, tool, type ToolCallPart, type TextPart } from "ai";
import { appleAI } from "../src/apple-ai-provider";
import type { ModelMessage, Tool } from "ai";
import z from "zod";
import chalk from "chalk";

// Use ModelMessage instead of ModelMessage for proper typing
const messages: ModelMessage[] = [
  {
    role: "system",
    content: "You are a helpful assistant.",
  },
];

const tools: Record<string, Tool> = {
  "get-weather": tool({
    description: "Use this tool to get the weather for a given location",
    inputSchema: z.object({
      location: z.string(),
    }),
    async execute(input, options) {
      console.log(
        chalk.cyan(
          `[TOOL CALLED — get-weather ${
            options.toolCallId
          }] args: ${JSON.stringify(input)}`
        )
      );

      return {
        content: "The weather in Tokyo is sunny.",
      };
    },
  }),
  "search-web": tool({
    description: "Use this tool to search the web for information",
    inputSchema: z.object({
      query: z.string(),
    }),
    async execute(input, options) {
      console.log(
        chalk.cyan(
          `[TOOL CALLED — search-web ${
            options.toolCallId
          }] args: ${JSON.stringify(input)}`
        )
      );

      return {
        content: "The moon landing was on July 20, 1969.",
      };
    },
  }),
};

let pendingMessages = [
  "What is the weather in Tokyo?",
  "Look up information about the moon landing",
];

// Helper to log when messages are added
function logMessageAdd(message: ModelMessage, source: string) {
  console.log(chalk.magenta(`\n[MESSAGE ADDED from ${source}]`));
  console.log(chalk.magenta(JSON.stringify(message, null, 2)));
  console.log(chalk.magenta(`[Total messages: ${messages.length + 1}]\n`));
}

for (const pendingMessage of pendingMessages) {
  console.log(chalk.bgAnsi256(124)(`> ${pendingMessage}`));

  const userMessage: ModelMessage = {
    role: "user",
    content: pendingMessage,
  };
  messages.push(userMessage);
  logMessageAdd(userMessage, "USER INPUT");

  // Log messages before streaming
  console.log(chalk.blue("\n=== MESSAGES BEFORE STREAMING ==="));
  console.log(JSON.stringify(messages, null, 2));
  console.log(chalk.blue("=== END ===\n"));

  const { fullStream } = streamText({
    model: appleAI("apple-on-device"),
    tools,
    messages,
  });

  let responseText = "";
  let toolCallsAdded = false;
  let assistantMessageToAdd: ModelMessage | null = null;

  for await (const chunk of fullStream) {
    // console.log(chalk.yellow(`[CHUNK] type: ${chunk.type}`));

    switch (chunk.type) {
      case "text":
        responseText += chunk.text ?? "";
        process.stdout.write(chunk.text ?? "");
        break;

      case "tool-result":
        // Add tool result message
        const toolMessage: ModelMessage = {
          role: "tool",
          content: [
            {
              type: "tool-result",
              toolCallId: chunk.toolCallId,
              toolName: chunk.toolName,
              output: chunk.output,
            },
          ],
        };
        messages.push(toolMessage);
        logMessageAdd(toolMessage, "TOOL RESULT");
        break;
    }
  }

  // Add assistant message if we collected tool calls
  if (assistantMessageToAdd) {
    messages.push(assistantMessageToAdd);
    logMessageAdd(assistantMessageToAdd, "ASSISTANT TOOL CALLS");
  }

  // Add assistant text message if there was text response and no tool calls
  if (responseText.trim() && !toolCallsAdded) {
    const textMessage: ModelMessage = {
      role: "assistant",
      content: responseText,
    };
    messages.push(textMessage);
    logMessageAdd(textMessage, "ASSISTANT TEXT");
  }

  console.log("\n");

  // Final state
  console.log(chalk.green("\n=== FINAL MESSAGES AFTER INTERACTION ==="));
  console.log(JSON.stringify(messages, null, 2));
  console.log(chalk.green("=== END ===\n"));

  await new Promise((resolve) => setTimeout(resolve, 1000));
}

process.exit(0);
