import CircleScreen2 from './CircleScreen2'

// Inline default theme to avoid circular import with App.jsx
const defaultTheme = {
  id: 'default',
  name: 'Current',
  desc: 'Purple + Teal',
  bg: 'linear-gradient(180deg, #0f0f18 0%, #0a0a0f 100%)',
  accent1: '#a78bfa',
  accent2: '#81e6d9',
  text: '#ffffff',
  textMuted: 'rgba(255,255,255,0.5)',
  glassBg: 'rgba(255,255,255,0.03)',
  glassBorder: 'rgba(255,255,255,0.08)',
}

const PhoneMockup = ({
  eyebrow = 'Actual App Preview',
  title = 'Watch your circle grow the right way',
  subtitle = 'Your circle builds the way it does in real life: slowly, naturally, through people you trust.\nOver time, introductions turn one connection into a connected world. Still close, still yours.',
}) => {
  const theme = defaultTheme

  return (
    <section className="phone-mockup-page" aria-label="Phone mockup preview of the mknoon app">
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

                <div className="phone-screen-content">
                  <CircleScreen2
                    onSwitchView={() => {}}
                    theme={theme}
                    blockedIds={new Set()}
                    onBlockFriend={() => {}}
                    onUnblockFriend={() => {}}
                  />
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

export default PhoneMockup
