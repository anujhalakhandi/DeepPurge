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
  const lastRun = () => cmds.filter(c => c.includes('setsid')).pop() || '';

  t('Optimizer tab shown first, tuning listed', (await p.$$('input[data-tune]')).length >= 3 && !(await p.isVisible('#runBtn')));
  await p.click('#tabCln'); await p.waitForTimeout(100);
  t('Cleaner tab shows modes', await p.isVisible('#modeQuick') && await p.isVisible('#runBtn'));
  t('no section list or All toggle', (await p.$$('input[data-sec], #all')).length === 0);
  t('run button says quick', (await p.getAttribute('#modeQuick', 'aria-pressed')) === 'true');
  await p.click('#runBtn'); await p.click('#dlgOk'); await p.waitForTimeout(1500);
  t('quick run command', /cleaner\.sh --mode=quick --sections=all /.test(lastRun()) && !lastRun().includes('reboot-ok'));
  t('while running: Close disabled, Stop enabled', await p.isDisabled('#closeOut') && !(await p.isDisabled('#cancelBtn')));
  await p.waitForTimeout(6000);
  t('finished: Close enabled, Stop disabled', !(await p.isDisabled('#closeOut')) && await p.isDisabled('#cancelBtn'));
  await p.click('#closeOut');

  await p.click('#modeFull'); await p.waitForTimeout(100);
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
