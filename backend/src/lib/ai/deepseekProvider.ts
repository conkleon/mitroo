import { AIProvider } from "./types";

interface DeepSeekChatResponse {
  choices?: { message?: { content?: string } }[];
}

export class DeepSeekProvider implements AIProvider {
  constructor(
    private readonly apiKey: string,
    private readonly model: string = "deepseek-chat",
  ) {}

  async generatePressRelease(prompt: string): Promise<string> {
    const response = await fetch("https://api.deepseek.com/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${this.apiKey}`,
      },
      body: JSON.stringify({
        model: this.model,
        messages: [{ role: "user", content: prompt }],
        temperature: 0.7,
      }),
    });

    if (!response.ok) {
      const text = await response.text().catch(() => "");
      throw new Error(`DeepSeek API error (${response.status}): ${text}`);
    }

    const data = (await response.json()) as DeepSeekChatResponse;
    const content = data.choices?.[0]?.message?.content;
    if (!content) {
      throw new Error("DeepSeek API returned no content");
    }
    return content.trim();
  }
}
