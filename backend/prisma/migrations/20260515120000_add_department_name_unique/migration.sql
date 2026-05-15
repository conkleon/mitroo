-- Add unique constraint on department name to prevent duplicates
-- and enable safe upsert semantics during concurrent login
CREATE UNIQUE INDEX "departments_name_key" ON "departments"("name");
