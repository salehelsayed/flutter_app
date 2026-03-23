const ibrahimAvatar = 'https://images.unsplash.com/photo-1531891437562-4301cf35b7e4?w=200&h=200&fit=crop&crop=face'
const mouAvatar = 'https://images.unsplash.com/photo-1524504388940-b1c1722653e1?w=200&h=200&fit=crop&crop=face'
const hisamAvatar = 'https://images.unsplash.com/photo-1463453091185-61582044d556?w=200&h=200&fit=crop&crop=face'

// Mini feed that renders live inside the phone frame
const MiniFeed = () => (
  <div className="mini-feed">
    {/* Status bar */}
    <div className="mini-feed-statusbar">
      <span className="mini-feed-time">01:22</span>
      <div className="mini-feed-statusbar-right">
        <svg width="16" height="12" viewBox="0 0 16 12" fill="white"><path d="M8 0C3.58 0 0 2.69 0 6h2c0-2.21 2.69-4 6-4s6 1.79 6 4h2c0-3.31-3.58-6-8-6z" opacity=".3"/><path d="M8 4C5.79 4 4 5.12 4 6.5h2c0-.28.9-.5 2-.5s2 .22 2 .5h2C12 5.12 10.21 4 8 4z" opacity=".6"/><circle cx="8" cy="9" r="1.5" opacity="1"/></svg>
        <svg width="18" height="12" viewBox="0 0 24 12" fill="white"><rect x="1" y="1" width="20" height="10" rx="2" stroke="white" strokeWidth="1.5" fill="none"/><rect x="22" y="4" width="2" height="4" rx="0.5" fill="white" opacity=".4"/><rect x="2.5" y="2.5" width="14" height="7" rx="1" fill="white"/></svg>
      </div>
    </div>

    {/* Header */}
    <div className="mini-feed-header">
      <div className="mini-feed-header-left">
        <span className="mini-feed-username">mknoon/@Rami</span>
        <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="rgba(255,255,255,0.35)" strokeWidth="2"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>
      </div>
      <div className="mini-feed-header-right">
        <div className="mini-feed-online-badge">
          <span className="mini-feed-online-dot" />
          <span className="mini-feed-online-text">Online</span>
          <span className="mini-feed-online-count">(2)</span>
        </div>
        <div className="mini-feed-avatar">
          <img src={ibrahimAvatar} alt="Rami" />
        </div>
      </div>
    </div>

    {/* Composer */}
    <div className="mini-feed-composer">
      <span className="mini-feed-composer-plus">+</span>
      <span className="mini-feed-composer-text">Continue...</span>
      <span className="mini-feed-composer-send">↑</span>
    </div>

    {/* Introduction Card */}
    <div className="mini-feed-card">
      <div className="mini-feed-intro-top">
        <div className="mini-feed-intro-avatar-small">
          <img src={mouAvatar} alt="Sara" />
        </div>
        <span className="mini-feed-intro-label">Introduced by Sara</span>
      </div>
      <div className="mini-feed-intro-avatars">
        <div className="mini-feed-intro-person">
          <div className="mini-feed-intro-photo mini-feed-intro-photo--plain">
            <img src={ibrahimAvatar} alt="Rami" />
          </div>
          <span className="mini-feed-intro-name">Rami</span>
        </div>
        <svg className="mini-feed-intro-line" width="32" height="6" viewBox="0 0 32 6">
          <line x1="0" y1="3" x2="32" y2="3" stroke="#4ade80" strokeWidth="1.5" strokeDasharray="4 3" strokeLinecap="round" />
        </svg>
        <div className="mini-feed-intro-person">
          <div className="mini-feed-intro-photo mini-feed-intro-photo--plain">
            <img src={hisamAvatar} alt="Oliver" />
          </div>
          <span className="mini-feed-intro-name">Oliver</span>
        </div>
      </div>
      <button className="mini-feed-send-btn">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
        </svg>
        Send Message
      </button>
    </div>

    {/* Connected Card */}
    <div className="mini-feed-card mini-feed-card--connected">
      <h3 className="mini-feed-connected-title">Connected!</h3>
      <div className="mini-feed-connected-avatar">
        <div className="mini-feed-intro-photo mini-feed-intro-photo--plain">
          <img src={mouAvatar} alt="Sara" />
        </div>
      </div>
      <div className="mini-feed-connected-name">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="#1DB954">
          <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/>
        </svg>
        <span>Sara</span>
      </div>
      <button className="mini-feed-send-btn">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
        </svg>
        Send Message
      </button>
    </div>

    {/* Bottom Nav */}
    <div className="mini-feed-nav">
      <div className="mini-feed-nav-item mini-feed-nav-item--active">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round">
          <line x1="4" y1="7" x2="20" y2="7" />
          <line x1="4" y1="12" x2="16" y2="12" />
          <line x1="4" y1="17" x2="20" y2="17" />
        </svg>
        <span>Feed</span>
      </div>
      <div className="mini-feed-nav-item">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
          <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
        </svg>
        <span>Remember</span>
      </div>
      <div className="mini-feed-nav-item">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
          <circle cx="12" cy="12" r="3" />
          <path d="M12 2v2m0 16v2M2 12h2m16 0h2" />
          <path d="M4.93 4.93l1.41 1.41m11.32 11.32l1.41 1.41M4.93 19.07l1.41-1.41m11.32-11.32l1.41-1.41" />
        </svg>
        <span>Orbit</span>
      </div>
    </div>
  </div>
)


const PhoneMockupFeed = ({
  eyebrow = 'Actual App Preview',
  title = 'Introductions are personal. That\u2019s the point.',
  subtitle = 'When you connect friends, your name goes with it. mknoon keeps introductions built on trust.',
}) => {
  return (
    <section className="phone-mockup-page" aria-label="Phone mockup of the mknoon feed">
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
                  <MiniFeed />
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
}

export default PhoneMockupFeed
