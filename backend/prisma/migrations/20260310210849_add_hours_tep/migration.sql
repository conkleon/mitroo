-- AlterTable
ALTER TABLE "services" ADD COLUMN     "default_hours_tep" INTEGER NOT NULL DEFAULT 0;

-- AlterTable
ALTER TABLE "user_services" ADD COLUMN     "hours_tep" INTEGER NOT NULL DEFAULT 0;
