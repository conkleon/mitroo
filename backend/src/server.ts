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

import app from "./app";

const PORT = parseInt(process.env.APP_PORT || "4000", 10);

app.listen(PORT, () => {
  console.log(`🚀 Mitroo API running on http://localhost:${PORT}`);
  console.log(`   Environment: ${process.env.NODE_ENV}`);
});
