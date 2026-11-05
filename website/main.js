// Points the hero button at the visitor's platform, wires the copy buttons
// and runs the merge-and-undo demo. Without JS the button falls back to the
// download section and the demo stays a still picture of the graph.
(function () {
  function detectOs() {
    var p = ((navigator.userAgentData && navigator.userAgentData.platform) || navigator.platform || '').toLowerCase();
    var ua = navigator.userAgent.toLowerCase();
    if (/iphone|ipad|ipod|android/.test(ua)) return null;
    // iPadOS reports itself as a Mac; only it has a touch screen.
    if (/macintosh/.test(ua) && navigator.maxTouchPoints > 1) return null;
    if (p.indexOf('mac') === 0 || /macintosh/.test(ua)) return 'mac';
    if (p.indexOf('win') === 0 || /windows/.test(ua)) return 'win';
    if (/linux|x11|cros/.test(p + ' ' + ua)) return 'linux';
    return null;
  }

  var os = detectOs();
  var labels = { mac: 'Download for macOS', win: 'Install on Windows', linux: 'Download for Linux' };
  var cards = document.querySelectorAll('.dl[data-os="' + os + '"]');
  cards.forEach(function (c) { c.classList.add('current'); });

  // Only macOS gets a direct file link. Linux has two packages, and the
  // Windows installer is offered from the GitHub release page rather than
  // linked from this site, so both scroll to their rows instead.
  if (os === 'mac') {
    var link = cards[0] && cards[0].querySelector('a.btn');
    if (link) document.getElementById('primary-download').href = link.href;
  }
  if (labels[os]) document.getElementById('primary-label').textContent = labels[os];

  document.querySelectorAll('.copy').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var text = btn.previousElementSibling.textContent;
      if (!navigator.clipboard) return;
      navigator.clipboard.writeText(text).then(function () {
        btn.textContent = 'Copied';
        setTimeout(function () { btn.textContent = 'Copy'; }, 1500);
      });
    });
  });

  // The undo clip plays only while it is on screen, never when the visitor
  // asked for reduced motion, and can always be paused.
  var clip = document.querySelector('.clip');
  if (clip) {
    var toggle = clip.querySelector('.clip-toggle');
    var reduce = window.matchMedia('(prefers-reduced-motion: reduce)');
    var dark = window.matchMedia('(prefers-color-scheme: dark)');
    var paused = reduce.matches;
    var inView = false;
    var current = function () { return clip.querySelector(dark.matches ? '.clip-dark' : '.clip-light'); };
    var sync = function () {
      clip.querySelectorAll('video').forEach(function (v) {
        if (v !== current() || paused || !inView) v.pause();
      });
      var v = current();
      if (!paused && inView) {
        var p = v.play();
        if (p && p.catch) p.catch(function () {});
      }
      toggle.textContent = paused ? 'Play' : 'Pause';
    };
    toggle.addEventListener('click', function () { paused = !paused; sync(); });
    if (dark.addEventListener) dark.addEventListener('change', sync);
    if ('IntersectionObserver' in window) {
      new IntersectionObserver(function (entries) {
        inView = entries[0].isIntersecting;
        sync();
      }, { threshold: 0.5 }).observe(clip);
    }
    toggle.hidden = false;
    toggle.textContent = paused ? 'Play' : 'Pause';
  }

  var demo = document.getElementById('demo');
  if (!demo) return;
  var merge = document.getElementById('demo-merge');
  var undo = document.getElementById('demo-undo');
  var status = document.getElementById('demo-status');
  var messages = {
    merged: 'Merged feature/login into main. main now points at the new merge commit.',
    undone: 'Merge undone. main is back where it was, and feature/login still has both its commits.'
  };

  function show(state, focusNext) {
    demo.setAttribute('data-state', state);
    status.textContent = messages[state];
    merge.disabled = state === 'merged';
    undo.disabled = state !== 'merged';
    // The pressed button turns disabled, so hand focus to the one that is
    // now live instead of dropping it on the page.
    if (focusNext) focusNext.focus();
  }

  merge.addEventListener('click', function () { show('merged', undo); });
  undo.addEventListener('click', function () { show('undone', merge); });
  status.textContent += ' Merge it, then take it back.';
  demo.querySelector('.demo-actions').hidden = false;
})();
