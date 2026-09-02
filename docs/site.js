(function () {
  // ── Floating nav: morphs into a glassy pill after scrolling past the hero ──
  const nav = document.getElementById('site-nav');
  if (nav) {
    const THRESHOLD = 40;
    let ticking = false;

    function updateNav() {
      nav.classList.toggle('is-floating', window.scrollY > THRESHOLD);
      ticking = false;
    }

    window.addEventListener('scroll', () => {
      if (!ticking) {
        requestAnimationFrame(updateNav);
        ticking = true;
      }
    }, { passive: true });

    updateNav();
  }

  // ── Scroll reveal: fade + rise elements into view once ──────────────────
  const revealEls = document.querySelectorAll('.reveal');
  if (revealEls.length && 'IntersectionObserver' in window) {
    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-visible');
          observer.unobserve(entry.target);
        }
      });
    }, { threshold: 0.15, rootMargin: '0px 0px -40px 0px' });

    revealEls.forEach((el) => observer.observe(el));
  } else {
    revealEls.forEach((el) => el.classList.add('is-visible'));
  }

  // ── Accordion / disclosure groups (features + FAQ) ──────────────────────
  document.querySelectorAll('.disclosure-trigger').forEach((trigger) => {
    const panel = trigger.nextElementSibling;
    if (!panel) return;

    trigger.addEventListener('click', () => {
      const isOpen = trigger.getAttribute('aria-expanded') === 'true';

      if (isOpen) {
        panel.style.maxHeight = '0px';
        trigger.setAttribute('aria-expanded', 'false');
        return;
      }

      trigger.setAttribute('aria-expanded', 'true');
      panel.style.maxHeight = panel.scrollHeight + 'px';
    });
  });

  // Keep open panels correctly sized if the layout reflows (e.g. font load, resize).
  window.addEventListener('resize', () => {
    document.querySelectorAll('.disclosure-trigger[aria-expanded="true"]').forEach((trigger) => {
      const panel = trigger.nextElementSibling;
      if (panel) panel.style.maxHeight = panel.scrollHeight + 'px';
    });
  });

  // ── Draggable ticker: idle auto-scroll, mouse-drag with flick momentum,
  // native touch scrolling on mobile. Cards are duplicated once in the
  // markup so the loop can wrap seamlessly. ─────────────────────────────
  function initTicker(wrapSelector, trackSelector) {
    const wrap = document.querySelector(wrapSelector);
    const track = document.querySelector(trackSelector);
    if (!wrap || !track) return;

    const SPEED = 0.4;
    const RESUME_DELAY = 1200;
    const FRICTION = 0.95;
    const MIN_VELOCITY = 0.02;
    const MAX_VELOCITY = 3;

    // Respect the OS "reduce motion" setting: no idle auto-scroll. The ticker
    // stays put and remains fully draggable / touch-scrollable.
    const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    let loopWidth = track.scrollWidth / 2;
    let rafId = null;
    let resumeTimer = null;

    let dragging = false;
    let startX = 0;
    let startScrollLeft = 0;
    let lastX = 0;
    let lastTime = 0;
    let velocity = 0;

    function normalize() {
      if (wrap.scrollLeft >= loopWidth) wrap.scrollLeft -= loopWidth;
      else if (wrap.scrollLeft <= 0) wrap.scrollLeft += loopWidth;
    }

    function stopRaf() {
      if (rafId) cancelAnimationFrame(rafId);
      rafId = null;
    }

    function idleTick() {
      wrap.scrollLeft += SPEED;
      normalize();
      rafId = requestAnimationFrame(idleTick);
    }

    function playIdle() {
      if (reduceMotion || rafId) return;
      rafId = requestAnimationFrame(idleTick);
    }

    function scheduleResume(delay) {
      clearTimeout(resumeTimer);
      resumeTimer = setTimeout(playIdle, delay);
    }

    function momentumTick() {
      wrap.scrollLeft += velocity * 16.67;
      normalize();
      velocity *= FRICTION;
      if (Math.abs(velocity) < MIN_VELOCITY) {
        stopRaf();
        scheduleResume(RESUME_DELAY);
        return;
      }
      rafId = requestAnimationFrame(momentumTick);
    }

    function playMomentum() {
      stopRaf();
      rafId = requestAnimationFrame(momentumTick);
    }

    playIdle();

    wrap.addEventListener('mouseenter', () => {
      if (!dragging) {
        clearTimeout(resumeTimer);
        stopRaf();
      }
    });
    wrap.addEventListener('mouseleave', () => {
      if (!dragging && !rafId) playIdle();
    });

    wrap.addEventListener('mousedown', (e) => {
      dragging = true;
      wrap.classList.add('dragging');
      startX = lastX = e.pageX;
      startScrollLeft = wrap.scrollLeft;
      lastTime = performance.now();
      velocity = 0;
      clearTimeout(resumeTimer);
      stopRaf();
    });

    window.addEventListener('mousemove', (e) => {
      if (!dragging) return;
      e.preventDefault();
      const now = performance.now();
      const dt = now - lastTime || 16.67;
      const dx = e.pageX - lastX;
      velocity = Math.max(-MAX_VELOCITY, Math.min(MAX_VELOCITY, -dx / dt));
      wrap.scrollLeft = startScrollLeft - (e.pageX - startX);
      normalize();
      lastX = e.pageX;
      lastTime = now;
    });

    window.addEventListener('mouseup', () => {
      if (!dragging) return;
      dragging = false;
      wrap.classList.remove('dragging');
      if (Math.abs(velocity) > MIN_VELOCITY) {
        playMomentum();
      } else {
        scheduleResume(RESUME_DELAY);
      }
    });

    wrap.addEventListener('touchstart', () => {
      clearTimeout(resumeTimer);
      stopRaf();
    }, { passive: true });

    function onTouchDone() {
      scheduleResume(RESUME_DELAY);
    }
    wrap.addEventListener('touchend', onTouchDone);
    wrap.addEventListener('touchcancel', onTouchDone);

    wrap.addEventListener('scroll', normalize);

    window.addEventListener('resize', () => {
      loopWidth = track.scrollWidth / 2;
    });
  }

  initTicker('.roadmap-ticker-wrap', '.roadmap-ticker-track');
})();
