// Shared mobile nav toggle for the marketing site. Included on every page
// (index, product, pricing, help, contact) so Pricing/Help/Contact are
// reachable on phones without scrolling to the footer — the nav links
// themselves still just hide below 800px (see css/style.css), but this
// hamburger + slide-down panel now covers that gap.
(function () {
  var btn = document.getElementById('nav-hamburger');
  var panel = document.getElementById('mobile-nav');
  if (!btn || !panel) return;

  function setOpen(open) {
    panel.classList.toggle('open', open);
    btn.classList.toggle('open', open);
    btn.setAttribute('aria-expanded', open ? 'true' : 'false');
  }

  btn.addEventListener('click', function () {
    setOpen(!panel.classList.contains('open'));
  });

  // Close after tapping a link, so navigating away doesn't leave it open.
  panel.querySelectorAll('a').forEach(function (a) {
    a.addEventListener('click', function () { setOpen(false); });
  });
})();
