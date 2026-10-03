# Zunft: AI Back-Office & Capacity-Sharing App for German Handwerk
## Comprehensive Phase 1 Build Plan, Architecture & Task Breakdown

---

## 1. Executive Summary & Product Brief

**Product Name:** Zunft (German for "guild")  
**Target Audience:** German craft businesses (*Handwerksbetriebe*), starting with solo to 10-person businesses in one trade and city (e.g. Electricians in Hamburg / *Elektrohandwerk Hamburg*).  
**Core Value Proposition:**
- **Layer 1 (The Hook):** AI Back-Office. On-site voice note/photo capture → instant transcription + Claude 3.5 structured extraction → editable draft estimate/invoice (with § 35a EStG labor/material separation) → 1-tap PDF generation & client delivery.
- **Layer 2 (The Retention & Network Moat - Phase 3):** Overflow-sharing network. Nearby peer capacity matching based on PostGIS geospatial queries with automated referral fee tracking.
- **Layer 3 (Compliance - Phase 4):** GoBD-compliant sequential numbering & audit trails, ZUGFeRD / XRechnung e-invoicing for B2B mandate.

---

## 2. Tech Stack Sanity Check & Critical Architecture Decisions

### 2.1 The PDF Dilemma: Hybrid On-Device vs. Server-Side
* **The Conflict:** Craftsmen operate in low/zero connectivity environments (cellars, raw builds). A requirement for server-side PDF generation fails offline and adds heavy Chromium/Puppeteer binary overhead to serverless edge functions.
* **The Solution (Hybrid):**
  1. **Primary / On-Device:** Use Flutter's native [`pdf`](https://pub.dev/packages/pdf) and [`printing`](https://pub.dev/packages/printing) packages for 100% offline-capable, instant vector PDF generation and printing/sharing via native OS share sheets.
  2. **Secondary / Server-Side (Cloud Archive):** When synced to Supabase, the generated PDF is archived to Supabase Storage, or re-rendered in an Edge Function using a lightweight pure-JS vector engine (`pdf-lib`) for canonical record keeping.

### 2.2 Speech-to-Text (STT) Vendor Comparison for German
German Handwerk vocabulary features complex compound nouns (*Unterputzsteckdose*, *Verteilerkasten*, *FI-Schutzschalter*, *Durchgangsprüfung*).

| Provider | German Domain Accuracy | Speed / Latency | Pricing | Est. Cost (15 users @ 5 notes/day) | Recommendation |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Deepgram (Nova-2 German)** | **Highest** (custom keyword boosting) | ~300ms | $0.0043 / min | **~$9.70 / month** | **Recommended.** Best domain handling + fast. |
| **Groq (Whisper-large-v3)** | Very High | ~400ms | $0.00185 / min | **~$4.16 / month** | Ultra-low cost, blazing fast fallback. |
| **OpenAI Whisper API** | High | 2–4s | $0.0060 / min | **~$13.50 / month** | Standard reliability, higher latency. |
| **Google Cloud Speech-to-Text** | High | 1–3s | $0.0160 / min | **~$36.00 / month** | Overpriced for this stage. |

> **Verdict:** Use **Deepgram Nova-2** with custom trade vocabulary lists. Cost for 15 users is less than €10/month.

### 2.3 German Tax Law Constraint: § 35a EStG
Under German tax law (*§ 35a Abs. 3 EStG*), homeowners can deduct 20% of craft labor costs up to €1,200/year from their income tax.
* **Non-Negotiable Rule:** Invoices **must clearly separate labor costs (*Lohnkosten*) and material costs (*Materialkosten*)**.
* The AI prompt and the data model enforce this split at the database level.

---

## 3. Database Schema (Postgres + PostGIS)

Designed for Supabase in an EU region (e.g. Frankfurt `eu-central-1`) with strict Row Level Security (RLS). Includes forward-compatibility for PostGIS proximity matching and GoBD/e-invoicing.

