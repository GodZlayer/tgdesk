WITH ranked_devices AS (
    SELECT id,
           row_number() OVER (
               PARTITION BY lower(btrim(mac))
               ORDER BY
                   CASE WHEN state = 'ativo' THEN 0 ELSE 1 END,
                   last_seen_at DESC NULLS LAST,
                   created_at ASC
           ) AS duplicate_rank
    FROM devices
    WHERE mac IS NOT NULL AND btrim(mac) <> ''
)
DELETE FROM devices
WHERE id IN (
    SELECT id FROM ranked_devices WHERE duplicate_rank > 1
);

CREATE UNIQUE INDEX IF NOT EXISTS devices_unique_mac
    ON devices (lower(btrim(mac)))
    WHERE mac IS NOT NULL AND btrim(mac) <> '';
