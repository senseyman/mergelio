// Points the hero button at the visitor's platform and wires the copy buttons.
// Without JS the button falls back to the download section.
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
  var labels = { mac: 'Download for macOS', win: 'Download for Windows', linux: 'Download for Linux' };
  var cards = document.querySelectorAll('.dl[data-os="' + os + '"]');
  cards.forEach(function (c) { c.classList.add('current'); });

  // Only macOS gets a direct file link. Linux has two packages, and the
  // Windows installer is offered from the GitHub release page rather than
  // linked from this site, so both scroll to their cards instead.
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
})();
