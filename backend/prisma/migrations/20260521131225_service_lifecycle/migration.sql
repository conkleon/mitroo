-- CreateEnum
CREATE TYPE "service_lifecycle_status" AS ENUM ('active', 'closed', 'completed');

-- AlterEnum
ALTER TYPE "service_status" ADD VALUE 'participated';

-- AlterTable
ALTER TABLE "services" ADD COLUMN     "lifecycle_status" "service_lifecycle_status" NOT NULL DEFAULT 'active';
