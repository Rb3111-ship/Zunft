# Zunft: working notes for Claude

Flutter + Supabase app for German craft businesses (Handwerk). A German voice note (or typed text, or a photographed receipt) becomes structured positions (labour § 35a EStG vs material) and then a DIN 5008 PDF quote or invoice. Target user: a self-employed craftsman up to a small firm (about 10 people). The app is in German; docs and code comments are in English.

See `README.md` (setup, deploy), `ZUNFT_BUILD_PLAN.md` (original brief), `docs/Zunft_Project_Guide.html/.pdf` (beginner guide and test script), `docs/Zunft_Steuerberater.html/.pdf` (questions for a tax advisor).

## Rules of the house
- The user keeps the beginner guide up to date: when a feature changes, update `docs/Zunft_Project_Guide.html`, regenerate the PDF, bump the test counts and add a numbered check (N19 is the last).
- **All money arithmetic is done in code, never by the AI.** Amounts are integer cents. The model only copies printed values.
- Issued documents are immutable (GoBD). Corrections go through a Stornorechnung. Nothing issued is ever deleted from the app.
- Legal wording and tax behaviour are proposals until the tax advisor / lawyer has answered. Never claim legal compliance in the UI or docs. Open questions live in `docs/Zunft_Steuerberater.html`.
- Never put service-role, Gemini or Deepgram keys in the app.
- Do not commit or push unless asked. Commit messages end with the attribution line given by the session.

## Decisions that stand
- Gemini (`gemini-3.5-flash-lite`), not Claude, for parsing. Deepgram stays for speech-to-text (no model change, no multi-language yet).
- Flat fee (Anfahrt etc.) counts as labour (§ 35a), pending advisor.
- The customer comes from the job. A job collects notes from all workers into ONE invoice. Jobs are closed when invoiced or finished (reopenable by managers).
- Roles: `owner`, `buero` are managers; `meister`, `geselle` are employees and see only assigned jobs. Employees may create customers/jobs only if the owner switches it on.
- One business per account. Removing someone never deletes their account. Owner deletion is a support process.
- Payments are deferred: seat limit and storage limit (default 1 GB) are set by hand in SQL.
- Privacy notice and data-processing terms need a lawyer.
- NOT building: bank connection, link to the customer's own cloud, quote-to-invoice conversion, own price list, tax calculations (VAT payable, EÜR, Voranmeldung). Revisit only if users ask.

## Build, test, run (this machine)
- Android SDK `D:\Android\Sdk`, JDK 17 `D:\Android\jdk17`. C: is nearly full: set `TMP`/`TEMP` to `D:\tmp` for tests and builds.
- Tests: `cd zunft_app && flutter test` (387 app tests). Deno tests (104) cannot run locally: transpile with `npx esbuild <test>.ts --bundle --format=esm --platform=node --alias:jsr:@std/assert@1=D:/tmp/rt/shim.mjs --outfile=D:/tmp/rt/bundle.mjs` and run `node D:/tmp/rt/run.mjs`.
- APK: `flutter build apk --release --dart-define=SUPABASE_URL=https://wwssjssjxurycxcshgey.supabase.co --dart-define=SUPABASE_ANON_KEY=sb_publishable_48pRr-ejaDLYtoyNwosA0A_8dxJlFN7`, then copy to `D:\Zunft_APK\zunft.apk`. A build with new plugins can take 10 minutes: run it in the background.
- Supabase project ref `wwssjssjxurycxcshgey`. SQL: `npx supabase db query --linked -f file.sql`. Deploy: `npx supabase functions deploy process-capture`. Test RLS with rolled-back `DO $$` blocks (`set_config('request.jwt.claims', ...)`, `SET LOCAL ROLE authenticated`, finish with `RAISE EXCEPTION`).
- PDF guide: headless Edge `--print-to-pdf`. Push with `timeout 90 git push`.
- Use the Write/Edit tools (not shell heredocs or Python string replacement) for text containing backslashes or newlines. Source files use CRLF: multi-line replacements through scripts silently fail.

## Roadmap (decided 2026-10-11)
Order: 1 quick wins, 2 e-invoice, 3 scheduler, 4 time tracking, 5 monthly overview. Each step: build, add tests, deploy, update the guide, build the APK. Each ends with a closing report that says what is untested on a real phone.

