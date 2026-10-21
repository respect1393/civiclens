import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "node",
    include: ["tests/**/*.test.ts"],
    globalSetup: ["./tests/setup/global-setup.ts"],
    setupFiles: ["./tests/setup/db.ts"],
    // A single disposable temp database is shared by all suites, so files must
    // not run concurrently (each suite truncates the shared tables).
    fileParallelism: false,
    hookTimeout: 30000,
    testTimeout: 20000,
  },
});
