// Get Psst on a Psst-invite page (/p/CODE): copy the code during the tap (browsers
// only allow it then), then go to the App Store. After installing, the app offers it.
var get = document.getElementById("get");
if (get) {
  get.addEventListener("click", function (event) {
    var code = get.getAttribute("data-code");
    if (!code || !navigator.clipboard) return;
    event.preventDefault();
    var store = get.href;
    var go = function () { location.href = store; };
    navigator.clipboard.writeText(code).then(go, go);
  });
}