### Step 1: Quick wins (DONE 2026-10-11, pushed; checks N20-N24 in the guide, not yet tried on a phone)
What was built, and where it differs from the plan below:
- Logo: `businesses.logo_path` (documents bucket, `<biz>/logo/`), `LogoStore` caches it on the phone, `Din5008PdfGenerator.generate(data, logo:)`. A missing or broken logo never blocks a PDF. A document re-created from data (file missing) uses the CURRENT logo (advisor question W5).
- App lock: `core/security/app_lock.dart` (`local_auth`, `shared_preferences`), lock screen covers every route via `MaterialApp.builder`. Android needs `FlutterFragmentActivity` + AppCompat launch theme (done); untested on a real phone.
- Duplicate receipts: `capture_logs.receipt_key` (number+date+total, or first supplier word+date+total). Warn only. Verified live.
- Duplicate customers: contact-only match (same phone/e-mail, other name) added; `customers.merged_into`; manager-only merge screens; NO undo (the merged record is kept and hidden, so data is not lost, but there is no unmerge button). Deleting a customer with documents is refused (the server FK would reject it anyway).
- Recording retention: `jobs.closed_at` (trigger), `businesses.recording_retention_days` (7..90), Edge Function `purge-recordings` (deployed with `--no-verify-jwt`, secret `CRON_SECRET`), pg_cron job at 03:15 UTC reading the secret from Vault (`purge_secret`). Verified: auth, due-selection logic, cannot lengthen. Not verified: a real file deletion (no data old enough).
- Receipt net/gross fix (from the Bauhaus test): decided from printed numbers, not the AI.

Original plan text:
1. **Logo on the PDF.** Owner picks an image under Betrieb → Bearbeiten (stored in the private bucket, counts against storage). The DIN 5008 template draws it top right. Fallback: none. Keep it small (resize on the phone).
2. **App lock (fingerprint / face).** `local_auth`. Optional switch per device; locks after the app was in the background for a set time (default 1 min). Fallback to the phone's PIN. Never blocks sign-out.
3. **Duplicate receipt check by content.** Today only the file checksum (`capture_logs.image_sha256`) is compared. Add a content key from the read data: supplier + receipt number + total + date (without a number: supplier + date + time + total), across the whole business. Only a warning ("Möglicherweise schon erfasst am ..."), never a block. Store the key in `ai_parsed_json.receipt` or a new indexed column.
4. **Duplicate customers.** Never by name alone. Strong signals: same normalised phone, same e-mail, same street + house number + postcode. Name similarity only adds weight to a strong signal. (a) Warning while creating or editing a customer. (b) Manual merge screen (managers), side by side; jobs move to the kept customer; issued documents keep their printed name/address snapshot. Keep the merged record marked, so a merge can be undone for a while.
5. **Recording retention.** Default: delete the audio 90 days after the job is closed (invoiced or completed); the note text and positions stay. Owner may shorten (30/60) but not lengthen. Scheduled job on the server; remove the file from storage and mark the capture. Open questions for advisor/lawyer: is a voice note an accounting record, how long must the note text stay.
6. Add these questions to `docs/Zunft_Steuerberater.html`: recordings, note text, duplicate detection.

### Step 2: E-invoice (ZUGFeRD) (DONE 2026-10-11 except XRechnung; checks N25-N27)
Built: the spike was a GO. `pdf` package (3.13) already supports PDF/A-3b + Factur-X (`PdfaRdf`, `PdfaAttachedFiles`, `PdfaColorProfile`; ICC in `assets/icc`); PDF version 1.4 is used for it. `einvoice_xml.dart` builds the CII XML (EN 16931) from `PdfDocumentData`; `Din5008PdfGenerator.generate(data, eInvoice: true)`. `documents.e_invoice` (frozen with the document; `create_document` and `cancel_document` patched, Storno copies the flag). Finalize dialog switch, pre-selected for company customers (`defaultEInvoiceFor`), requirements checked BEFORE the number is issued (`eInvoiceBlockReason`). Credit note = type 381 with positive amounts and a reference parsed from the cancellation title. Validated with Mustang 2.26 (`D:/tmp/ei/mustang.jar`; the validation tests in `einvoice_test.dart` run only where the jar exists, or `MUSTANG_JAR`): PDF/A-3 and EN 16931 valid; only XRechnung-profile notices remain (BuyerReference BR-DE-15, business process, guideline BR-DE-21). Not done: pure XRechnung export (needs a Leitweg-ID/buyer reference field on the customer, the XRechnung guideline id `urn:cen.eu:en16931:2017#compliant#urn:xeinkauf.de:kosit:xrechnung_3.0` and business process), reading the XML of received ZUGFeRD PDFs. Original plan text:
Why now: receiving e-invoices is mandatory since 2025; issuing to business customers (B2B) becomes mandatory 2027 (turnover over 800 000 €) and 2028 (everyone). Private customers are exempt. Many craftsmen bill Hausverwaltungen. (Dates are our understanding: confirm with the advisor, question W1.)
- **Format:** ZUGFeRD 2.x / Factur-X, profile EN 16931 (COMFORT): our DIN 5008 PDF stays the visible half, a CII XML is embedded (PDF/A-3, file `factur-x.xml`, relationship Alternative, XMP metadata with the conformance level). Pure XRechnung (XML only) as a second export for public-sector customers (needs a Leitweg-ID field on the customer).
- **Spike first (go / no-go before any UI):** the Dart `pdf` package may not produce valid PDF/A-3. Options: (a) post-process the generated PDF in Dart; (b) generate in an Edge Function with `pdf-lib` (attach file, XMP, output intent, embedded fonts); (c) render on the server. Choose the simplest that validates.
- **Data to add:** buyer: address, e-mail, optional Leitweg-ID / buyer reference, USt-IdNr for businesses; seller: Steuernummer or USt-IdNr (exists), contact, IBAN (exists); unit codes (UN/ECE: HUR hour, C62 piece, MTR metre); VAT category (S standard; E with exemption reason for Kleinunternehmer § 19); payment terms and means.
- **Types:** invoice 380; Stornorechnung 381 (credit note) referencing the original number. Quotes are never e-invoices.
- **When:** switch on per customer type (business vs private) or per business; default for B2B customers; private customers keep the plain PDF. The XML is generated by code from the same integer-cent document data, never by the AI. Store the final hybrid file in the `documents` bucket like today (immutable).
- **Validation:** official KoSIT validator or Mustang CLI (Java, JDK 17 is installed) in a test script against sample invoices (normal, mixed VAT, Kleinunternehmer, storno). The Deno/Dart unit tests check the XML values against the document totals. A failing validation blocks the release.
- **Receiving:** nothing to build now: the original PDF (including any embedded XML) is stored unchanged. Later optional: read the XML of a supplier's ZUGFeRD PDF instead of OCR (exact values).
- Add to the advisor questions: which profile is acceptable, retention of the XML.

