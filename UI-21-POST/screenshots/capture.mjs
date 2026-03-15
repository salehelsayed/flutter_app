import { createRequire } from 'module';
const require = createRequire('/tmp/pw-helper/node_modules/playwright-core/index.js');
const { chromium } = require('/tmp/pw-helper/node_modules/playwright-core');

const WIDE = { width: 800, height: 844 };
const BASE = 'http://localhost:5199';
const OUT = '/Users/I560101/Project-Sat/mknoon-2/kitchen/landing-screen-claude/screenshots';

async function main() {
  const browser = await chromium.launch();
  const context = await browser.newContext({
    viewport: WIDE,
    deviceScaleFactor: 2,
  });

  async function goToPosts(page) {
    await page.goto(BASE);
    await page.waitForTimeout(800);
    await page.evaluate(() => {
      const nodes = document.querySelectorAll('.flow-node');
      for (const n of nodes) {
        if (n.textContent.includes('Posts')) {
          n.scrollIntoView({ block: 'center' });
          n.click();
          break;
        }
      }
    });
    await page.waitForTimeout(1000);
    // Hide flow map, constrain screen to phone width
    await page.evaluate(() => {
      const flowMap = document.querySelector('.flow-map-panel');
      if (flowMap) flowMap.style.display = 'none';
      const sc = document.querySelector('.screen-container');
      if (sc) {
        sc.style.flex = '1';
        sc.style.maxWidth = '390px';
        sc.style.width = '390px';
        sc.style.margin = '0 auto';
      }
    });
    await page.waitForTimeout(200);
  }

  async function hideNav(page) {
    await page.evaluate(() => {
      const navs = document.querySelectorAll('nav');
      navs.forEach(n => n.style.display = 'none');
    });
    await page.waitForTimeout(100);
  }

  async function shot(page, name, file) {
    console.log(`  ✓ ${name}`);
    const sc = await page.$('.screen-container');
    if (sc) {
      await sc.screenshot({ path: `${OUT}/${file}` });
    } else {
      await page.screenshot({ path: `${OUT}/${file}` });
    }
  }

  // ── 1. Default Posts feed ──
  const p1 = await context.newPage();
  await goToPosts(p1);
  await hideNav(p1);
  await shot(p1, 'Default Posts feed', '01-default-feed.png');
  await p1.close();

  // ── 2. Direct-friend text post card ──
  // p6 = Mike's biryani post (type:'friend', text-only, no scope label, reshared by Olivia)
  // p4 = Olivia's translator request (type:'friend', scope:'pick')
  // Best: scroll to p4 which is a direct-friend text-only card with "Shared with you" badge
  const p2 = await context.newPage();
  await goToPosts(p2);
  await hideNav(p2);
  // Scroll to show p4 (Olivia's translator post) — it's the 4th card
  await p2.evaluate(() => {
    const container = document.querySelector('.app-container');
    // Walk all divs to find one containing "translator" with border-radius (card wrapper)
    const allDivs = container.querySelectorAll('div');
    for (const div of allDivs) {
      const cs = getComputedStyle(div);
      if (cs.borderRadius === '16px' && div.textContent.includes('translator') && div.textContent.includes('Olivia')) {
        container.scrollTop = div.offsetTop - 80;
        break;
      }
    }
  });
  await p2.waitForTimeout(500);
  await shot(p2, 'Direct-friend text post card', '02-friend-text-post.png');
  await p2.close();

  // ── 3. Nearby post card with distance label ──
  // p1 = Sarah's dog post (scope:'nearby', 200m away)
  const p3 = await context.newPage();
  await goToPosts(p3);
  await hideNav(p3);
  await p3.evaluate(() => document.querySelector('.app-container').scrollTop = 200);
  await p3.waitForTimeout(500);
  await shot(p3, 'Nearby post card with distance', '03-nearby-post-distance.png');
  await p3.close();

  // ── 4. Passed-along post card ──
  // p2 = Noor's furniture (reshared by Mike)
  const p4 = await context.newPage();
  await goToPosts(p4);
  await hideNav(p4);
  await p4.evaluate(() => document.querySelector('.app-container').scrollTop = 450);
  await p4.waitForTimeout(500);
  await shot(p4, 'Passed-along post card', '04-passed-along-post.png');
  await p4.close();

  // ── 5. Pinned section collapsed ──
  const p5 = await context.newPage();
  await goToPosts(p5);
  await hideNav(p5);
  await p5.evaluate(() => {
    const container = document.querySelector('.app-container');
    const pinnedSection = document.querySelector('[data-pinned-section]');
    if (pinnedSection) {
      container.scrollTop = pinnedSection.offsetTop - 80;
    }
  });
  await p5.waitForTimeout(500);
  await shot(p5, 'Pinned section collapsed', '05-pinned-collapsed.png');

  // ── 6. Pinned section expanded / See all ──
  // Click the Pinned header to expand
  await p5.evaluate(() => {
    const btns = document.querySelectorAll('button');
    for (const b of btns) {
      if (b.textContent.includes('Pinned') && b.textContent.includes('22')) {
        b.click();
        break;
      }
    }
  });
  await p5.waitForTimeout(600);
  await p5.evaluate(() => {
    const container = document.querySelector('.app-container');
    const pinnedSection = document.querySelector('[data-pinned-section]');
    if (pinnedSection) {
      container.scrollTop = pinnedSection.offsetTop - 60;
    }
  });
  await p5.waitForTimeout(300);
  await shot(p5, 'Pinned section expanded', '06-pinned-expanded.png');
  await p5.close();

  // ── 7. Compose sheet default state ──
  const p7 = await context.newPage();
  await goToPosts(p7);
  await p7.locator('text=Share something...').click();
  await p7.waitForTimeout(500);
  await shot(p7, 'Compose sheet default', '07-compose-default.png');
  await p7.close();

  // ── 8. Compose with People Nearby — stale-blocked state ──
  const p8 = await context.newPage();
  await goToPosts(p8);
  await p8.locator('text=Share something...').click();
  await p8.waitForTimeout(400);
  await p8.locator('text=People Nearby').click();
  await p8.waitForTimeout(300);
  // Scroll compose sheet to show the stale status box
  await p8.evaluate(() => {
    const divs = document.querySelectorAll('div');
    for (const el of divs) {
      const s = el.style;
      if (s.position === 'fixed' && s.bottom === '0px' && s.overflow === 'auto') {
        el.scrollTop = el.scrollHeight;
        break;
      }
    }
  });
  await p8.waitForTimeout(300);
  await shot(p8, 'Compose People Nearby — stale-blocked', '08-compose-nearby-stale.png');

  // ── 9. Compose with People Nearby — ready state ──
  // Click "Refresh nearby" button
  await p8.getByRole('button', { name: 'Refresh nearby' }).click();
  await p8.waitForTimeout(1200); // Wait for the 900ms timeout + animation
  // Scroll again to show the ready state
  await p8.evaluate(() => {
    const divs = document.querySelectorAll('div');
    for (const el of divs) {
      const s = el.style;
      if (s.position === 'fixed' && s.bottom === '0px' && s.overflow === 'auto') {
        el.scrollTop = el.scrollHeight;
        break;
      }
    }
  });
  await p8.waitForTimeout(300);
  await shot(p8, 'Compose People Nearby — ready', '09-compose-nearby-ready.png');
  await p8.close();

  // ── 10. Compose with media attached ──
  const p10 = await context.newPage();
  await goToPosts(p10);
  await p10.locator('text=Share something...').click();
  await p10.waitForTimeout(400);
  // Click the "Media" button to attach an image
  await p10.evaluate(() => {
    const btns = document.querySelectorAll('button');
    for (const b of btns) {
      if (b.textContent.trim() === 'Media') {
        b.click();
        break;
      }
    }
  });
  await p10.waitForTimeout(500);
  await shot(p10, 'Compose with media attached', '10-compose-media.png');
  await p10.close();

  // ── 11. Compose while voice recording is active ──
  const p11 = await context.newPage();
  await goToPosts(p11);
  await p11.locator('text=Share something...').click();
  await p11.waitForTimeout(400);
  // Click the "Voice" button to start recording
  await p11.evaluate(() => {
    const btns = document.querySelectorAll('button');
    for (const b of btns) {
      if (b.textContent.trim() === 'Voice') {
        b.click();
        break;
      }
    }
  });
  await p11.waitForTimeout(2500); // Let timer run for a couple seconds
  await shot(p11, 'Compose voice recording active', '11-compose-voice-recording.png');

  // ── 12. Compose after voice recording stops — draft preview ──
  await p11.locator('text=Stop').click();
  await p11.waitForTimeout(400);
  await shot(p11, 'Compose voice draft preview', '12-compose-voice-draft.png');
  await p11.close();

  // ── 13. Comments sheet ──
  const p13 = await context.newPage();
  await goToPosts(p13);
  // Click reply on the first post (has 3 comments)
  await p13.evaluate(() => {
    const buttons = document.querySelectorAll('button');
    for (const btn of buttons) {
      const svg = btn.querySelector('svg path[d*="21 11.5a8"]');
      if (svg) { btn.click(); break; }
    }
  });
  await p13.waitForTimeout(500);
  await shot(p13, 'Comments sheet', '13-comments.png');
  await p13.close();

  // ── 14. Caught-up / empty state ──
  const p14 = await context.newPage();
  await goToPosts(p14);
  await hideNav(p14);
  await p14.evaluate(() => document.querySelector('.app-container').scrollTop = 99999);
  await p14.waitForTimeout(500);
  await shot(p14, 'Caught-up empty state', '14-caught-up.png');
  await p14.close();

  await browser.close();
  console.log('\nDone! 14 screenshots saved to screenshots/');
}

main().catch(e => { console.error(e); process.exit(1); });
