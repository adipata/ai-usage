import Foundation

/// JavaScript run with `WebPage.callJavaScript` in the hidden Claude pages.
/// Each script returns a JSON string, or '' while the page is not ready yet (so `poll` keeps waiting).
/// None of them reads or returns secrets or raw HTML.
enum ClaudeScripts {

    /// claude.ai Usage modal (`https://claude.ai/new#settings/usage`), fallback only.
    /// Reads the weekly row and every model-scoped row inside `pace-week`; the
    /// "usage by product" meters elsewhere on the screen are ignored.
    /// Expands the collapsed scoped panel first, because hidden elements lose their line breaks in innerText.
    static let usageDOM = #"""
    const dlg = document.querySelector('[role="dialog"][data-perf-screen="usage"]');
    const week = dlg?.querySelector('[data-testid="pace-week"]');
    if (!week) return '';
    const toggle = week.querySelector('[data-testid="pace-week-toggle"]');
    if (toggle && toggle.getAttribute('aria-expanded') === 'false') {
      toggle.click();
      await new Promise(r => setTimeout(r, 500));
    }
    const read = (row, meter) => ({
      name: document.getElementById(meter.getAttribute('aria-labelledby'))?.innerText.trim() ?? '',
      percent: Number(meter.getAttribute('aria-valuenow')),
      reset: (row.innerText.split('\n').find(l => /^Resets\s/.test(l.trim())) ?? '').trim()
    });
    const scopedRows = [...week.querySelectorAll('[data-testid="pace-week-scoped"]')];
    const weeklyMeter = [...week.querySelectorAll('[role="meter"]')]
      .find(m => !scopedRows.some(r => r.contains(m)));
    return JSON.stringify({
      weekly: weeklyMeter ? read(week, weeklyMeter) : null,
      scoped: scopedRows
        .filter(r => r.querySelector('[role="meter"]'))
        .map(r => read(r, r.querySelector('[role="meter"]')))
    });
    """#
}

enum PlatformScripts {

    /// platform.claude.com/dashboard. Each figure is read inside its own `[data-cds="Card"]`,
    /// found by the card title link's href. `a[href="/usage"]` must stay an exact match:
    /// a prefix match would hit the Prompt caching card (`/usage/cache`).
    static let dashboard = #"""
    const cardFor = sel => document.querySelector(`[data-cds="Card"] ${sel}`)?.closest('[data-cds="Card"]');
    const linesOf = c => c ? c.innerText.split('\n').map(s => s.trim()).filter(Boolean) : [];
    const money = /^[$€£][\d,]+(\.\d+)?$/;
    const credits = linesOf(cardFor('a[href="/settings/billing"]'));
    const spend   = linesOf(cardFor('a[href^="/cost"]'));
    const tokCard = cardFor('a[href="/usage"]');
    const tokens  = linesOf(tokCard);
    if ([credits, spend, tokens].some(l => l.length === 0 || l.includes('Loading'))) return '';
    const svg = tokCard.querySelector('svg[viewBox="0 0 100 32"]');
    const bars = svg ? [...svg.querySelectorAll(':scope > g')].map(g =>
      [...g.querySelectorAll('rect')].reduce((s, r) => s + Number(r.getAttribute('height') || 0), 0)) : [];
    const m = (lines, re) => { for (const l of lines) { const x = l.match(re); if (x) return x; } return null; };
    return JSON.stringify({
      credits:      credits.find(l => money.test(l)) ?? null,
      spend:        spend.find(l => money.test(l)) ?? null,
      spendLimit:   m(spend, /^of (.+) limit$/)?.[1] ?? null,
      spendPercent: Number(m(spend, /^(\d+(?:\.\d+)?)% used$/)?.[1] ?? NaN),
      spendResets:  m(spend, /^resets (.+)$/)?.[1] ?? null,
      tokens:       tokens.find(l => /^[\d.,]+\s?[KMB]?$/.test(l)) ?? null,
      tokenTrend:   m(tokens, /^(Up|Down) (\d+(?:\.\d+)?)%/)?.slice(1, 3).join(' ') ?? null,
      tokenPeriod:  tokens.find(l => /^last \d+ days$/.test(l)) ?? null,
      tokenBars:    bars
    });
    """#

    /// platform.claude.com/settings/keys. Columns are found by header text, not position.
    /// The key name comes from the row button's aria-label (or the cell's first line);
    /// the `<code>` element with the masked secret is never touched.
    static let keys = #"""
    const table = [...document.querySelectorAll('table')]
      .find(t => [...t.querySelectorAll('thead th')].some(h => /^Cost/.test(h.innerText.trim())));
    if (!table) return '';
    const heads = [...table.querySelectorAll('thead th')].map(h => h.innerText.trim().split('\n')[0]);
    const col = name => heads.findIndex(h => h === name);
    const [iKey, iScope, iCost] = [col('Key'), col('Scope'), col('Cost')];
    const rows = [...table.querySelectorAll('tbody tr')].map(r => {
      const nameCell = r.cells[iKey];
      const name = (nameCell?.querySelector('button[aria-label]')?.getAttribute('aria-label')
                || nameCell?.innerText.split('\n').map(s => s.trim()).find(Boolean) || '').trim();
      const cost = r.cells[iCost]?.innerText.trim() ?? '';
      return { name, scope: iScope >= 0 ? r.cells[iScope]?.innerText.trim() : null,
               cost: /\d/.test(cost) ? cost : null };
    }).filter(k => k.name);
    return JSON.stringify({ keys: rows, headers: heads });
    """#
}
