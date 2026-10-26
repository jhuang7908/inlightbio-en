/* InLight Bio (EN) newsletter signup: POST to the subscribe API with source=en.
   Falls back to the original mailto request if the API is unreachable. */
(function () {
  if (window.__nlBound) return; window.__nlBound = true;
  var API = window.NL_API || "https://inlightbio.cn/api/subscribe";
  var css = ".nl-hp{position:absolute!important;left:-9999px!important;width:1px;height:1px;opacity:0}" +
    ".nl-status{font-size:14px;line-height:1.5;margin:6px 0 0;text-align:left;text-indent:0}.nl-status[data-state=ok]{color:inherit;font-weight:700}" +
    ".nl-status[data-state=err]{color:inherit;font-weight:700;text-decoration:underline dotted}.nl-status[data-state=busy]{opacity:.7}";
  var st = document.createElement("style"); st.textContent = css; document.head.appendChild(st);
  var M = { ok: "Check your inbox and click the link to confirm your subscription.",
    bad_email: "Please enter a valid email address.", rate_limited: "Too many requests. Please try again later.",
    fallback: "Our signup service is unavailable right now, so we opened your email app instead. Just hit send.",
    busy: "Subscribing…" };
  function mailto(e) {
    return "mailto:contact@inlightbio.com?subject=" + encodeURIComponent("Subscribe [EN]") +
      "&body=" + encodeURIComponent("Please add " + e + " to the InLight Bio weekly email (English).");
  }
  function bind(f) {
    var i = f.querySelector("input[type=email]"), btn = f.querySelector("button[type=submit]");
    var s = f.nextElementSibling && f.nextElementSibling.classList.contains("nl-status") ? f.nextElementSibling : f.querySelector(".nl-status");
    function say(t, k) { if (s) { s.textContent = t; s.setAttribute("data-state", k || ""); s.hidden = false; } }
    f.addEventListener("submit", function (e) {
      e.preventDefault();
      if (!i.checkValidity()) { i.reportValidity(); return; }
      var em = i.value.trim(), hp = f.querySelector("input[name=website]");
      if (btn) btn.disabled = true; say(M.busy, "busy");
      var ctl = window.AbortController ? new AbortController() : null, tm = setTimeout(function () { ctl && ctl.abort(); }, 8000);
      fetch(API, { method: "POST", headers: { "Content-Type": "application/json" }, signal: ctl && ctl.signal,
        body: JSON.stringify({ email: em, source: f.getAttribute("data-nl-source") || "en", lang: "en", website: hp ? hp.value : "" }) })
        .then(function (r) { return r.json().catch(function () { return {}; }).then(function (j) { return { r: r, j: j }; }); })
        .then(function (x) {
          if (x.r.ok && x.j.ok) { say(x.j.message || M.ok, "ok"); f.reset(); return; }
          if (x.r.status === 400 || x.r.status === 429) { say(x.j.message || M[x.j.error] || M.bad_email, "err"); return; }
          throw new Error("api " + x.r.status);
        })
        .catch(function () { say(M.fallback, "err"); location.href = mailto(em); })
        .then(function () { clearTimeout(tm); if (btn) btn.disabled = false; });
    });
  }
  function init() { Array.prototype.forEach.call(document.querySelectorAll("form[data-subform]"), bind); }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init); else init();
})();
