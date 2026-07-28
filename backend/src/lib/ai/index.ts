import { AIProvider } from "./types";
import { DeepSeekProvider } from "./deepseekProvider";

export function getAIProvider(): AIProvider {
  const provider = (process.env.AI_PROVIDER || "deepseek").toLowerCase();

  switch (provider) {
    case "deepseek": {
      const apiKey = process.env.DEEPSEEK_API_KEY;
      if (!apiKey) {
        throw new Error("DEEPSEEK_API_KEY environment variable is not set");
      }
      return new DeepSeekProvider(apiKey, process.env.DEEPSEEK_MODEL || "deepseek-chat");
    }
    default:
      throw new Error(`Unknown AI_PROVIDER: ${provider}`);
  }
}

export type { AIProvider } from "./types";
