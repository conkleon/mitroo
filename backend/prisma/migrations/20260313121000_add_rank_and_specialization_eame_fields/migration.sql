-- RenameColumn
ALTER TABLE "users"
RENAME COLUMN "ename" TO "eame";

-- RenameIndex
ALTER INDEX "users_ename_key"
RENAME TO "users_eame_key";

-- AlterTable
ALTER TABLE "users"
ADD COLUMN "rank" VARCHAR(4) NOT NULL DEFAULT 'Γ';

-- AlterTable
ALTER TABLE "specializations"
ADD COLUMN "hours_tep" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN "eame_prefix" VARCHAR(8);
