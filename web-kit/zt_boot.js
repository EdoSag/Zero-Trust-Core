// Zero-Trust web kit: removes the loading screen once the app has drawn
// its first frame. Kept in its own file because the page's security policy
// allows no inline scripts.
(function () {
  function done() {
    var el = document.getElementById('zt-loading');
    if (el) el.remove();
  }
  window.addEventListener('flutter-first-frame', done, { once: true });
})();
