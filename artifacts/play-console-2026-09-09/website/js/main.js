const nav = document.getElementById("nav");
const reveals = Array.from(document.querySelectorAll(".reveal"));

const updateNav = () => {
  if (!nav) return;
  nav.classList.toggle("is-scrolled", window.scrollY > 12);
};

const setupRevealObserver = () => {
  if (!("IntersectionObserver" in window)) {
    reveals.forEach((node) => node.classList.add("is-visible"));
    return;
  }

  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add("is-visible");
        observer.unobserve(entry.target);
      });
    },
    { threshold: 0.16, rootMargin: "0px 0px -8% 0px" }
  );

  reveals.forEach((node) => observer.observe(node));
};

const setupNetworkCanvas = () => {
  const canvas = document.getElementById("network-canvas");
  if (!canvas) return;

  const ctx = canvas.getContext("2d");
  if (!ctx) return;

  let width = 0;
  let height = 0;
  let animationId = 0;
  const prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const particleCount = prefersReducedMotion ? 16 : 34;
  const particles = [];

  const palette = [
    "rgba(29, 185, 84, 0.9)",
    "rgba(129, 230, 217, 0.8)",
    "rgba(167, 139, 250, 0.72)",
  ];

  const resize = () => {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    width = window.innerWidth;
    height = Math.max(window.innerHeight, document.documentElement.clientHeight);
    canvas.width = Math.floor(width * dpr);
    canvas.height = Math.floor(height * dpr);
    canvas.style.width = `${width}px`;
    canvas.style.height = `${height}px`;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

    particles.length = 0;
    for (let i = 0; i < particleCount; i += 1) {
      particles.push({
        x: Math.random() * width,
        y: Math.random() * height * 0.92,
        vx: (Math.random() - 0.5) * (prefersReducedMotion ? 0.08 : 0.22),
        vy: (Math.random() - 0.5) * (prefersReducedMotion ? 0.05 : 0.16),
        r: 1.2 + Math.random() * 2.2,
        c: palette[i % palette.length],
      });
    }
  };

  const draw = () => {
    ctx.clearRect(0, 0, width, height);

    for (let i = 0; i < particles.length; i += 1) {
      const a = particles[i];
      a.x += a.vx;
      a.y += a.vy;

      if (a.x < -40) a.x = width + 40;
      if (a.x > width + 40) a.x = -40;
      if (a.y < -40) a.y = height + 40;
      if (a.y > height + 40) a.y = -40;

      for (let j = i + 1; j < particles.length; j += 1) {
        const b = particles[j];
        const dx = a.x - b.x;
        const dy = a.y - b.y;
        const distance = Math.hypot(dx, dy);
        const maxDistance = 160;
        if (distance > maxDistance) continue;

        ctx.strokeStyle = `rgba(255, 255, 255, ${0.12 * (1 - distance / maxDistance)})`;
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(a.x, a.y);
        ctx.lineTo(b.x, b.y);
        ctx.stroke();
      }

      ctx.fillStyle = a.c;
      ctx.beginPath();
      ctx.arc(a.x, a.y, a.r, 0, Math.PI * 2);
      ctx.fill();
    }

    if (!prefersReducedMotion) {
      animationId = window.requestAnimationFrame(draw);
    }
  };

  resize();
  draw();
  if (prefersReducedMotion) return;

  window.addEventListener("resize", resize, { passive: true });
  window.addEventListener(
    "beforeunload",
    () => {
      window.cancelAnimationFrame(animationId);
    },
    { once: true }
  );
};

updateNav();
setupRevealObserver();
setupNetworkCanvas();
window.addEventListener("scroll", updateNav, { passive: true });
