-- AlterTable
ALTER TABLE "specializations" ADD COLUMN     "mission_categories" JSONB NOT NULL DEFAULT '[]';
