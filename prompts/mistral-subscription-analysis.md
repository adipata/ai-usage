# Prompt: Find out why the Vibe Code allowance is no longer read from admin.mistral.ai

> Give this prompt to an agent that can open **https://admin.mistral.ai/subscription** in a browser where the user is **already signed in**, for example Claude in Chrome. The agent needs to run JavaScript in the page and inspect the DOM. A plain web-fetch agent won't work, because the page needs the user's session.

---

## Your role

You are analysing the live admin.mistral.ai Subscription page for an iOS app called "AI Usage". The app reads this page in a hidden web view and shows the two included monthly allowances on a dashboard card. As of 23 Nov 2026 the app still reads the **API** allowance but no longer finds the **Vibe Code** allowance. Your job is to find out what changed in the page and to hand back a corrected extraction script that you have tested on the live page.

You are only investigating. **Do not change anything in the account.** Don't click upgrade, buy, cancel, top-up, billing or plan-change buttons, and don't submit any forms. The only interactions allowed are expanding collapsed sections, switching tabs and scrolling, if needed to reveal the allowance.

## What the app sees today

The app's script returned this on 23 Nov 2026:

```json
{"api":{"used":"€0.22","limit":"€25.5","reset":"Resets in 7 days","barPercent":0.8662839999999932},
 "vibeCode":null}
```

The card shows the API row (€0.22 / €25.5, "in 7 days") and the note "Vibe Code allowance not found".

## How the page looked when the script was written (6 Nov 2026, Pro plan)

```
main
└─ h1 "Subscription"
   … section label "Included monthly allowance"   (rendered uppercase by CSS)
   ├─ div  ← allowance block (API)
   │  ├─ div > span "Included API usage"
   │  ├─ p "Included allowance for API/Studio usage. Resets on the first day of each calendar month, …"
   │  └─ div
   │     ├─ span "€0.1"          used
   │     ├─ span "€25.5"         limit
   │     ├─ div[role="progressbar"] > div style="transform: translateX(-99.6%)"
   │     └─ span "Resets in 24 days"
   └─ div  ← allowance block (Vibe Code), same shape
         span "Included Vibe Code usage" · €4.02 · €255 · "Resets in 24 days"
```

The page was server-rendered (Next.js). No JSON request carried the allowances; the only XHR was a `user.meSession` tRPC call.

## The script the app runs (via `WKWebView` `callAsyncJavaScript`, with a top-level `return`)

```js
const leafWithText = t => [...document.querySelectorAll('main span, main div, main h2, main h3')]
  .find(e => [...e.childNodes].some(n => n.nodeType === 3 && n.textContent.trim().toLowerCase() === t.toLowerCase()));
const read = label => {
  const head = leafWithText(label);
  if (!head) return null;
  let block = head;
  for (let i = 0; i < 6 && block; i++) {
    if (/€|\$|£/.test(block.innerText) && /(^|\n)\s*Resets in/i.test(block.innerText)) break;
    block = block.parentElement;
  }
  if (!block) return null;
  const amounts = [...block.querySelectorAll('span')]
    .map(s => s.textContent.trim())
    .filter(t => /^([€$£]\s?\d[\d.,]*|\d[\d.,]*\s?[€$£])$/.test(t));
  const reset = block.innerText.split('\n').map(s => s.trim()).find(l => /^Resets in /i.test(l)) ?? null;
  const tx = block.querySelector('[role="progressbar"] > div')?.style.transform.match(/translateX\((-?[\d.]+)%\)/);
  return { used: amounts[0] ?? null, limit: amounts[1] ?? null, reset,
           barPercent: tx ? Math.max(0, Math.min(100, 100 + Number(tx[1]))) : null };
};
const api = read('Included API usage');
const vibeCode = read('Included Vibe Code usage');
if (!api && !vibeCode) return '';
return JSON.stringify({ api, vibeCode });
```

To run it in the DevTools console, wrap it as `(() => { … })()`.

