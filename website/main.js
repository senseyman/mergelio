// Runs the merge-and-undo demo and the undo clip. Without JS the demo stays
// a still picture of the graph.
(function () {
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
