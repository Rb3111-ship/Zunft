# Zunft

AI back-office for German craft businesses. A craftsman records a German voice note on site, and the app turns it into a draft quote or invoice (labor and material split for § 35a EStG) with a DIN 5008 PDF.

- `zunft_app/`: Flutter app
- `supabase/`: Postgres schema, RLS, and the `process-capture` Edge Function (speech-to-text plus Gemini). Notes are stored on a job; the customer comes from the job, never from the AI.
- `ZUNFT_BUILD_PLAN.md`: product brief and sprint plan

## Setup
1. Windows needs Developer Mode on for Flutter plugins (`start ms-settings:developers`).
2. `cd zunft_app && flutter pub get && flutter test`
3. `supabase start`, then copy `.env.example` to `supabase/functions/.env` and fill in the keys.
4. Run the app with the public Supabase URL and anon key (from `supabase status`). The Android emulator reaches your PC at `10.0.2.2`:
   `flutter run --dart-define=SUPABASE_URL=http://10.0.2.2:54321 --dart-define=SUPABASE_ANON_KEY=<anon key>`
   Never put the service-role key or the Gemini/Deepgram keys in the app.

## Deploying the cloud pieces (first real test)
1. Create a Supabase project (or use `supabase start` locally) and link it: `supabase link --project-ref <ref>`
2. Apply the five migrations: `supabase db push`
3. Set the secret keys (server-side only): `supabase secrets set GEMINI_API_KEY=... DEEPGRAM_API_KEY=... LLM_MODEL=gemini-2.5-flash-lite`
   (`SUPABASE_URL` and `SUPABASE_ANON_KEY` are provided to Edge Functions automatically.)
4. Deploy the function: `supabase functions deploy process-capture`
5. Run the app with the project's URL and public key (see above), register, set up the business, add a customer and a job, and record a note on that job. Several notes (from any worker) collect on the job; "Alle Notizen prüfen und abrechnen" turns them into one invoice.

## Local database (Drift)
The generated file `zunft_app/lib/core/database/app_database.g.dart` is committed. After changing the tables in `app_database.dart`, regenerate it and bump `schemaVersion` with a migration:
`cd zunft_app && dart run build_runner build --delete-conflicting-outputs`

## Tests
- App: `cd zunft_app && flutter test`
- SQL (RLS, numbering, GoBD locks): `cd supabase/tests && npm install && npm test`
- Edge Function logic: `cd supabase/functions && deno test _shared/`
