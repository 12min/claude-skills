---
name: find-google-flight
description: >
  Use this skill when the user wants to programmatically query Google Flights —
  build deep links from origin/destination/date triples (one-way, round-trip,
  multi-city), scrape prices headless with Playwright, monitor over time via
  cron + Telegram alerts, or extract the price-history qualifier ("baixos/típicos/altos").
  Trigger on phrases like "monitorar passagens", "rastrear voos", "preço aéreo",
  "google flights tfs", "deep link voo", "alerta passagem", or any task that needs
  airfare without paying Skyscanner/Kiwi/Travelpayouts API costs.
version: 1.0.0
author: Renato Filho
license: MIT
metadata:
  tags: [flights, google-flights, playwright, monitoring, telegram, tfs, deep-link]
  related_skills: [livelo-flights]
  shareable: true
  any-ai-client: true
---

# find-google-flight — Google Flights Programmatic Search

## Overview

Google Flights has no public API. But it accepts a `tfs=` query parameter — a base64-protobuf payload that encodes origin, destination, date(s), and trip type. With that, you can build deep links from code, scrape results headless, and monitor prices over time without scraping the UI form. Falls back to qualifier-only when prices change shape (the "baixos/típicos/altos" indicator stays stable).

## When to Use

- User wants to **monitor airfare prices** for specific routes/dates
- User asks to **build a deep link** to Google Flights from origin/destination/date
- User wants a **cron-based price monitor with Telegram alerts**
- User wants to extract **price qualifier** (low/typical/high) from Google's insights panel
- Task involves comparing **cash price vs miles** (Livelo, Smiles, etc.) — combine with `livelo-flights` skill

## When NOT to Use

