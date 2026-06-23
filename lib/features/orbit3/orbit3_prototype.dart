/// Master switch for the Orbit3 "One Circle" visual prototype.
///
/// When `true`, a temporary 4th "Orbit3" tab appears beside Feed / Orbit /
/// Orbit2. Orbit3 reproduces ONLY the One Circle view (no template selector,
/// Messages, Manage, or floating scatter) so the dense single-circle experience
/// can be iterated on without touching the shipped Orbit2 comparison.
///
/// Flip to `false` (one line) to hide it everywhere before a real build.
/// Orbit3 is visuals-only: mock data, no DB/backend/real messages.
const bool kOrbit3PrototypeEnabled = true;