### Step 3: Scheduler ("the app the craftsman lives in")
- **Model:** `appointments` (business, optional job and customer, title, start, end, note, status, created_by) and `appointment_assignees`. Synced like jobs (Drift + Supabase, RLS by business; employees see only their own or assigned ones; managers see all). Absences (Urlaub, krank) as a kind of appointment.
- **A. Core:** day and week view (new bottom tab "Termine"), create from a job or a customer (address pre-filled), assign workers (managers), double-booking warning, tap to call and open in Maps. Solo users see only their own calendar.
- **B. Reminders:** local notifications on the phone (works offline). Push to a worker when a manager creates or changes an appointment: needs Firebase Cloud Messaging; Android first, iOS needs a Mac and an Apple developer account.
- **C. Extras:** export or subscribe via ICS to the phone calendar; "Termin bestätigen" text for the customer by WhatsApp/SMS (a shared text, no server-side messaging); job status changes from the appointment ("Start", "Fertig").
- Tests: RLS (employee cannot see others' appointments), overlap detection, time zone (Europe/Berlin, daylight saving), sync conflicts.

### Step 4: Time tracking
- Start/stop timer per job or appointment (button on the job and on the appointment). Entries are editable and addable by hand. Employees see their own, managers see all. No GPS.
- Feeds the invoice as a suggestion: the labour position for the job proposes the summed hours (the boss can change it). Hours from a spoken note and tracked hours must not be added twice: show both and let the boss choose.
- Open legal question (do not claim compliance): whether this counts as working-time recording (Arbeitszeiterfassung) and the data-protection side of employee time data. Ask the lawyer before marketing it as such.
- Mileage log (Fahrtenbuch) is a separate later item.

### Step 5: Monthly overview (plain sums only)
- Monthly and yearly sums of issued documents: net, VAT, gross, cancellations netted, per VAT rate, Kleinunternehmer aware; plus the list of receipts with their printed totals. Pure sums of immutable records, labelled "Zusammenstellung, keine Steuerberechnung. Maßgeblich sind die Belege."
- Not included: VAT payable, EÜR, Voranmeldung, anything that claims to be a tax figure. A DATEV format only after the advisor says exactly what they need. Optional "send the monthly export to my Steuerberater" (e-mail with the ZIP).

### Later / on demand
Open invoices list and friendly payment reminder text (no bank link, no fees, no legal Mahnung); reuse of customer data; photos of the site before/after; customer portal; WhatsApp intake; merged multi-page receipts; hourly-rate default; iOS build (Mac needed); STT benchmark and multi-language; third test with deliberately wrong data; lawyer review; payment plans (replace the SQL limits); Supabase Site URL fix for the confirmation e-mail.

## Still to be tested on a real phone
Listen-before-send, replay, Belege search, e-mail prefill, QR scanner, job closing and refresh, Stornorechnung, permission switch, receipt flow (scanner, gallery, PDF), archive and ZIP export, markup, storage card, net/gross receipt (N18), job tabs (N19). Checks N1–N19 and Tests A and B in the guide.
