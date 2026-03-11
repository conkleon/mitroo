-- AlterTable
ALTER TABLE "file_attachments" ADD COLUMN     "height" INTEGER,
ADD COLUMN     "is_image" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "thumbnail_path" TEXT,
ADD COLUMN     "width" INTEGER;

-- CreateIndex
CREATE INDEX "file_attachments_user_id_idx" ON "file_attachments"("user_id");

-- CreateIndex
CREATE INDEX "file_attachments_department_id_idx" ON "file_attachments"("department_id");

-- CreateIndex
CREATE INDEX "file_attachments_service_id_idx" ON "file_attachments"("service_id");

-- CreateIndex
CREATE INDEX "file_attachments_item_id_idx" ON "file_attachments"("item_id");

-- CreateIndex
CREATE INDEX "file_attachments_vehicle_id_idx" ON "file_attachments"("vehicle_id");
