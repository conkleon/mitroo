import dotenv from "dotenv";
import path from "path";

// Load backend-local .env first (has localhost URLs for dev),
// then the shared root .env (won't override existing vars).
dotenv.config({ path: path.resolve(__dirname, "../.env") });
dotenv.config({ path: path.resolve(__dirname, "../../.env") });

import app from "./app";

const PORT = parseInt(process.env.APP_PORT || "4000", 10);

app.listen(PORT, () => {
  console.log(`🚀 Mitroo API running on http://localhost:${PORT}`);
  console.log(`   Environment: ${process.env.NODE_ENV}`);
});
