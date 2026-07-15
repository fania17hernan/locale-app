# Locale

**Your trips, beautifully kept.** Locale turns "we should plan that trip" into a day-by-day plan your whole crew can see — itinerary, budget, packing, and local tips in one place, on any device.

**Live:** [localetrips.app](https://localetrips.app) · currently in small-group beta

## What it does

- Day-by-day itineraries drafted by AI, then fully editable
- Crew invites with roles: Crew Members can edit and RSVP, Viewers get read-only access
- Shared budgets with uneven splits and Venmo/Zelle settle-up
- Packing lists and pre-trip checklists tuned to the trip
- Entry-requirement alerts for international trips
- Installable as a PWA (iPhone/Android), works offline, syncs across devices

## How it's built

Single-file React app (`locale-v2.html`) served via GitHub Pages, with Supabase for auth (magic links), row-level-secured storage, and a locked-down server-side AI proxy — API keys never touch the browser.

## Who built this

Built by Stephanie Hernandez — a traveler who got tired of trips living across six group chats, three spreadsheets, and someone's Notes app. Background leading AI transformation in enterprise settings across automotive and healthcare.

Feedback is welcome: use the 💬 button inside the app.