`read()` returns `null` in exactly three cases. Work out which one applies:
1. **No heading match:** no `span`/`div`/`h2`/`h3` inside `main` has a direct text node equal to "Included Vibe Code usage" (case-insensitive). Possible reasons: the heading was renamed, it is now another element type (`p`, `h4`, `label`, `button`, `dt`), the text is split across nodes, or the block is outside `main`.
2. **Climb failed:** within 6 ancestors, no element contains both a currency symbol and a line starting with "Resets in".
3. **Not rendered:** the block isn't in the DOM when the script runs. It might be in a closed tab, accordion or dialog, loaded lazily or client-side, on a different page, or only rendered for some plans.

Also find out whether the allowance itself changed, not just the markup. Was it renamed (e.g. "Mistral Vibe", "Vibe usage", "Code usage", "Le Chat / Vibe")? Was it merged into the API allowance, or moved to another page (e.g. `/usage`, `/billing`, a "Vibe" or "Code" section)? Is it no longer part of the user's plan?

## Steps

1. Open https://admin.mistral.ai/subscription and wait for it to finish loading. Note the final URL, in case it redirects.
2. Run the current script unchanged and record its output.
3. Inventory the page without dumping it all:
   - Every element inside `main` whose text contains "vibe" or "code" (case-insensitive): tag, a short CSS path, its own text, and whether it is visible (`offsetParent !== null`).
   - Every text node matching `/Included .* usage/i`, plus the "Included monthly allowance" section label and its siblings.
   - Every `[role="progressbar"]` and every `span` whose whole text is a currency amount, each with its nearest heading-like ancestor text.
   - Any tabs (`[role="tab"]`), accordions (`[aria-expanded]`), `details` elements or "Show more" buttons near the allowances, with their state.
4. If there is no Vibe Code block on this page:
   - Check whether expanding a section or switching a tab reveals it, and record what had to be clicked (selector and `aria-*` state).
   - Check the navigation for related links (`a[href]` containing "vibe", "code", "usage", "billing", "limits") and look at those pages read-only.
   - Check the Network panel to see whether the data now arrives as JSON (tRPC, `/api/…`, RSC payloads with `RSC: 1`). If so, record the request path and method, and the parts of the response shape that carry used, limit and reset. **Do not record cookies, auth headers, tokens, IDs or emails.**
5. Write a corrected script that meets these requirements:
   - Same return contract: `JSON.stringify({ api, vibeCode })`, each `{ used, limit, reset, barPercent }` or `null`, and `''` while not ready.
   - Still finds the API allowance.
   - Still reads only inside each allowance's own block, so the plan price or pay-as-you-go amounts can't leak in.
   - Tolerant of the most likely next change, e.g. matching headings by `/^Included .*vibe/i` instead of exact text, and allowing the extra element types you observed.
   - If a click is needed to reveal the block, does it in the script (like `toggle.click()` and `await new Promise(r => setTimeout(r, 500))`) and only on a clearly identified disclosure control.
6. Run the corrected script on the live page and paste its exact output.

## What to hand back

A short report in Markdown with these sections:

1. **Diagnosis:** which of the three failure cases applied, and what changed on the page. Give before/after heading text, element types and location.
2. **Current anatomy:** a tree like the one above, for both allowance blocks, using only stable hooks (text, roles, `aria-*`, `data-*`). Leave out hashed class names.
3. **Corrected script:** the full script, ready to paste into `ai-usage/Mistral/MistralScripts.swift` as the `allowances` raw string.
4. **Verified output:** the exact JSON the corrected script returned on the live page, and the date.
5. **App changes needed beyond the script:** for example a different URL in `MistralWebService.subscriptionURL`, a new nav-link fallback, a click before reading, a JSON endpoint instead of the DOM, or a renamed row title in `MistralUsageParser`. Say "none" if there are none.
6. **Test fixture:** a JSON string of the script output to add to `ai-usageTests/Fixtures.swift`. Round the amounts but keep them realistic.
7. **Still unknown:** anything you couldn't confirm.

## Privacy rules for the report

- Don't include the full page HTML, or any `outerHTML` longer than one short element.
- Don't include emails, names, organization or workspace IDs, invoice numbers, payment details, cookies, tokens or request headers.
- Euro amounts for the two allowances are fine, because the app shows them anyway.
