import './QRMockup.css'

const ramiAvatar = 'https://images.unsplash.com/photo-1531891437562-4301cf35b7e4?w=200&h=200&fit=crop&crop=face'

// ── QR Share Screen — matches actual app screenshot ──
const QRShareScreen = () => (
  <div style={{
    width: '100%', height: '100%',
    background: 'linear-gradient(180deg, #0a120e 0%, #060d09 40%, #040a06 100%)',
    display: 'flex', flexDirection: 'column',
    alignItems: 'center',
    fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
    color: '#fff',
    position: 'relative',
    overflow: 'hidden',
  }}>
    {/* Dark green ambient glow — top area */}
    <div style={{
      position: 'absolute', inset: 0, pointerEvents: 'none',
    }}>
      <div style={{
        position: 'absolute',
        top: '-15%', left: '50%', transform: 'translateX(-50%)',
        width: '160%', height: '55%',
        background: 'radial-gradient(ellipse at 50% 10%, rgba(20,140,60,0.45) 0%, rgba(15,100,45,0.2) 30%, transparent 60%)',
      }} />
      <div style={{
        position: 'absolute',
        bottom: '0%', left: '50%', transform: 'translateX(-50%)',
        width: '100%', height: '35%',
        background: 'radial-gradient(ellipse at 50% 90%, rgba(15,100,40,0.06) 0%, transparent 60%)',
      }} />
    </div>

    {/* Status bar */}
    <div style={{
      width: '100%',
      display: 'flex', justifyContent: 'space-between',
      alignItems: 'center', padding: '8px 20px 4px',
      fontSize: 14, fontWeight: 600, zIndex: 1,
    }}>
      <span>02:57</span>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
        <svg width="16" height="12" viewBox="0 0 16 12" fill="white">
          <path d="M8 0C3.58 0 0 2.69 0 6h2c0-2.21 2.69-4 6-4s6 1.79 6 4h2c0-3.31-3.58-6-8-6z" opacity=".3"/>
          <path d="M8 4C5.79 4 4 5.12 4 6.5h2c0-.28.9-.5 2-.5s2 .22 2 .5h2C12 5.12 10.21 4 8 4z" opacity=".6"/>
          <circle cx="8" cy="9" r="1.5" opacity="1"/>
        </svg>
        <svg width="18" height="12" viewBox="0 0 24 12" fill="white">
          <rect x="1" y="1" width="20" height="10" rx="2" stroke="white" strokeWidth="1.5" fill="none"/>
          <rect x="22" y="4" width="2" height="4" rx="0.5" fill="white" opacity=".4"/>
          <rect x="2.5" y="2.5" width="14" height="7" rx="1" fill="white"/>
        </svg>
      </div>
    </div>

    {/* Settings back link */}
    <div style={{
      width: '100%', padding: '4px 16px 0',
      display: 'flex', justifyContent: 'space-between', alignItems: 'center',
      zIndex: 1,
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 2 }}>
        <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="rgba(29,185,84,0.8)" strokeWidth="2.5" strokeLinecap="round">
          <polyline points="15 18 9 12 15 6"/>
        </svg>
        <span style={{ fontSize: 12, color: 'rgba(29,185,84,0.8)', fontWeight: 500 }}>Settings</span>
      </div>
      {/* Online badge */}
      <div style={{
        display: 'flex', alignItems: 'center', gap: 4,
        padding: '4px 10px', borderRadius: 20,
        background: 'rgba(29, 185, 84, 0.08)',
        border: '1px solid rgba(29, 185, 84, 0.2)',
      }}>
        <span style={{ width: 6, height: 6, borderRadius: '50%', background: '#4ade80' }} />
        <span style={{ fontSize: 11, fontWeight: 600, color: '#4ade80' }}>Online</span>
        <span style={{ fontSize: 11, fontWeight: 600, color: '#4ade80' }}>(1)</span>
      </div>
    </div>

    {/* Avatar */}
    <div style={{
      marginTop: 14,
      width: 68, height: 68, borderRadius: '50%',
      position: 'relative',
      zIndex: 1,
    }}>
      <div style={{
        width: '100%', height: '100%', borderRadius: '50%',
        overflow: 'hidden',
        border: '2px solid rgba(255,255,255,0.1)',
      }}>
        <img src={ramiAvatar} alt="User" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
      </div>
      {/* Camera icon */}
      <div style={{
        position: 'absolute', bottom: -1, right: -1,
        width: 22, height: 22, borderRadius: '50%',
        background: '#1DB954',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        border: '2px solid #060d09',
      }}>
        <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2.5">
          <path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"/>
          <circle cx="12" cy="13" r="4"/>
        </svg>
      </div>
    </div>

    {/* Username */}
    <div style={{
      marginTop: 8,
      display: 'flex', alignItems: 'center', gap: 1,
      zIndex: 1,
    }}>
      <span style={{ fontSize: 13, color: 'rgba(255,255,255,0.45)', fontWeight: 400 }}>mknoon/</span>
      <span style={{ fontSize: 14, fontWeight: 700, color: '#fff' }}>@Rami</span>
      <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="rgba(255,255,255,0.35)" strokeWidth="2" style={{ marginLeft: 4 }}>
        <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/>
        <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/>
      </svg>
    </div>

    {/* QR description */}
    <div style={{
      marginTop: 12,
      fontSize: 12, color: 'rgba(255,255,255,0.35)',
      textAlign: 'center',
      letterSpacing: 0.1,
      zIndex: 1,
    }}>
      Show this to someone you want in your circle...
    </div>

    {/* QR Code */}
    <div style={{
      marginTop: 12,
      position: 'relative',
      zIndex: 1,
    }}>
      <div style={{
        width: 180, height: 180,
        padding: 12,
        background: '#ffffff',
        borderRadius: 18,
        boxShadow: '0 8px 40px rgba(0,0,0,0.5)',
      }}>
        <img
          src="/qr-code.png"
          alt="QR Code"
          style={{
            width: '100%', height: '100%',
            objectFit: 'contain', borderRadius: 6,
          }}
        />
      </div>
    </div>

    {/* Long-press hint */}
    <div style={{
      marginTop: 6,
      fontSize: 10, color: 'rgba(255,255,255,0.2)',
      letterSpacing: 0.2,
      zIndex: 1,
    }}>
      Long-press QR to copy data
    </div>

    {/* Scan friend button */}
    <div style={{
      margin: '14px 16px 0', width: 'calc(100% - 32px)',
      padding: '12px 14px',
      borderRadius: 14,
      background: 'rgba(255,255,255,0.04)',
      border: '1px solid rgba(255,255,255,0.08)',
      display: 'flex', alignItems: 'center', gap: 12,
      zIndex: 1,
    }}>
      <div style={{
        width: 36, height: 36, borderRadius: 10,
        background: 'rgba(29,185,84,0.08)',
        border: '1px solid rgba(29,185,84,0.2)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        flexShrink: 0,
      }}>
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#4ade80" strokeWidth="2" strokeLinecap="round">
          <path d="M3 7V5a2 2 0 0 1 2-2h2"/>
          <path d="M17 3h2a2 2 0 0 1 2 2v2"/>
          <path d="M21 17v2a2 2 0 0 1-2 2h-2"/>
          <path d="M7 21H5a2 2 0 0 1-2-2v-2"/>
        </svg>
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 13, fontWeight: 600, color: 'rgba(255,255,255,0.95)', whiteSpace: 'nowrap' }}>
          Scan a friend's code
        </div>
        <div style={{ fontSize: 10, color: 'rgba(255,255,255,0.35)', marginTop: 1 }}>
          Add someone to your circle
        </div>
      </div>
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="rgba(255,255,255,0.25)" strokeWidth="2" strokeLinecap="round" style={{ flexShrink: 0 }}>
        <polyline points="9 18 15 12 9 6"/>
      </svg>
    </div>

    {/* Empty state — orbital illustration */}
    <div style={{
      marginTop: 'auto',
      padding: '0 24px 20px',
      display: 'flex', flexDirection: 'column', alignItems: 'center',
      zIndex: 1,
    }}>
      {/* Concentric rings with dots */}
      <div style={{
        position: 'relative',
        width: 56, height: 56,
        marginBottom: 10,
      }}>
        <div style={{
          position: 'absolute', inset: 0, borderRadius: '50%',
          border: '1px solid rgba(255,255,255,0.06)',
        }} />
        <div style={{
          position: 'absolute', inset: 8, borderRadius: '50%',
          border: '1px solid rgba(255,255,255,0.08)',
        }} />
        <div style={{
          position: 'absolute', inset: 16, borderRadius: '50%',
          border: '1px dashed rgba(255,255,255,0.06)',
        }} />
        <svg style={{ position: 'absolute', inset: 0 }} viewBox="0 0 56 56">
          <circle cx="28" cy="8" r="2" fill="rgba(29,185,84,0.4)" />
          <circle cx="14" cy="34" r="1.5" fill="rgba(29,185,84,0.25)" />
          <circle cx="42" cy="30" r="2" fill="rgba(29,185,84,0.35)" />
          <circle cx="22" cy="44" r="1.5" fill="rgba(29,185,84,0.2)" />
          <circle cx="36" cy="46" r="1" fill="rgba(29,185,84,0.3)" />
        </svg>
      </div>

      <div style={{
        fontSize: 12, fontWeight: 700, color: 'rgba(255,255,255,0.8)',
        marginBottom: 3,
      }}>
        Your circle is waiting to be filled
      </div>
      <div style={{
        fontSize: 10, color: 'rgba(255,255,255,0.3)',
        textAlign: 'center',
      }}>
        Scan a friend's code or share yours to connect
      </div>
    </div>
  </div>
)

