import { PrismaClient } from "./src/generated/prisma/client";
import { PrismaBetterSqlite3 } from "@prisma/adapter-better-sqlite3";
import bcrypt from "bcryptjs";

const adapter = new PrismaBetterSqlite3({
  url: process.env.DATABASE_URL ?? "file:./dev.db",
});

const prisma = new PrismaClient({ adapter });

async function main() {
  const email = "admin@example.com";
  const password = "adminpassword123";

  // Check if admin already exists
  const existing = await prisma.user.findUnique({ where: { email } });
  if (existing) {
    console.log("Admin user already exists");
    await prisma.$disconnect();
    return;
  }

  const hashedPassword = await bcrypt.hash(password, 10);

  const admin = await prisma.user.create({
    data: {
      name: "Admin User",
      email,
      passwordHash: hashedPassword,
      role: "ADMIN",
      state: null, // Admin can have null state/district to indicate they can see all
      district: null,
    },
    select: {
      id: true,
      name: true,
      email: true,
      role: true,
      state: true,
      district: true,
    },
  });

  console.log("Created admin user:", admin);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
