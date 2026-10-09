/* Visual plan page script: disclosure controls, deep links, navigation, copy.
   Inlined by plan_render.py. No network, no dependencies; every feature
   degrades to the plain <details> page when the script cannot run. */

// Review state: pure helpers, kept apart from the DOM so they can be tested alone.
var planReview = (function () {
  'use strict';
  function key(sha, spec) { return 'jplugin-plan-review:' + sha + ':' + spec; }
  // A store that never throws: `ok` is false when the browser refuses storage.
  function openStore(getStorage, name) {
    var storage = null;
    try {
      storage = getStorage();
      storage.setItem(name + ':probe', '1');
      storage.removeItem(name + ':probe');
    } catch (err) { storage = null; }
    return {
      ok: storage !== null,
      load: function () {
        if (!storage) { return {}; }
        try { return JSON.parse(storage.getItem(name) || '{}') || {}; } catch (err) { return {}; }
      },
      save: function (state) {
        if (!storage) { return false; }
        try { storage.setItem(name, JSON.stringify(state)); return true; } catch (err) { return false; }
      }
    };
  }
  function flat(text) { return String(text || '').replace(/\s+/g, ' ').trim(); }
  // One export line per item: a pick or an answer wins over the bare mark.
  function line(id, s) {
    var note = flat(s.note) ? ' — ' + flat(s.note) : '';
    if (flat(s.pick)) { return id + ': pick ' + flat(s.pick) + note; }
    if (flat(s.answer)) { return id + ': answer — ' + flat(s.answer) + note; }
    if (s.mark) { return id + ': ' + s.mark + note; }
    return null;
  }
  function format(spec, sha, items) {
    var lines = ['Review of ' + spec + ' @ ' + sha];
    items.forEach(function (item) {
      var text = line(item[0], item[1] || {});
      if (text) { lines.push(text); }
    });
    return lines.join('\n');
  }
  return { key: key, openStore: openStore, line: line, format: format };
})();
if (typeof module === 'object' && module.exports) { module.exports = planReview; }

(function () {
  'use strict';
  if (typeof document === 'undefined') { return; }
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

  // ------------------------------------------------------------ review
  var panel = doc.getElementById('review');
  var cards = all('.review[data-review]');
  if (panel && cards.length) {
    var spec = panel.getAttribute('data-spec');
    var sha = panel.getAttribute('data-sha');
    var store = planReview.openStore(function () { return window.localStorage; }, planReview.key(sha, spec));
    var state = store.load();
    var status = doc.getElementById('review-status');
    if (!store.ok) {
      status.textContent = 'Browser storage is unavailable: review marks will not persist past this page.';
    }
    var showMark = function (box, mark) {
      all('button[data-mark]', box).forEach(function (b) {
        b.setAttribute('aria-pressed', b.getAttribute('data-mark') === mark ? 'true' : 'false');
      });
    };
    cards.forEach(function (box) {
      var saved = state[box.getAttribute('data-review')] || {};
      showMark(box, saved.mark);
      all('[data-field]', box).forEach(function (f) { f.value = saved[f.getAttribute('data-field')] || ''; });
    });
    var update = function (box, change) {
      var id = box.getAttribute('data-review');
      var entry = state[id] || {};
      Object.keys(change).forEach(function (k) { entry[k] = change[k]; });
      state[id] = entry;
      store.save(state);
    };
    doc.addEventListener('click', function (event) {
      var button = event.target.closest && event.target.closest('.review button[data-mark]');
      if (!button) { return; }
      var box = button.closest('.review');
      var mark = button.getAttribute('aria-pressed') === 'true' ? '' : button.getAttribute('data-mark');
      showMark(box, mark);
      update(box, { mark: mark });
    });
    doc.addEventListener('input', function (event) {
      var field = event.target.closest && event.target.closest('.review [data-field]');
      if (!field) { return; }
      var change = {};
      change[field.getAttribute('data-field')] = field.value;
      update(field.closest('.review'), change);
    });
    var exportButton = panel.querySelector('[data-action="export-review"]');
    exportButton.addEventListener('click', function () {
      var items = cards.map(function (box) {
        var id = box.getAttribute('data-review');
        return [id, state[id]];
      });
      var text = planReview.format(spec, sha, items);
      doc.getElementById('review-export').textContent = text;
      copyText(text, exportButton, 'Review copied');
    });
  }

  openTo(location.hash);
})();
