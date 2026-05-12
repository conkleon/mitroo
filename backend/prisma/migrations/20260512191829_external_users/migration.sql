/*
  Warnings:

  - A unique constraint covering the columns `[external_id]` on the table `users` will be added. If there are existing duplicate values, this will fail.

*/
-- AlterTable
ALTER TABLE "services" ADD COLUMN     "external_mission_id" INTEGER,
ADD COLUMN     "external_shift_id" INTEGER;

-- AlterTable
ALTER TABLE "user_services" ADD COLUMN     "external_application_id" INTEGER;

-- AlterTable
ALTER TABLE "users" ADD COLUMN     "external_id" INTEGER;

-- CreateTable
CREATE TABLE "department_sync_configs" (
    "id" SERIAL NOT NULL,
    "department_id" INTEGER NOT NULL,
    "external_username" VARCHAR(255) NOT NULL,
    "external_password" TEXT NOT NULL,
    "sync_enabled" BOOLEAN NOT NULL DEFAULT false,
    "last_user_sync_at" TIMESTAMP(3),
    "last_service_sync_at" TIMESTAMP(3),
    "last_sync_status" VARCHAR(20),
    "last_sync_error" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "department_sync_configs_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "department_sync_configs_department_id_key" ON "department_sync_configs"("department_id");

-- CreateIndex
CREATE UNIQUE INDEX "users_external_id_key" ON "users"("external_id");

-- AddForeignKey
ALTER TABLE "department_sync_configs" ADD CONSTRAINT "department_sync_configs_department_id_fkey" FOREIGN KEY ("department_id") REFERENCES "departments"("id") ON DELETE CASCADE ON UPDATE CASCADE;
