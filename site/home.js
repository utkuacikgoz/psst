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

// Try a psst (owner picks 1A 2A 3A, 7 Nov 2026): tap the hero's first band and it
// whispers, says sent · seen, lands on Zoe's phone, then asks you to do it for real.
// Nothing is sent anywhere.
(function () {
  var root = document.getElementById("try");
  if (!root) return;
  var band = root.querySelector(".try-band");
  var ln = root.querySelector(".try-ln");
  var hint = root.querySelector(".try-hint");
  var line = root.querySelector(".try-line");
  var get = root.querySelector(".try-get");
  var again = root.querySelector(".try-again");
  var reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var sound = null;
  var tried = false;
  // Anonymous counts in Vercel Web Analytics, as the privacy policy says: a tap, and an
  // App Store tap after it. No cookies, nothing about the visitor.
  function count(name) {
    window.va = window.va || function () { (window.vaq = window.vaq || []).push(arguments); };
    try { window.va("event", { name: name }); } catch (e) {}
  }
  get.addEventListener("click", function () { if (tried) count("Try a psst: App Store"); });
  var busy = false;

  function restart(el, cls) { el.classList.remove(cls); void el.offsetWidth; el.classList.add(cls); }

  band.addEventListener("click", function () {
    if (busy) return;
    busy = true;
    if (!tried) { tried = true; count("Try a psst"); }
    band.setAttribute("aria-disabled", "true");
    hint.hidden = true;
    try {
      sound = sound || new Audio("/sounds/psst.wav");
      sound.currentTime = 0;
      var played = sound.play();
      if (played && played.catch) played.catch(function () {});
    } catch (e) {}
    ln.textContent = "Sending…";
    if (!reduce) restart(band, "sweep");
    setTimeout(function () {
      ln.textContent = "Sent just now · seen ✓";
      if (!reduce) restart(band, "bump");
      setTimeout(function () { root.classList.add("landed"); }, reduce ? 0 : 500);
      setTimeout(function () {
        line.textContent = "Now psst someone real.";
        root.classList.add("done");
        get.removeAttribute("tabindex");
        again.hidden = false;
      }, reduce ? 100 : 1300);
    }, reduce ? 150 : 700);
  });

  again.addEventListener("click", function () {
    busy = false;
    band.removeAttribute("aria-disabled");
    root.classList.remove("landed", "done");
    ln.textContent = "Tap to psst";
    hint.hidden = false;
    get.setAttribute("tabindex", "-1");
    again.hidden = true;
    band.focus();
  });
})();
