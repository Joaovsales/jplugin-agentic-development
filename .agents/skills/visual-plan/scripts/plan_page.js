/* Visual plan page script: disclosure controls, deep links, navigation, copy.
   Inlined by plan_render.py. No network, no dependencies; every feature
   degrades to the plain <details> page when the script cannot run. */
(function () {
  'use strict';
  var doc = document;
  var all = function (sel, root) { return Array.prototype.slice.call((root || doc).querySelectorAll(sel)); };

  // ------------------------------------------------------------ deep links
  function openTo(hash) {
    if (!hash || hash.length < 2) { return null; }
    var target = doc.getElementById(decodeURIComponent(hash.slice(1)));
    if (!target) { return null; }
    if (target.tagName === 'DETAILS') { target.open = true; }
    var node = target.parentElement && target.parentElement.closest('details');
    while (node) {
      node.open = true;
      node = node.parentElement && node.parentElement.closest('details');
    }
    var inner = target.querySelector(':scope > details');
    if (inner) { inner.open = true; }
    target.scrollIntoView({ block: 'start' });
    return target;
  }
  window.addEventListener('hashchange', function () { openTo(location.hash); });
  doc.addEventListener('click', function (event) {
    var link = event.target.closest && event.target.closest('a[href^="#"]');
    if (link && link.getAttribute('href') === location.hash) { openTo(location.hash); }
  });

  // ------------------------------------------------------------ navigation
  var menu = doc.querySelector('.toc-menu');
  var narrow = window.matchMedia('(max-width: 767px)');
  function fitMenu() { if (menu) { menu.open = !narrow.matches; } }
  if (menu) {
    fitMenu();
    if (narrow.addEventListener) { narrow.addEventListener('change', fitMenu); }
    menu.addEventListener('click', function (event) {
      if (event.target.closest('a') && narrow.matches) { menu.open = false; }
    });
  }
  var links = all('.toc a[href^="#"]');
  function markCurrent(id) {
    links.forEach(function (a) {
      if (a.getAttribute('href') === '#' + id) { a.setAttribute('aria-current', 'true'); }
      else { a.removeAttribute('aria-current'); }
    });
  }
  if ('IntersectionObserver' in window) {
    var spy = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) { if (entry.isIntersecting) { markCurrent(entry.target.id); } });
    }, { rootMargin: '0px 0px -70% 0px' });
    links.forEach(function (a) {
      var section = doc.getElementById(a.getAttribute('href').slice(1));
      if (section) { spy.observe(section); }
    });
  }

  // ------------------------------------------------------------ disclosure
  function setAll(open) { all('main details').forEach(function (d) { d.open = open; }); }
  var onlyBlockers = doc.querySelector('[data-action="blockers"]');
  function toggleBlockers() {
    var on = !doc.body.classList.contains('only-blockers');
    doc.body.classList.toggle('only-blockers', on);
    onlyBlockers.setAttribute('aria-pressed', on ? 'true' : 'false');
    if (on) { all('.sec.has-blockers > details').forEach(function (d) { d.open = true; }); }
  }
  doc.addEventListener('click', function (event) {
    var button = event.target.closest && event.target.closest('button[data-action]');
    if (!button) { return; }
    var action = button.getAttribute('data-action');
    if (action === 'expand') { setAll(true); }
    if (action === 'collapse') { setAll(false); }
    if (action === 'blockers') { toggleBlockers(); }
  });
  var printed = [];
  window.addEventListener('beforeprint', function () {
    printed = all('details:not([open])');
    printed.forEach(function (d) { d.open = true; });
  });
  window.addEventListener('afterprint', function () {
    printed.forEach(function (d) { d.open = false; });
    printed = [];
  });

  // ------------------------------------------------------------ copy
  function copyText(text, button, done) {
    function report(ok) {
      var label = button.getAttribute('data-label') || button.textContent;
      button.setAttribute('data-label', label);
      button.textContent = ok ? (done || 'Copied') : 'Copy failed: select the text';
      setTimeout(function () { button.textContent = label; }, 2000);
    }
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(function () { report(true); }, function () { report(false); });
      return;
    }
    var area = doc.createElement('textarea');
    area.value = text;
    doc.body.appendChild(area);
    area.select();
    var ok = false;
    try { ok = doc.execCommand('copy'); } catch (err) { ok = false; }
    doc.body.removeChild(area);
    report(ok);
  }
  window.planCopy = copyText;
  doc.addEventListener('click', function (event) {
    var button = event.target.closest && event.target.closest('button.copy[data-copy-from]');
    if (!button || button.disabled) { return; }
    var source = doc.getElementById(button.getAttribute('data-copy-from'));
    if (source) { copyText(source.textContent, button); }
  });

  openTo(location.hash);
})();
