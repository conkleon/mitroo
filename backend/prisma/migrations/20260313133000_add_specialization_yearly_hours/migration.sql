-- AlterTable
ALTER TABLE "specializations"
ADD COLUMN "yearly_hours" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN "yearly_hours_training" INTEGER NOT NULL DEFAULT 0;
