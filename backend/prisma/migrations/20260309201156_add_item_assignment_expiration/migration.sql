-- AlterTable
ALTER TABLE "items" ADD COLUMN     "assigned_to_id" INTEGER,
ADD COLUMN     "available_for_assignment" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "expiration_date" TIMESTAMP(3);

-- AddForeignKey
ALTER TABLE "items" ADD CONSTRAINT "items_assigned_to_id_fkey" FOREIGN KEY ("assigned_to_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;
