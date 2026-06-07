# Locale — Engineering History & Architecture Record

**Document type:** Technical institutional memory  
**Audience:** Future engineers, future AI agents, technical stakeholders  
**Source of truth for:** Architecture, technical decisions, debt, and evolution  
**Not for:** Product vision, investor materials, user testing (see locale-brief.html)  
**Last updated:** 2026-06-07  
**Current version:** v0.5 · APP_VERSION `'0.5'` · CACHE `'locale-v7'` · SCHEMA_VERSION `3`

---

## Table of Contents

1. [Current State Architecture](#1-current-state-architecture)
2. [Product Evolution Timeline](#2-product-evolution-timeline)
3. [Architecture Decision Log (ADR)](#3-architecture-decision-log-adr)
4. [Feature Evolution](#4-feature-evolution)
5. [Technical Debt Register](#5-technical-debt-register)
6. [Experiment Log](#6-experiment-log)
7. [MVP Readiness Assessment](#7-mvp-readiness-assessment)
8. [Architecture Snapshots](#8-architecture-snapshots)

---

## 1. Current State Architecture

### Overview

Locale is a **single-file HTML Progressive Web App** (PWA). The entire application — HTML structure, CSS design system, JavaScript logic, React components, service worker registration, PWA manifest generation, and inline test suite — lives in one file: `locale.html`. There is no build step, no npm, no bundler, and no backend.

This is an intentional architectural decision made to maximize iteration speed during proof-of-concept validation. A future production version would separate concerns into a proper project structure with a backend and real-time sync.

### Runtime Stack

| Layer | Technology | Version | Notes |
|---|---|---|---|
| UI Framework | React | 18.2.0 | Loaded from cdnjs CDN |
| JSX transpiler | Babel Standalone | 7.23.2 | In-browser transpilation — no build step |
| Drag-to-reorder | SortableJS | 1.15.2 | Loaded from cdnjs; non-fatal if missing |
| Fonts | Google Fonts | — | Cormorant Garamond + DM Sans |
| AI | Claude API (Anthropic) | claude-haiku-4-5-20251001 | User-supplied API key; session storage |
| Storage | Browser localStorage | — | Storage key `locale_v4`; SCHEMA_VERSION 3 |
| Deployment | GitHub Pages | — | `fania17hernan.github.io/locale-app/locale.html` |
| CI/CD | GitHub Actions | — | Auto-deploys on push to main |

### Key Constants (as of v0.5)

```
APP_VERSION    = '0.5'
SCHEMA_VERSION = 3        // increment when trip data shape changes
CACHE          = 'locale-v7'
SK             = 'locale_v4'   // localStorage key for trips array
AI_KEY_SK      = 'locale_ai_key'  // localStorage key for API key
```

### Frontend Architecture

The entire app renders from a single `<div id="root">`. React manages all state. There is no router — navigation is a state machine inside the root `App` component:

```
App
├── sharedTrip? → SharedTripBanner (modal sheet)
├── offline? → offline-banner
├── showInstall? → install-banner (PWA prompt)
├── view === 'dashboard' → Dashboard
│     └── TripCard[] → onClick → setView('detail')
├── view === 'detail' → TripDetail
│     ├── Trip hero (title, dates, flags, back/share/pdf/delete)
│     ├── Sticky pill nav (tabs)
│     └── Tab panels:
│           ├── 'overview'   → CurrencyConverter + CityTidbits + AtAGlance
│           ├── 'checklist'  → ChecklistView
│           ├── 'packing'    → PackingView
│           ├── 'itinerary'  → DayView[]
│           └── 'ai'         → ItineraryAIPlanner
├── showNew? → NewTripSheet (multi-step wizard overlay)
└── BugReportButton (floating, always visible)
```

### Data Model

The canonical trip object after `normalizeTrip()`:

```javascript
{
  id: string,              // UUID v4
  schemaVersion: 3,        // migration guard
  title: string,           // includes leading emoji if user typed one
  startDate: 'YYYY-MM-DD',
  endDate:   'YYYY-MM-DD',
  occasion:  string,       // 'vacation' | 'wedding' | 'sports' | etc.
  travelerCount: number,
  travelerPassportCountry: string,  // ISO 2-letter country code, default 'US'
  
  destinations: [{         // ordered array, multi-stop supported
    id: string,
    city: string,
    country: string,
    countryCode: string,   // ISO 2-letter
    isInternational: bool,
    arrivalDate: string,
    departureDate: string,
  }],
  
  collaborators: [{        // trip group members
    id: string,
    name: string,
    avatarColor: string,
  }],
  
  lodging: [{              // hotels / Airbnbs
    id: string,
    name: string,
    address: string,
    checkIn: string,
    checkOut: string,
    confirmationNumber: string,
  }],
  
  flights: [{              // flight legs
    id: string,
    direction: 'outbound' | 'return',
    flightNumber: string,
    departureAirport: string,
    arrivalAirport: string,
    departureTime: string, // ISO datetime
    confirmationNumber: string,
  }],
  
  checklist: [{            // pre-trip prep items
    id: string,
    label: string,
    completed: bool,
    category: string,      // 'document' | 'booking' | 'packing' | 'entry'
    url: string,           // optional booking link
  }],
  
  packingList: null | [{   // null = never generated; [] is normalized to null
    id: string,
    name: string,
    packed: bool,
    category: string,
  }],
  
  days: [{                 // AI-generated or manual itinerary days
    id: string,
    date: 'YYYY-MM-DD',
    label: string,
    destinationId: string,
    notes: string,
    activities: [Activity],
    restaurants: [Restaurant],
  }],
  
  color: string,           // CSS color string for card theming
}
```

**Critical sentinel:** `packingList: null` means "never generated." An empty array `[]` is normalized to `null` by `normalizeTrip()` so the `PackingView` component correctly triggers auto-generation. This was a source of a persistent bug (see Technical Debt #3).

### State Management

All state lives in the `App` component. There is no global state library (no Redux, no Zustand, no Context API for data). State flows:

- **Source of truth:** `trips[]` array in `App` state
- **Persistence:** `saveTrips(trips)` → `localStorage.setItem(SK, JSON.stringify(trips))`
- **Loading:** `loadTrips()` called once on mount via `useState(() => loadTrips())`
- **Mutations:** `handleUpdateTrip(updatedTrip)` replaces the matching trip by ID and calls `saveAndSet()`
- **Child writes:** Every component that modifies trip data receives `onUpdateTrip` as a prop and calls it directly

This is functional but does not scale — every save re-serializes the entire trips array.

### Storage Architecture

```
localStorage
├── locale_v4          → JSON array of all trip objects (entire data store)
├── locale_ai_key      → Anthropic API key string (user-entered, persisted)
└── locale_error_log   → JSON array of last 50 error/test-failure entries
```

**Storage limit concern:** localStorage cap is typically 5–10 MB. Trips with AI-generated itineraries (many days × activities × restaurants) grow large. A quota-exceeded error now surfaces as a visible toast (added v0.4) but does not gracefully degrade — trip is simply not saved.

### PWA Architecture

Both the PWA manifest and the service worker are generated at runtime as Blob URLs and registered dynamically. This is an unusual pattern necessitated by the single-file constraint: GitHub Pages serves only static files, and a real `manifest.json` or `sw.js` would require separate files.

```javascript
// Manifest: JSON → Blob → Object URL → <link rel="manifest" href="...">
const manifestBlob = new Blob([JSON.stringify(manifest)], {type:'application/json'});
document.getElementById('manifest-link').href = URL.createObjectURL(manifestBlob);

// Service Worker: code string → Blob → Object URL → navigator.serviceWorker.register(...)
const swBlob = new Blob([swCode], {type:'text/javascript'});
navigator.serviceWorker.register(URL.createObjectURL(swBlob));
```

**Implication:** The service worker's scope is `blob:` origin, not the page origin. This means it cannot intercept the page's own navigation requests in all browsers. Cache-busting is done by changing the `CACHE` constant name (e.g., `locale-v6` → `locale-v7`), which triggers the `activate` event to delete old caches.

### AI Integration

```
User enters API key → stored in localStorage (locale_ai_key)
User enters prompt → ItineraryAIPlanner component
↓
buildSystemPrompt() → constructs context-rich system prompt with:
  - trip metadata (dates, destinations, occasion, traveler count)
  - lodging details (names, check-in/out dates)
  - flight details (numbers, times, confirmation codes)
  - CRITICAL RULES for non-negotiables
  - Output schema specification (exact JSON shape)
↓
fetch('https://api.anthropic.com/v1/messages', {
  method: 'POST',
  headers: { 'x-api-key': apiKey, 'anthropic-version': '2023-06-01',
             'anthropic-beta': 'output-128k-2025-02-19' },
  body: JSON.stringify({
    model: 'claude-haiku-4-5-20251001',
    max_tokens: 16000,
    system: buildSystemPrompt(),    // system param (not in messages array)
    messages: [{ role: 'user', content: 'User request: ' + prompt }]
  })
})
↓
JSON extraction:
  1. Strip markdown fences (```json ... ```)
  2. Find array bounds: indexOf('[') / lastIndexOf(']')
  3. JSON.parse()
  4. Map each day to canonical day object
↓
onUpdateTrip({...trip, days: parsedDays})
```

**API key security model:** The key is entered by the user, stored in `localStorage`, and sent directly from the browser to `api.anthropic.com`. There is no backend proxy. Users are warned about this before entering their key.

### Sharing Architecture

Trip sharing is link-based with no backend:

```
Share → JSON.stringify(trip) → encodeURIComponent → btoa (base64) → URL hash
Receive → window.location.hash → atob → JSON.parse → normalizeTrip → SharedTripBanner
```

Shared trips are **static snapshots** — not live. The recipient gets a copy; subsequent changes by the organizer are not synced. This is documented in the brief and in-app.

### Inline Test Suite

An IIFE at the bottom of the script block runs `console.assert`-style checks on every page load:

- `uuid()` — format and uniqueness
- `normalizeTrip()` — field defaults, schema version, legacy field migration
- `generateChecklist()` — returns array with correct shape
- `buildPackingDefaults()` — returns array with names
- `CITY_TO_COUNTRY` — spot checks for known cities
- `CITY_LOCAL_TIPS` — spot checks for known cities

Failures are logged to `locale_error_log` in localStorage and printed to DevTools. The bug report button automatically includes the last 5 error log entries.

### Deployment

```
GitHub repository: fania17hernan/locale-app
Branch: main
Deploy target: GitHub Pages
URL: https://fania17hernan.github.io/locale-app/locale.html
CI: GitHub Actions — pushes to main trigger automatic deployment
```

No build step. The file is served as-is. In-browser Babel transpiles JSX at runtime on first load (cached by service worker after that).

---

## 2. Product Evolution Timeline

### 2026-05 (Early May) — Origin

**Started:** as `trip-planner.html`, a one-off HTML itinerary for a Miami group trip (Art Deco / dark gold theme). The intent was to make a shareable link for friends, not to build a product.

**Pivot:** After building the Miami file, the decision was made to extract the concept into a reusable group trip planner. A new file was started from scratch with a proper component structure.

---

### 2026-05 (Mid May) — Phase 1: Foundation (v0.1)

**What was built:**
- Visual design system: CSS custom properties, Cormorant Garamond + DM Sans, cream/ocean brand palette
- Trip dashboard with card grid
- Multi-step new trip wizard (name, dates, destinations, travelers, occasion)
- Multi-stop destination support
- 8 color themes for trip cards
- localStorage persistence with schema versioning
- PWA shell: service worker (Blob URL strategy), manifest (Blob URL strategy), install prompt
- Trip sharing via base64 URL hash
- SharedTripBanner modal for receiving shared trips
- React ErrorBoundary

**App name at this stage:** First called `trip-planner.html`. Later renamed to `voya.html` (Voya brand identity explored but abandoned — Voya Financial trademark conflict discovered). Then `cartae.html` (Cartae brand abandoned — conflict with cartae.net SaaS). Final name: **Locale** — no trademark conflict found after 30+ name searches.

**Technical decisions made:**
- Single-file HTML (speed over structure)
- In-browser Babel (no build toolchain)
- localStorage only (no backend)
- Blob URL for service worker (single-file constraint)

---

### 2026-05 (Late May) — Phase 2: Core Itinerary (v0.2)

**What was built:**
- AI itinerary generator (Claude Haiku via direct API call)
- Day-by-day itinerary view with activity and restaurant cards
- Smart checklist auto-generated from trip metadata
- Currency converter (fixed rates, no API)
- International entry flags: EES (Schengen), UK entry, Australia eTA
- City Tips: curated local content for initial set of cities
- PDF export (jsPDF-style inline generation)

**Major bug fixes (v0.2):**
- iPhone zoom on form inputs (set all inputs to 16px minimum)
- Keyboard pushing Back/Preview buttons off screen (100dvh + sticky layout)
- End date before start date allowed (added inline validation)
- Wrong flag shown on user-created trips
- City name capitalization missing
- Text truncation in itinerary cards (hotel name/address clipping)
- Two confusingly similar share buttons (duplicate removed)
- Checklist booking items showed URL as plain text (added tappable "Book tickets →" button)

---

### 2026-06-03 — v0.4 (skipped v0.3 for internal reasons)

**What was built:**
- Confirmation upload: user photographs/uploads hotel or flight PDF/image; Claude extracts details and populates trip
- "What Claude knows" summary panel in AI generator: shows all context Claude will use before generating
- Expanded City Tips: London, Paris, Austin, Anaheim, Miami, New York, Chicago, Nashville, Las Vegas (9 cities)
- In-app bug report button: floating 🐞 button, auto-attaches version + screen + device info + error log, mailto
- Travelers input: replaced free-text number with +/− stepper buttons (clamped 1–20)
- AI generator non-negotiables: rebuilt system prompt with CRITICAL RULES ordering
- Post-generation refinement panel: stays visible after generation with "Regenerate with changes" prompt
- JSON backup export/import on dashboard
- localStorage quota error surfaced as visible toast
- PDF checklist fix: `item.checked` → `item.completed`
- SRI integrity hashes explored (reverted — curl produced wrong hashes from redirect page)
- Bug report `window.open` → `window.location.href` (Safari popup blocker fix)
- APP_VERSION bumped to `'0.4'`, CACHE to `'locale-v5'`

---

### 2026-06-04 — v0.5

**What was built:**
- Entry flags auto-dismiss on checklist completion: `getIntlFlags()` now cross-references `trip.checklist` and skips any flag whose matching item is `completed: true`
- Non-US traveler entry requirements: ESTA for VWP passport holders visiting US; US Visa flag for all others. Both generate matching checklist items
- Passport field expanded: 6 countries → all 195 countries (alphabetical). Field label updated to "Your Passport / Citizenship"
- Packing list auto-generation: opens immediately on first `PackingView` mount via `useEffect`; `useRef(didInit)` guard prevents double-fire; `buildPackingDefaults()` generates seasonal/destination-aware list
- `normalizeTrip` packing sentinel: `packingList: []` now normalized to `null` (critical bug fix — see Debt #3)
- Emoji picker removed: users type emoji directly in trip name; card and hero strip leading emoji with `/^\p{Emoji}\s*/u` for display separation
- AI generator max_tokens: 8000 → 16000; system prompt moved to `system` param (not `messages`); per-trip item scaling for long trips
- JSON extraction hardened: strip markdown fences before parsing; `indexOf('[')` / `lastIndexOf(']')` instead of regex
- City input fields: `autocomplete="off" autocorrect="off" autocapitalize="words"` to suppress iOS contacts icon
- Trip hero redesigned for mobile: Back top-left; Share/PDF/Delete grouped right; `clamp()` on title font size
- Tab nav: `boxShadow: none`, `borderBottom: none` (clean separator removed)
- CITY_TO_COUNTRY expanded: Versailles, Nice, Cannes, Lyon, Bordeaux, Strasbourg, Marseille, Bruges, Ghent, Salzburg, Dubrovnik, Reykjavik, Bath, Oxford, Cambridge, Amalfi, Positano, Cinque Terre, Marrakech, Nairobi, Brooklyn, Manhattan, Queens, Bronx, Harlem, Jersey City, Hoboken + 30+ more
- Borough aliases: Brooklyn/Manhattan/Queens/Bronx resolved to New York in `CityTidbits` via alias map
- EES deduplication: `getIntlFlags()` now uses `new Set()` on unique country codes before iterating — fixed triple-EES bug on Paris→Versailles→Paris multi-stop
- Overview layout: `maxWidth: 720`, unified padding, card `marginBottom: 12`
- Emoji double-display fixed: card title and hero h1 strip leading emoji before rendering
- APP_VERSION bumped to `'0.5'`, CACHE to `'locale-v7'`

---

## 3. Architecture Decision Log (ADR)

### ADR-001: Single-File HTML Architecture

**Decision:** Entire application in one `locale.html` file — HTML, CSS, JS, React components, service worker, manifest, tests.

**Alternatives considered:**
- Standard React project (Vite + separate files)
- Next.js
- Vanilla JS (no framework)

**Reason:** Fastest path to deployable POC. No build toolchain, no npm, no configuration. A non-engineer can deploy this to GitHub Pages with a single file push. Focus on product validation, not infrastructure.

**Tradeoffs accepted:**
- In-browser Babel transpilation is slow on first load (~2–4 seconds on mobile)
- No code splitting — entire app loads at once
- Can't use npm packages; limited to CDN libraries
- Hard to lint, test in isolation, or apply standard dev tools
- File grows large over time (~3,800+ lines at v0.5); becomes harder to navigate

**Future revisit trigger:** When the product is validated and ready for production, this should be the first thing replaced with a proper project structure (Vite + React + TypeScript).

---

### ADR-002: localStorage as the Database

**Decision:** All trip data stored in `localStorage` under key `locale_v4`, as a JSON-serialized array.

**Alternatives considered:**
- IndexedDB (more capacity, structured queries)
- Supabase (real-time sync, user accounts)
- No persistence (session only)

**Reason:** Lowest friction for MVP. No backend setup, no auth, no cost. Users can use the app without accounts. Data is private by default.

**Tradeoffs accepted:**
- No cross-device sync — trips on your phone are not on your laptop
- No real-time collaboration — sharing is snapshot-based
- Data lost if user clears browser storage
- 5–10 MB localStorage limit; large AI-generated trips approach this
- JSON stringify/parse entire dataset on every save (no partial updates)

**Mitigations added:**
- JSON backup export/import (v0.4) for manual backup
- Storage quota error toast (v0.4) so data loss is visible
- Schema versioning (`SCHEMA_VERSION`) and `normalizeTrip()` for forward compatibility

**Future revisit trigger:** Introduction of user accounts. Supabase is the recommended backend for Phase 2 (already evaluated; free tier sufficient for MVP scale).

---

### ADR-003: Blob URL Service Worker

**Decision:** Service worker is defined as a string inside `locale.html`, converted to a Blob, and registered via `URL.createObjectURL()`.

**Alternatives considered:**
- Separate `sw.js` file (standard approach)
- No service worker (no offline support)

**Reason:** The single-file constraint requires this workaround. GitHub Pages will serve whatever files are in the repo — if we had a `sw.js` file, we'd have a two-file app. The single-file goal was prioritized.

**Tradeoffs accepted:**
- Blob URL service workers have `blob:` scope, not the page's origin scope. In some browsers (notably Safari) this can limit their ability to intercept navigation requests
- Service worker update cycle is non-standard — users may not get updates until they close all tabs and reopen
- Cache busting requires changing the `CACHE` constant name with each deploy (e.g., `locale-v7` → `locale-v8`)

**Future revisit trigger:** Moving to a multi-file project structure. At that point, use a standard `sw.js` with Workbox.

---

### ADR-004: Direct Anthropic API Call from Browser

**Decision:** AI itinerary generation calls `api.anthropic.com` directly from the user's browser, using a user-supplied API key.

**Alternatives considered:**
- Backend proxy (Next.js API route, Supabase Edge Function, Cloudflare Worker)
- Pre-generated itineraries (no live AI)
- OpenAI or other providers

**Reason:** No backend exists. A backend proxy requires infrastructure. For POC validation, user-supplied API keys are acceptable. Testers (focus group participants) are technically adjacent and can create free Anthropic accounts.

**Tradeoffs accepted:**
- User's API key is exposed in browser network requests (can be seen in DevTools)
- User pays for API usage from their own account
- Requires user setup friction (get API key, enter it in the app)
- CORS must be permitted by Anthropic's API (it is — they allow browser requests)
- No rate limiting or abuse protection

**Future revisit trigger:** User accounts. Once there's a backend, move to a proxied call where the API key lives server-side. This is the standard pattern for production AI apps.

---

### ADR-005: Haiku Over Sonnet/Opus for Itinerary Generation

**Decision:** Use `claude-haiku-4-5-20251001` for all AI generation tasks.

**Alternatives considered:**
- `claude-sonnet-4-6` (more capable, higher cost)
- `claude-opus-4-6` (most capable, highest cost)

**Reason:** Haiku is significantly cheaper per token. Itinerary generation requests are large (full trip context + JSON schema + output) but the task is structured enough that Haiku performs well. Users pay from their own API accounts, so cost matters.

**Tradeoffs accepted:**
- Occasionally generates venue names that don't exist or addresses that are incorrect
- Less nuanced understanding of complex multi-stop itineraries
- May omit non-negotiables if prompt is poorly structured (mitigated by CRITICAL RULES in system prompt)

**Future revisit trigger:** If AI quality becomes a user complaint that affects retention. Consider making model selectable (Haiku default, Sonnet as "Pro" option).

---

### ADR-006: Schema Versioning Strategy

**Decision:** `SCHEMA_VERSION` integer in each trip object. `normalizeTrip()` acts as the migration function — it accepts any version and returns a current-schema object.

**Alternatives considered:**
- Version-namespaced localStorage keys (migrate by writing to new key)
- No versioning (breaking changes would corrupt data)

**Reason:** Additive field migrations are the most common change pattern in this app. `normalizeTrip()` defaults missing fields safely, making it safe to add new fields without breaking existing stored trips.

**Pattern:**
```javascript
// Adding a new field in v4:
const newField = t.newField ?? defaultValue;
// Then return it in the spread
```

**Tradeoffs accepted:**
- Destructive data changes (renames, removals) require explicit migration code in `normalizeTrip()`
- No "down" migration — can't roll back schema changes
- Schema version is stored in each trip object, not globally

**Future revisit trigger:** If a schema change requires non-additive transformation (e.g., splitting a field, changing types). At that point, add explicit `if (v < X)` migration blocks in `normalizeTrip()`.

---

### ADR-007: No SRI Integrity Hashes

**Decision:** CDN script tags do not use `integrity` attributes.

**Alternatives considered:**
- SRI hashes on all CDN scripts (standard security practice)

**Reason:** Attempted in v0.4. The `curl` approach to generating hashes returned a redirect page hash, not the actual resource hash. Getting correct SRI hashes requires fetching the exact resource bytes that the browser would receive, which is browser-dependent (gzip, brotli encoding). This was deferred as a beta-phase tradeoff.

**Security risk:** If cdnjs.cloudflare.com is compromised, a malicious script could be injected. For a POC with no user accounts or sensitive data, this risk is accepted.

**Future revisit trigger:** Production launch. Use a proper build tool to vendor dependencies locally instead of relying on CDN at runtime.

---

### ADR-008: VWP List Hardcoded in Two Places

**Decision:** The Visa Waiver Program country list (`VWP` array) is defined twice: once in `getIntlFlags()` and once in `generateChecklist()`.

**Why:** These two functions were developed in separate sessions and the duplication wasn't caught at implementation time.

**Risk:** If the VWP list needs to be updated (countries are added/removed from the program), both places must be updated. A bug introduced by maintaining only one will cause flags and checklist items to diverge.

**Recommended fix:** Extract `VWP` to a module-level constant, reference it from both functions.

---

## 4. Feature Evolution

### Feature: AI Itinerary Generator

| Version | Change | Reason |
|---|---|---|
| v0.2 | Initial implementation. Single prompt, basic system prompt, no lodging/flight context. `max_tokens: 4000`. | Validate core value proposition |
| v0.4 | System prompt rebuilt with CRITICAL RULES ordering. Non-negotiables treated as mandatory. Lodging check-in/check-out added to day objects. Flight prep added. max_tokens increased. | Testers reported generator ignored stated activities; lodging days broken |
| v0.4 | "What Claude knows" panel added before generation | Testers couldn't understand what context the AI had; gaps went unnoticed |
| v0.4 | Post-generation refinement panel (describe changes → regenerate) | AI tab disappeared after generation; testers had no way to iterate |
| v0.5 | `max_tokens: 8000 → 16000`. System prompt moved to `system` param. Item scaling for long trips (8–14 nights: 2 activities + 1 restaurant/day). | 13-night Italy trip was truncating mid-JSON at 8000 tokens |
| v0.5 | JSON extraction hardened: strip markdown fences, use `indexOf`/`lastIndexOf` | Claude was returning valid JSON wrapped in ```json``` fences; JSON.parse failed |

### Feature: Trip Sharing

| Version | Change | Reason |
|---|---|---|
| v0.1 | Base64 URL hash sharing. Recipient sees SharedTripBanner with "Add to my trips". | Core collaboration feature |
| v0.4 | Share sheet explicitly labeled "Read-only snapshot" | Testers thought changes would sync to recipients; confusion about collaboration model |

### Feature: International Entry Flags

| Version | Change | Reason |
|---|---|---|
| v0.2 | EES (Schengen), UK entry, Australia eTA flags. Static — always shown for international trips. | Validate entry-requirement awareness feature |
| v0.5 | Flags auto-dismiss when matching checklist item is completed. | Flags were showing as "done" trips still had alerts; felt like nagging |
| v0.5 | Non-US traveler ESTA/US Visa flags added. | Only US passport holders were supported; discriminatory omission |
| v0.5 | EES deduplication via `new Set()` on country codes. | Paris→Versailles→Paris multi-stop showed EES flag 3 times |
| v0.5 | Passport selector expanded from 6 to 195 countries. | Non-US focus group participants couldn't select their passport country |

### Feature: Packing List

| Version | Change | Reason |
|---|---|---|
| v0.4 | `buildPackingDefaults()` implemented. Seasonal logic (beach, mountain, cold/rainy, Northern EU). Power adapters by region. | Move packing from checklist into dedicated tab |
| v0.4 | PackingView shows "Generate packing list" button on first open. | Initial UX; required explicit user action |
| v0.5 | Auto-generation on first tab open via `useEffect`. Button retained as manual fallback. | "Generate" button was invisible to many users; list appeared empty |
| v0.5 | `normalizeTrip` sentinel fixed: `packingList: []` → `null`. | `initialised` check was `!= null`, which passed for `[]`; auto-generate never fired for existing/demo trips |

### Feature: City Tips

| Version | Change | Reason |
|---|---|---|
| v0.2 | Initial CityTidbits component. Static Miami content hardcoded. | POC for local tips concept |
| v0.4 | Dynamic per-city content. 9 cities: London, Paris, Austin, Anaheim, Miami, New York, Chicago, Nashville, Las Vegas. Getting Around uses city-specific transport text. | Tester reported all City Tips showed "Miami" regardless of destination |
| v0.5 | Borough aliases: Brooklyn/Manhattan/Queens/Bronx → resolve to New York key in CITY_LOCAL_TIPS. | Users typing "Brooklyn" as their city saw no Nearby/Food/Insider sections |
| v0.5 | CITY_TO_COUNTRY expanded with 50+ cities: Versailles, French cities, Austrian cities, Scandinavian cities, NZ cities, African cities, NYC boroughs | Versailles destination showed US flag; multi-stop European trips missing city recognition |

### Feature: PWA / Offline

| Version | Change | Reason |
|---|---|---|
| v0.1 | Service worker via Blob URL. Cache-first for CDN assets. Network-first for everything else. | Enable offline use after first load |
| v0.4 | STATIC asset list explicitly cached on install. `Promise.allSettled` (not `Promise.all`) to avoid install failure on one asset miss. | Install was failing if a single font variant failed to cache |
| v0.5 | CACHE bumped to `locale-v7` | Force cache refresh after v0.5 changes not appearing for users |

---

## 5. Technical Debt Register

### Debt-001: In-Browser Babel Transpilation

**Description:** JSX is transpiled by Babel Standalone at runtime in the user's browser on every first load.

**Impact:** 2–4 second delay on first load on mobile. No tree-shaking. No source maps in production. DevTools debugging is awkward.

**Severity:** High — directly affects perceived performance and developer experience.

**Why accepted:** Single-file constraint requires it. Build toolchain (Vite, webpack) requires separate files.

**Recommended fix:** Migrate to Vite + React project structure. Pre-compile JSX at build time.

---

### Debt-002: No Backend / No Real-Time Sync

**Description:** Trips are local-only. Sharing is snapshot-based. No user accounts.

**Impact:** Users lose trips if they clear storage. Shared trips go stale. Group collaboration is simulated (share → add → diverge).

**Severity:** High — limits core value proposition for group travel use case.

**Why accepted:** Backend setup takes weeks. POC goal is to validate the concept before investing in infrastructure.

**Recommended fix:** Supabase for auth + real-time database. Trips stored server-side. Sharing becomes a reference (trip ID) rather than a data payload.

---

### Debt-003: packingList Sentinel Bug (Resolved in v0.5)

**Description (historical):** `normalizeTrip()` originally set `packingList: t.packingList ?? []`, so all trips (including those that had never generated a packing list) had `packingList: []`. The PackingView check `trip.packingList != null` returned `true` for `[]`, so `initialised = true` and auto-generation never fired.

**Resolution:** `normalizeTrip()` now sets `packingList` to `null` if the array is empty: `(Array.isArray(t.packingList) && t.packingList.length > 0) ? t.packingList : null`. PackingView checks `Array.isArray(trip.packingList) && trip.packingList.length > 0`.

**Lesson:** Empty array and "never set" are semantically different states and must be represented differently. `null` = uninitialised; `[]` is ambiguous.

---

### Debt-004: VWP Array Duplicated

**Description:** The Visa Waiver Program country list (`VWP`) is defined identically in `getIntlFlags()` (line ~762) and `generateChecklist()` (line ~822).

**Impact:** Risk of divergence if one is updated and not the other. Flags could show "ESTA required" but checklist item says "US Visa required" for the same passport country.

**Severity:** Medium — latent correctness risk.

**Recommended fix:** Extract to a module-level constant:
```javascript
const VWP_COUNTRIES = ['GB','DE','FR',...];
```
Reference from both functions.

---

### Debt-005: No API Key Security

**Description:** User's Anthropic API key is stored in `localStorage` in plain text and sent from the browser directly to `api.anthropic.com`. Any JavaScript running on the page can read it. If the user is on a compromised network, the key is visible in transit (HTTPS protects against passive eavesdropping but not malicious JS).

**Impact:** If the API key is compromised, the attacker can make API calls on the user's account until they rotate the key.

**Severity:** Medium — acceptable for beta with technical testers; not acceptable for general consumer release.

**Why accepted:** No backend proxy exists. For POC with informed testers, risk is disclosed.

**Recommended fix:** Backend proxy. The app sends a trip description to your own server; the server calls Anthropic with a server-side key; the server returns the result. Users never handle API keys.

---

### Debt-006: Full-Array Save on Every Mutation

**Description:** Every time any field of any trip changes, `JSON.stringify(allTrips)` is called and the entire array is written to localStorage.

**Impact:** As trips accumulate or grow large (AI-generated itineraries), saves become slower. On mobile, this can cause a visible freeze. More importantly, it increases the risk of hitting the localStorage quota.

**Severity:** Low now, Medium at scale.

**Recommended fix:** IndexedDB for storage (supports partial record updates). Or backend persistence with partial updates (PATCH vs PUT).

---

### Debt-007: No Input Sanitization on AI Output

**Description:** The AI generator parses Claude's response and uses the data directly to populate the trip's `days` array. If Claude returns unexpected field types, deeply nested objects, or malicious content (prompt injection through venue names), it goes straight into state.

**Impact:** Malformed AI output can crash the app. In theory, a crafted venue name could contain script content that gets rendered unsafely (though React's JSX escaping mitigates XSS).

**Severity:** Low — Claude Haiku's output is generally well-structured and React escapes text content.

**Recommended fix:** Validate and sanitize each `day`, `activity`, and `restaurant` object against a schema before saving. Zod would be ideal in a proper project.

---

### Debt-008: Service Worker Scope Limitation

**Description:** The Blob URL service worker may not intercept navigation requests in all browsers because its scope is `blob:` origin rather than the page's origin. Safari in particular has inconsistent behavior with this pattern.

**Impact:** Offline mode may not work correctly for navigation (returning to the app while offline). CDN asset caching (fonts, React, Babel) may still work because those are CDN fetch requests, not navigation.

**Severity:** Medium — offline mode is partially broken on Safari, which is the primary test device (iPhone).

**Recommended fix:** Move to a proper multi-file project with a real `sw.js`. This is the only clean fix.

---

## 6. Experiment Log

### Experiment: SRI Integrity Hashes (v0.4)

**What:** Added `integrity` and `crossorigin` attributes to CDN `<script>` tags. A helper script was generated to compute SHA-384 hashes.

**Why:** Standard security practice to prevent CDN-injected malicious scripts.

**Method:** `curl` to fetch resource bytes, pipe through `openssl` to compute hash.

**Result:** The curl approach returned hashes for a redirect response page, not the actual script content. The wrong hashes caused the browser to refuse to load React/Babel, breaking the entire app.

**Decision:** **Reverted.** SRI hashes deferred to production phase. At that point, the recommended fix is to vendor dependencies locally (eliminate CDN dependency entirely) rather than use SRI.

---

### Experiment: Emoji Picker (v0.1–v0.4)

**What:** A preset grid of trip-relevant emoji (✈️, 🏖️, 🏔️, etc.) shown in the new trip wizard. Selected emoji stored in `trip.emoji` field and shown as a badge on trip cards.

**Why:** Wanted trip cards to feel distinctive and fun without requiring users to browse a full emoji keyboard.

**Result:** Users found the preset selection limiting. The grid added visual clutter to the creation form. The `trip.emoji` field created a parallel display path alongside title-embedded emoji.

**Decision:** **Removed in v0.5.** Users now type emoji directly in the trip name field from their device keyboard. The card and hero strip the leading emoji from the title using `/^\p{Emoji}\s*/u` and render it separately from the text title. More flexible, less cluttered.

---

### Experiment: Name Search — Wandr, Voya, Cartae, Traverse, Drift, Passage, Portolan (Pre-v0.1)

**What:** 30+ potential product names evaluated against trademark registries, App Store search, and web presence.

**Result:** All above names had conflicts:
- Wandr — too common, multiple existing apps
- Voya — Voya Financial (NYSE: VOYA) trademark conflict
- Cartae — cartae.net SaaS; also a musician with that name
- Traverse, Drift, Passage, Portolan — all taken

**Final choice:** **Locale** — "a place" — clean, no USPTO conflict found, no major app or SaaS using it for travel.

---

## 7. MVP Readiness Assessment

*As of v0.5 — June 2026*

| Capability | Status | Notes |
|---|---|---|
| Trip creation (multi-stop) | **User Tested** | Working well; date picker UX still native browser widget |
| AI itinerary generation | **User Tested** | Works; requires user API key (friction point); hallucinations on venue details |
| Smart checklist | **User Tested** | Auto-generates correctly; international entry logic now covers US, EU, UK, AU |
| Packing list | **Functional** | Auto-generates on first open; custom add works; not yet user-tested post-fix |
| Day-by-day itinerary view | **User Tested** | SortableJS drag-to-reorder works on desktop; iOS drag needs testing |
| Trip sharing (snapshot) | **User Tested** | Works; limitation (not live sync) is documented in-app |
| PDF export | **User Tested** | Functional; styling matches app brand; not print-perfect |
| City Tips | **Functional** | 9 cities; borough alias fix in v0.5 not yet validated post-deploy |
| Currency converter | **User Tested** | Fixed rates; works for quick estimates |
| International entry flags | **User Tested** | All passport types now covered; auto-dismiss on checklist completion works |
| Offline mode | **Prototype** | CDN assets cached; navigation interception unreliable on Safari (Blob SW scope issue) |
| PWA install | **Functional** | Install banner works on Android; iPhone requires manual Share → Add to Home Screen |
| Backup export/import | **Functional** | JSON download + restore works; not user-tested |
| Confirmation upload (AI extraction) | **Functional** | Hotel + flight PDFs/images extracted correctly; requires API key |
| Bug reporting | **Functional** | Auto-collects device/version/error log info; mailto workaround for Safari |

### Overall MVP Readiness

**Current state:** Strong proof of concept. The core loop (create trip → generate itinerary → share with group) works end-to-end. The app is usable for real trip planning by early adopters who are comfortable with a beta product.

**Blockers before public launch:**
1. Backend sync (without it, "group planning" is misleading — it's solo planning + read-only sharing)
2. API key friction (most consumers won't create an Anthropic account)
3. Offline mode reliability on Safari
4. AI venue accuracy (hallucinated addresses undermine trust)

**Recommended path to MVP:**
1. Supabase backend for trip storage + real-time sync
2. Backend API proxy (remove user API key requirement)
3. Proper multi-file project structure (Vite + React)
4. Move service worker to real `sw.js`
5. User accounts (optional for MVP if trip sharing uses a read/write link pattern)

---

## 8. Architecture Snapshots

### Snapshot: June 2026 (v0.5)

**Date:** 2026-06-07  
**Version:** v0.5 · 3,885 lines

**Architecture:**
- Single HTML file, in-browser Babel, React 18.2.0, no build step
- localStorage (key: `locale_v4`), SCHEMA_VERSION 3
- Service worker via Blob URL, CACHE `locale-v7`
- PWA manifest via Blob URL
- Claude Haiku via direct browser API call, user-supplied key
- Trip sharing via base64 URL hash (snapshot, not live)
- GitHub Pages deployment, GitHub Actions CI/CD

**Major capabilities live:**
- Trip creation wizard (multi-step, multi-stop)
- AI itinerary generator + confirmation upload + refinement panel
- Day-by-day itinerary view with drag-to-reorder
- Smart checklist + packing list (auto-generated)
- Currency converter (fixed rates)
- City Tips for 9 cities + borough aliases
- International entry flags (all passport types, checklist-dismissible)
- PDF export
- Trip sharing (snapshot)
- Backup export/import
- PWA (install, offline partial)
- Inline test suite (35 assertions)
- Bug report button (floating, auto-attaches context)

**Known technical debt:**
- In-browser Babel (load time)
- No backend / no real-time sync
- VWP array duplicated in two functions
- API key stored in localStorage, no proxy
- Full-array save on every mutation
- Service worker Blob URL scope limitation on Safari
- No AI output validation/sanitization

**Open testing feedback (pending validation post v0.5 push):**
- Packing list auto-generation (sentinel fix) — not yet confirmed on live device
- Borough City Tips (Brooklyn → New York alias) — not yet confirmed on live device
- Overview box alignment — not yet confirmed on live device

---

*End of Engineering History & Architecture Record v1.0*  
*Next update: When meaningful architecture changes are made, new features ship, or at start of next month (July 2026 snapshot).*
