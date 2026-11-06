/* Visual-only pointer lighting and 3D tilt; delegates over dynamic NUI cards.
   No click handlers, server calls, events, game controls, storage or polling. */
(() => {
  'use strict';
  const app = document.getElementById('app');
  if (!app) return;
  const matches = '.tablet-screen .content .workspace-tile, .tablet-screen .content .action-tile, .tablet-screen .content .card, .tablet-screen .content .library-card, .tablet-screen .content .world-card, .tablet-screen .content .theme-card, .tablet-screen .content .prank';
  const reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)');
  let active = null;
  let rect = null;
  let next = null;
  let raf = 0;
  const enabled = () => !app.classList.contains('hidden') && !['off','none'].includes(app.dataset.motion) && !(reduce && reduce.matches);
  const reset = () => {
    if (active && active.isConnected) {
      active.style.removeProperty('--rsfx-rx');
      active.style.removeProperty('--rsfx-ry');
      active.style.removeProperty('--rsfx-mx');
      active.style.removeProperty('--rsfx-my');
    }
    active = null; rect = null; next = null;
    if (raf) cancelAnimationFrame(raf);
    raf = 0;
  };
  const pick = node => node && node.closest ? node.closest(matches) : null;
  app.addEventListener('pointerover', e => {
    if (e.pointerType === 'touch' || !enabled()) return;
    const el = pick(e.target);
    if (!el || el === active) return;
    reset(); active = el; rect = el.getBoundingClientRect();
  }, { passive:true });
  app.addEventListener('pointermove', e => {
    if (!enabled() || e.pointerType === 'touch') { if(active)reset(); return; }
    const el = pick(e.target);
    if (!el) {if(active)reset(); return;}
    if (el !== active) {reset();active = el;rect = el.getBoundingClientRect();}
    if (!rect.width || !rect.height) return;
    const x = Math.max(0,Math.min(1,(e.clientX - rect.left)/rect.width));
    const y = Math.max(0,Math.min(1,(e.clientY - rect.top)/rect.height));
    next = {x,y};
    if (raf) return;
    raf = requestAnimationFrame(() => {
      raf = 0;
      if (!active || !active.isConnected || !next || !enabled()) {reset();return;}
      const {x,y} = next;
      active.style.setProperty('--rsfx-rx',`${((.5-y)*5).toFixed(2)}deg`);
      active.style.setProperty('--rsfx-ry',`${((x-.5)*6).toFixed(2)}deg`);
      active.style.setProperty('--rsfx-mx',`${Math.round(x*100)}%`);
      active.style.setProperty('--rsfx-my',`${Math.round(y*100)}%`);
    });
  }, {passive:true});
  app.addEventListener('pointerout',e => {
    if (!active || !active.contains(e.target)) return;
    if (e.relatedTarget && active.contains(e.relatedTarget)) return;
    reset();
  }, {passive:true});
  window.addEventListener('blur',reset);
})();
