import Foundation

enum MistralScripts {

    /// admin.mistral.ai/subscription. Finds each heading by its text, climbs to the smallest ancestor
    /// holding both a currency amount and a "Resets in" line, and reads only inside that block,
    /// so other € amounts on the page (plan price, pay-as-you-go) can never leak in.
    /// Returns '' until both blocks exist, so `poll` keeps waiting.
    static let allowances = #"""
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
    """#
}
