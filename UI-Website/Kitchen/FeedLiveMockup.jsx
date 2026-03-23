const saraAvatar = 'https://images.unsplash.com/photo-1524504388940-b1c1722653e1?w=200&h=200&fit=crop&crop=face'
const ramiAvatar = 'https://images.unsplash.com/photo-1531891437562-4301cf35b7e4?w=200&h=200&fit=crop&crop=face'
const oliverAvatar = 'https://images.unsplash.com/photo-1463453091185-61582044d556?w=200&h=200&fit=crop&crop=face'
const noraAvatar = 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=200&h=200&fit=crop&crop=face'

// Shared image for the photo message
const sharedPhoto = 'https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=600&h=400&fit=crop'

// ── Message Card ──
const MessageCard = ({ avatar, name, time, badge, message, image, collapsed = false }) => (
  <div style={{
    margin: '0 10px 10px',
    borderRadius: 16,
    background: 'rgba(12, 18, 12, 0.7)',
    border: '1px solid rgba(29, 185, 84, 0.12)',
    borderLeft: '2px solid rgba(29, 185, 84, 0.3)',
    overflow: 'hidden',
  }}>
    {/* Card header */}
    <div style={{
      display: 'flex', alignItems: 'center',
      padding: '12px 12px 0',
      gap: 10,
    }}>
      <div style={{
        width: 36, height: 36, borderRadius: '50%',
        overflow: 'hidden', flexShrink: 0,
        border: '2px solid rgba(29, 185, 84, 0.25)',
      }}>
        <img src={avatar} alt={name} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
      </div>
      <div style={{ flex: 1 }}>
        <div style={{ fontSize: 14, fontWeight: 600, color: '#fff' }}>{name}</div>
        <div style={{ fontSize: 10, color: 'rgba(255,255,255,0.35)' }}>{time}</div>
      </div>
      {badge && (
        <div style={{
          width: 20, height: 20, borderRadius: '50%',
          background: '#1DB954', display: 'flex',
          alignItems: 'center', justifyContent: 'center',
          fontSize: 11, fontWeight: 700, color: '#fff',
        }}>
          {badge}
        </div>
      )}
    </div>

    {/* View earlier */}
    <div style={{
      padding: '8px 12px 4px',
      fontSize: 11, color: 'rgba(255,255,255,0.3)',
      textAlign: 'center',
    }}>
      View earlier messages
    </div>

    {/* Message content */}
    <div style={{ padding: '4px 12px 8px' }}>
      {image && (
        <div style={{
          borderRadius: 10, overflow: 'hidden',
          marginBottom: 6, border: '1px solid rgba(255,255,255,0.06)',
        }}>
          <img src={image} alt="shared" style={{
            width: '100%', height: 160, objectFit: 'cover', display: 'block',
          }} />
        </div>
      )}
      <div style={{
        fontSize: 12, color: 'rgba(255,255,255,0.75)',
        lineHeight: 1.5, padding: '2px 0',
      }}>
        <span style={{ color: 'rgba(255,255,255,0.5)', fontWeight: 500 }}>{name}: </span>
        {message}
      </div>
      <div style={{
        fontSize: 10, color: 'rgba(255,255,255,0.25)',
        textAlign: 'right', marginTop: 2,
      }}>
        {time}
      </div>
    </div>

    {/* Collapse */}
    {!collapsed && (
      <div style={{
        padding: '6px 0 8px',
        fontSize: 11, color: 'rgba(255,255,255,0.3)',
        textAlign: 'center',
        borderTop: '1px solid rgba(255,255,255,0.04)',
        display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 4,
      }}>
        <span style={{ fontSize: 8 }}>&#9652;</span> Collapse
      </div>
    )}

    {/* Reply bar */}
    <div style={{
      display: 'flex', alignItems: 'center',
      padding: '6px 10px 10px', gap: 8,
    }}>
      <div style={{
        width: 26, height: 26, borderRadius: '50%',
        background: 'rgba(255,255,255,0.06)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        fontSize: 16, color: 'rgba(255,255,255,0.3)', fontWeight: 300,
      }}>+</div>
      <div style={{
        flex: 1, padding: '6px 12px',
        borderRadius: 20,
        background: 'rgba(255,255,255,0.04)',
        border: '1px solid rgba(255,255,255,0.06)',
        fontSize: 12, color: 'rgba(255,255,255,0.2)',
      }}>Reply...</div>
      <div style={{
        width: 26, height: 26, borderRadius: '50%',
        background: 'rgba(29, 185, 84, 0.2)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        fontSize: 13, color: '#4ade80', fontWeight: 600,
      }}>↑</div>
    </div>
  </div>
)

