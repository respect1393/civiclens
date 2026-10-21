import "dotenv/config";
import { createInterface } from "node:readline";
import { stdin, stdout } from "node:process";
import bcrypt from "bcryptjs";
import { prisma } from "./src/db";

function hiddenPrompt(prompt: string): Promise<string> {
  return new Promise((resolve, reject) => {
    stdout.write(prompt);
    stdin.setRawMode(true);
    let value = "";

    const onData = (chunk: Buffer) => {
      for (const char of chunk.toString()) {
        if (char === "\u0003") {
          cleanup();
          reject(new Error("Cancelled."));
          return;
        }

        if (char === "\r" || char === "\n") {
          cleanup();
          stdout.write("\n");
          resolve(value);
          return;
        }

        if (char === "\u007f" || char === "\b") {
          value = value.slice(0, -1);
        } else {
          value += char;
        }
      }
    };

    function cleanup() {
      stdin.off("data", onData);
      stdin.setRawMode(false);
    }

    stdin.on("data", onData);
    stdin.resume();
  });
}

async function main() {
  if (!stdin.isTTY || !stdout.isTTY) {
    throw new Error("Run this script directly in an interactive terminal.");
  }

  try {
    const password = await hiddenPrompt("New admin password (12+ characters): ");

    if (password.length < 12) {
      throw new Error("Password must contain at least 12 characters.");
    }

    const confirmation = await hiddenPrompt("Confirm new password: ");

    if (password !== confirmation) {
      throw new Error("Passwords do not match.");
    }

    const admin = await prisma.user.findUnique({
      where: { email: "admin@example.com" },
      select: { id: true, role: true },
    });

    if (!admin || admin.role !== "ADMIN") {
      throw new Error("Admin account not found or role mismatch. No changes made.");
    }

    const passwordHash = await bcrypt.hash(password, 10);

    const result = await prisma.user.updateMany({
      where: { email: "admin@example.com", role: "ADMIN" },
      data: { passwordHash },
    });

    if (result.count !== 1) {
      throw new Error(`Expected one updated admin account; got ${result.count}.`);
    }

    console.log("Admin password updated. Account and role preserved.");
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((error) => {
  console.error(error.message || "Password reset failed.");
  process.exitCode = 1;
});
