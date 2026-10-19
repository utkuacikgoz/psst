// Hide a launch badge whose image fails to load, so a dead badge never shows
// as a broken-image icon with squashed alt text. If none load, the whole
// "Launched on" card goes too, rather than an empty white box.
document.querySelectorAll(".badges .badge img").forEach(function (img) {
  function hide() {
    img.closest(".badge").hidden = true;
    var box = img.closest(".badges");
    if (box && !box.querySelector(".badge:not([hidden])")) box.hidden = true;
  }
  if (img.complete && img.naturalWidth === 0 && img.getAttribute("src")) hide();
  else img.addEventListener("error", hide);
});
