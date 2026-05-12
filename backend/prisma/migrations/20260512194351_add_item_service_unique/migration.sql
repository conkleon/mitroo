-- AddUniqueConstraint
CREATE UNIQUE INDEX "item_services_service_id_user_id_item_id_key" ON "item_services"("service_id", "user_id", "item_id");
