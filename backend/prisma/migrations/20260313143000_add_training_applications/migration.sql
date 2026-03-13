-- CreateEnum
CREATE TYPE "training_application_status" AS ENUM ('submitted', 'training', 'rejected', 'enabled');

-- CreateTable
CREATE TABLE "training_applications" (
    "id" SERIAL NOT NULL,
    "email" VARCHAR(255) NOT NULL,
    "forename" VARCHAR(150) NOT NULL,
    "surname" VARCHAR(150) NOT NULL,
    "phone_primary" VARCHAR(30) NOT NULL,
    "phone_secondary" VARCHAR(30),
    "address" TEXT,
    "birth_date" DATE,
    "extra_info" TEXT,
    "department_id" INTEGER NOT NULL,
    "specialization_id" INTEGER NOT NULL,
    "status" "training_application_status" NOT NULL DEFAULT 'submitted',
    "review_notes" TEXT,
    "reviewed_at" TIMESTAMP(3),
    "reviewed_by_id" INTEGER,
    "enabled_at" TIMESTAMP(3),
    "linked_user_id" INTEGER,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "training_applications_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "training_applications_status_idx" ON "training_applications"("status");

-- CreateIndex
CREATE INDEX "training_applications_department_id_status_idx" ON "training_applications"("department_id", "status");

-- CreateIndex
CREATE INDEX "training_applications_email_idx" ON "training_applications"("email");

-- CreateIndex
CREATE UNIQUE INDEX "training_applications_linked_user_id_key" ON "training_applications"("linked_user_id");

-- AddForeignKey
ALTER TABLE "training_applications" ADD CONSTRAINT "training_applications_department_id_fkey" FOREIGN KEY ("department_id") REFERENCES "departments"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "training_applications" ADD CONSTRAINT "training_applications_specialization_id_fkey" FOREIGN KEY ("specialization_id") REFERENCES "specializations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "training_applications" ADD CONSTRAINT "training_applications_reviewed_by_id_fkey" FOREIGN KEY ("reviewed_by_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "training_applications" ADD CONSTRAINT "training_applications_linked_user_id_fkey" FOREIGN KEY ("linked_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;