```sql
-- Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";

-- 1. BUSINESSES (Betriebe)
CREATE TABLE businesses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    trade_category TEXT NOT NULL, -- e.g. 'elektro', 'shk', 'maler', 'dachdecker'
    owner_name TEXT NOT NULL,
    tax_number TEXT,              -- Steuernummer
    vat_id TEXT,                  -- USt-IdNr (DE...)
    iban TEXT,
    bic TEXT,
    bank_name TEXT,
    phone TEXT,
    email TEXT,
    website TEXT,
    address_street TEXT,
    address_zip TEXT,
    address_city TEXT,
    -- PostGIS geography point for Phase 3 radius search (longitude, latitude)
    location GEOGRAPHY(Point, 4326),
    default_hourly_rate_cents INT DEFAULT 6500, -- 65,00 €/hr in cents
    default_vat_rate NUMERIC(4,2) DEFAULT 19.00,
    subscription_status TEXT DEFAULT 'trialing',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_businesses_location ON businesses USING GIST(location);

-- 2. PROFILES (Staff linked to Supabase Auth)
CREATE TABLE profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    role TEXT DEFAULT 'owner', -- 'owner', 'journeyman', 'office'
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. CUSTOMERS (Kundenstamm)
CREATE TABLE customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    salutation TEXT,            -- 'Herr', 'Frau', 'Firma'
    name TEXT NOT NULL,         -- 'Müller' or 'Müller Hausverwaltung GmbH'
    first_name TEXT,
    email TEXT,
    phone TEXT,
    street TEXT,
    zip TEXT,
    city TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_customers_business ON customers(business_id);

-- 4. JOBS (Aufträge)
CREATE TABLE jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    customer_id UUID REFERENCES customers(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    description TEXT,
    status TEXT NOT NULL DEFAULT 'draft', 
    -- 'draft', 'quote_sent', 'in_progress', 'completed', 'invoiced', 'overflow_ready'
    location GEOGRAPHY(Point, 4326),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_jobs_business ON jobs(business_id);

-- 5. CAPTURE LOGS (Sprachnotizen & KI-Protokolle)
CREATE TABLE capture_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    job_id UUID REFERENCES jobs(id) ON DELETE CASCADE,
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    audio_storage_path TEXT,
    photo_storage_paths TEXT[],
    raw_transcript TEXT,
    ai_parsed_json JSONB,
    confidence_flags JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. DOCUMENTS (Angebote & Rechnungen)
CREATE TABLE documents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    job_id UUID REFERENCES jobs(id) ON DELETE SET NULL,
    customer_id UUID NOT NULL REFERENCES customers(id),
    
    doc_type TEXT NOT NULL, -- 'quote' (Angebot) or 'invoice' (Rechnung)
    doc_number TEXT NOT NULL, -- e.g. ANG-2026-0001, RE-2026-0001
    status TEXT NOT NULL DEFAULT 'draft', -- 'draft', 'sent', 'paid', 'canceled'
    
    date_issued DATE NOT NULL DEFAULT CURRENT_DATE,
    date_due DATE,
    delivery_period TEXT, -- 'Leistungszeitraum' (Mandatory in Germany)
    
    -- Monetary amounts stored in CENTS
    subtotal_labor_cents INT DEFAULT 0,    -- Lohnanteil nach § 35a EStG
    subtotal_material_cents INT DEFAULT 0, -- Materialanteil
    total_net_cents INT NOT NULL,
    vat_amount_cents INT NOT NULL,
    total_gross_cents INT NOT NULL,
    
    line_items JSONB NOT NULL,
    pdf_url TEXT,
    
    -- Phase 4 Compliance fields
    is_gobd_locked BOOLEAN DEFAULT FALSE,
    gobd_locked_at TIMESTAMPTZ,
    zugferd_xml_metadata JSONB,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    CONSTRAINT unique_doc_number_per_business UNIQUE (business_id, doc_type, doc_number)
);

CREATE INDEX idx_documents_business ON documents(business_id);

-- ROW LEVEL SECURITY (RLS)
ALTER TABLE businesses ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE capture_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION get_user_business_id() 
RETURNS UUID AS $$
  SELECT business_id FROM profiles WHERE id = auth.uid() LIMIT 1;
$$ LANGUAGE sql SECURITY DEFINER STABLE;

CREATE POLICY "Access own business" ON businesses FOR ALL USING (id = get_user_business_id());
CREATE POLICY "Access own customers" ON customers FOR ALL USING (business_id = get_user_business_id());
CREATE POLICY "Access own jobs" ON jobs FOR ALL USING (business_id = get_user_business_id());
CREATE POLICY "Access own capture logs" ON capture_logs FOR ALL USING (business_id = get_user_business_id());
CREATE POLICY "Access own documents" ON documents FOR ALL USING (business_id = get_user_business_id());
```

