import dotenv from "dotenv";
import path from "path";

// Load the single root .env (Docker Compose overrides URLs for containers).
dotenv.config({ path: path.resolve(__dirname, "../../.env") });

import app from "./app";

const PORT = parseInt(process.env.APP_PORT || "4000", 10);

app.listen(PORT, () => {
  console.log(`🚀 Mitroo API running on http://localhost:${PORT}`);
  console.log(`   Environment: ${process.env.NODE_ENV}`);
});
