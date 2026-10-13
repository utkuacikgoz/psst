// The code is the last part of /invite/CODE.
var code = (location.pathname.split("/").filter(Boolean)[1] || "").toUpperCase().replace(/[^A-Z0-9]/g, "");
if (code) {
  document.getElementById("code").textContent = code.length === 8 ? code.slice(0, 4) + " " + code.slice(4) : code;
  document.getElementById("open").href = "psst://invite/" + code;
  // Lets the banner's OPEN hand the invite to the app where Safari supports it.
  document.querySelector('meta[name="apple-itunes-app"]')
    .setAttribute("content", "app-id=6815764359, app-argument=https://psstapp.fun/invite/" + code);
} else {
  document.getElementById("code").textContent = "No code";
}
document.getElementById("copy").addEventListener("click", function () {
  var btn = this;
  navigator.clipboard.writeText(code).then(function () { btn.textContent = "Copied"; },
                                           function () { btn.textContent = "Select the code above to copy it"; });
});

// Get Psst: copy the code during the tap (browsers only allow it then), then go
// to the App Store. After installing, "I have a code" → Paste picks it up.
document.getElementById("get").addEventListener("click", function (event) {
  if (!code || !navigator.clipboard) return;
  event.preventDefault();
  var store = this.href;
  var go = function () { location.href = store; };
  navigator.clipboard.writeText(code).then(go, go);
});
