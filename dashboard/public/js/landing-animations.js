// landing page section animations (extracted from landing.js for file size limit)
/* global gsap, ScrollTrigger, ScrollToPlugin */

// lower viewport percentages mean the trigger fires later
var OVERLAY_SECTION_START = 'top 74%';
var OVERLAY_ITEM_START = 'top 78%';

// feature cards scroll-triggered fade in
function initFeatureAnimations() {
  var cards = gsap.utils.toArray('.feature-card');

  cards.forEach(function (card, i) {
    gsap.to(card, {
      opacity: 1,
      y: 0,
      duration: 0.8,
      ease: 'power3.out',
      scrollTrigger: {
        trigger: card,
        start: OVERLAY_ITEM_START,
        toggleActions: 'play none none reverse',
      },
      delay: (i % 3) * 0.1,
    });
  });

  gsap.fromTo(
    '.features-header',
    { opacity: 0, y: 30 },
    {
      opacity: 1,
      y: 0,
      duration: 0.8,
      ease: 'power3.out',
      scrollTrigger: {
        trigger: '.features-header',
        start: OVERLAY_ITEM_START,
        toggleActions: 'play none none reverse',
      },
    }
  );
}

// about section animations
function initAboutAnimations() {
  gsap.fromTo(
    '.about .section-title',
    { opacity: 0, x: -30 },
    {
      opacity: 1,
      x: 0,
      duration: 0.8,
      ease: 'power3.out',
      scrollTrigger: {
        trigger: '.about',
        start: OVERLAY_SECTION_START,
        toggleActions: 'play none none reverse',
      },
    }
  );

  gsap.fromTo(
    '.about-desc',
    { opacity: 0, y: 20 },
    {
      opacity: 1,
      y: 0,
      duration: 0.7,
      ease: 'power3.out',
      scrollTrigger: {
        trigger: '.about-desc',
        start: OVERLAY_ITEM_START,
        toggleActions: 'play none none reverse',
      },
    }
  );

  var stats = gsap.utils.toArray('.about-stat');
  stats.forEach(function (stat, i) {
    gsap.to(stat, {
      opacity: 1,
      y: 0,
      duration: 0.6,
      delay: i * 0.15,
      ease: 'power3.out',
      scrollTrigger: {
        trigger: '.about-stats',
        start: OVERLAY_ITEM_START,
        toggleActions: 'play none none reverse',
      },
    });
  });

  gsap.to('.about-visual', {
    opacity: 1,
    scale: 1,
    duration: 0.8,
    ease: 'power3.out',
    scrollTrigger: {
      trigger: '.about-visual',
      start: OVERLAY_ITEM_START,
      toggleActions: 'play none none reverse',
    },
  });
}

// team cards animation
function initTeamAnimations() {
  gsap.fromTo(
    '.team .section-title',
    { opacity: 0, y: 20 },
    {
      opacity: 1,
      y: 0,
      duration: 0.7,
      ease: 'power3.out',
      scrollTrigger: {
        trigger: '.team',
        start: OVERLAY_SECTION_START,
        toggleActions: 'play none none reverse',
      },
    }
  );

  gsap.fromTo(
    '.team .section-subtitle',
    { opacity: 0, y: 15 },
    {
      opacity: 1,
      y: 0,
      duration: 0.6,
      delay: 0.1,
      ease: 'power3.out',
      scrollTrigger: {
        trigger: '.team',
        start: OVERLAY_SECTION_START,
        toggleActions: 'play none none reverse',
      },
    }
  );

  var teamCards = gsap.utils.toArray('.team-card');
  teamCards.forEach(function (card, i) {
    gsap.to(card, {
      opacity: 1,
      y: 0,
      duration: 0.7,
      delay: i * 0.12,
      ease: 'power3.out',
      scrollTrigger: {
        trigger: '.team-grid',
        start: OVERLAY_ITEM_START,
        toggleActions: 'play none none reverse',
      },
    });
  });
}

// footer cta animation
function initFooterAnimation() {
  gsap.fromTo(
    '.footer-cta',
    { opacity: 0, y: 30 },
    {
      opacity: 1,
      y: 0,
      duration: 0.8,
      ease: 'power3.out',
      scrollTrigger: {
        trigger: '.footer-cta',
        start: 'top 85%',
        toggleActions: 'play none none reverse',
      },
    }
  );
}

// nav background on scroll
function initNavScroll() {
  var nav = document.querySelector('.landing-nav');
  if (!nav) return;

  ScrollTrigger.create({
    trigger: '.hero',
    start: 'top top',
    end: '80% top',
    onUpdate: function (self) {
      if (self.progress > 0.2) {
        nav.classList.add('is-scrolled');
      } else {
        nav.classList.remove('is-scrolled');
      }
    },
  });
}

// smooth anchor scroll for nav links
function initSmoothAnchors() {
  document.querySelectorAll('a[href^="#"]').forEach(function (anchor) {
    anchor.addEventListener('click', function (e) {
      e.preventDefault();
      var target = document.querySelector(this.getAttribute('href'));
      if (target) {
        gsap.to(window, {
          scrollTo: { y: target, offsetY: 80 },
          duration: 1,
          ease: 'power3.inOut',
        });
      }
    });
  });
}
