// Checks the WebUI in preview mode (sample data, no device) with headless Chromium.
//   node tests/webui.cjs
const { chromium } = require('playwright');
const path = require('path');
const url = 'file://' + path.resolve(__dirname, '../module/webroot/index.html');
let fail = 0;
const t = (name, cond) => { console.log((cond ? '  ok   ' : '  FAIL ') + name); if (!cond) fail = 1; };
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 400, height: 900 } });
  const errs = []; p.on('pageerror', e => errs.push(e.message));
  const cmds = []; await p.exposeFunction('logCmd', c => cmds.push(c));
  await p.goto(url);
  await p.evaluate(() => { const o = window.mockExec; window.mockExec = c => { window.logCmd(c); return o(c); }; });
  await p.waitForTimeout(300);
  const secs = () => p.$$eval('input[data-sec]', e => e.map(x => ({ n: +x.dataset.sec, d: x.disabled, c: x.checked })));
  const lastRun = () => cmds.filter(c => c.includes('setsid')).pop() || '';

  let s = await secs();
  t('10 sections shown', s.length === 10);
  t('quick mode: ART reset (9) locked', s.find(x => x.n === 9).d && !s.find(x => x.n === 2).d);
  t('run button says quick', (await p.textContent('#runBtn')).includes('quick'));
  t('nothing selected: run disabled', await p.isDisabled('#runBtn'));

  await p.locator('input[data-sec="3"]').check({ force: true });
  await p.click('#runBtn'); await p.click('#dlgOk'); await p.waitForTimeout(1500);
  t('quick run command', /cleaner\.sh --mode=quick --sections=3 /.test(lastRun()) && !lastRun().includes('reboot-ok'));
  await p.click('#closeOut');

  await p.click('#modeFull'); await p.waitForTimeout(100);
  s = await secs();
  t('full mode: ART reset unlocked', !s.find(x => x.n === 9).d);
  await p.locator('#all').check({ force: true }); await p.waitForTimeout(100);
  s = await secs();
  t('All sections: every toggle off and greyed', s.every(x => x.d && !x.c));

  await p.click('#runBtn'); await p.waitForTimeout(100);
  t('full: reboot dialog', (await p.textContent('#dlgTitle')).includes('reboot'));
  t('full: OK disabled until box ticked', await p.isDisabled('#dlgOk'));
  await p.check('#ackBox');
  t('full: OK enabled after tick', !(await p.isDisabled('#dlgOk')));
  await p.click('#dlgOk'); await p.waitForTimeout(1500);
  t('full run command', /--mode=full --sections=all --reboot-ok/.test(lastRun()));

  t('no sideways scroll at 400px', (await p.evaluate(() => document.documentElement.scrollWidth)) <= 400);
  t('no JS errors', errs.length === 0);
  if (errs.length) console.log(errs);
  await b.close();
  console.log(fail ? 'SOME WEBUI TESTS FAILED' : 'ALL WEBUI TESTS PASSED');
  process.exit(fail);
})();
