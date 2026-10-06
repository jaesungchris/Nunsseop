// Headless browser check of docs/index.html (Playwright + Chromium headless shell).
// Run: scripts/site-test.sh
const path = require('path');
const { chromium } = require('playwright');

const url = 'file://' + path.resolve(__dirname, '../docs/index.html');
const langs = ['en', 'ko', 'ja', 'zh', 'es', 'de', 'fr'];
const failures = [];
const check = (ok, msg) => { if (!ok) failures.push(msg); };
const pickLang = async (page, lang) => {
  await page.click('.lang-btn');
  await page.click(`[data-set="${lang}"]`);
};

(async () => {
  const browser = await chromium.launch();

  // Desktop: errors, images, every language.
  const page = await browser.newPage({ viewport: { width: 1280, height: 800 }, locale: 'en-US' });
  page.on('pageerror', e => failures.push('page error: ' + e.message));
  page.on('console', m => { if (m.type() === 'error') failures.push('console error: ' + m.text()); });
  await page.goto(url);
  await page.waitForLoadState('load');

  // Lazy images only load near the viewport, so load them all before checking.
  const broken = await page.$$eval('img', imgs => Promise.all(imgs.map(i => {
    i.loading = 'eager';
    return i.decode().then(() => null, () => i.getAttribute('src'));
  })).then(r => r.filter(Boolean)));
  check(broken.length === 0, 'broken images: ' + broken.join(', '));

  for (const lang of langs) {
    await pickLang(page, lang);
    const r = await page.evaluate(([lang, langs]) => {
      const visible = el => el.getClientRects().length > 0 && getComputedStyle(el).visibility !== 'hidden';
      const own = [...document.querySelectorAll('.' + lang)].filter(visible);
      const others = langs.filter(l => l !== lang)
        .flatMap(l => [...document.querySelectorAll('.' + l)]).filter(visible);
      return {
        own: own.length,
        empty: own.filter(el => !el.textContent.trim() && !el.querySelector('img')).length,
        leaked: others.length,
        htmlLang: document.documentElement.lang,
      };
    }, [lang, langs]);
    check(r.own > 0, `${lang}: no visible text`);
    check(r.empty === 0, `${lang}: ${r.empty} empty visible elements`);
    check(r.leaked === 0, `${lang}: ${r.leaked} elements of other languages visible`);
    check(r.htmlLang.startsWith(lang), `${lang}: <html lang> is ${r.htmlLang}`);
  }

  // Choice survives a reload.
  await pickLang(page, 'de');
  await page.reload();
  check(await page.getAttribute('body', 'data-lang') === 'de', 'language choice not kept after reload');

  // First visit follows the browser language.
  for (const [locale, want] of [['ko-KR', 'ko'], ['ja-JP', 'ja'], ['zh-CN', 'zh'], ['fr-FR', 'fr'], ['it-IT', 'en']]) {
    const ctx = await browser.newContext({ locale });
    const p = await ctx.newPage();
    await p.goto(url);
    const got = await p.getAttribute('body', 'data-lang');
    check(got === want, `locale ${locale}: expected ${want}, got ${got}`);
    await ctx.close();
  }

  // Mobile: nothing wider than the screen.
  const mobile = await browser.newPage({ viewport: { width: 375, height: 812 } });
  await mobile.goto(url);
  // Decorations may extend past the edge; what matters is that the page can't scroll sideways.
  const scrollX = await mobile.evaluate(() => { window.scrollTo(1000, 0); return window.scrollX; });
  check(scrollX === 0, `mobile: page scrolls sideways by ${scrollX}px`);

  await browser.close();
  if (failures.length) {
    console.error(failures.map(f => 'FAIL ' + f).join('\n'));
    process.exit(1);
  }
  console.log(`site OK: ${langs.length} languages, images, persistence, locale detection, mobile width`);
})().catch(e => { console.error(e); process.exit(1); });
