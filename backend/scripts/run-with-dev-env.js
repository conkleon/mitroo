const path = require("path");
const { spawn } = require("child_process");
const dotenv = require("dotenv");

dotenv.config({ path: path.resolve(__dirname, "../../.env") });

if (process.env.DATABASE_URL_DEV) {
  process.env.DATABASE_URL = process.env.DATABASE_URL_DEV;
}

if (process.env.REDIS_URL_DEV) {
  process.env.REDIS_URL = process.env.REDIS_URL_DEV;
}

const [command, ...args] = process.argv.slice(2);

if (!command) {
  console.error("Missing command to run.");
  process.exit(1);
}

const child = spawn(command, args, {
  stdio: "inherit",
  shell: true,
  env: process.env,
});

child.on("exit", (code, signal) => {
  if (signal) {
    process.kill(process.pid, signal);
    return;
  }

  process.exit(code ?? 1);
});
