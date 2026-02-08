// landing page scroll animations with gsap + scrolltrigger
/* global gsap, ScrollTrigger, ScrollToPlugin */

gsap.registerPlugin(ScrollTrigger, ScrollToPlugin);

const THEME_STORAGE_KEY = 'landing-theme';
const VIDEO_FALLBACK_SOURCE = '/assets/video-white-background-kf1.mp4';
const THEME_VIDEO_SOURCES = {
  light: '/assets/video-white-background-kf1.mp4',
  dark: '/assets/video-white-background-kf1.mp4',
};

function initThemeToggle(onThemeChange) {
  const root = document.documentElement;
  const toggle = document.getElementById('themeToggle');

  function applyTheme(theme, persist) {
    root.setAttribute('data-theme', theme);
    if (toggle) {
      toggle.setAttribute('aria-pressed', String(theme === 'dark'));
      toggle.setAttribute(
        'aria-label',
        theme === 'dark' ? 'Activate light mode' : 'Activate dark mode'
      );
    }
    if (persist) {
      localStorage.setItem(THEME_STORAGE_KEY, theme);
    }
    if (typeof onThemeChange === 'function') {
      onThemeChange(theme);
    }
  }

  const storedTheme = localStorage.getItem(THEME_STORAGE_KEY);
  const initialTheme = storedTheme === 'dark' ? 'dark' : 'light';
  applyTheme(initialTheme, false);

  if (toggle) {
    toggle.addEventListener('click', function () {
      const currentTheme = root.getAttribute('data-theme') === 'dark' ? 'dark' : 'light';
      const nextTheme = currentTheme === 'dark' ? 'light' : 'dark';
      applyTheme(nextTheme, true);
    });
  }

  return initialTheme;
}

// hero entrance animations
function initHeroAnimations() {
  const tl = gsap.timeline({ delay: 0.3 });

  tl.to('.hero-badge', {
    opacity: 1,
    y: 0,
    duration: 0.6,
    ease: 'power3.out',
  })
    .to(
      '.hero-title-line',
      {
        opacity: 1,
        y: 0,
        duration: 0.7,
        ease: 'power3.out',
        stagger: 0.15,
      },
      '-=0.3'
    )
    .to(
      '.hero-subtitle',
      {
        opacity: 1,
        y: 0,
        duration: 0.6,
        ease: 'power3.out',
      },
      '-=0.4'
    )
    .to(
      '.hero-actions',
      {
        opacity: 1,
        y: 0,
        duration: 0.6,
        ease: 'power3.out',
      },
      '-=0.3'
    )
    .to(
      '.hero-scroll-indicator',
      {
        opacity: 1,
        duration: 0.8,
        ease: 'power2.out',
      },
      '-=0.2'
    );

  // fade out hero on scroll
  gsap.to('.hero-content', {
    opacity: 0,
    y: -60,
    scale: 0.95,
    scrollTrigger: {
      trigger: '.hero',
      start: 'top top',
      end: '80% top',
      scrub: 1,
    },
  });

  gsap.to('.hero-scroll-indicator', {
    opacity: 0,
    scrollTrigger: {
      trigger: '.hero',
      start: '20% top',
      end: '40% top',
      scrub: 1,
    },
  });
}

