(function () {
  const wrap = document.querySelector('.ticker-wrap');
  const track = document.querySelector('.ticker-track');
  if (!wrap || !track) return;

  const SPEED = 0.5; // px per frame
  const RESUME_DELAY = 1200; // ms after interaction ends before auto-scroll resumes

  let loopWidth = track.scrollWidth / 2; // cards are duplicated once for the seamless loop
  let rafId = null;
  let resumeTimer = null;
  let dragging = false;
  let startX = 0;
  let startScrollLeft = 0;

  function normalize() {
    if (wrap.scrollLeft >= loopWidth) wrap.scrollLeft -= loopWidth;
    else if (wrap.scrollLeft <= 0) wrap.scrollLeft += loopWidth;
  }

  function tick() {
    wrap.scrollLeft += SPEED;
    normalize();
    rafId = requestAnimationFrame(tick);
  }

  function play() {
    if (rafId) return;
    rafId = requestAnimationFrame(tick);
  }

  function pause() {
    if (rafId) cancelAnimationFrame(rafId);
    rafId = null;
  }

  function pauseAndScheduleResume(delay) {
    pause();
    clearTimeout(resumeTimer);
    resumeTimer = setTimeout(play, delay);
  }

  play();

  // Hover pause (desktop)
  wrap.addEventListener('mouseenter', () => {
    clearTimeout(resumeTimer);
    pause();
  });
  wrap.addEventListener('mouseleave', () => {
    if (!dragging) play();
  });

  // Click-and-drag (mouse)
  wrap.addEventListener('mousedown', (e) => {
    dragging = true;
    wrap.classList.add('dragging');
    startX = e.pageX;
    startScrollLeft = wrap.scrollLeft;
    clearTimeout(resumeTimer);
    pause();
  });

  window.addEventListener('mousemove', (e) => {
    if (!dragging) return;
    e.preventDefault();
    wrap.scrollLeft = startScrollLeft - (e.pageX - startX);
    normalize();
  });

  window.addEventListener('mouseup', () => {
    if (!dragging) return;
    dragging = false;
    wrap.classList.remove('dragging');
    pauseAndScheduleResume(RESUME_DELAY);
  });

  // Touch (mobile) — native swipe scrolling handles the drag itself;
  // just pause the marquee during the gesture and resume after.
  wrap.addEventListener('touchstart', () => {
    clearTimeout(resumeTimer);
    pause();
  }, { passive: true });

  wrap.addEventListener('touchend', () => pauseAndScheduleResume(RESUME_DELAY));

  // Keep the loop illusion intact for any scroll source (wheel, trackpad, etc.)
  wrap.addEventListener('scroll', normalize);

  window.addEventListener('resize', () => {
    loopWidth = track.scrollWidth / 2;
  });
})();
