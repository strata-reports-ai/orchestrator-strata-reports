# StrataReport AI — MVP Product Requirements Document (PRD)

**Product Name**: StrataReport AI
**Version**: 2.1 (MVP, refined)
**Target Launch**: 10–14 weeks from kickoff (solo dev, nights/weekends adjusted)
**Author**: [Your Name]
**Last Updated**: May 25, 2026
**Status**: Draft for solo build

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Problem Statement & Market Context](#2-problem-statement--market-context)
3. [Users & Personas](#3-users--personas)
4. [Product Scope](#4-product-scope)
5. [Success Metrics & KPIs](#5-success-metrics--kpis)
6. [Architecture & Tech Stack](#6-architecture--tech-stack)
7. [Data Model](#7-data-model)
8. [Epics & User Stories](#8-epics--user-stories)
9. [AI / LLM Design](#9-ai--llm-design)
10. [API Specification](#10-api-specification)
11. [Non-Functional Requirements & SLOs](#11-non-functional-requirements--slos)
12. [Security, Privacy & Compliance](#12-security-privacy--compliance)
13. [Observability & Telemetry](#13-observability--telemetry)
14. [Risks & Mitigations](#14-risks--mitigations)
15. [Onboarding & First-Run Experience](#15-onboarding--first-run-experience)
16. [Build Sequencing & Roadmap](#16-build-sequencing--roadmap)
17. [Open Questions & Assumptions](#17-open-questions--assumptions)
18. [Definition of Done & Launch Checklist](#18-definition-of-done--launch-checklist)

---

## 1. Executive Summary

StrataReport AI is a SaaS tool that generates professional, owner-facing quarterly performance reports for short-term rental (STR) property managers. The MVP turns messy operational data (PMS exports, expense CSVs, guest reviews) into a polished 4–8 page PDF in under two minutes, replacing 10–20 hours of manual spreadsheet wrangling per reporting cycle.

**The wedge**: Existing PMS platforms (Guesty, Hostfully, OwnerRez) produce data dumps, not narrative reports. Owners don't want dashboards — they want a quarterly story that justifies the management fee. StrataReport fills that gap with AI-generated narrative bound to verified numbers.

**MVP bet**: One report type (Quarterly Owner Performance), CSV-first ingestion, no PMS integrations. Prove that a single owner-ready PDF is worth $20–50/property/month before building integrations.

**Solo-dev constraints driving design**:
- Azure-first because of existing familiarity (don't experiment on new infra mid-build).
- Managed services over self-hosted (Azure Functions, Flexible Server, Blob) to minimize ops.
- No mobile-native, no real-time features, no background workers beyond Azure Functions triggers.
- LLM cost ceiling: report generation must stay under **$0.25/report** in API costs.

---

## 2. Problem Statement & Market Context

### 2.1 The Problem

STR property managers face a recurring pain point: **the owner update**. Owners expect periodic reports proving their property is being managed well, but the data lives in 4–8 disconnected systems:

- **PMS** (Guesty, Hostaway, Hostfully): bookings, ADR, occupancy
- **Channel data** (Airbnb, Vrbo, Booking.com): reviews, ratings
- **Accounting** (QuickBooks, Xero, or spreadsheets): expenses, owner statements
- **Ops tools** (Breezeway, Properly, Turno): cleaning, inspections, maintenance
- **Guest comms** (Hospitable, custom): complaints, escalations

Existing solutions either (a) produce raw data exports requiring manual narrative, or (b) require deep integration and 6-figure annual contracts (Guesty Pro, etc.). Mid-market managers (3–30 properties) are stuck doing this manually in Excel + Word.

### 2.2 Why Now

- LLMs are finally good enough at structured summarization with low hallucination when bound to source data.
- STR oversupply (2022–2025) means owners are scrutinizing manager performance more aggressively. Churn risk is higher.
- The Hostaway/Guesty/Hostfully API ecosystem is mature enough that *post-MVP* integrations are cheap to add.

### 2.3 Competitive Landscape (brief)

| Tool             | Reports?         | Gap StrataReport fills                            |
| ---------------- | ---------------- | ------------------------------------------------- |
| Guesty           | Data export only | No AI narrative; expensive                         |
| Hostfully        | Owner statements | Financial-only, no operational/guest synthesis     |
| OwnerRez         | Basic statements | No narrative, no review synthesis                  |
| PriceLabs        | None (pricing)   | Different category                                 |
| Custom Excel     | Manual           | What we're replacing                               |

**Differentiation**: AI-generated narrative + multi-source synthesis + zero-integration cold start (CSV upload). Speed of value: 10 minutes from signup to first report.

---

## 3. Users & Personas

### 3.1 Persona A — "Maria the Co-Host" (Primary)

- **Profile**: 38, ex-hospitality. Manages 12 properties across 4 owners in Asheville, NC.
- **Tools**: Hostaway, QuickBooks Self-Employed, Turno, iMessage with owners.
- **Pain**: Spends one full Saturday per month writing owner emails with stats pulled from 3 systems. Loses sleep before quarterly reviews.
- **Goal**: Send each owner a 5-page PDF every quarter that looks professional and answers "is my property doing well?" without her writing prose.
- **Willingness to pay**: $25–40/property/month if it saves the Saturday.
- **Tech comfort**: Comfortable with spreadsheets and CSV exports. Will not write SQL or call APIs.

### 3.2 Persona B — "Derek the Boutique Manager" (Primary)

- **Profile**: 45, runs a 25-property boutique management company in Sevierville/Gatlinburg.
- **Tools**: Guesty, Xero, Breezeway, plus 2 admin assistants.
- **Pain**: Has an assistant who spends ~15 hrs/cycle building reports in Canva from data dumps. Cost of that labor ≈ $400/cycle.
- **Goal**: Standardize report quality across all owners and reduce the assistant's load.
- **Willingness to pay**: $50–80/property/month at scale, more if branded/white-label (post-MVP).
- **Tech comfort**: Will not touch the tool himself — his assistant will.

### 3.3 Persona C — "Sam the Solo Owner" (Secondary)

- **Profile**: Owns 4 STR cabins, self-manages.
- **Pain**: Wants to professionalize for tax/lender purposes; not for "owner reporting" but self-documentation and quarterly review.
- **Note**: Useful for marketing and beta, but not the core wedge. Designed-for-but-not-optimized-for in MVP.

### 3.4 Anti-Personas (explicitly not building for)

- Large enterprise managers (100+ properties) — need integrations and SSO we won't build.
- Long-term residential property managers — different data, different report needs.
- Hotels — different category entirely.

---

## 4. Product Scope

### 4.1 In Scope (MVP)

| Capability                  | Detail                                                                  |
| --------------------------- | ----------------------------------------------------------------------- |
| Auth                        | Email/password + Microsoft Entra SSO; email verification                |
| Multi-tenancy               | Tenant-per-company; full row-level isolation                            |
| Properties CRUD             | Create, edit, soft-delete properties                                    |
| CSV ingestion               | Revenue, Expenses, Tasks, Reviews, Inspections                          |
| One report type             | Quarterly Owner Performance Report (QOPR)                               |
| AI narrative generation     | Claude Sonnet 4.6 (primary), GPT-4o (fallback)                          |
| PDF rendering               | QuestPDF, professional 4–8 page layout                                  |
| Report history              | List, preview, re-download, regenerate                                  |
| Dashboard                   | Recent activity, KPIs, quick actions                                    |
| **Mobile-responsive web**   | **First-class mobile UX (360px+); all primary flows usable on a phone. No native app.** |
| Billing                     | Stripe — per-property monthly subscription (see §4.3)                   |

### 4.2 Explicitly Out of Scope (MVP)

- Direct PMS / accounting integrations (Guesty, Hostaway, QuickBooks, Xero)
- Monthly or annual report variants
- Automated email distribution to owners
- Owner portal / self-serve owner access
- White-labeling / custom branding per tenant
- Multi-user-per-tenant with roles & permissions (single user per tenant in MVP)
- Mobile native app
- Slack / Teams notifications
- Custom report templates / builder
- Real-time data sync
- Multi-currency, multi-language

### 4.3 Pricing Hypothesis (to validate during beta)

- **Starter**: $29/mo, up to 5 properties, 4 reports/quarter included.
- **Pro**: $79/mo, up to 20 properties, 20 reports/quarter.
- **Scale**: $199/mo, up to 50 properties, unlimited reports.

Overages: $2/report beyond included quota. Stripe metered billing for overage.

**Decision deferred**: Free tier (1 property, 1 report) — likely yes for beta funnel, deferred until launch metrics show CAC.

---

## 5. Success Metrics & KPIs

### 5.1 MVP Launch Criteria (must-hit before public launch)

| Metric                                    | Target                          |
| ----------------------------------------- | ------------------------------- |
| End-to-end report generation              | < 120 seconds (p95)             |
| AI cost per report                        | < $0.25                         |
| Report sent-to-owner rate                 | ≥ 70% (of generated reports)    |
| Beta users completing full onboarding     | ≥ 10                            |
| Reports generated by beta users           | ≥ 30 total                      |
| Critical bug count at launch              | 0                               |

### 5.2 Leading Indicators (track weekly)

- Signups → first property created (target: ≥ 80%)
- First property → first CSV uploaded (target: ≥ 60%)
- First CSV → first report generated (target: ≥ 70%)
- Report generated → report downloaded (target: ≥ 90%)
- Report downloaded → owner feedback recorded (manual interview signal)

### 5.3 Lagging Indicators (track monthly)

- MRR
- Properties under management (PUM) in the system
- Reports generated per active tenant
- Churn (logo and revenue)
- LLM API spend per active tenant

### 5.4 North Star Metric

**Weekly Reports Generated** — single number that captures whether the product is delivering value at frequency. If this grows, everything else follows.

---

## 6. Architecture & Tech Stack

### 6.1 Stack Summary

| Layer            | Choice                                              | Rationale                                                                             |
| ---------------- | --------------------------------------------------- | ------------------------------------------------------------------------------------- |
| Frontend         | React 18 + Vite + TypeScript, mobile-responsive from day one | Familiar; Vite faster than CRA; TS keeps a solo dev from shooting their foot. Designed mobile-first — see §11.4. |
| Frontend hosting | Azure Static Web Apps (Standard plan)               | Static SPA hosting — no SSR, no containers, no app service. Built-in CDN, custom domains, free SSL. Functions API exposed via SWA's `/api` route bridge or as a separate Functions App. |
| UI library       | Material-UI v6                                      | Production-quality components, accessible by default, responsive primitives (`Grid`, `Stack`, `useMediaQuery`). Fits PM/business-tool aesthetic. |
| State / API      | Redux Toolkit + RTK Query                           | Auto-caching, optimistic updates, generated hooks. Less boilerplate than raw Redux.   |
| Routing          | React Router v6                                     |                                                                                       |
| Backend          | .NET 10 (LTS, supported through Nov 2028) on Azure Functions v4, isolated worker | LTS is the safe pick for solo maintenance. Isolated worker = clean DI, easier testing. |
| API style        | HTTP-triggered Functions, REST/JSON                 | No GraphQL — adds complexity solo devs don't need.                                    |
| Auth             | Microsoft Entra External ID (B2C successor)         | Managed; supports SSO + email/password; cheaper than rolling own.                     |
| Database         | Azure Database for PostgreSQL Flexible Server — **Burstable B1ms** for dev/staging, **Burstable B2s** for prod | Mature; RLS is native; cheap at small scale. B1ms (~$13/mo, 1 vCPU / 2 GB) is fine for non-prod. B2s (~$50/mo, 2 vCPU / 4 GB) for prod gives headroom; scale up before public launch. See §11.3 for scale-up triggers. |
| Data access      | **Hybrid: EF Core 10 + Dapper**                     | EF Core handles migrations, CRUD writes, and simple reads (~80% of code). Dapper handles hot read paths: report context aggregation (Story 4.2), filtered list queries, anything with multi-table joins or aggregations. Skips EF's change tracker and materialization overhead where it matters. |
| Storage          | Azure Blob Storage                                  | Raw CSVs, generated PDFs. Hot tier; lifecycle policy to cool after 90 days.           |
| LLM              | Anthropic API (Claude Sonnet 4.6) — primary; OpenAI GPT-4o — fallback | Sonnet 4.6 is current price/quality sweet spot. Direct API to avoid Azure OpenAI quota constraints. |
| PDF generation   | QuestPDF (community license, fits revenue < $1M)    | Pure C#, no Chromium, deterministic layouts.                                          |
| Charts in PDF    | ScottPlot 5 → PNG embed                             | Pure C#, no headless browser; sufficient for bar/line charts.                         |
| Background jobs  | Azure Functions queue-triggered                     | Avoid Hangfire / dedicated worker host for MVP.                                       |
| Queues           | Azure Storage Queues (sufficient) — Service Bus only if scale demands | Queues are cheap; Service Bus is overkill at MVP volume.                              |
| Email            | Postmark (transactional)                            | Better deliverability than SendGrid free tier; cheap.                                 |
| Payments         | Stripe                                              | Industry standard; one-day integration.                                               |
| CI/CD            | GitHub Actions → Azure                              | Free for public repos; fine for private at this scale.                                |
| Observability    | Azure Application Insights + Serilog                | Bundled with Functions; good enough for solo ops.                                     |
| Secrets          | Azure Key Vault, referenced via Functions app settings |                                                                                       |
| IaC              | Bicep (Azure-native)                                | Simpler than Terraform for an all-Azure stack.                                        |

### 6.2 Architecture Diagram (textual)

```
┌─────────────────┐         ┌─────────────────────────────┐
│  React SPA      │  HTTPS  │  Azure Static Web Apps      │
│  (MUI + RTKQ)   ├────────►│  (Standard plan, CDN edge)  │
│  mobile-first   │         │                             │
└────────┬────────┘         └─────────────────────────────┘
         │ JWT (Entra)
         ▼
┌────────────────────────────────────────────────────────┐
│  Azure Functions (isolated worker, .NET 10)            │
│  ┌──────────────────────────────────────────────────┐  │
│  │  HTTP triggers: /api/*                           │  │
│  │  Queue triggers: report-generation, csv-process  │  │
│  │  Timer triggers: cleanup, billing reconciliation │  │
│  │  Data access: EF Core (writes) + Dapper (reads)  │  │
│  └──────────────────────────────────────────────────┘  │
└──┬─────────────┬─────────────┬─────────────┬───────────┘
   │             │             │             │
   ▼             ▼             ▼             ▼
┌──────┐  ┌──────────┐  ┌────────────┐  ┌─────────────┐
│ PG   │  │ Blob     │  │ Anthropic  │  │ Stripe API  │
│ (RLS)│  │ Storage  │  │ API        │  └─────────────┘
│ B1ms │  └──────────┘  └────────────┘
│ /B2s │
└──────┘
```

### 6.3 Key Architectural Decisions

- **No multi-region** for MVP. Single region (East US 2 or Central US given the NC base). Document the DR steps but don't pay for warm standby.
- **Mobile-first responsive web, no native app.** The product is designed and built for phones first (360–414px viewport), then enhanced for tablet (768px+) and desktop (1024px+). Property managers run their businesses from their phones; the SPA must work there without "view on desktop" prompts. See §11.4 for breakpoints and component patterns.
- **Static Web Apps as the only frontend host.** No App Service, no container, no SSR. Bundles published to SWA; SWA proxies `/api/*` to the Functions app for same-origin cookies. Custom domain + free managed SSL.
- **Hybrid data access — EF Core + Dapper.** EF Core owns the schema (migrations, model snapshot), all writes, and reads of single aggregates. Dapper is reserved for read paths where shape or throughput matters: report context aggregation (multi-table aggregates across 5 detail tables), property list with last-import/last-report joins, and report history filtering. Rule of thumb: if the query has a `GROUP BY`, multiple `JOIN`s, or returns a custom projection, use Dapper. Both share the same connection string and connection pool.
- **DB sizing policy.** Start every non-prod environment on Burstable B1ms (~$13/mo). Production launches on B2s (~$50/mo). Scale-up triggers documented in §11.3 — do not pre-scale.
- **Asynchronous report generation** via queue trigger. The HTTP endpoint returns `202 Accepted` with a `reportId`. The frontend polls (or uses SignalR — but defer SignalR for MVP, polling is fine).
- **Tenant isolation via PostgreSQL RLS**, not just application-level checks. Belt-and-suspenders for the worst class of bugs. Applies to both EF Core and Dapper paths (the GUC is set on the open connection, before any query runs).
- **No ESM / Edge / Workers** anywhere. Cold start budget is tight on Functions Consumption plan — consider Functions Premium (EP1) post-MVP if cold starts hurt UX, but accept them at MVP.

---

## 7. Data Model

### 7.1 Schema (PostgreSQL)

All tables have `tenant_id UUID NOT NULL`, `created_at TIMESTAMPTZ DEFAULT NOW()`, `updated_at TIMESTAMPTZ DEFAULT NOW()`, and a `deleted_at TIMESTAMPTZ` for soft deletes. RLS policies use `current_setting('app.current_tenant_id')` set by the Functions middleware at the start of each request.

#### `tenants`
```
id              UUID PK
name            TEXT NOT NULL
stripe_customer_id  TEXT
plan            TEXT  -- 'starter' | 'pro' | 'scale' | 'beta'
status          TEXT  -- 'active' | 'past_due' | 'cancelled'
trial_ends_at   TIMESTAMPTZ
```

#### `users`
```
id              UUID PK
tenant_id       UUID FK -> tenants.id
entra_object_id TEXT UNIQUE  -- maps to Entra subject claim
email           TEXT UNIQUE NOT NULL
display_name    TEXT
role            TEXT  -- 'owner' (MVP has one role only; reserved for future)
last_login_at   TIMESTAMPTZ
```

#### `properties`
```
id                      UUID PK
tenant_id               UUID FK
name                    TEXT NOT NULL
address_line1           TEXT
city                    TEXT
state                   TEXT
postal_code             TEXT
country_code            TEXT DEFAULT 'US'
units                   INTEGER DEFAULT 1
owner_name              TEXT
owner_email             TEXT
management_start_date   DATE
timezone                TEXT DEFAULT 'America/New_York'
currency_code           TEXT DEFAULT 'USD'
external_pms_id         TEXT  -- nullable, for future PMS integrations
notes                   TEXT
```

#### `imports`
```
id                  UUID PK
tenant_id           UUID FK
property_id         UUID FK NULLABLE  -- some imports may be tenant-wide
import_type         TEXT  -- 'revenue' | 'expenses' | 'tasks' | 'reviews' | 'inspections'
source_filename     TEXT
blob_path           TEXT  -- raw file location in Blob Storage
status              TEXT  -- 'pending' | 'processing' | 'succeeded' | 'failed' | 'partial'
records_total       INTEGER
records_imported    INTEGER
records_skipped     INTEGER
error_summary       TEXT
column_mapping      JSONB  -- snapshot of resolved column mapping
checksum_sha256     TEXT  -- for idempotency
uploaded_by_user_id UUID FK
```

#### `revenue_records`
```
id                  UUID PK
tenant_id           UUID FK
property_id         UUID FK
import_id           UUID FK
booking_external_id TEXT  -- platform's booking ID, for idempotency
platform            TEXT  -- 'airbnb' | 'vrbo' | 'booking' | 'direct' | 'other'
checkin_date        DATE
checkout_date       DATE
nights              INTEGER
gross_revenue       NUMERIC(12,2)
cleaning_fee        NUMERIC(12,2)
platform_fee        NUMERIC(12,2)
host_fee            NUMERIC(12,2)
net_revenue         NUMERIC(12,2)
guest_name_hash     TEXT  -- hashed; we don't store guest PII
currency_code       TEXT DEFAULT 'USD'

UNIQUE(tenant_id, property_id, booking_external_id)
```

#### `expense_records`
```
id              UUID PK
tenant_id       UUID FK
property_id     UUID FK
import_id       UUID FK
expense_date    DATE
category        TEXT  -- 'cleaning' | 'maintenance' | 'utilities' | 'supplies' | 'fees' | 'other'
vendor          TEXT
description     TEXT
amount          NUMERIC(12,2)
currency_code   TEXT DEFAULT 'USD'
external_ref    TEXT  -- e.g., QuickBooks transaction ID
```

#### `task_records`
```
id              UUID PK
tenant_id       UUID FK
property_id     UUID FK
import_id       UUID FK
task_type       TEXT  -- 'cleaning' | 'maintenance' | 'inspection' | 'turnover' | 'other'
scheduled_at    TIMESTAMPTZ
completed_at    TIMESTAMPTZ
status          TEXT  -- 'completed' | 'missed' | 'late' | 'cancelled'
assignee        TEXT
notes           TEXT
external_ref    TEXT
```

#### `review_records`
```
id              UUID PK
tenant_id       UUID FK
property_id     UUID FK
import_id       UUID FK
platform        TEXT
review_date     DATE
rating          NUMERIC(3,2)  -- 0.00 to 5.00
review_text     TEXT
guest_name_hash TEXT
response_text   TEXT
external_ref    TEXT
```

#### `inspection_records`
```
id              UUID PK
tenant_id       UUID FK
property_id     UUID FK
import_id       UUID FK
inspection_date DATE
inspector       TEXT
score           NUMERIC(5,2)
issues_found    INTEGER
issues_resolved INTEGER
notes           TEXT
external_ref    TEXT
```

#### `reports`
```
id                  UUID PK
tenant_id           UUID FK
property_id         UUID FK
report_type         TEXT  -- 'quarterly_owner' (only one for MVP)
period_start        DATE
period_end          DATE
status              TEXT  -- 'queued' | 'generating' | 'succeeded' | 'failed'
ai_model            TEXT  -- e.g. 'claude-sonnet-4-6'
ai_input_tokens     INTEGER
ai_output_tokens    INTEGER
ai_cost_usd         NUMERIC(8,4)
generation_ms       INTEGER
pdf_blob_path       TEXT
json_payload        JSONB  -- the AI's structured output, for re-rendering
error_message       TEXT
generated_by_user_id UUID FK

UNIQUE(tenant_id, property_id, report_type, period_start, period_end)
  -- enforces "no duplicate reports for same parameters"; regenerate replaces
```

#### `audit_log` (append-only)
```
id              UUID PK
tenant_id       UUID FK NULLABLE
user_id         UUID FK NULLABLE
action          TEXT  -- 'login', 'property.create', 'report.generate', etc.
entity_type     TEXT
entity_id       UUID
metadata        JSONB
ip_address      INET
user_agent      TEXT
occurred_at     TIMESTAMPTZ DEFAULT NOW()
```

### 7.2 RLS Policy Sketch

```sql
ALTER TABLE properties ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_properties ON properties
  FOR ALL
  USING (tenant_id = current_setting('app.current_tenant_id')::uuid)
  WITH CHECK (tenant_id = current_setting('app.current_tenant_id')::uuid);

-- Repeat for every tenant-scoped table.
-- Functions middleware sets the GUC at the start of each connection:
--   SET LOCAL app.current_tenant_id = '<uuid>';
```

### 7.3 Indexes (initial)

- `properties (tenant_id, deleted_at)` partial WHERE deleted_at IS NULL
- `revenue_records (tenant_id, property_id, checkin_date)`
- `expense_records (tenant_id, property_id, expense_date)`
- `task_records (tenant_id, property_id, scheduled_at)`
- `review_records (tenant_id, property_id, review_date)`
- `reports (tenant_id, property_id, period_start, period_end)`
- `imports (tenant_id, status, created_at DESC)`

---

## 8. Epics & User Stories

Story format: `As a <persona>, I want <outcome>, so that <reason>.`
Each story includes: AC = Acceptance Criteria, T = T-shirt estimate (S/M/L/XL), Dep = Dependencies.

### Epic 1: Foundation & Authentication

#### Story 1.1 — Sign up & log in
**As Maria, I want to sign up with email or Microsoft SSO, so that I can start using the product immediately.**

**AC**:
- Email/password registration with email verification (Postmark, 24-hour token TTL).
- Microsoft Entra External ID SSO via OAuth/OIDC.
- Tenant auto-provisioned on first signup; user marked as tenant owner.
- JWT in httpOnly + Secure + SameSite=Lax cookie. Refresh token rotation.
- Rate limit: 10 auth attempts per IP per minute (Functions middleware).
- Logout endpoint invalidates refresh token server-side.
- Post-signup redirect to `/onboarding/welcome`.

**T**: L · **Dep**: none

#### Story 1.2 — Multi-tenancy enforcement
**As the developer, I want strict tenant isolation enforced at the DB level, so that a bug in middleware cannot leak data across tenants.**

**AC**:
- Every tenant-scoped table has `tenant_id` and RLS enabled.
- Middleware sets `app.current_tenant_id` GUC at the start of each request.
- Integration test: pretend to be Tenant A, attempt direct SQL to read Tenant B's properties — must return zero rows.
- Audit log entry written for every authenticated request (entity_type='request').

**T**: M · **Dep**: 1.1

#### Story 1.3 — Password reset & account management
**As Maria, I want to reset my password and update my profile, so that I'm not locked out and my info stays current.**

**AC**:
- Password reset via email link (Postmark), 1-hour token TTL.
- Profile page: display name, email (change requires re-verification), password change.
- Tenant settings page: company name, default timezone, default currency.

**T**: M · **Dep**: 1.1

### Epic 2: Properties Management

#### Story 2.1 — Create & edit properties
**As Maria, I want to add my properties with the info needed for reporting, so that I can generate reports against them.**

**AC**:
- Fields per §7.1 `properties` table.
- Address with optional autocomplete (Mapbox or Google Places — defer to post-MVP, manual entry for now).
- Validation: name required, owner_email valid format if provided, units ≥ 1, management_start_date not in future.
- Soft delete (sets `deleted_at`); deleted properties hidden from default list but recoverable for 30 days.
- Hard delete only via cleanup job after 30 days.

**T**: M · **Dep**: 1.2

#### Story 2.2 — Property list view
**As Maria, I want to see all my properties at a glance, so that I can find and act on the right one quickly.**

**AC**:
- Table with columns: Name, City, Owner, Units, Last Report, Last Import, Actions.
- Search by name/address/owner.
- Filter by city, owner.
- Sort by name, last report date, last import date.
- Pagination if > 25 properties.
- RTK Query caching; optimistic updates on edit/delete.
- Empty state with "Add your first property" CTA.

**T**: M · **Dep**: 2.1

### Epic 3: Data Ingestion

#### Story 3.1 — Upload CSV
**As Maria, I want to upload CSVs from my PMS and accounting tools, so that the report has the data it needs.**

**AC**:
- Drag-and-drop UI with file picker fallback.
- Five import types: Revenue, Expenses, Tasks, Reviews, Inspections.
- Max file size 10 MB; rejection with friendly error if exceeded.
- File type validation: `.csv` or `.tsv` only by extension AND content sniff.
- Raw file uploaded to Blob via SAS-token-protected direct upload (avoids Functions size limits).
- Progress bar shows upload progress.
- After upload, file is queued for parsing (Story 3.2); user sees "Processing…" state.

**T**: L · **Dep**: 2.1

#### Story 3.2 — Parse & normalize CSV
**As the developer, I want robust CSV parsing that tolerates real-world variations, so that imports succeed without bespoke per-customer engineering.**

**AC**:
- Queue-triggered Function picks up new uploads.
- Uses CsvHelper with auto-mapping + fuzzy column matching.
- Predefined column synonyms per import type (e.g., for Revenue: `Reservation ID | Booking ID | Confirmation Code` → `booking_external_id`).
- If required columns can't be resolved, status → `failed` with actionable error: "Could not find a column for 'Booking ID'. Expected one of: ..."
- Idempotency: `(tenant_id, property_id, booking_external_id)` unique on revenue; checksum on file prevents same file being processed twice.
- Partial success allowed: rows that fail validation are skipped and logged; status → `partial` with count.
- Each ingestion writes one row to `imports` and N rows to the appropriate detail table.
- Per-import processing time logged.

**T**: XL · **Dep**: 3.1

**Notes**:
- Document the expected schemas for each import type in the help section.
- Provide downloadable template CSVs for each type.
- Solo-dev shortcut: start with Hostaway + QuickBooks + Airbnb export formats. Add others on demand.

#### Story 3.3 — Import history
**As Maria, I want to see what I've imported and what failed, so that I can fix problems.**

**AC**:
- `/imports` page table: File Name, Type, Property, Uploaded At, Status, Records, Actions.
- Status badge: pending/processing/succeeded/failed/partial.
- Click row → drawer with full error details, sample failed rows, column mapping used.
- "Re-process" action for failed imports (after the user fixes the file and re-uploads).
- "Download original file" link.

**T**: M · **Dep**: 3.2

### Epic 4: Report Generation

#### Story 4.1 — Generate report UI
**As Maria, I want a one-screen flow to generate a quarterly report, so that I don't have to think about how the sausage is made.**

**AC**:
- Form: Property (dropdown, searchable) + Quarter (Q1/Q2/Q3/Q4) + Year picker.
- Optional fields: custom note (max 500 chars, appears in the report's "From your manager" callout), include comparison to previous quarter (default on).
- Pre-flight check: warn if no data exists for the period; block if all data sources are empty.
- "Generate" button posts to `/api/reports/generate`, gets back `reportId`, polls `/api/reports/{id}` every 3s.
- Progress states shown to user: Queued → Aggregating data → Generating narrative → Rendering PDF → Done.
- Duplicate prevention: if a non-failed report already exists for the same (property, type, period), prompt "Regenerate? This will replace the existing report."
- Success → toast + auto-redirect to report detail page with download button.
- Failure → toast with error reason + "Try again" CTA.

**T**: L · **Dep**: 4.2, 4.3, 5.1

#### Story 4.2 — Aggregate report context
**As the developer, I want to assemble a complete, deterministic data context before calling the LLM, so that the AI works against verified numbers rather than hallucinating them.**

**AC**:
- A pure function `BuildReportContext(propertyId, periodStart, periodEnd)` produces a structured DTO containing:
  - Property metadata
  - Revenue summary: total, by month, by platform, occupancy rate, ADR, RevPAR, vs. previous quarter
  - Expense summary: total, by category, by month, vs. previous quarter, net to owner
  - Task summary: total, completion rate, on-time rate, missed/late counts
  - Review summary: average rating, count, distribution, list of reviews (text + rating) with PII stripped, vs. previous quarter
  - Inspection summary: count, average score, issues found/resolved
  - Flagged issues: missed tasks, sub-3-star reviews, expenses > 2σ above category median
- All numbers computed in code, not by the LLM. The LLM only receives this DTO.
- **Implementation uses Dapper**, not EF Core. Each summary is a single SQL query with `GROUP BY` and window functions where useful (e.g., `LAG()` for prior-quarter comparisons). Target: the entire context build should complete in < 2 seconds on B2s for a property with one year of data.
- Property metadata pulled via EF (it's a simple aggregate); summaries pulled via Dapper into typed DTOs.
- Function is unit-tested with fixture data; integration-tested against a seeded Postgres instance with realistic row counts (10k+ revenue rows, 50k+ tasks).
- Tenant context (`app.current_tenant_id` GUC) is set on the Dapper connection before any query.

**T**: L · **Dep**: 3.2

#### Story 4.3 — AI narrative generation
**As the developer, I want the LLM to produce narrative grounded in the supplied context, so that reports are factually accurate and tonally consistent.**

**AC**:
- Calls Anthropic Messages API with Claude Sonnet 4.6 (primary) — see §9 for full prompt strategy.
- Returns JSON matching the schema in §9.3. Schema enforced via JSON mode / structured outputs.
- Temperature 0.3, max_tokens 4000.
- Validation layer: every numeric claim in the narrative is cross-checked against the input context. If a number in the narrative isn't in the context, regenerate once; if still wrong, fail the report with a specific error.
- Fallback: if Anthropic API errors or times out (30s), retry once with backoff; on second failure, fall back to GPT-4o with the same prompt.
- All input tokens, output tokens, model, latency, and cost stored on the `reports` row.

**T**: XL · **Dep**: 4.2

### Epic 5: PDF Generation

#### Story 5.1 — Render PDF
**As the developer, I want to render the AI's structured output to a polished PDF, so that the owner-facing deliverable looks professional.**

**AC**:
- QuestPDF generates a 4–8 page PDF with sections:
  1. Cover page: property name, period, manager logo (default to text wordmark), prepared-by, prepared-on
  2. Executive Summary (1 page)
  3. Revenue Performance (with bar chart of monthly revenue, line chart of occupancy vs. ADR)
  4. Guest Feedback (with rating distribution chart and 2–3 representative review quotes)
  5. Operational Activity (task completion table, inspection scores)
  6. Issues & Resolutions (bullet list)
  7. Recommendations (bullet list)
  8. Footer with page numbers, "Generated by StrataReport AI on [date]"
- Charts rendered via ScottPlot to PNG, embedded as images.
- Fonts embedded; PDF/A-compliant for archival.
- PDF saved to Blob at `tenants/{tenantId}/reports/{reportId}.pdf`.
- Generation returns a SAS URL with 24-hour TTL; client downloads via that URL.
- Filename convention: `{PropertyName}_{Q1-2026}_Owner_Report.pdf`.

**T**: XL · **Dep**: 4.3

**Decision**: QuestPDF Community license requires revenue under $1M/year — fine for MVP and well past. Document the license requirement in the repo README.

### Epic 6: Dashboard & UX

#### Story 6.1 — Main dashboard
**As Maria, I want to land on a useful homepage, so that I can see what's going on and jump to my next action.**

**AC**:
- KPI cards: Total Properties, Reports This Quarter, Pending Imports, MRR-at-Stake (sum of property fees for active properties).
- "Recent Activity" feed: last 10 events (imports, reports, property changes) from `audit_log`.
- Quick actions: "Generate Report", "Upload Data", "Add Property".
- Empty state for fresh accounts that walks through the 3-step onboarding.

**T**: M · **Dep**: 2.2, 3.3, 4.1

#### Story 6.2 — Report history & detail
**As Maria, I want to see all past reports and re-access them, so that I can resend or compare.**

**AC**:
- `/reports` list: Property, Period, Generated At, Generated By, Status, Actions (View PDF, Regenerate, Delete).
- Filter by property, date range, status.
- Report detail page: PDF preview embedded (PDF.js or browser native), metadata, "Regenerate" button (warns it replaces the current PDF).
- "Delete" is soft-delete; PDF blob retained for 90 days then purged.

**T**: M · **Dep**: 5.1

#### Story 6.3 — Global navigation & shell (mobile-first)
**As Maria, I want consistent, phone-friendly navigation, so that I can use the product wherever I am.**

**AC**:
- **Mobile (`xs`)**: bottom tab bar with 5 destinations (Dashboard, Properties, Imports, Reports, More). "More" opens a sheet with Settings, Billing, Profile, Logout. Header is a compact app bar with title only.
- **Tablet (`sm`/`md`)**: collapsible left drawer with same destinations; hamburger toggle in app bar.
- **Desktop (`lg`+)**: persistent left sidebar; user menu in top bar.
- Top bar: tenant name, user menu (profile, logout, billing) on `md`+ only.
- Loading skeletons on all pages (no blank screens).
- Global error boundary with "Something went wrong" page + correlation ID surfaced to the user.
- Toast system for success/error/info (MUI Snackbar), positioned above bottom tab bar on `xs`.
- Touch targets ≥ 44×44 px on all primary actions.
- No horizontal scroll on any view at 360px width.
- Hardware back-button behavior on Android: navigates within app history, not out of the SPA.

**T**: M · **Dep**: none

### Epic 7: Billing

#### Story 7.1 — Stripe subscription
**As Maria, I want to start a trial and pay when I'm ready, so that I can evaluate without commitment.**

**AC**:
- 14-day free trial on signup (no card required).
- Trial countdown banner; expires → read-only mode (existing reports downloadable, no new generation).
- Stripe Checkout for plan selection.
- Stripe Customer Portal for plan changes, payment method updates, invoices.
- Webhook handlers: `checkout.session.completed`, `customer.subscription.updated`, `customer.subscription.deleted`, `invoice.payment_failed`.
- Plan enforcement: max properties and reports-per-quarter checked before relevant actions.
- Past-due tenants: degraded mode (read-only) after 7-day grace period.

**T**: L · **Dep**: 1.1

---

## 9. AI / LLM Design

This section gets disproportionate attention because it's where the product lives or dies.

### 9.1 Principles

1. **The LLM never invents numbers.** All quantitative claims are pre-computed and supplied in the prompt. The LLM only produces narrative around them.
2. **Structured output, always.** Use JSON mode / structured outputs. Parse, validate, then render.
3. **Cross-validate before showing the user.** Run numeric claims back through the source context and reject if mismatch.
4. **Cap costs hard.** Token budgets per request; per-tenant daily caps; alerting at 70% of monthly LLM budget.
5. **Tone is part of the spec.** "Professional, factual, non-salesy" must be measurable.

### 9.2 Prompt Strategy

System prompt (abbreviated):

> You are a property management analyst writing a quarterly performance report for a homeowner. You produce concise, factual, professional narrative grounded in the data supplied. You do not invent numbers, dates, or events. If data is missing or ambiguous, say so explicitly rather than guessing. You write in plain American English at a 9th-grade reading level. You do not use marketing language ("exciting", "amazing", "robust"). You do not editorialize beyond what the data supports. Output strictly conforms to the JSON schema provided.

User prompt structure:
1. Report metadata (property, period, tenant company name)
2. Pre-computed context DTO (revenue, expenses, tasks, reviews, inspections, flags, comparisons)
3. Output schema (inline)
4. Optional: 1–2 few-shot examples for tone calibration

Few-shot examples kept in a fixtures file, version-controlled, reviewed for tone.

### 9.3 Output Schema (canonical)

```json
{
  "executiveSummary": "string (3–5 sentences, max 600 chars)",
  "revenuePerformance": {
    "totalRevenue": "number",
    "occupancyRate": "number (0-1)",
    "avgDailyRate": "number",
    "revPAR": "number",
    "trend": "string ('up' | 'down' | 'stable')",
    "vsPreviousQuarter": {
      "revenueChangePct": "number",
      "occupancyChangePct": "number"
    },
    "insights": "string (2–4 sentences)"
  },
  "guestFeedback": {
    "avgRating": "number (0-5)",
    "reviewCount": "integer",
    "ratingDistribution": { "5": "integer", "4": "integer", "3": "integer", "2": "integer", "1": "integer" },
    "positiveThemes": ["string"],
    "negativeThemes": ["string"],
    "sampleQuotes": [
      { "text": "string", "rating": "number", "platform": "string", "date": "YYYY-MM-DD" }
    ],
    "insights": "string"
  },
  "operationalActivity": {
    "tasksTotal": "integer",
    "tasksCompletedOnTime": "integer",
    "tasksMissed": "integer",
    "inspectionsCount": "integer",
    "avgInspectionScore": "number",
    "insights": "string"
  },
  "expenseSummary": {
    "totalExpenses": "number",
    "netToOwner": "number",
    "topCategories": [{ "category": "string", "amount": "number", "pctOfTotal": "number" }],
    "insights": "string"
  },
  "issuesAndResolutions": [
    { "issue": "string", "resolution": "string", "status": "string" }
  ],
  "recommendations": [
    { "title": "string", "rationale": "string", "priority": "high | medium | low" }
  ],
  "chartData": {
    "monthlyRevenue": [{ "month": "YYYY-MM", "revenue": "number" }],
    "occupancyVsAdr": [{ "month": "YYYY-MM", "occupancy": "number", "adr": "number" }],
    "ratingDistribution": [{ "rating": "integer", "count": "integer" }]
  }
}
```

### 9.4 Validation Pipeline

1. **Schema validation** (System.Text.Json + JSON schema validator). Reject if invalid.
2. **Numeric grounding check**: every number in `revenuePerformance`, `expenseSummary`, `operationalActivity` must match the source context within rounding tolerance.
3. **PII scan**: regex check on `sampleQuotes` and free-text fields for emails, phone numbers, full names that weren't hashed. Strip and log if found.
4. **Length / safety check**: any field exceeding 2× expected length is flagged for review.
5. If any check fails: retry once with the failure described in the prompt. On second failure, mark report `failed` and surface the specific reason.

### 9.5 Cost Model & Budgeting

Estimated tokens per report:
- Input: ~6,000 tokens (system + context + schema + examples)
- Output: ~2,000 tokens

At Claude Sonnet 4.6 pricing (~$3/M input, ~$15/M output as of this writing — **verify before launch**):
- Input cost: $0.018
- Output cost: $0.030
- **Total: ~$0.05 per report**

Headroom against the $0.25 ceiling allows for retries, fallbacks to GPT-4o, and unexpected verbosity.

**Cost controls**:
- Per-tenant daily report cap (configurable; default 20).
- Global daily LLM spend cap (Functions checks Application Insights metric, returns 503 if exceeded).
- Weekly Slack alert if any tenant exceeds $5/week.

### 9.6 Eval Strategy

Before launch:
- Hand-curate 10–15 fixture cases (real anonymized data) with expected output structure.
- Automated snapshot tests: schema match, numeric grounding, no PII, length bounds.
- Manual review of 100% of beta-generated reports for the first 4 weeks; track edit distance between AI output and what beta users actually sent to owners.

Post-launch: spot-check 5% of generated reports weekly. Maintain a "bad output" log to drive prompt iteration.

### 9.7 Fallback & Degraded Mode

- If Anthropic API is fully down: queue the report, retry every 5 minutes for 30 minutes, then fall back to GPT-4o.
- If both LLMs down: report stays `queued`, user notified, retry on next cron pass.
- If only the narrative is broken but the data context built fine, offer a "deterministic" fallback PDF — just the charts and computed numbers with templated section headers, no AI prose. Better than nothing.

---

## 10. API Specification

### 10.1 Conventions

- Base URL: `https://api.stratareport.ai/v1`
- Auth: `Authorization: Bearer <jwt>` header OR `__Host-session` httpOnly cookie.
- Content type: `application/json` unless noted.
- Errors: RFC 7807 (Problem Details) format.
- Pagination: cursor-based, `?cursor=<opaque>&limit=25`.
- All timestamps ISO 8601 UTC.
- All money fields decimal strings to avoid float issues.

### 10.2 Endpoints

#### Auth
- `POST /auth/register` — email/password registration. Returns `202` and triggers verification email.
- `POST /auth/verify-email` — body: `{ token }`. Sets verified flag.
- `POST /auth/login` — body: `{ email, password }`. Returns JWT, sets refresh cookie.
- `POST /auth/refresh` — uses refresh cookie. Returns new JWT.
- `POST /auth/logout` — invalidates refresh token.
- `POST /auth/forgot-password` — sends reset email.
- `POST /auth/reset-password` — body: `{ token, newPassword }`.
- `GET /auth/me` — returns current user + tenant context.

#### Properties
- `GET /properties` — list, paginated.
- `POST /properties` — create.
- `GET /properties/{id}` — detail.
- `PATCH /properties/{id}` — partial update.
- `DELETE /properties/{id}` — soft delete.

#### Imports
- `POST /imports/upload-url` — returns SAS URL for direct Blob upload.
- `POST /imports` — body: `{ blobPath, importType, propertyId? }`. Queues parsing job. Returns `importId` and status.
- `GET /imports` — list.
- `GET /imports/{id}` — detail with errors.
- `POST /imports/{id}/reprocess` — retry a failed import after re-upload.

#### Reports
- `POST /reports/generate` — body: `{ propertyId, reportType, periodStart, periodEnd, customNote?, includeComparison? }`. Returns `202` with `{ reportId, status: 'queued' }`.
- `GET /reports` — list, paginated, filterable.
- `GET /reports/{id}` — status, metadata, downloadUrl (SAS, 24h TTL) if ready.
- `POST /reports/{id}/regenerate` — replaces existing.
- `DELETE /reports/{id}` — soft delete.

#### Billing
- `POST /billing/checkout-session` — returns Stripe Checkout URL.
- `POST /billing/portal-session` — returns Stripe Customer Portal URL.
- `POST /webhooks/stripe` — Stripe event handler (HMAC-verified).

#### Tenant / Settings
- `GET /tenant` — current tenant info, plan, usage.
- `PATCH /tenant` — update tenant settings.

### 10.3 Rate Limits

- Authenticated endpoints: 60 req/min/user, 600 req/min/tenant.
- Auth endpoints: 10 req/min/IP.
- Report generation: 1 in-flight per (tenant, property, period) combination; max 5 concurrent per tenant.
- File upload: max 10 uploads/min/tenant.

Implementation: in-memory token bucket in the Functions middleware backed by Redis (Azure Cache for Redis Basic C0, ~$16/mo). Acceptable cost; significantly simpler than reinventing.

---

## 11. Non-Functional Requirements & SLOs

### 11.1 Performance Targets

| Metric                            | Target (p95)             |
| --------------------------------- | ------------------------ |
| API latency (read endpoints)      | < 500 ms                 |
| API latency (write, non-AI)       | < 1 s                    |
| CSV import (10k rows)             | < 60 s                   |
| Report generation end-to-end      | < 120 s                  |
| PDF render time                   | < 15 s                   |
| Frontend Time-to-Interactive      | < 3 s on broadband       |

### 11.2 Availability SLO

- Public availability target: **99.5%** for MVP (≈ 3.6 hrs downtime/month allowed).
- Pre-announce planned maintenance ≥ 48 hours via email + in-app banner.
- No SLA offered to beta users; document the target internally.

### 11.3 Scalability Targets (MVP)

Sized to support: 100 tenants × 20 properties × 4 reports/quarter = **8,000 reports/quarter** (~90/day peak).

| Component       | Dev / Staging              | Production launch      | Scale-up trigger                                                                      |
| --------------- | -------------------------- | ---------------------- | ------------------------------------------------------------------------------------- |
| PG Flexible Server | **Burstable B1ms** (1 vCPU, 2 GB) | **Burstable B2s** (2 vCPU, 4 GB) | Move from B2s → General Purpose D2s_v3 (2 vCPU, 8 GB) when any of: sustained CPU > 70% over a week; p95 query latency > 200ms; connection count > 80% of pool max; "credits remaining" on Burstable drops below 30% during peak hours. |
| Functions       | Consumption plan           | Consumption plan       | Upgrade to Premium EP1 when cold-start p95 > 3s OR DAU > 50 OR sustained per-minute invocations > 100. |
| Blob Storage    | Standard LRS (Hot)         | Standard GRS (Hot)     | Add lifecycle policy to move blobs > 90 days to Cool tier; revisit when monthly storage cost > $50. |
| Static Web Apps | Free tier                  | Standard plan          | Standard is required for custom auth, larger app size, and SLA — bake into prod from day one. |
| Azure Cache for Redis | Skip in dev (in-memory rate limit) | Basic C0 (~$16/mo) | Upgrade to C1 if rate-limit lookups exceed 100 RPS or cache memory pressure appears. |

**Important B1ms caveats** (so you don't get surprised):
- No high-availability option on Burstable tier — accepted for non-prod.
- IOPS capped at ~120 baseline; bursty workloads (CSV imports) may need credits. If imports start queueing on B1ms in dev, that's a signal, not a problem to fix on B1ms.
- Connection limit ~50 — fine for one developer; would be tight under load.
- No read replicas on Burstable. If you ever need them (you won't at MVP scale), that's the migration point to General Purpose.

### 11.4 Mobile-First Responsive Design

The product is mobile-first, not mobile-tolerated. Property managers run their businesses from phones.

**Breakpoints** (Material-UI defaults):
- `xs`: 0–599px — phone portrait. **Primary design target.**
- `sm`: 600–899px — phone landscape, small tablet.
- `md`: 900–1199px — tablet, small laptop.
- `lg`: 1200px+ — desktop. Comfortable but not the focus.

**Layout patterns**:
- **Navigation**: bottom tab bar on `xs`, collapsible drawer on `sm`+, persistent sidebar on `lg`. Five tabs max: Dashboard, Properties, Imports, Reports, More.
- **Tables**: become card lists on `xs`. Each card surfaces the 3 most important fields (e.g. for properties: Name, Last Report, Status). Tap to drill in.
- **Forms**: single-column on `xs`/`sm`; never side-by-side labels. Stepper or accordion for forms >5 fields.
- **Modals**: full-screen sheets on `xs`; centered dialogs on `md`+.
- **Charts**: in-PDF charts are fine at any size (PDF is the deliverable). In-app chart previews simplify to sparkline-style on `xs`.
- **Touch targets**: minimum 44×44 px (Apple HIG), even where MUI defaults are smaller. Verify with the MUI `size="large"` variants on buttons in form-heavy flows.

**Specific flow notes**:
- **Onboarding**: must complete on a phone. No "go to desktop" prompts.
- **CSV upload**: drag-drop is desktop-only by nature; on mobile, the same dropzone accepts taps and opens the system file picker (which includes Files, iCloud Drive, Google Drive on iOS; same on Android).
- **Report generation**: the form fits one phone screen without scroll; the progress states are clearly visible above the fold.
- **Report PDF viewing**: native PDF viewer in mobile browsers is fine. Don't try to embed PDF.js on mobile — link out instead.
- **Data tables on mobile**: critical reports/imports/properties lists must have a "filter chips" row pinned to the top with the 2–3 most useful filters.

**Testing requirements**:
- Manual smoke test on a real iOS device (Safari) and a real Android device (Chrome) before every release. Browserstack or local devices, your call.
- Chrome DevTools device emulation for iPhone SE (smallest target) and iPad in CI/PR review checklists.
- No release with horizontal scroll on `xs`. No release with a touch target < 44px on a primary action.

### 11.5 Browser Support

Latest 2 versions of: Chrome, Edge, Safari, Firefox. No IE. Mobile: iOS Safari 16+, Chrome Android 110+.

### 11.6 Accessibility

- WCAG 2.1 Level AA target (not certified, but design with it in mind).
- All MUI components used in accessible mode; keyboard nav for all primary flows.
- Color contrast ≥ 4.5:1 for body text.
- Mobile accessibility: respect system font scaling up to 200%; no text in images for critical content; visible focus rings preserved on mobile keyboards.

### 11.7 Internationalization

MVP is English-only and USD-centric. Schema supports `currency_code` and `timezone` per property for future. Defer translation infra.

---

## 12. Security, Privacy & Compliance

### 12.1 Authentication & Authorization

- Microsoft Entra External ID handles password hashing, MFA support, breach detection.
- JWT signed with RS256, rotating keys via JWKS endpoint.
- Refresh tokens rotated on every use, revocable.
- Session cookies: `Secure`, `HttpOnly`, `SameSite=Lax`, `__Host-` prefix.

### 12.2 Tenant Isolation

- DB-level: Postgres RLS as primary guarantee (§7.2).
- App-level: middleware that fails closed if `tenant_id` claim missing.
- Storage: blob paths prefixed by `tenants/{tenantId}/`; SAS tokens scoped to that prefix.
- Integration tests assert cross-tenant queries return zero rows.

### 12.3 Data at Rest & In Transit

- TLS 1.2+ for all traffic; HSTS enabled with 1-year max-age.
- Postgres: TDE (Microsoft-managed keys) — sufficient for MVP.
- Blob: AES-256 at rest (Azure default).
- Secrets in Key Vault; never in source.

### 12.4 PII Handling

The data we receive contains some PII (guest names from reviews, owner emails). Posture:
- Owner email: stored, used only for tenant-owned reporting workflows.
- Guest names: hashed (SHA-256 + per-tenant salt) before storage. Never sent to LLM in plaintext.
- Review text: stored verbatim (necessary for the product) but scanned for emails/phone numbers before LLM inclusion.
- Right to delete: implement tenant deletion endpoint that purges all data within 30 days (GDPR Article 17 alignment).

### 12.5 Compliance Posture

MVP target: **good-faith compliance, no certifications**.

- GDPR: not actively targeting EU but designing schema and deletion flows to be compatible.
- CCPA: privacy policy + data deletion endpoint covers the basics.
- SOC 2: not pursued for MVP; deferred until first enterprise prospect demands it (probably 12+ months out).
- HIPAA: out of scope; explicitly disclaimed.

### 12.6 Vulnerability Management

- GitHub Dependabot enabled.
- `dotnet list package --vulnerable` in CI.
- `npm audit` in CI; fail build on high/critical.
- Quarterly manual review of dependencies.

### 12.7 Backups & DR

- Postgres: 7-day point-in-time-restore (Azure-managed default).
- Blob: geo-redundant storage (GRS) for tenant data; locally-redundant for ephemeral content.
- Weekly logical backup dump exported to a separate subscription's Blob (defense against account compromise).
- **RPO**: 1 hour. **RTO**: 4 hours. Documented runbook in repo.

---

## 13. Observability & Telemetry

### 13.1 Logging

- Serilog → Application Insights.
- Structured logs with `tenant_id`, `user_id`, `request_id`, `endpoint`.
- Log levels: Debug local, Info+ in prod. Never log secrets, PII (use scrubbing rules), or full LLM prompts (log token counts only).
- Application Insights retention: 90 days.

### 13.2 Metrics

Custom metrics published to App Insights:
- `report.generation.duration_ms`
- `report.generation.success` / `.failure`
- `llm.tokens.input` / `.output`
- `llm.cost_usd`
- `csv.import.duration_ms`
- `csv.import.rows_processed`
- `auth.login.success` / `.failure`

### 13.3 Tracing

- W3C Trace Context propagated from frontend through Functions to DB calls (EF Core has built-in OpenTelemetry support; enable it).
- Sample at 10% in prod, 100% in dev.

### 13.4 Alerting

- Error rate > 5% over 5 minutes → email.
- Report generation p95 > 180s over 15 minutes → email.
- LLM daily spend > 80% of monthly budget / 30 → email.
- Postgres CPU > 80% sustained 10 minutes → email.
- Failed Stripe webhook → email immediately.

For a solo developer, "email" is the right channel (no PagerDuty noise). Critical alerts also send SMS via Twilio.

### 13.5 Product Analytics

- PostHog (self-hosted is overkill — use cloud free tier for MVP).
- Track: signup, property_created, csv_uploaded, csv_processed, report_generation_started, report_generation_succeeded, report_downloaded, plan_changed, churned.
- All events include `tenant_id` and `user_id` (hashed for PostHog if you want extra paranoia).

---

## 14. Risks & Mitigations

| Risk                                                         | Likelihood | Impact   | Mitigation                                                                                                                                  |
| ------------------------------------------------------------ | ---------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| LLM hallucinates a financial number in an owner report       | Medium     | Critical | Numbers computed in code, never LLM-generated. Cross-validation pipeline (§9.4). Manual review of all beta reports.                          |
| Tenant data leak via RLS bypass / app bug                    | Low        | Critical | RLS at DB; middleware double-check; integration tests; pen-test before launch.                                                              |
| LLM cost runaway (prompt injection, runaway loops)           | Medium     | High     | Per-tenant daily caps; global spend ceiling; alerting at 70%; structured outputs cap output length.                                          |
| CSV import too fragile; high support burden                  | High       | Medium   | Provide template CSVs; fuzzy column matching; clear errors; ship with 3 top PMS formats pre-tested; collect failure samples aggressively.    |
| Anthropic API outage during launch demo                      | Low        | High     | Fallback to GPT-4o; deterministic-only PDF fallback (§9.7).                                                                                  |
| Solo-dev burnout / scope creep                                | High       | High     | This PRD's "Out of Scope" section is the contract with yourself. Cut, don't add. Single weekend = one story max.                            |
| QuestPDF license change (rare but possible)                  | Low        | Low      | Watch the license; budget for the commercial license in year 2.                                                                              |
| Owner sees an embarrassing AI-written sentence and complains | Medium     | Medium   | Mandatory human-review step in MVP (in-app "Review before sending" banner). De-risk in v1.1 once tone is dialed in.                          |
| GDPR complaint from EU user we didn't target                  | Low        | Medium   | Privacy policy; deletion endpoint; geo-block EU on signup if it becomes a real concern.                                                      |
| Customer requests a refund and Stripe dispute                | Medium     | Low      | Clear ToS; reasonable refund policy (pro-rated within 30 days); document everything in audit log.                                            |

---

## 15. Onboarding & First-Run Experience

The single most important UX surface in the product. If the first 10 minutes don't deliver value, churn is near-certain.

### 15.1 Flow

1. **Signup** (email/SSO) → 30 seconds.
2. **Welcome screen**: "Let's get your first report in 10 minutes." Three-step progress bar: Add Property → Upload Data → Generate Report.
3. **Add property**: minimal form (name, address, owner name). "You can fill in details later."
4. **Sample data option**: prominent "Try with sample data" button that pre-seeds a demo property with realistic CSVs and lets the user generate a sample report end-to-end without uploading their own data. Critical for the "show me, then I'll trust it" buyer.
5. **Upload data**: import type picker. Template CSV downloads visible. Drag-and-drop area. Status updates as parsing completes.
6. **Generate first report**: pre-fills the property and current/last quarter. One click. Progress states visible.
7. **Success screen**: PDF preview embedded, prominent "Download" and "How to send to your owner" panel.
8. **Email follow-up** (Postmark): 24h later, "How was your first report?" with a 1-question survey.

### 15.2 Empty States

Every primary list view (`/properties`, `/imports`, `/reports`) has a designed empty state with the next CTA and a 1-paragraph explainer. No blank tables.

### 15.3 In-App Help

- Tooltip on every column-matching error explaining what the system expected.
- A "Help" sidebar item linking to a Notion-hosted help center (no Intercom for MVP).
- "Contact support" button → mailto: link with pre-filled subject including tenant_id (for solo-dev triage).

---

## 16. Build Sequencing & Roadmap

### 16.1 MVP Build Order (solo dev, ~14 weeks)

Stories sequenced for maximum de-risk early. Each week assumes 15–25 focused hours.

**Week 1–2: Foundation**
- Repo setup, CI/CD pipeline, Bicep IaC, dev/test/prod environments.
- Story 1.1 (auth), Story 1.2 (multi-tenancy), Story 1.3 (account mgmt).
- Skeleton of frontend shell (Story 6.3).

**Week 3: Properties**
- Story 2.1, 2.2.
- First end-to-end vertical slice deployed: signup → add property → see it in list.

**Week 4–6: Data Ingestion (highest-risk subsystem)**
- Story 3.1, 3.2, 3.3.
- Build the three CSV templates first (Hostaway revenue, QuickBooks expenses, Airbnb reviews).
- Spend extra time on Story 3.2 — this is where the product lives or dies.

**Week 7–9: Report Generation**
- Story 4.2 (context builder) — pure functions, heavily tested.
- Story 4.3 (LLM integration) — including validation pipeline.
- Story 4.1 (UI).
- Story 5.1 (PDF rendering).

**Week 10: Dashboard & polish**
- Story 6.1, 6.2.
- Onboarding flow (Section 15).

**Week 11: Billing**
- Story 7.1.

**Week 12: Beta hardening**
- Manual QA pass; fix top 20 bugs.
- Onboard first 3 beta users (handhold them personally).
- Iterate on prompt and CSV parsing based on real data.

**Week 13–14: Beta → Launch**
- Onboard next 7 beta users.
- Performance tuning based on real traffic.
- Marketing site (separate, Webflow or Astro).
- Public launch.

### 16.2 Post-MVP Roadmap (Quarters 2–4)

**v1.1 (post-launch +6 weeks)**
- Multi-user per tenant + roles.
- White-label branding (logo, colors, footer).
- Monthly report variant.
- Automated email distribution to owners.

**v1.2 (+12 weeks)**
- First PMS integration: Hostaway API (largest mid-market PMS).
- Slack/Teams notifications.
- Custom report sections.

**v2.0 (+24 weeks)**
- Owner portal (read-only).
- Multi-property summary reports for portfolios.
- Guesty and OwnerRez integrations.
- Mobile-responsive becomes mobile-first.

### 16.3 Cut List (in order of what to drop if behind)

1. Billing (Story 7.1) — run beta on manual invoicing.
2. Microsoft SSO — email/password only.
3. Comparison-to-previous-quarter feature in reports.
4. Inspections import type (carve out, ship the other 4).
5. Custom note on reports.

Do not cut: multi-tenancy enforcement, LLM validation pipeline, soft deletes, audit log.

---

## 17. Open Questions & Assumptions

### 17.1 Open Questions

- **Pricing**: Is per-property or per-report the better unit? Beta will tell.
- **Geographic scope**: US-only at launch, or US+Canada+UK? Probably US-only — easier privacy story.
- **Domain & branding**: `stratareport.ai` available? If not, alternatives. (Verify before any marketing spend.)
- **Anthropic vs Azure OpenAI for Claude**: Direct Anthropic API for now; revisit when Azure OpenAI offers Sonnet 4.6 with adequate quota.
- **Should we build a "demo mode" public-accessible page** that lets prospects generate a report from canned data without signing up? Strong consideration for v1.1.
- **Refund policy**: 30-day money-back, or none? Defaults to 30-day for trust.

### 17.2 Assumptions

- Beta users are willing to upload real (sanitized) CSVs from their PMS. If not, this is a much harder product.
- Owners actually want PDFs, not links to a web view. Validate during beta interviews; switch if wrong.
- LLM pricing trajectory is downward (it has been). If it reverses, the cost ceiling needs revisiting.
- A solo developer can ship and support 10–30 beta tenants. If support burden balloons, the next hire is a customer success / ops person, not another engineer.
- Microsoft Entra External ID is stable and reasonably priced at this volume. (Free tier covers ~50k MAU; revisit if/when that's a real concern.)

---

## 18. Definition of Done & Launch Checklist

### 18.1 Per-Story DoD

A story is "done" when:
- Code written, self-reviewed, merged to `main`.
- Unit tests pass; integration tests pass for critical paths.
- Deployed to staging environment.
- Manually verified by exercising the user-facing flow.
- **For any UI story: verified on a real phone (iOS Safari and Chrome Android) in addition to desktop.**
- Documented (README for any new env vars, help center if user-facing).
- No P0/P1 bugs filed against it.
- Telemetry events emitted (where defined).

### 18.2 Pre-Launch Checklist

**Engineering**:
- [ ] All MVP epics complete (Stories 1.1 through 7.1).
- [ ] Bicep IaC clean-deploys to a fresh subscription in < 30 minutes.
- [ ] Backup and restore tested end-to-end on a staging tenant.
- [ ] All API endpoints have rate limits applied.
- [ ] All endpoints return Problem Details on errors.
- [ ] Cross-tenant data isolation test suite passes.
- [ ] LLM cost ceiling enforced and tested.
- [ ] Application Insights alerts configured and verified.
- [ ] Stripe webhook signature validation tested.
- [ ] Secrets in Key Vault; nothing sensitive in repo or env vars in source.

**Product**:
- [ ] Onboarding flow tested by 3 non-developers without help.
- [ ] **Onboarding flow completed end-to-end on a real iPhone and a real Android phone.**
- [ ] **Core flows (signup, add property, upload CSV, generate report, view PDF) verified on iOS Safari and Chrome Android.**
- [ ] **No horizontal scroll on any view at 360px width.**
- [ ] Sample data tenant works end-to-end.
- [ ] At least 5 beta users have generated reports they actually sent to owners.
- [ ] Help center has articles for the top 10 expected questions.
- [ ] Privacy policy and ToS reviewed (consider $500–1k for a lawyer review).

**Marketing / Ops**:
- [ ] Domain, SSL, email sending domain (Postmark) verified.
- [ ] Marketing site live.
- [ ] Status page (statuspage.io free or upptime on GitHub) live.
- [ ] support@ email monitored.
- [ ] Pricing page accurate; Stripe products and prices match.

**Legal / Admin**:
- [ ] LLC or equivalent formed if not already.
- [ ] Business bank account + Stripe connected to it.
- [ ] Trademark search for "StrataReport" before heavy marketing spend.

### 18.3 Launch Day Plan

- Soft launch via personal network, IndieHackers, and 1–2 STR-focused communities (BiggerPockets, Hosting Hotline Slack, AirHosts Forum).
- No paid acquisition until LTV/CAC is measurable (≥ 3 months of retention data).
- Monitor App Insights constantly for the first 48 hours.
- Personal email to every signup for the first 50 users.

---

**End of PRD v2.1**

*Changelog from v1.0 → v2.0*:
- Added executive summary, problem statement, personas, competitive context.
- Added complete data model with schema sketches.
- Greatly expanded AI section with prompt strategy, validation, cost model, eval plan.
- Added Security & Compliance, Observability, Risks, Onboarding, Roadmap sections.
- Added Build Sequencing tailored to solo-dev cadence.
- Added Open Questions and explicit Cut List.
- Fixed markdown formatting throughout (closed code fences, consistent heading levels).

*Changelog from v2.0 → v2.1*:
- Promoted mobile-responsive web to a first-class capability (§4.1, §6.3, §11.4) — phones are the primary design target, not desktop.
- Added detailed mobile-first specification with breakpoints, layout patterns per view type, touch-target rules, and a per-release mobile test requirement.
- Rewrote Story 6.3 with mobile-first navigation acceptance criteria (bottom tabs on `xs`, drawer on tablet, sidebar on desktop).
- Clarified frontend hosting as Azure Static Web Apps (Standard plan) — no app service, no SSR, no containers.
- Split ORM into hybrid **EF Core + Dapper** stack: EF for migrations and writes, Dapper for hot read paths (report context aggregation, multi-table joins).
- Specified Story 4.2 implementation as Dapper-based with a 2-second performance target.
- Locked DB tier policy: **B1ms** for dev/staging, **B2s** for prod, with explicit scale-up triggers documented in §11.3.
- Documented B1ms caveats (no HA, IOPS limits, connection caps) so they're not surprises later.
- Added mobile-specific items to launch checklist and per-story DoD.