// canvas-based video scrubbing controlled by scroll
// renders video frames to a 2d canvas for consistent cross-browser display
function initVideoScrub(initialTheme) {
  var video = document.getElementById('landingVideo');
  var canvas = document.getElementById('videoCanvas');
  var videoSection = document.querySelector('.video-section');
  var videoContainer = document.querySelector('.video-container');
  if (!video || !canvas || !videoSection || !videoContainer) return;

  var ctx = canvas.getContext('2d', { alpha: false });
  var scrubTrigger = null;
  var videoDuration = 0;
  var rafId = null;
  var needsDraw = true;
  var displayW = 0;
  var displayH = 0;
  var currentDpr = 1;

  // set canvas buffer to match container size with retina scaling
  function resizeCanvas() {
    var rect = videoContainer.getBoundingClientRect();
    currentDpr = Math.min(window.devicePixelRatio || 1, 2);
    displayW = rect.width;
    displayH = rect.height;
    canvas.width = Math.round(displayW * currentDpr);
    canvas.height = Math.round(displayH * currentDpr);
    ctx.setTransform(currentDpr, 0, 0, currentDpr, 0, 0);
    needsDraw = true;
  }

  // draw current video frame to canvas with cover-fit scaling
  function drawFrame() {
    var vw = video.videoWidth;
    var vh = video.videoHeight;
    if (!vw || !vh || !displayW || !displayH) return;

    var videoRatio = vw / vh;
    var canvasRatio = displayW / displayH;
    var sx, sy, sw, sh;

    if (canvasRatio > videoRatio) {
      // canvas wider than video: crop top/bottom
      sw = vw;
      sh = vw / canvasRatio;
      sx = 0;
      sy = (vh - sh) / 2;
    } else {
      // canvas taller than video: crop left/right
      sh = vh;
      sw = vh * canvasRatio;
      sx = (vw - sw) / 2;
      sy = 0;
    }

    ctx.drawImage(video, sx, sy, sw, sh, 0, 0, displayW, displayH);
  }

  // render loop: only paints when a new frame is available
  function renderLoop() {
    if (needsDraw && video.readyState >= 2) {
      drawFrame();
      needsDraw = false;
    }
    rafId = requestAnimationFrame(renderLoop);
  }

  // redraw whenever the browser finishes seeking to a new time
  video.addEventListener('seeked', function () { needsDraw = true; });

  // requestVideoFrameCallback for precise frame timing when available
  if ('requestVideoFrameCallback' in HTMLVideoElement.prototype) {
    var onFrame = function () {
      needsDraw = true;
      video.requestVideoFrameCallback(onFrame);
    };
    video.requestVideoFrameCallback(onFrame);
  }

  function setupVideoScroll() {
    var duration = video.duration;
    if (!duration || isNaN(duration)) return;
    videoDuration = duration;

    video.pause();
    video.currentTime = 0;
    resizeCanvas();

    if (scrubTrigger) scrubTrigger.kill();

    // use a proxy tween with scrub smoothing so the video eases
    // into position rather than jumping frame-to-frame
    var progress = { value: 0 };
    var scrubTween = gsap.to(progress, {
      value: 1,
      ease: 'none',
      scrollTrigger: {
        trigger: videoSection,
        start: 'top top',
        // keep the media pinned until the full overlay sequence is consumed
        endTrigger: '.content-overlay',
        end: 'bottom bottom',
        pin: videoContainer,
        // keep following sections in normal flow so they layer over the pinned media
        pinSpacing: false,
        scrub: 0.5,
        anticipatePin: 1,
        invalidateOnRefresh: true,
        onLeave: function () {
          video.currentTime = videoDuration;
          needsDraw = true;
        },
        onLeaveBack: function () {
          video.currentTime = 0;
          needsDraw = true;
        },
      },
      onUpdate: function () {
        video.currentTime = progress.value * videoDuration;
      },
    });
    scrubTrigger = scrubTween.scrollTrigger;

    if (!rafId) rafId = requestAnimationFrame(renderLoop);
    needsDraw = true;
    ScrollTrigger.refresh(true);
  }

  // debounced resize handler
  var resizeTimer;
  window.addEventListener('resize', function () {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(resizeCanvas, 100);
  });

  function loadVideoForTheme(theme) {
    var desiredSrc = THEME_VIDEO_SOURCES[theme] || THEME_VIDEO_SOURCES.light;
    var currentSrc = video.getAttribute('src') || '';

    // already loaded with the correct source
    if (currentSrc === desiredSrc && video.readyState >= 2) {
      if (!scrubTrigger) setupVideoScroll();
      return;
    }

    if (scrubTrigger) {
      scrubTrigger.kill();
      scrubTrigger = null;
    }

    video.pause();
    video.currentTime = 0;

    // same source but not ready yet
    if (currentSrc === desiredSrc) {
      video.addEventListener('canplay', setupVideoScroll, { once: true });
      return;
    }

    video.addEventListener('canplay', setupVideoScroll, { once: true });
    video.addEventListener('error', function () {
      if (desiredSrc !== VIDEO_FALLBACK_SOURCE) {
        video.src = VIDEO_FALLBACK_SOURCE;
        video.load();
      }
    }, { once: true });

    video.src = desiredSrc;
    video.load();
  }

  loadVideoForTheme(initialTheme || 'light');

  return {
    setTheme: function (theme) { loadVideoForTheme(theme); },
  };
}

// section animations loaded from landing-animations.js:
// initFeatureAnimations, initAboutAnimations, initTeamAnimations,
// initFooterAnimation, initNavScroll, initSmoothAnchors

// initialize everything
function init() {
  let videoController = null;
  const initialTheme = initThemeToggle(function (theme) {
    if (videoController) {
      videoController.setTheme(theme);
    }
  });

  initHeroAnimations();
  videoController = initVideoScrub(initialTheme);
  initFeatureAnimations();
  initAboutAnimations();
  initTeamAnimations();
  initFooterAnimation();
  initNavScroll();
  initSmoothAnchors();
}

// run on dom ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}

// refresh scrolltrigger after all assets load
window.addEventListener('load', function () {
  ScrollTrigger.refresh(true);
});
