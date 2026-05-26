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

const fhirSystemUserId = parseInt(process.env.FHIR_SYSTEM_USER_ID ?? '', 10);
if (process.env.FHIR_API_KEY && (!fhirSystemUserId || fhirSystemUserId <= 0)) {
  console.warn('FHIR_API_KEY is set but FHIR_SYSTEM_USER_ID is missing or invalid — API key auth for FHIR endpoints is disabled.');
}

httpServer.listen(PORT, () => {
  console.log(`🚀 Mitroo API running on http://localhost:${PORT}`);
  console.log(`   Environment: ${process.env.NODE_ENV}`);
});
