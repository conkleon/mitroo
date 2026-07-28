// backend/src/lib/ai/deepseekProvider.test.ts
import { DeepSeekProvider } from "./deepseekProvider";

describe("DeepSeekProvider", () => {
  const originalFetch = global.fetch;

  afterEach(() => {
    global.fetch = originalFetch;
    jest.restoreAllMocks();
  });

  it("posts the prompt to the DeepSeek chat completions endpoint and returns the trimmed content", async () => {
    const mockFetch = jest.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        choices: [{ message: { content: "  Το κείμενο του δελτίου τύπου.  " } }],
      }),
    });
    global.fetch = mockFetch as unknown as typeof fetch;

    const provider = new DeepSeekProvider("test-key", "deepseek-chat");
    const result = await provider.generatePressRelease("Γράψε ένα δελτίο τύπου.");

    expect(result).toBe("Το κείμενο του δελτίου τύπου.");
    expect(mockFetch).toHaveBeenCalledWith(
      "https://api.deepseek.com/chat/completions",
      expect.objectContaining({
        method: "POST",
        headers: expect.objectContaining({
          "Content-Type": "application/json",
          Authorization: "Bearer test-key",
        }),
      }),
    );
    const body = JSON.parse((mockFetch.mock.calls[0][1] as RequestInit).body as string);
    expect(body.model).toBe("deepseek-chat");
    expect(body.messages).toEqual([{ role: "user", content: "Γράψε ένα δελτίο τύπου." }]);
  });

  it("throws when the API responds with a non-ok status", async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: false,
      status: 401,
      text: async () => "Unauthorized",
    }) as unknown as typeof fetch;

    const provider = new DeepSeekProvider("bad-key");
    await expect(provider.generatePressRelease("prompt")).rejects.toThrow(
      "DeepSeek API error (401): Unauthorized",
    );
  });

  it("throws when the response has no message content", async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ choices: [] }),
    }) as unknown as typeof fetch;

    const provider = new DeepSeekProvider("test-key");
    await expect(provider.generatePressRelease("prompt")).rejects.toThrow(
      "DeepSeek API returned no content",
    );
  });
});
