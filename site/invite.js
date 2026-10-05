// The code is the last part of /invite/CODE.
var code = (location.pathname.split("/").filter(Boolean)[1] || "").toUpperCase().replace(/[^A-Z0-9]/g, "");
if (code) {
  document.getElementById("code").textContent = code.length === 8 ? code.slice(0, 4) + " " + code.slice(4) : code;
  document.getElementById("open").href = "psst://invite/" + code;
} else {
  document.getElementById("code").textContent = "No code";
}
document.getElementById("copy").addEventListener("click", function () {
  var btn = this;
  navigator.clipboard.writeText(code).then(function () { btn.textContent = "Copied"; },
                                           function () { btn.textContent = "Select the code above to copy it"; });
});
