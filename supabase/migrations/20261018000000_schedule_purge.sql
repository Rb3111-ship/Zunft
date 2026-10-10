-- Runs the recording purge every night at 03:15 UTC. The shared secret is read from Vault
-- (name: purge_secret) and must also be set as the function secret CRON_SECRET:
--   select vault.create_secret('<secret>', 'purge_secret');
--   npx supabase secrets set CRON_SECRET=<secret>
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

SELECT cron.schedule(
    'purge-recordings',
    '15 3 * * *',
    $job$
    SELECT net.http_post(
        url := 'https://wwssjssjxurycxcshgey.supabase.co/functions/v1/purge-recordings',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'x-cron-secret', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'purge_secret')),
        body := '{}'::jsonb
    );
    $job$
);
