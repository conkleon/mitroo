import { getAIProvider } from "./index";
import { DeepSeekProvider } from "./deepseekProvider";

describe("getAIProvider", () => {
  const ORIGINAL_ENV = process.env;

  beforeEach(() => {
    process.env = { ...ORIGINAL_ENV };
  });

  afterAll(() => {
    process.env = ORIGINAL_ENV;
  });

  it("returns a DeepSeekProvider by default", () => {
    delete process.env.AI_PROVIDER;
    process.env.DEEPSEEK_API_KEY = "key-123";
    const provider = getAIProvider();
    expect(provider).toBeInstanceOf(DeepSeekProvider);
  });

  it("throws a clear error when DEEPSEEK_API_KEY is missing", () => {
    process.env.AI_PROVIDER = "deepseek";
    delete process.env.DEEPSEEK_API_KEY;
    expect(() => getAIProvider()).toThrow("DEEPSEEK_API_KEY environment variable is not set");
  });

  it("throws on an unknown AI_PROVIDER value", () => {
    process.env.AI_PROVIDER = "openai";
    expect(() => getAIProvider()).toThrow("Unknown AI_PROVIDER: openai");
  });
});
