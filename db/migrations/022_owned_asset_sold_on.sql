-- Day the owned asset was sold. On and after this date it contributes 0 to net worth.

ALTER TABLE owned_assets
    ADD COLUMN IF NOT EXISTS sold_on BIGINT;
