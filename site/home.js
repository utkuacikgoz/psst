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
