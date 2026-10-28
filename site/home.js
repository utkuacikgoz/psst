// BuildHop's feedback button sits over the "Get Psst" bar on phones, so it only
// loads on wider screens (owner request, 28 Oct 2026).
(function () {
  if (!window.matchMedia("(min-width: 821px)").matches) return;
  var s = document.createElement("script");
  s.async = true;
  s.src = "https://buildhop.io/feedback-widget.js";
  s.setAttribute("data-launch-id", "77957af2-a32a-4802-be4f-4db44d27b978");
  s.setAttribute("data-theme", "light");
  document.body.appendChild(s);
})();

// 5A: on phones, a "Get Psst" bar appears once the hero's App Store button has
// scrolled out of view, and goes again when it comes back.
(function () {
  var bar = document.getElementById("sticky-get");
  var cta = document.querySelector(".hero .cta");
  if (!bar || !cta || !("IntersectionObserver" in window)) return;
  var phone = window.matchMedia("(max-width: 820px)");
  var past = false;
  function update() {
    bar.hidden = !(phone.matches && past);
    document.body.classList.toggle("has-sticky", !bar.hidden);
  }
  new IntersectionObserver(function (entries) {
    var e = entries[0];
    past = !e.isIntersecting && e.boundingClientRect.top < 0;
    update();
  }).observe(cta);
  if (phone.addEventListener) phone.addEventListener("change", update);
})();