- Real-time booking (Google doesn't expose booking API; redirects to OTA)
- Hotels (use `decolar` or `livelo-flights` for hotels)
- Buses (use ClickBus skills; Google doesn't index bus)
- Detailed fare breakdown (baggage, class) — Google only exposes total

## Build the `tfs=` URL

The encoding is protobuf serialized as base64 (URL-safe `_` and `-`, no padding `=`).

### Trip-type byte (last varint field 19)

| Type | Last bytes |
|---|---|
| One-way | `mgB 01` → in base64 ends with `AZgBAg` (binary `0x98 0x01 0x02`) |
| Round-trip | `AZgBAQ` (binary `0x98 0x01 0x01`) |
| Multi-city | `AZgBAw` (binary `0x98 0x01 0x03`) |

### Per-leg structure (30 bytes)

```
0x1a 0x1e               // field 3 length-delimited, 30 bytes (leg wrapper)
  0x12 0x0a "YYYY-MM-DD"  // field 2 string (date, 10 ASCII bytes)
  0x6a 0x07 0x08 0x01 0x12 0x03 "ORG"  // field 13 (origin IATA 3-char)
  0x72 0x07 0x08 0x01 0x12 0x03 "DST"  // field 14 (destination IATA)
```

### Full payload

```
0x08 0x1c 0x10 0x02   // header (passenger count + marker)
<leg 1>               // 32 bytes total
<leg 2 if round-trip> // 32 bytes
0x40 0x01 0x48 0x01 0x70 0x01                              // misc fields
0x82 0x01 0x0b 0x08 ff ff ff ff ff ff ff ff ff 0x01        // varint
0x98 0x01 <trip-type>                                       // trip-type field
```

### Node.js builder

```js
function buildTfs(legs, type /* 1=oneway, 2=roundtrip, 3=multicity */) {
  const writeLeg = (date, orig, dest) => {
    const dateField = Buffer.concat([Buffer.from([0x12, 0x0a]), Buffer.from(date)]);
    const origField = Buffer.concat([Buffer.from([0x6a, 0x07, 0x08, 0x01, 0x12, 0x03]), Buffer.from(orig)]);
    const destField = Buffer.concat([Buffer.from([0x72, 0x07, 0x08, 0x01, 0x12, 0x03]), Buffer.from(dest)]);
    const body = Buffer.concat([dateField, origField, destField]);
    return Buffer.concat([Buffer.from([0x1a, body.length]), body]);
  };
  const header = Buffer.from([0x08, 0x1c, 0x10, 0x02]);
  const legsBuf = Buffer.concat(legs.map(l => writeLeg(l.date, l.orig, l.dest)));
  const tail = Buffer.from([
    0x40, 0x01, 0x48, 0x01, 0x70, 0x01,
    0x82, 0x01, 0x0b, 0x08, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01,
    0x98, 0x01, type,
  ]);
  return Buffer.concat([header, legsBuf, tail])
    .toString('base64')
    .replace(/=+$/, '')
    .replace(/\//g, '_')
    .replace(/\+/g, '-');
}

// Example: round-trip GRU → SCL 2026-10-28 → 2026-11-02
const tfs = buildTfs([
  { date: '2026-10-28', orig: 'GRU', dest: 'SCL' },
  { date: '2026-11-02', orig: 'SCL', dest: 'GRU' },
], 1);
const url = `https://www.google.com/travel/flights/search?tfs=${tfs}&hl=pt-BR&curr=BRL`;
```

## Scrape Prices Headless

### Setup

```bash
npm i playwright
npx playwright install chromium --with-deps
```

### Working scraper

```js
import { chromium } from 'playwright';

async function fetchRoute(url) {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  const ctx = await browser.newContext({
    userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
    viewport: { width: 1480, height: 800 },
    locale: 'pt-BR',
  });
  const page = await ctx.newPage();
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.waitForFunction(() => /R\$\s*\d/i.test(document.body.innerText), { timeout: 45000 });
  await page.waitForTimeout(3000);

  const text = await page.evaluate(() => document.body.innerText);

  // Match prices labeled "ida e volta" (round-trip) OR "viagem completa" (multi-city)
  // For one-way add "ida" to the alternation.
  const matches = [...text.matchAll(
    /R\$\s*(\d{1,3}(?:\.\d{3})*)\s*\n?\s*(ida e volta|viagem completa|ida)/gi
  )].map(m => parseInt(m[1].replace(/\./g, ''), 10))
    .filter(v => v >= 100 && v <= 20000);

  const min = matches.length ? Math.min(...matches) : null;

  // Extract Google's qualifier — "baixos|típicos|altos"
  const qualifier = text.match(/Os preços estão (baixos|típicos|altos)/i)?.[1] ?? null;

  await browser.close();
  return { min, count: matches.length, qualifier };
}
```

### Pitfalls

- **Locale matters.** Without `locale: 'pt-BR'` + `&hl=pt-BR&curr=BRL`, the page renders in English with `$` and the regex misses.
- **The regex's `(ida e volta|viagem completa)` only matches round-trip + multi-city.** For one-way add `|ida` — but be careful, the word "ida" also appears in labels like "Ida e volta" → use exact alternation matching.
- **Wait for `R$` text in body**, not for a DOM selector. Google changes class names; the text label is stable.
- **Filter `100 ≤ v ≤ 20000`** to drop bagage fees (single-digit R$) and outliers.

## Price Qualifier (Google's Built-in Baseline)

Google Flights shows a `<div>` with text like:

> "Os preços estão **altos** no momento"

Possible values:

| Qualifier | Meaning | Action |
|---|---|---|
| **baixos** 🟢 | Current price below typical range — buy now | Trigger immediate alert |
| **típicos** 🟡 | Within historical median range | Hold |
| **altos** 🔴 | Above typical — wait for dip | Hold, monitor more |

This is a **qualitative baseline** that doesn't expose the absolute minimum. The full numeric history is only in the "Gráfico de preços" modal (60-day bars with `aria-label="R$ X"` each). Clicking the modal is brittle; the qualifier text is reliable.

## Cron + Telegram Monitor Pattern

### File layout

```
~/livelo-monitor/
├── monitor.mjs      # main script
├── run.sh           # cron wrapper (sources .env, calls node)
├── .env             # TG_TOKEN + TG_CHAT (gitignored)
├── state.json       # last-seen prices per route
└── monitor.log      # rolling log
```

### Crontab

```
0 * * * * cd /path/to/monitor && ./run.sh
```

Runs hourly at minute 0. ~720 executions/month. Within fair use for cheap VPS.

### Alert logic

Trigger Telegram message when any of:
1. **First-run** for a route (no previous state)
2. **Variation ≥ 5%** vs previous measurement
3. **Min < baseline** (per-route hardcoded floor)
4. **Error** (timeout, blocked, no prices found)
5. **Qualifier flip to "baixos"** (Google says low)

### Telegram send

```js
async function tgSend(text) {
  if (!process.env.TG_TOKEN || !process.env.TG_CHAT) return;
  await fetch(`https://api.telegram.org/bot${process.env.TG_TOKEN}/sendMessage`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      chat_id: process.env.TG_CHAT,
      text,
      parse_mode: 'Markdown',
      disable_web_page_preview: true,
    }),
  });
}
```

### Bot setup (one-time)

1. Talk to `@BotFather` on Telegram → `/newbot` → copy token
2. Message the bot once with `/start` (so it can DM you)
3. `curl https://api.telegram.org/bot<TOKEN>/getUpdates` → grab `chat.id`

## What This Skill Does NOT Cover

- **Livelo / Smiles / Latam Pass headless scraping** — these sites use Akamai bot detection and block headless Chromium even with stealth plugins. Use Chrome MCP with a real logged session instead (`livelo-flights` skill).
- **Hotel prices** — use `decolar` or Booking. Note Booking returns `AWS WAF/HTTP 202` for headless; Airbnb works.
- **Bus prices** — ClickBus filters out searches >60d ahead.

## Reference Implementation

Full working monitor: <https://github.com/renatosousafilho/flight-price-monitor> (private)
17+ routes, hourly cron, Telegram alerts with qualifier flip detection.

## Output Format

When this skill is invoked, return:

1. **The tfs= URL(s)** for the requested route(s)
2. **Current min price** scraped (if execution allowed)
3. **Qualifier** (baixos/típicos/altos)
4. **Recommendation**: buy now / wait / monitor more
5. **Monitor stub** (if user wants ongoing tracking) — show cron line + 1-line ROUTE config to append to existing monitor.mjs

Keep responses concise. Include the URL even if scrape failed — user can click through manually.
