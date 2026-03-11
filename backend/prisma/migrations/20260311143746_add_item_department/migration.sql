-- AlterTable: add department_id as nullable first
ALTER TABLE "items" ADD COLUMN "department_id" INTEGER;

-- Backfill: assign existing items to the first department
UPDATE "items" SET "department_id" = (SELECT "id" FROM "departments" ORDER BY "id" LIMIT 1) WHERE "department_id" IS NULL;

-- Now make it NOT NULL
ALTER TABLE "items" ALTER COLUMN "department_id" SET NOT NULL;

-- AddForeignKey
ALTER TABLE "items" ADD CONSTRAINT "items_department_id_fkey" FOREIGN KEY ("department_id") REFERENCES "departments"("id") ON DELETE CASCADE ON UPDATE CASCADE;
