-- CreateTable
CREATE TABLE "service_types" (
    "id" SERIAL NOT NULL,
    "name" VARCHAR(255) NOT NULL,
    "external_mission_type_id" INTEGER,
    "is_default_visible" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "service_types_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "service_types_name_key" ON "service_types"("name");

-- CreateIndex
CREATE UNIQUE INDEX "service_types_external_mission_type_id_key" ON "service_types"("external_mission_type_id");

-- CreateTable
CREATE TABLE "specialization_service_types" (
    "specialization_id" INTEGER NOT NULL,
    "service_type_id" INTEGER NOT NULL,

    CONSTRAINT "specialization_service_types_pkey" PRIMARY KEY ("specialization_id","service_type_id")
);

-- AlterTable — Service
ALTER TABLE "services" ADD COLUMN "service_type_id" INTEGER;

-- AddForeignKey — Service → ServiceType
ALTER TABLE "services" ADD CONSTRAINT "services_service_type_id_fkey" FOREIGN KEY ("service_type_id") REFERENCES "service_types"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey — SpecializationServiceType → Specialization
ALTER TABLE "specialization_service_types" ADD CONSTRAINT "specialization_service_types_specialization_id_fkey" FOREIGN KEY ("specialization_id") REFERENCES "specializations"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey — SpecializationServiceType → ServiceType
ALTER TABLE "specialization_service_types" ADD CONSTRAINT "specialization_service_types_service_type_id_fkey" FOREIGN KEY ("service_type_id") REFERENCES "service_types"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AlterTable — Specialization: drop mission_categories
ALTER TABLE "specializations" DROP COLUMN "mission_categories";

-- DropTable
DROP TABLE "service_visibility";
