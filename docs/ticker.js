(function () {
  const wrap = document.querySelector('.ticker-wrap');
  const track = document.querySelector('.ticker-track');
  if (!wrap || !track) return;

  const SPEED = 0.5; // px per frame, idle auto-scroll
  const RESUME_DELAY = 1200; // ms after interaction ends before auto-scroll resumes
  const FRICTION = 0.95; // per-frame velocity decay for mouse-flick momentum
  const MIN_VELOCITY = 0.02; // px/ms — momentum stops below this
  const MAX_VELOCITY = 3; // px/ms — clamp against noisy pointer timing

  let loopWidth = track.scrollWidth / 2; // cards are duplicated once for the seamless loop
  let rafId = null;
  let resumeTimer = null;

  let dragging = false;
  let startX = 0;
  let startScrollLeft = 0;
  let lastX = 0;
  let lastTime = 0;
  let velocity = 0; // px of scrollLeft change per ms

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
    if (rafId) return;
    rafId = requestAnimationFrame(idleTick);
  }

  function pauseAll() {
    stopRaf();
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

  // Hover pause (desktop)
  wrap.addEventListener('mouseenter', () => {
    if (!dragging) {
      clearTimeout(resumeTimer);
      pauseAll();
    }
  });
  wrap.addEventListener('mouseleave', () => {
    if (!dragging && !rafId) playIdle();
  });

  // Click-and-drag (mouse), with flick momentum on release
  wrap.addEventListener('mousedown', (e) => {
    dragging = true;
    wrap.classList.add('dragging');
    startX = lastX = e.pageX;
    startScrollLeft = wrap.scrollLeft;
    lastTime = performance.now();
    velocity = 0;
    clearTimeout(resumeTimer);
    pauseAll();
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

  // Touch (mobile) — native swipe scrolling (with its own native momentum)
  // handles the gesture itself; just pause the idle marquee during it and
  // resume after. Browsers commonly fire touchcancel instead of touchend
  // once they take over a scroll gesture, so both must resume playback or
  // the marquee gets stuck paused after the very first swipe.
  wrap.addEventListener('touchstart', () => {
    clearTimeout(resumeTimer);
    pauseAll();
  }, { passive: true });

  function onTouchDone() {
    scheduleResume(RESUME_DELAY);
  }
  wrap.addEventListener('touchend', onTouchDone);
  wrap.addEventListener('touchcancel', onTouchDone);

  // Keep the loop illusion intact for any scroll source (wheel, trackpad, etc.)
  wrap.addEventListener('scroll', normalize);

  window.addEventListener('resize', () => {
    loopWidth = track.scrollWidth / 2;
  });
})();
