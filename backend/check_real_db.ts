import { PrismaBetterSqlite3 } from "@prisma/adapter-better-sqlite3";
import { PrismaClient } from "./src/generated/prisma/client";

const adapter = new PrismaBetterSqlite3({
  url: process.env.DATABASE_URL ?? "file:./dev.db",
});

const prisma = new PrismaClient({ adapter });

async function main() {
  const userCount = await prisma.user.count();
  const reportCount = await prisma.report.count();
  console.log(`Real DB - Users: ${userCount}, Reports: ${reportCount}`);

  // Check one user and one report to see if state and district are null
  const user = await prisma.user.findFirst();
  const report = await prisma.report.findFirst();

  console.log("First user:", user ? JSON.stringify(user) : "null");
  console.log("First report:", report ? JSON.stringify(report) : "null");
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
