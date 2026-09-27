-- Existing development database only. Stops on incompatible columns; never rebuilds data.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
ALTER TABLE public.inventory_item ADD COLUMN IF NOT EXISTS notes TEXT;
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'inventory_item'
          AND column_name = 'notes' AND data_type = 'text' AND is_nullable = 'YES'
    ) THEN
        RAISE EXCEPTION 'inventory_item.notes must be nullable TEXT; no automatic conversion';
    END IF;
END $$;
COMMIT;