// ── Phone Mockup Wrapper ──
const QRMockup = ({
  eyebrow = 'Add Friends',
  title = 'The closest people aren\u2019t found online.',
  subtitle = 'Add people by QR code, get introduced through friends you trust, and grow a circle that stays personal.',
}) => (
  <section className="phone-mockup-page" aria-label="Phone mockup of the mknoon QR code screen">
    <div className="phone-mockup-bg" aria-hidden="true">
      <div className="phone-mockup-glow phone-mockup-glow-1" />
      <div className="phone-mockup-glow phone-mockup-glow-2" />
    </div>

    <div className="phone-mockup-shell">
      <div className="phone-mockup-stage">
        <div className="phone-stage-orbit phone-stage-orbit-1" aria-hidden="true" />
        <div className="phone-stage-orbit phone-stage-orbit-2" aria-hidden="true" />

        <div className="phone-device-wrapper">
          <div className="phone-device">
            <div className="phone-btn phone-btn-silent" />
            <div className="phone-btn phone-btn-vol-up" />
            <div className="phone-btn phone-btn-vol-down" />
            <div className="phone-btn phone-btn-power" />
            <div className="phone-bezel-highlight" />

            <div className="phone-screen">
              <div className="phone-dynamic-island" />
              <div className="phone-screen-sheen" />

              <div className="phone-screen-image">
                <QRShareScreen />
              </div>
            </div>
          </div>
        </div>
      </div>

      <div className="phone-mockup-copy">
        <span className="phone-mockup-eyebrow">{eyebrow}</span>
        <div className="phone-mockup-copy-stack">
          <h2 className="phone-mockup-title">{title}</h2>
          <p className="phone-mockup-subtitle">{subtitle}</p>
        </div>
      </div>
    </div>
  </section>
)

export default QRMockup
