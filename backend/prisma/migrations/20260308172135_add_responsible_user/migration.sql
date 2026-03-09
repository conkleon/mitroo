-- AlterTable
ALTER TABLE "services" ADD COLUMN     "responsible_user_id" INTEGER;

-- AddForeignKey
ALTER TABLE "services" ADD CONSTRAINT "services_responsible_user_id_fkey" FOREIGN KEY ("responsible_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;