---

## 4. Flutter Project Structure & Offline-Sync Architecture

### 4.1 Feature-First Folder Structure
```
zunft_app/
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── core/
│   │   ├── constants/            # German VAT, units (Std, Stk, m, pauschal)
│   │   ├── database/             # Drift (SQLite) schema & DAOs
│   │   │   ├── app_database.dart
│   │   │   ├── tables/           # Local mirrors of jobs, customers, documents
│   │   │   └── outbox_table.dart # Offline sync queue
│   │   ├── network/
│   │   │   ├── supabase_client.dart
│   │   │   └── sync_manager.dart # Outbox queue background runner
│   │   ├── theme/                # High-contrast craft theme (usable in daylight)
│   │   │   ├── app_colors.dart
│   │   │   └── app_theme.dart
│   │   └── utils/
│   │       ├── currency_formatter.dart # 1.250,50 €
│   │       └── date_formatter.dart     # dd.MM.yyyy
│   │
│   ├── features/
│   │   ├── auth/                 # Login & Business Setup Wizard
│   │   ├── capture/              # Voice recording, waveform UI, photo picker
│   │   ├── review/               # AI review screen (Edit items, check § 35a split)
│   │   │   ├── presentation/
│   │   │   │   ├── review_draft_screen.dart
│   │   │   │   ├── components/line_item_card.dart
│   │   │   │   └── components/tax_summary_card.dart
│   │   │   └── controllers/draft_review_controller.dart
│   │   ├── documents/            # DIN 5008 PDF template, preview, native share
│   │   │   ├── pdf_generator/
│   │   │   │   └── din_5008_invoice_template.dart
│   │   │   └── presentation/document_detail_screen.dart
│   │   ├── jobs/                 # Job list & status pipeline
│   │   ├── customers/            # Customer directory & quick search
│   │   └── settings/             # Business profile, rates, Steuernummer, IBAN
```

### 4.2 Offline Outbox Pattern (Drift SQLite)
```
[User records voice / edits quote]
               │
               ▼
      [Drift Local SQLite] ──> UI updates immediately (0ms delay)
               │
               ▼
     [sync_outbox Table] (Action: UPLOAD_AUDIO / SAVE_DRAFT / ISSUE_DOC)
               │
               ▼
      [Connectivity Check]
      ├── Offline  ──> Retry on network change
      └── Online   ──> [SyncManager Worker]
                            ├── 1. Upload audio to Supabase Storage
                            ├── 2. Invoke Edge Function 'process-capture'
                            ├── 3. Upsert records to Supabase Postgres
                            └── 4. Delete item from sync_outbox
```

---

## 5. Capture → Transcribe → AI-Parse Pipeline & Review UX

### 5.1 Supabase Edge Function (`process-capture`)
Calls Deepgram Nova-2 German for STT and Claude 3.5 Sonnet with Tool Calling for deterministic JSON output.

```typescript
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  const { jobId, audioStoragePath } = await req.json();
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  // 1. Fetch business context & existing customers for fuzzy matching
  const { data: job } = await supabase
    .from("jobs")
    .select("business_id, businesses(*)")
    .eq("id", jobId)
    .single();

  const { data: customers } = await supabase
    .from("customers")
    .select("id, name, city")
    .eq("business_id", job.business_id);

  // 2. Transcribe with Deepgram Nova-2 German
  const { data: audioBlob } = await supabase.storage
    .from("captures")
    .download(audioStoragePath);

  const deepgramRes = await fetch(
    "https://api.deepgram.com/v1/listen?model=nova-2&language=de&smart_format=true&keywords=Steckdose:2,Kabel:2,Unterputz:2,Gira:2,WAGO:2",
    {
      method: "POST",
      headers: {
        "Authorization": `Token ${Deno.env.get("DEEPGRAM_API_KEY")!}`,
        "Content-Type": "audio/m4a"
      },
      body: audioBlob,
    }
  );
  const transcript = (await deepgramRes.json()).results?.channels[0]?.alternatives[0]?.transcript || "";

  // 3. Prompt Claude 3.5 Sonnet with Tool Calling
  const hourlyRateCents = job.businesses.default_hourly_rate_cents || 6500;
  const systemPrompt = `Du bist der KI-Backoffice-Assistent "Zunft" für einen deutschen Handwerksbetrieb (${job.businesses.trade_category}).
