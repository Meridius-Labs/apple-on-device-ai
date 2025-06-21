/**
 * Basic Text Generation with AI SDK
 *
 * This example demonstrates simple text generation using the Apple AI provider
 * with the Vercel AI SDK.
 */

import { generateText, streamText } from "ai";
import { appleAI } from "../src/apple-ai-provider";

async function basicGeneration() {
  console.log("🍎 Basic Text Generation with AI SDK");
  console.log("====================================");

  try {
    // Simple text generation
    console.log("\n1. Simple question:");
    const { text: answer1 } = await generateText({
      model: appleAI("apple-on-device"),
      prompt: "What is the capital of France?",
      temperature: 0.7,
      maxOutputTokens: 50,
    });
    console.log("Answer:", answer1);

    // Creative writing
    console.log("\n2. Creative writing:");
    const { text: story } = await generateText({
      model: appleAI("apple-on-device"),
      prompt: "Write a short poem about technology and nature.",
      temperature: 0.8,
      maxOutputTokens: 100,
    });
    console.log("Poem:", story);

    // Technical explanation
    console.log("\n3. Technical explanation:");
    const { text: explanation } = await generateText({
      model: appleAI("apple-on-device"),
      prompt: "Explain machine learning in simple terms for a beginner.",
      temperature: 0.3,
      maxOutputTokens: 150,
    });
    console.log("Explanation:", explanation);

    console.log("\n✅ Basic generation examples completed!");
  } catch (error) {
    console.error("❌ Error:", error);
  }
}

// Run the example if this file is executed directly
if (import.meta.main) {
  basicGeneration().catch(console.error);
}

export { basicGeneration };
