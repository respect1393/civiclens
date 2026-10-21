import { prisma } from "./db";

async function main() {
  const email = "demo-citizen@civiclens.local";

  const citizen = await prisma.user.upsert({
    where: { email },
    update: {},
    create: {
      name: "Demo Citizen",
      email,
      passwordHash: "NOT_A_REAL_PASSWORD_HASH",
      role: "CITIZEN",
    },
  });

  const report = await prisma.report.create({
    data: {
      title: "Pothole on Main Road",
      description: "A pothole needs repair near the market.",
      category: "ROADS",
      area: "Demo Area",
      address: "Main Road, Demo Area",
      userId: citizen.id,
    },
  });

  const result = await prisma.report.findUnique({
    where: { id: report.id },
    include: {
      user: {
        select: {
          name: true,
          email: true,
        },
      },
    },
  });

  console.log("Created report and retrieved it successfully:");
  console.dir(result, { depth: null });
}

main()
  .catch((error) => {
    console.error("Database demo failed:", error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