Wandle die Sprachnotiz in ein sauberes deutsches Angebot oder eine Rechnung um.

REGELN:
1. Trenne IMMER Arbeitszeit (Lohnkosten nach § 35a EStG) und Material.
2. Wenn keine Stundenzahl genannt ist, schätze plausibel oder setze "requires_confirmation: true".
3. Standard-Stundensatz: ${(hourlyRateCents / 100).toFixed(2)} €/Std.
4. MwSt: 19%.
5. Bekannte Kunden zum Abgleich: ${JSON.stringify(customers)}.`;

  const claudeRes = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": Deno.env.get("ANTHROPIC_API_KEY")!,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: "claude-3-5-sonnet-20241022",
      max_tokens: 1500,
      system: systemPrompt,
      tools: [{
        name: "save_handwerk_draft",
        description: "Speichert das strukturierte Angebot oder die Rechnung",
        input_schema: {
          type: "object",
          properties: {
            customer_match: {
              type: "object",
              properties: {
                matched_customer_id: { type: ["string", "null"] },
                extracted_name: { type: "string" },
                confidence: { type: "string", enum: ["exact", "fuzzy", "new"] }
              },
              required: ["extracted_name", "confidence"]
            },
            document_type: { type: "string", enum: ["quote", "invoice"] },
            title: { type: "string" },
            line_items: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  type: { type: "string", enum: ["labor", "material", "flat_fee"] },
                  description: { type: "string" },
                  quantity: { type: "number" },
                  unit: { type: "string", enum: ["Std", "Stk", "m", "Pauschal"] },
                  unit_price_net_cents: { type: "integer" },
                  requires_confirmation: { type: "boolean" }
                },
                required: ["type", "description", "quantity", "unit", "unit_price_net_cents"]
              }
            },
            warnings: { type: "array", items: { type: "string" } }
          },
          required: ["customer_match", "document_type", "title", "line_items"]
        }
      }],
      tool_choice: { type: "tool", name: "save_handwerk_draft" },
      messages: [{ role: "user", content: `Sprachnotiz-Transkript:\n"${transcript}"` }]
    })
  });

  const claudeJson = await claudeRes.json();
  const toolCall = claudeJson.content?.find((c: any) => c.type === "tool_use");
  const parsedData = toolCall.input;

  // 4. Save to capture_logs
  await supabase.from("capture_logs").insert({
    job_id: jobId,
    business_id: job.business_id,
    audio_storage_path: audioStoragePath,
    raw_transcript: transcript,
    ai_parsed_json: parsedData,
    confidence_flags: { warnings: parsedData.warnings }
  });

  return new Response(JSON.stringify({ success: true, parsedData, transcript }), {
    headers: { "Content-Type": "application/json" }
  });
});
```

### 5.2 60-Second Review UI Specification
- **Audio Playback Header:** Play original voice note + collapsible German transcript.
- **Customer Assignment Bar:** Displays matched customer with confidence indicator (Green = exact match, Amber = new customer to save).
- **Line Items Split Table:**
  - Section 1: *Arbeitslohn (§ 35a EStG)* with hours and hourly rate.
  - Section 2: *Materialkosten* with item names and unit prices.
  - Amber badges on any item flagged with `requires_confirmation: true`.
- **Instant Numeric Editing:** Single tap opens a large, on-site friendly numpad for quick price/quantity adjustment.
- **Action Buttons:** "Angebot erstellen" (Quote) / "Rechnung erstellen" (Invoice).

---

## 6. Sized 6–8 Week Solo Developer Build Plan

### Sprint 1: Foundation & Local Architecture (Weeks 1–2)
* **Task 1.1:** Setup Supabase EU project, apply PostgreSQL schema, RLS policies, and Storage buckets (`captures`, `documents`). *(Effort: 1 day)*
* **Task 1.2:** Initialize Flutter project, theme tokens (high-contrast German craft style), and routing. *(Effort: 2 days)*
* **Task 1.3:** Setup Drift SQLite database with tables for jobs, customers, documents, and `sync_outbox`. *(Effort: 3 days)*
* **Task 1.4:** Build `SyncManager` background runner to sync outbox queue with exponential retry backoff. *(Effort: 3 days)*
* **Task 1.5:** Build Business Profile & Settings screen (IBAN, Steuernummer, default hourly rate). *(Effort: 1 day)*

