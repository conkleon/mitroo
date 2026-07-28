export interface AIProvider {
  generatePressRelease(prompt: string): Promise<string>;
}
