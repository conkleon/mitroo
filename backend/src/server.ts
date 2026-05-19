import dotenv from "dotenv";
import path from "path";

// Load the single root .env (Docker Compose overrides URLs for containers).
dotenv.config({ path: path.resolve(__dirname, "../../.env") });

if (process.env.NODE_ENV !== "production") {
  if (process.env.DATABASE_URL_DEV) {
    process.env.DATABASE_URL = process.env.DATABASE_URL_DEV;
  }

  if (process.env.REDIS_URL_DEV) {
    process.env.REDIS_URL = process.env.REDIS_URL_DEV;
  }
}

import { createServer } from "http";
import app from "./app";
import { initSocket } from "./socket";
import { cleanupExpiredChats } from "./lib/chatCleanup";
import { autoSyncAllDepartments } from "./lib/mitrooSync";

const PORT = parseInt(process.env.APP_PORT || "4000", 10);

const httpServer = createServer(app);
initSocket(httpServer);

// Run cleanup every 15 minutes
setInterval(cleanupExpiredChats, 15 * 60 * 1000);

// Hourly auto-sync of all departments from original Mitroo
setInterval(autoSyncAllDepartments, 60 * 60 * 1000);

httpServer.listen(PORT, () => {
  console.log(`🚀 Mitroo API running on http://localhost:${PORT}`);
  console.log(`   Environment: ${process.env.NODE_ENV}`);
});
