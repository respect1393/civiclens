import "dotenv/config";
import { createApp } from "./app";
import { getJwtSecret, getUploadDir } from "./config";
import { ensureDir } from "./storage";

// Environment validation: fail fast with a clear startup message.
try {
  getJwtSecret();
} catch (error) {
  console.error(`FATAL: ${(error as Error).message}`);
  process.exit(1);
}

const PORT = Number(process.env.PORT) || 3000;

// Runtime directories are created on first start so a fresh clone never needs
// a copied-in uploads folder from another developer.
const app = createApp();

ensureDir(getUploadDir())
  .then(() => {
    app.listen(PORT, () => {
      console.log(`CivicLens backend running at http://localhost:${PORT}`);
      // Bind every interface so a phone on the same LAN can reach the API
      // during development. This is a developer machine, not production.
      console.log(`Listening on all interfaces; the API is reachable at :${PORT}.`);
    });
  })
  .catch((error) => {
    console.error("FATAL: could not create the upload directory:", error);
    process.exit(1);
  });
