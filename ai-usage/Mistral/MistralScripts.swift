import Foundation

enum MistralScripts {

    /// admin.mistral.ai/subscription. Finds each allowance heading by pattern (not exact text, since
    /// Mistral renames them: "Included Vibe Code usage" became "Included Vibe & Studio usage" in
    /// Nov 2026), climbs to the smallest ancestor holding both a currency amount and a "Resets in"
    /// line, and reads only inside that block, so other € amounts on the page (plan price,
    /// pay-as-you-go) can never leak in.
    /// Headings must be short (≤ 60 chars) and end in "usage", which skips the description paragraphs
    /// ("Included allowance for Vibe & Studio. Resets…") and "Pay-as-you-go for Vibe & Studio".
    /// Returns '' until at least one block exists, so `poll` keeps waiting.
    static let allowances = #"""
    const root = document.querySelector('main');
    if (!root) return '';
    const HEAD_TAGS = 'span,div,p,h1,h2,h3,h4,h5,label,dt,button,strong';
    const ownText = el => [...el.childNodes].filter(n => n.nodeType === 3).map(n => n.textContent).join('').trim();
    const leafWithText = re => [...root.querySelectorAll(HEAD_TAGS)]
      .find(el => { const t = ownText(el); return t.length > 0 && t.length <= 60 && re.test(t); }) ?? null;
    const read = re => {
      const head = leafWithText(re);
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
    const api = read(/^Included\s+API\b.*\busage$/i);
    const vibeCode = read(/^Included\s+(?!API\b).*\b(vibe|code)\b.*\busage$/i);
    if (!api && !vibeCode) return '';
    return JSON.stringify({ api, vibeCode });
    """#
}
