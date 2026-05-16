-- CreateTable
CREATE TABLE "victims" (
    "id" SERIAL NOT NULL,
    "name" TEXT NOT NULL,
    "age" INTEGER,
    "date_of_birth" TIMESTAMP(3),
    "gender" TEXT,
    "address" TEXT,
    "city" VARCHAR(255),
    "postal_code" VARCHAR(20),
    "telephone" VARCHAR(30),
    "emergency_contact" VARCHAR(255),
    "emergency_phone" VARCHAR(30),
    "chief_complaint" TEXT,
    "allergies" TEXT,
    "medications" TEXT,
    "medical_history" TEXT,
    "gcs_eye" INTEGER,
    "gcs_verbal" INTEGER,
    "gcs_motor" INTEGER,
    "gcs_total" INTEGER,
    "avpu" TEXT,
    "latitude" DOUBLE PRECISION,
    "longitude" DOUBLE PRECISION,
    "location_notes" TEXT,
    "service_id" INTEGER,
    "notes" TEXT,
    "is_finalized" BOOLEAN NOT NULL DEFAULT false,
    "finalized_at" TIMESTAMP(3),
    "finalized_by_id" INTEGER,
    "created_by_id" INTEGER NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "victims_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "vital_signs" (
    "id" SERIAL NOT NULL,
    "victim_id" INTEGER NOT NULL,
    "systolic_bp" INTEGER,
    "diastolic_bp" INTEGER,
    "heart_rate" INTEGER,
    "respiratory_rate" INTEGER,
    "oxygen_sat" INTEGER,
    "temperature" DOUBLE PRECISION,
    "blood_glucose" DOUBLE PRECISION,
    "pain_score" INTEGER,
    "measured_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "notes" TEXT,
    "measured_by" VARCHAR(255),

    CONSTRAINT "vital_signs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "treatments" (
    "id" SERIAL NOT NULL,
    "victim_id" INTEGER NOT NULL,
    "action" TEXT NOT NULL,
    "material_used" TEXT,
    "notes" TEXT,
    "item_id" INTEGER,
    "consumed_note" TEXT,
    "performed_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "performed_by" VARCHAR(255),

    CONSTRAINT "treatments_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "victims_created_by_id_idx" ON "victims"("created_by_id");

-- CreateIndex
CREATE INDEX "victims_service_id_idx" ON "victims"("service_id");

-- CreateIndex
CREATE INDEX "victims_created_at_idx" ON "victims"("created_at");

-- CreateIndex
CREATE INDEX "vital_signs_victim_id_idx" ON "vital_signs"("victim_id");

-- CreateIndex
CREATE INDEX "vital_signs_measured_at_idx" ON "vital_signs"("measured_at");

-- CreateIndex
CREATE INDEX "treatments_victim_id_idx" ON "treatments"("victim_id");

-- CreateIndex
CREATE INDEX "treatments_performed_at_idx" ON "treatments"("performed_at");

-- AddForeignKey
ALTER TABLE "victims" ADD CONSTRAINT "victims_created_by_id_fkey" FOREIGN KEY ("created_by_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "victims" ADD CONSTRAINT "victims_finalized_by_id_fkey" FOREIGN KEY ("finalized_by_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "victims" ADD CONSTRAINT "victims_service_id_fkey" FOREIGN KEY ("service_id") REFERENCES "services"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "vital_signs" ADD CONSTRAINT "vital_signs_victim_id_fkey" FOREIGN KEY ("victim_id") REFERENCES "victims"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "treatments" ADD CONSTRAINT "treatments_victim_id_fkey" FOREIGN KEY ("victim_id") REFERENCES "victims"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "treatments" ADD CONSTRAINT "treatments_item_id_fkey" FOREIGN KEY ("item_id") REFERENCES "items"("id") ON DELETE SET NULL ON UPDATE CASCADE;
