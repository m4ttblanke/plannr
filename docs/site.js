/* Plannr marketing site — progressive enhancement only.
   The page is fully readable and coherent with this file absent or failed:
   the Conversion section is a static numbered walk-through, the FAQ answers
   are all visible, nothing is hidden behind JS. */
(function () {
  "use strict";

  /* Mark the document as enhanced so CSS can arm the scroll-reveal.
     If this file never loads/runs, .reveal elements stay visible. */
  document.documentElement.classList.add("js-ready");

  var reduce = window.matchMedia
    ? window.matchMedia("(prefers-reduced-motion: reduce)").matches
    : false;

  /* ---------------------------------------------------- floating nav ---- */
  var nav = document.getElementById("site-nav");
  if (nav) {
    var stick = function () {
      nav.classList.toggle("is-stuck", window.scrollY > 24);
    };
    window.addEventListener("scroll", stick, { passive: true });
    stick();
  }

  /* -------------------------------------------------- reveal on scroll -- */
  var revealables = document.querySelectorAll(".reveal");
  if (reduce || !("IntersectionObserver" in window)) {
    for (var r = 0; r < revealables.length; r++) revealables[r].classList.add("in");
  } else {
    var revObs = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (e) {
          if (e.isIntersecting) {
            e.target.classList.add("in");
            revObs.unobserve(e.target);
          }
        });
      },
      { threshold: 0.12, rootMargin: "0px 0px -8% 0px" }
    );
    revealables.forEach(function (el) { revObs.observe(el); });
  }

  /* ---------------------------------------------------------- FAQ ------- */
  /* Default markup shows every answer. JS turns it into an accordion and
     marks collapsed panels [hidden] so their links aren't focusable. */
  var faqList = document.querySelector(".faq__list");
  if (faqList) {
    faqList.classList.add("faq__list--js");
    faqList.querySelectorAll(".faq__item").forEach(function (item) {
      var btn = item.querySelector(".faq__q");
      var panel = item.querySelector(".faq__panel");
      if (!btn || !panel) return;

      btn.setAttribute("type", "button");
      btn.setAttribute("aria-expanded", "false");
      panel.hidden = true;

      btn.addEventListener("click", function () {
        var open = !item.classList.contains("is-open");
        btn.setAttribute("aria-expanded", open ? "true" : "false");

        if (open) {
          panel.hidden = false;
          if (reduce) {
            item.classList.add("is-open");
          } else {
            requestAnimationFrame(function () { item.classList.add("is-open"); });
          }
        } else {
          item.classList.remove("is-open");
          if (reduce) {
            panel.hidden = true;
          } else {
            var hide = function () {
              if (!item.classList.contains("is-open")) panel.hidden = true;
              panel.removeEventListener("transitionend", hide);
            };
            panel.addEventListener("transitionend", hide);
          }
        }
      });
    });
  }

  /* ============================================================ */
  /*  THE CONVERSION                                              */
  /*  Desktop (>=1000px, motion ok): one sticky stage scrubbed by */
  /*  scroll into a single physical story — site.js sets --seq    */
  /*  plus eased "cue" props that time the moments in each beat.   */
  /*  Tablet / phone: the static walk-through stays; each beat's   */
  /*  internals animate in once on entry.                          */
  /*  Reduced motion / no JS: the static walk-through, no props.   */
  /* ============================================================ */
  var conv = document.querySelector(".conversion");
  var scene = conv && conv.querySelector(".conversion__scene");
  var rail = conv && conv.querySelector(".conversion__rail");
  var wide = window.matchMedia
    ? window.matchMedia("(min-width: 1000px)")
    : { matches: true, addEventListener: function () {} };

  var scrubbing = false;
  var frame = 0;

  /* smoothstep: 0 below a, 1 above b, eased S-curve between */
  function ss(x, a, b) {
    var t = (x - a) / (b - a);
    t = t < 0 ? 0 : t > 1 ? 1 : t;
    return t * t * (3 - 2 * t);
  }

  var CUES = [
    ["--scan", 0.02, 0.22],
    ["--chipsout", 0.51, 0.57],
    ["--cardin", 0.52, 0.60],
    ["--acc", 0.58, 0.63],
    ["--edit", 0.65, 0.70],
    ["--decl", 0.72, 0.77],
    ["--curgone", 0.79, 0.84],
    ["--hand", 0.78, 0.93],
    ["--devin", 0.76, 0.90],
    ["--settle", 0.91, 1.0]
  ];

  function readSeq() {
    frame = 0;
    var rect = scene.getBoundingClientRect();
    var span = scene.offsetHeight - window.innerHeight;
    var seq = span > 0 ? -rect.top / span : 0;
    if (seq < 0) seq = 0;
    else if (seq > 1) seq = 1;

    var st = conv.style;
    st.setProperty("--seq", seq.toFixed(4));
    for (var c = 0; c < CUES.length; c++) {
      st.setProperty(CUES[c][0], ss(seq, CUES[c][1], CUES[c][2]).toFixed(4));
    }

    if (rail) {
      var active = seq >= 0.77 ? 3 : seq >= 0.50 ? 2 : seq >= 0.20 ? 1 : 0;
      for (var i = 0; i < rail.children.length; i++) {
        var on = i === active;
        if (on) rail.children[i].setAttribute("data-on", "");
        else rail.children[i].removeAttribute("data-on");
        var b = rail.children[i].firstElementChild;
        if (b) {
          if (on) b.setAttribute("aria-current", "step");
          else b.removeAttribute("aria-current");
        }
      }
    }
  }

  /* A rail pill jumps the scroll to that step; the sticky scene animates
     through to it (smoothly, unless the user prefers reduced motion). */
  function jumpToSeq(target) {
    if (!scene) return;
    var span = scene.offsetHeight - window.innerHeight;
    if (span <= 0) return;
    var top = scene.getBoundingClientRect().top + window.scrollY + target * span;
    window.scrollTo({ top: Math.round(top), behavior: reduce ? "auto" : "smooth" });
  }
  if (rail) {
    rail.querySelectorAll("button[data-seq]").forEach(function (btn) {
      btn.addEventListener("click", function () {
        jumpToSeq(parseFloat(btn.getAttribute("data-seq")) || 0);
      });
    });
  }

  function onScrollScrub() {
    if (!frame) frame = requestAnimationFrame(readSeq);
  }

  function startScrub() {
    if (scrubbing || !scene) return;
    scrubbing = true;
    conv.classList.add("is-enhanced");
    window.addEventListener("scroll", onScrollScrub, { passive: true });
    window.addEventListener("resize", onScrollScrub);
    readSeq();
  }

  function stopScrub() {
    if (!scrubbing) return;
    scrubbing = false;
    conv.classList.remove("is-enhanced");
    conv.style.removeProperty("--seq");
    for (var c = 0; c < CUES.length; c++) conv.style.removeProperty(CUES[c][0]);
    window.removeEventListener("scroll", onScrollScrub);
    window.removeEventListener("resize", onScrollScrub);
    if (rail) {
      for (var i = 0; i < rail.children.length; i++) {
        rail.children[i].removeAttribute("data-on");
        var rb = rail.children[i].firstElementChild;
        if (rb) rb.removeAttribute("aria-current");
      }
    }
  }

  /* Tablet / phone: reveal each beat's internals once, on entry. Content is
     never left hidden — a scroll fallback catches any beat the observer
     missed (e.g. a fast fling past it). */
  var beatsRevealed = false;
  function revealBeats() {
    if (beatsRevealed || !conv) return;
    beatsRevealed = true;
    var beats = [].slice.call(conv.querySelectorAll(".beat"));
    var seeAll = function () {
      for (var i = 0; i < beats.length; i++) beats[i].classList.add("is-seen");
    };
    if (!("IntersectionObserver" in window)) { seeAll(); return; }

    var bo = new IntersectionObserver(function (es) {
      es.forEach(function (e) {
        if (e.isIntersecting) {
          e.target.classList.add("is-seen");
          bo.unobserve(e.target);
        }
      });
    }, { threshold: 0.18, rootMargin: "0px 0px -6% 0px" });
    beats.forEach(function (b) { bo.observe(b); });

    var sweep = function () {
      var pending = false;
      for (var i = 0; i < beats.length; i++) {
        if (beats[i].classList.contains("is-seen")) continue;
        if (beats[i].getBoundingClientRect().top < window.innerHeight * 0.9) {
          beats[i].classList.add("is-seen");
          bo.unobserve(beats[i]);
        } else pending = true;
      }
      if (!pending) window.removeEventListener("scroll", sweep);
    };
    window.addEventListener("scroll", sweep, { passive: true });
    sweep();
  }

  if (conv && scene && !reduce) {
    if (wide.matches) startScrub();
    else revealBeats();
    var onBpChange = function (e) {
      if (e.matches) startScrub();
      else { stopScrub(); revealBeats(); }
    };
    if (wide.addEventListener) wide.addEventListener("change", onBpChange);
    else if (wide.addListener) wide.addListener(onBpChange); // older Safari
  }

  /* ------------------------------------------ Coming soon / roadmap -- */
  /*  One-shot: draw the growth spine + fan the branches in on entry.    */
  /*  Drawn by default (CSS), so no JS / reduced motion is fine.         */
  var roadmap = document.querySelector(".roadmap");
  if (roadmap && !reduce) {
    if (!("IntersectionObserver" in window)) {
      roadmap.classList.add("is-armed");
    } else {
      var rmObs = new IntersectionObserver(function (entries) {
        entries.forEach(function (e) {
          if (e.isIntersecting) {
            roadmap.classList.add("is-armed");
            rmObs.disconnect();
          }
        });
      }, { threshold: 0.2, rootMargin: "0px 0px -10% 0px" });
      rmObs.observe(roadmap);
    }
  }

  /* ---------------------------------------------- Product proof ------- */
  /*  Scroll-linked emphasis (>=961px) + a whisper of pointer parallax.  */
  var proof = document.querySelector(".proof");
  if (proof && !reduce) {
    var wideProof = window.matchMedia
      ? window.matchMedia("(min-width: 961px)")
      : { matches: true };
    var finePointer = window.matchMedia
      ? window.matchMedia("(pointer: fine)").matches
      : false;
    var ZONES = [0.14, 0.5, 0.86];
    var pf = 0;
    var pTx = 0, pTy = 0;

    function paintProof() {
      pf = 0;
      var r = proof.getBoundingClientRect();
      var vh = window.innerHeight;
      var p = (vh * 0.68 - r.top) / (r.height + vh * 0.36);
      if (p < 0) p = 0; else if (p > 1) p = 1;
      var s = proof.style;
      for (var i = 0; i < 3; i++) {
        var em = 1 - Math.abs(p - ZONES[i]) * 2.4;
        s.setProperty("--em" + i, (em < 0 ? 0 : em).toFixed(3));
      }
      s.setProperty("--tx", pTx.toFixed(3));
      s.setProperty("--ty", pTy.toFixed(3));
    }
    function queueProof() { if (!pf) pf = requestAnimationFrame(paintProof); }

    if (wideProof.matches) {
      window.addEventListener("scroll", queueProof, { passive: true });
      window.addEventListener("resize", queueProof);
      if (finePointer) {
        proof.addEventListener("pointermove", function (e) {
          var r = proof.getBoundingClientRect();
          pTx = ((e.clientX - r.left) / r.width - 0.5) * 2;
          pTy = ((e.clientY - r.top) / r.height - 0.5) * 2;
          queueProof();
        });
        proof.addEventListener("pointerleave", function () {
          pTx = 0; pTy = 0; queueProof();
        });
      }
      paintProof();
    }
  }

  /* ------------------------------------------ campaign attribution --- */
  /*  Carry utm_* from the landing URL onto the Stripe CTAs so a purchase
      can be traced back to the campaign that drove it.

      Stripe Payment Links natively accept utm_source / utm_medium /
      utm_campaign / utm_term / utm_content, and a client_reference_id
      that surfaces in the checkout.session.completed webhook and on the
      payment row in the Dashboard.
      (https://docs.stripe.com/payment-links/url-parameters)

      No cookie, no storage, no third party: the params are read straight
      off the current URL. This is a one-page site, so ?utm_… set on the
      landing request is still on location.search when a CTA is clicked.
      See docs/ANALYTICS.md for the campaign-URL convention. */
  var UTM_KEYS = ["utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content"];
  var stripeCtas = document.querySelectorAll('a[href*="buy.stripe.com"]');
  if (stripeCtas.length && window.URL && window.URLSearchParams) {
    var landing = null;
    try { landing = new URLSearchParams(window.location.search); } catch (e) { landing = null; }
    if (landing) {
      /* Stripe keeps only [A-Za-z0-9_-] in these values and silently drops
         anything else, so normalise: lower-case, runs of other chars -> "_",
         trim, and bound the length. */
      var tidy = function (v) {
        return String(v).toLowerCase()
          .replace(/[^a-z0-9_]+/g, "_")
          .replace(/^_+|_+$/g, "")
          .slice(0, 60);
      };
      var utm = {};
      for (var ui = 0; ui < UTM_KEYS.length; ui++) {
        var rawv = landing.get(UTM_KEYS[ui]);
        if (rawv) {
          var cleanv = tidy(rawv);
          if (cleanv) utm[UTM_KEYS[ui]] = cleanv;
        }
      }
      if (utm.utm_source || utm.utm_campaign) {
        var refParts = [];
        if (utm.utm_campaign) refParts.push("cmp-" + utm.utm_campaign);
        if (utm.utm_source) refParts.push("src-" + utm.utm_source);
        if (utm.utm_medium) refParts.push("mdm-" + utm.utm_medium);
        var ref = refParts.join("__").slice(0, 200);

        for (var ci = 0; ci < stripeCtas.length; ci++) {
          var link;
          try { link = new URL(stripeCtas[ci].href); } catch (e) { continue; }
          for (var ki = 0; ki < UTM_KEYS.length; ki++) {
            if (utm[UTM_KEYS[ki]] && !link.searchParams.has(UTM_KEYS[ki])) {
              link.searchParams.set(UTM_KEYS[ki], utm[UTM_KEYS[ki]]);
            }
          }
          if (ref && !link.searchParams.has("client_reference_id")) {
            link.searchParams.set("client_reference_id", ref);
          }
          stripeCtas[ci].href = link.toString();
        }
      }
    }
  }
})();
