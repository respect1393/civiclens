import { prisma } from "./db";

async function main() {
  const userCount = await prisma.user.count();
  const reportCount = await prisma.report.count();

  console.log("Database connection successful!");
  console.log(`Users: ${userCount}`);
  console.log(`Reports: ${reportCount}`);
}

main()
  .catch((error) => {
    console.error("Database test failed:", error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
