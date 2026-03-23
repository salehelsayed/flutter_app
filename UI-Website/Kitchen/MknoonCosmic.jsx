// MknoonCosmic.jsx
// Standalone "Cosmic" logo variant for mknoon
// Usage: <MknoonCosmic size={64} animated={true} />
//
// Remember to import the CSS: import './MknoonCosmic.css'

import React from 'react'

const MknoonCosmic = ({ size = 64, animated = true }) => (
  <svg
    width={size} height={size} viewBox="0 0 100 100" fill="none"
    xmlns="http://www.w3.org/2000/svg"
    className={animated ? 'logo-cosmic-animated' : ''}
  >
    <defs>
      <radialGradient id="nebulaCore" cx="50%" cy="50%" r="50%">
        <stop offset="0%" stopColor="#1DB954" stopOpacity="0.9" />
        <stop offset="35%" stopColor="#1DB954" stopOpacity="0.3" />
        <stop offset="60%" stopColor="#0d7a35" stopOpacity="0.1" />
        <stop offset="100%" stopColor="#000000" stopOpacity="0" />
      </radialGradient>
      <radialGradient id="cosmicHaze" cx="50%" cy="50%" r="50%">
        <stop offset="0%" stopColor="#1DB954" stopOpacity="0.06" />
        <stop offset="50%" stopColor="#0d4a2a" stopOpacity="0.03" />
        <stop offset="100%" stopColor="#000000" stopOpacity="0" />
      </radialGradient>
      <radialGradient id="warmthGlow" cx="50%" cy="50%" r="50%">
        <stop offset="0%" stopColor="#ff3b3b" stopOpacity="0.25" />
        <stop offset="60%" stopColor="#ff3b3b" stopOpacity="0.05" />
        <stop offset="100%" stopColor="#000000" stopOpacity="0" />
      </radialGradient>
    </defs>

    {/* Background haze */}
    <circle cx="50" cy="50" r="48" fill="url(#cosmicHaze)" />

    {/* Orbital rings — 6 ellipses at various tilts, dashed/solid mix */}
    <ellipse cx="50" cy="50" rx="46" ry="18" stroke="#1DB954" strokeWidth="0.6" strokeDasharray="3 5" opacity="0.2" transform="rotate(-25 50 50)" className="logo-cosmic-ring-1" />
    <ellipse cx="50" cy="50" rx="42" ry="20" stroke="#ffffff" strokeWidth="0.7" strokeDasharray="4 4" opacity="0.12" transform="rotate(35 50 50)" className="logo-cosmic-ring-2" />
    <ellipse cx="50" cy="50" rx="38" ry="10" stroke="#1DB954" strokeWidth="0.8" opacity="0.25" transform="rotate(-60 50 50)" className="logo-cosmic-ring-3" />
    <ellipse cx="50" cy="50" rx="35" ry="35" stroke="#ffffff" strokeWidth="0.5" strokeDasharray="2 6" opacity="0.1" />
    <ellipse cx="50" cy="50" rx="26" ry="12" stroke="#ffffff" strokeWidth="1" strokeDasharray="6 3" opacity="0.18" transform="rotate(15 50 50)" className="logo-cosmic-ring-4" />
    <ellipse cx="50" cy="50" rx="20" ry="8" stroke="#1DB954" strokeWidth="1.2" opacity="0.35" transform="rotate(-40 50 50)" className="logo-cosmic-ring-5" />
    <ellipse cx="50" cy="50" rx="14" ry="6" stroke="#ff3b3b" strokeWidth="0.8" strokeDasharray="2 3" opacity="0.3" transform="rotate(55 50 50)" className="logo-cosmic-ring-6" />

    {/* Red warmth glow behind core */}
    <circle cx="50" cy="50" r="10" fill="url(#warmthGlow)" />

    {/* Nebula core */}
    <circle cx="50" cy="50" r="8" fill="url(#nebulaCore)" />
    <circle cx="50" cy="50" r="3" fill="#1DB954" opacity="0.5" />
    <circle cx="50" cy="50" r="1.8" fill="#ffffff" opacity="0.85" />

    {/* Orbital dots — scattered stars */}
    <circle cx="50" cy="6" r="1" fill="#1DB954" opacity="0.5" className="logo-cosmic-dot-1" />
    <circle cx="88" cy="35" r="0.8" fill="#ffffff" opacity="0.35" className="logo-cosmic-dot-2" />
    <circle cx="15" cy="62" r="0.7" fill="#ff3b3b" opacity="0.3" className="logo-cosmic-dot-3" />
    <circle cx="82" cy="72" r="0.9" fill="#1DB954" opacity="0.4" className="logo-cosmic-dot-4" />
    <circle cx="25" cy="20" r="0.6" fill="#ffffff" opacity="0.25" className="logo-cosmic-dot-5" />
  </svg>
)

export default MknoonCosmic