// ── Live Feed Screen ──
const LiveFeedScreen = () => (
  <div style={{
    width: '100%', height: '100%',
    background: '#0a0a0f',
    display: 'flex', flexDirection: 'column',
    fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
    overflow: 'hidden',
    color: '#fff',
  }}>
    {/* Status bar */}
    <div style={{
      display: 'flex', justifyContent: 'space-between',
      alignItems: 'center', padding: '8px 20px 4px',
      fontSize: 14, fontWeight: 600,
    }}>
      <span>02:29</span>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
        <svg width="16" height="12" viewBox="0 0 16 12" fill="white"><path d="M8 0C3.58 0 0 2.69 0 6h2c0-2.21 2.69-4 6-4s6 1.79 6 4h2c0-3.31-3.58-6-8-6z" opacity=".3"/><path d="M8 4C5.79 4 4 5.12 4 6.5h2c0-.28.9-.5 2-.5s2 .22 2 .5h2C12 5.12 10.21 4 8 4z" opacity=".6"/><circle cx="8" cy="9" r="1.5" opacity="1"/></svg>
        <svg width="18" height="12" viewBox="0 0 24 12" fill="white"><rect x="1" y="1" width="20" height="10" rx="2" stroke="white" strokeWidth="1.5" fill="none"/><rect x="22" y="4" width="2" height="4" rx="0.5" fill="white" opacity=".4"/><rect x="2.5" y="2.5" width="14" height="7" rx="1" fill="white"/></svg>
      </div>
    </div>

    {/* Header */}
    <div style={{
      display: 'flex', justifyContent: 'space-between',
      alignItems: 'center', padding: '12px 14px 10px',
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
        <span style={{ fontSize: 11, fontWeight: 600, color: 'rgba(255,255,255,0.7)' }}>
          mknoon/@Rami
        </span>
        <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="rgba(255,255,255,0.35)" strokeWidth="2">
          <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/>
          <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/>
        </svg>
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 4,
          padding: '3px 8px', borderRadius: 20,
          background: 'rgba(29, 185, 84, 0.1)',
          border: '1px solid rgba(29, 185, 84, 0.2)',
        }}>
          <span style={{ width: 5, height: 5, borderRadius: '50%', background: '#4ade80' }} />
          <span style={{ fontSize: 9, fontWeight: 600, color: '#4ade80' }}>Online</span>
          <span style={{ fontSize: 9, fontWeight: 600, color: '#4ade80' }}>(3)</span>
        </div>
        <div style={{
          width: 32, height: 32, borderRadius: '50%',
          overflow: 'hidden', border: '2px solid rgba(29, 185, 84, 0.4)',
        }}>
          <img src={ramiAvatar} alt="Rami" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
        </div>
      </div>
    </div>

    {/* Feed cards — scrollable */}
    <div style={{
      flex: 1, overflowY: 'auto', overflowX: 'hidden',
      paddingBottom: 10,
      scrollbarWidth: 'none',
    }}>
      {/* Sara — image + text message */}
      <MessageCard
        avatar={saraAvatar}
        name="Sara"
        time="2:27 AM"
        badge="1"
        image={sharedPhoto}
        message="one day we'll visit this place together"
      />

      {/* Oliver — text only */}
      <MessageCard
        avatar={oliverAvatar}
        name="Oliver"
        time="2:25 AM"
        badge="1"
        message="just finished the playlist, you're gonna love it"
        collapsed
      />

      {/* Nora — text only, no badge */}
      <MessageCard
        avatar={noraAvatar}
        name="Nora"
        time="1:48 AM"
        message="remind me to tell you about what happened today"
        collapsed
      />
    </div>

  </div>
)

// ── Phone Mockup Wrapper ──
const FeedLiveMockup = ({
  eyebrow = 'Live Feed Preview',
  title = 'Every message has a face.',
  subtitle = 'Your feed is private messages from friends. Open, reply, keep moving.',
}) => (
  <section className="phone-mockup-page" aria-label="Phone mockup of the mknoon live feed">
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
                <LiveFeedScreen />
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

export default FeedLiveMockup