### Sprint 2: Capture & AI Pipeline (Weeks 3–4)
* **Task 2.1:** Implement voice recording UI with `record` package, M4A caching, haptic feedback, and audio preview. *(Effort: 2 days)*
* **Task 2.2:** Develop Supabase Edge Function `process-capture` (Deepgram Nova-2 + Claude 3.5 Sonnet Tool Calling). *(Effort: 3 days)*
* **Task 2.3:** Connect offline audio caching to background upload and Edge Function trigger. *(Effort: 2 days)*
* **Task 2.4:** Benchmark and refine prompt against 25 real-world German spoken craft voice notes. *(Effort: 3 days)*

### Sprint 3: Review UI & DIN 5008 PDF Generation (Weeks 5–6)
* **Task 3.1:** Build the 60-second review screen with § 35a labor/material separation and amber alert pills. *(Effort: 3 days)*
* **Task 3.2:** Build the DIN 5008 vector PDF invoice template using Flutter `pdf` (letterhead, fold marks, tax split table, bank details). *(Effort: 3 days)*
* **Task 3.3:** Integrate native share sheet to email or WhatsApp the generated PDF immediately. *(Effort: 1 day)*
* **Task 3.4:** Implement sequential, gapless document numbering logic (`ANG-YYYY-XXXX` and `RE-YYYY-XXXX`). *(Effort: 2 days)*

### Sprint 4: Polish, Customer Views & Pilot Distribution (Weeks 7–8)
* **Task 4.1:** Test offline edge cases (airplane mode capture, reconnect sync). *(Effort: 2 days)*
* **Task 4.2:** Build customer management screen (search, call, view past jobs/quotes). *(Effort: 2 days)*
* **Task 4.3:** Setup Fastlane & deploy to iOS TestFlight and Android Closed Testing track for 15 test businesses. *(Effort: 3 days)*
* **Task 4.4:** On-site user shadowing with 2–3 craftsmen in Hamburg. *(Effort: 2 days)*

---

## 7. Strategic Cuts for Phase 1 (What NOT to Build)

To deliver a rock-solid product in 6–8 weeks as a solo developer:

1. **Defer Flutter Web for Phase 1:** Focus 100% on **iOS & Android**. Craftsmen capture notes on their phones at the job site. Flutter Web can be activated later for desk-based office work.
2. **De-scope Photo OCR to Simple Image Attachments:** Visual parsing of messy fuse boxes or handwritten notes adds substantial prompt failure modes. Allow attaching photos as job documentation, but drive the draft from **voice**.
3. **No Multi-Master CRDT Sync:** Solo businesses use one primary phone. An **Outbox Queue (Last-Write-Wins)** avoids months of distributed conflict resolution logic.
4. **Defer In-App Stripe Billing to Week 9+:** For the initial 15 pilot businesses in Hamburg, offer a free 30-day pilot or invoice them manually. Do not spend week 3 debugging app-store subscription webhooks before validating core utility.
5. **Defer Strict GoBD WORM Immutability to Phase 4:** Provide sequential numbering and lock finalized documents against edits, but defer full cryptographic hash-chain audit logging until product-market fit is proven.

---

## 8. Definition of "Done" for Phase 1

A craftsman in Hamburg can:
1. Open the app on an iPhone or Android device.
2. Tap a single large button and speak in German: *"Kunde Müller, neue Steckdose im Keller installiert, 2 Stunden gebraucht, Material Gira Doppelsteckdose ca. 40 Euro."*
3. See an AI-generated draft within 5 seconds with:
   - Customer assigned (or flagged as new)
   - Labor: 2.0 hrs × 65,00 € = 130,00 € (categorized under § 35a EStG)
   - Material: 1× Gira Doppelsteckdose = 40,00 €
   - 19% MwSt. computed accurately
4. Adjust any field in under 15 seconds if needed.
5. Generate a professional DIN 5008 PDF and send it to the customer via WhatsApp or Email.
6. Perform all steps even when in an offline basement, syncing seamlessly once back in network range.
