/**
 * PhoneCircleStandalone.jsx
 * Self-contained phone mockup with Circle (Inner Circle) screen.
 * Drop this single file into any React project — no external CSS needed.
 */

const avatarUrls = [
  'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=200&h=200&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=200&h=200&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=200&h=200&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=200&h=200&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=200&h=200&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?w=200&h=200&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1524504388940-b1c1722653e1?w=200&h=200&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1488426862026-3ee34a7d66df?w=200&h=200&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=200&h=200&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=200&h=200&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1531746020798-e6953c6e8e04?w=200&h=200&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=200&h=200&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1554151228-14d9def656e4?w=200&h=200&fit=crop&crop=face',
]

const centerAvatar = 'https://images.unsplash.com/photo-1603415526960-f7e0328c63b1?w=200&h=200&fit=crop&crop=face'

const orbitRings = [
  { count: 5, radius: 62, avatarSize: 38 },
  { count: 8, radius: 108, avatarSize: 30 },
]

const friendNames = ['Sarah','Mike','Emma','James','Olivia','Alex','Zoe','Liam','Mia','Noah','Ava','Ethan','Isla']
const friendUsernames = ['sarah_1','mike_2','emma_3','james_4','olivia_5','alex_6','zoe_7','liam_8','mia_9','noah_10','ava_11','ethan_12','isla_13']
const friendColors = ['#1DB954','#4ecdc4','#a855f7','#f59e0b','#10b981','#3b82f6','#ef4444','#ec4899','#8b5cf6','#06b6d4','#f97316','#84cc16','#14b8a6']
const friendStatuses = ['online','online','offline','online','offline','online','offline','online','offline','offline','online','offline','online']
const friendUnreads = [5, 0, 3, 0, 1, 0, 0, 8, 0, 0, 2, 0, 0]
const friendTimes = ['Active now','2m ago','5m ago','15m ago','30m ago','1h ago','2h ago','3h ago','5h ago','8h ago','12h ago','1d ago','2d ago']

const friends = friendNames.map((name, i) => ({
  id: i,
  name,
  username: friendUsernames[i],
  avatar: avatarUrls[i],
  color: friendColors[i],
  status: friendStatuses[i],
  unreadCount: friendUnreads[i],
  lastSeen: friendTimes[i],
}))

/* ── Orbital visualization (static) ── */
const OrbitalView = () => {
  let idx = 0
  const ringData = orbitRings.map(ring => {
    const f = friends.slice(idx, idx + ring.count)
    idx += ring.count
    return { ...ring, friends: f }
  })
  const totalShown = orbitRings.reduce((s, r) => s + r.count, 0)
  const remaining = friends.length - totalShown

  return (
    <div style={s.orbitalWrap}>
      {/* Ring circles */}
      {ringData.map((ring, i) => (
        <div key={i} style={{
          position: 'absolute',
          borderRadius: '50%',
          border: '1px solid rgba(129,230,217,0.12)',
          top: `${160 - ring.radius}px`,
          left: `${160 - ring.radius}px`,
          right: `${160 - ring.radius}px`,
          bottom: `${160 - ring.radius}px`,
        }} />
      ))}

      {/* Center avatar */}
      <div style={s.orbitalCenter}>
        <img src={centerAvatar} alt="You" style={{ width: 48, height: 48, borderRadius: '50%', objectFit: 'cover' }} />
      </div>

      {/* Orbital friends */}
      {ringData.map((ring, ringIndex) =>
        ring.friends.map((friend, i) => {
          const offset = ringIndex * 15
          const angle = (i * (360 / ring.count) + offset - 90) * (Math.PI / 180)
          const x = Math.cos(angle) * ring.radius
          const y = Math.sin(angle) * ring.radius
          return (
            <div key={friend.id} style={{
              position: 'absolute',
              top: '50%',
              left: '50%',
              transform: `translate(calc(-50% + ${x}px), calc(-50% + ${y}px))`,
              zIndex: 2,
            }}>
              <img
                src={friend.avatar}
                alt={friend.name}
                style={{
                  width: ring.avatarSize,
                  height: ring.avatarSize,
                  borderRadius: '50%',
                  objectFit: 'cover',
                  border: `2px solid ${friend.color}`,
                  display: 'block',
                }}
              />
              {friend.status === 'online' && (
                <span style={{
                  position: 'absolute',
                  bottom: ringIndex === 0 ? 0 : -1,
                  right: ringIndex === 0 ? 0 : -1,
                  width: ringIndex === 0 ? 9 : 7,
                  height: ringIndex === 0 ? 9 : 7,
                  borderRadius: '50%',
                  background: '#1DB954',
                  border: '2px solid #0a0a0f',
                }} />
              )}
            </div>
          )
        })
      )}

      {/* Overflow badge */}
      {remaining > 0 && (() => {
        const lastRing = orbitRings[orbitRings.length - 1]
        const angle = (lastRing.count * (360 / lastRing.count) + 15 - 90) * (Math.PI / 180)
        const x = Math.cos(angle) * lastRing.radius
        const y = Math.sin(angle) * lastRing.radius
        return (
          <div style={{
            position: 'absolute',
            top: '50%',
            left: '50%',
            transform: `translate(calc(-50% + ${x}px), calc(-50% + ${y}px))`,
            width: 28,
            height: 28,
            borderRadius: '50%',
            background: 'rgba(255,255,255,0.08)',
            border: '1px solid rgba(255,255,255,0.15)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            fontSize: 10,
            fontWeight: 700,
            color: 'rgba(255,255,255,0.7)',
            zIndex: 2,
          }}>
            +{remaining}
          </div>
        )
      })()}
    </div>
  )
}

/* ── Friend row ── */
const FriendRow = ({ friend }) => (
  <div style={s.friendRow}>
    <div style={{ position: 'relative', flexShrink: 0 }}>
      <img src={friend.avatar} alt={friend.name} style={s.friendAvatar} />
      {friend.status === 'online' && <span style={s.friendOnlineDot} />}
    </div>
    <div style={s.friendInfo}>
      <span style={s.friendName}>{friend.name}</span>
      <span style={s.friendUsername}>@{friend.username}</span>
    </div>
    <div style={s.friendMeta}>
      {friend.unreadCount > 0 ? (
        <>
          <span style={s.unreadBadge}>{friend.unreadCount}</span>
          <span style={s.friendTime}>{friend.lastSeen}</span>
        </>
      ) : (
        <span style={s.friendTime}>{friend.lastSeen}</span>
      )}
    </div>
  </div>
)

/* ── Circle Screen (static mockup) ── */
const CircleScreenMockup = () => (
  <div style={s.circleScreen}>
    {/* Ambient background */}
    <div style={s.ambientBg} />

    {/* Close button */}
    <div style={s.closeBtn}>
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round">
        <line x1="18" y1="6" x2="6" y2="18"/>
        <line x1="6" y1="6" x2="18" y2="18"/>
      </svg>
    </div>

    {/* Add button */}
    <div style={s.addBtn}>
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round">
        <line x1="12" y1="6" x2="12" y2="18" />
        <line x1="6" y1="12" x2="18" y2="12" />
      </svg>
    </div>

    {/* Orbital section */}
    <div style={s.orbitalSection}>
      <h2 style={s.orbitalTitle}>Your Inner Circle</h2>
      <OrbitalView />
      <p style={s.orbitalLabel}>Close Friends</p>
    </div>

    {/* Friends list header */}
    <div style={s.friendsHeader}>
      <h3 style={s.friendsTitle}>Friends</h3>
      <div style={{ display: 'flex', gap: 8 }}>
        <div style={s.actionBtn}>
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <rect x="3" y="3" width="7" height="7" rx="1"/>
            <rect x="14" y="3" width="7" height="7" rx="1"/>
            <rect x="3" y="14" width="7" height="7" rx="1"/>
            <rect x="14" y="14" width="3" height="3"/>
            <line x1="21" y1="14" x2="21" y2="17.5"/>
            <line x1="17" y1="21" x2="21" y2="21"/>
          </svg>
          <span>My QR</span>
        </div>
        <div style={s.actionBtn}>
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"/>
            <circle cx="12" cy="13" r="4"/>
          </svg>
          <span>Scan</span>
        </div>
      </div>
    </div>

    {/* Filter tabs */}
    <div style={s.filterRow}>
      <div style={{ ...s.filterBtn, ...s.filterBtnActive }}>
        All
        <span style={s.filterCount}>100</span>
      </div>
      <div style={s.filterBtn}>
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ marginRight: 3, verticalAlign: '-2px' }}>
          <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" />
          <circle cx="9" cy="7" r="4" />
          <path d="M23 21v-2a4 4 0 0 0-3-3.87" />
          <path d="M16 3.13a4 4 0 0 1 0 7.75" />
        </svg>
        Intros
        <span style={{ ...s.filterCount, background: 'rgba(29,185,84,0.2)', color: '#4ade80' }}>5</span>
      </div>
      <div style={s.filterBtn}>Archived</div>
    </div>

    {/* Intros banner */}
    <div style={s.introsBanner}>
      <div style={s.introsBannerIcon}>
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
          <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" />
          <circle cx="9" cy="7" r="4" />
          <path d="M23 21v-2a4 4 0 0 0-3-3.87" />
          <path d="M16 3.13a4 4 0 0 1 0 7.75" />
        </svg>
      </div>
      <div style={s.introsBannerContent}>
        <span style={s.introsBannerTitle}>5 introductions from N...</span>
        <span style={s.introsBannerDesc}>Review and accept to start chatting</span>
      </div>
      <span style={s.introsBadge}>New</span>
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="rgba(255,255,255,0.3)" strokeWidth="2">
        <polyline points="9 18 15 12 9 6"/>
      </svg>
    </div>

    {/* Friend rows */}
    {friends.slice(0, 4).map(f => (
      <FriendRow key={f.id} friend={f} />
    ))}

    {/* Search bar */}
    <div style={s.searchBar}>
      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" style={{ opacity: 0.4, flexShrink: 0 }}>
        <circle cx="11" cy="11" r="8"/>
        <line x1="21" y1="21" x2="16.65" y2="16.65"/>
      </svg>
      <span style={{ fontSize: 13, color: 'rgba(255,255,255,0.3)', flex: 1 }}>Search friends...</span>
      <div style={s.searchClose}>
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round">
          <line x1="18" y1="6" x2="6" y2="18" />
          <line x1="6" y1="6" x2="18" y2="18" />
        </svg>
      </div>
    </div>
  </div>
)

/* ── Phone device + Circle screen ── */
const PhoneCircleStandalone = () => (
  <div style={s.page}>
    <div style={s.stage}>
      <div style={s.deviceWrapper}>
        <div style={s.device}>
          <div style={{ ...s.btn, left: -3, top: 128, width: 3, height: 24 }} />
          <div style={{ ...s.btn, left: -3, top: 180, width: 3, height: 44 }} />
          <div style={{ ...s.btn, left: -3, top: 236, width: 3, height: 44 }} />
          <div style={{ ...s.btn, right: -3, top: 200, width: 3, height: 60, left: 'auto' }} />
          <div style={s.bezelHighlight} />
          <div style={s.screen}>
            <div style={s.dynamicIsland} />
            <div style={s.screenSheen} />
            <div style={s.screenImage}>
              <CircleScreenMockup />
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
)

/* ══════════════════════════════════════════════════════════
   All styles as JS objects
   ══════════════════════════════════════════════════════════ */
const DEVICE_W = 304
const DEVICE_H = DEVICE_W * 2.0666667

const s = {
  /* ── Page / phone frame ── */
  page: {
    position: 'relative',
    width: '100%',
    display: 'flex',
    justifyContent: 'center',
    padding: '40px 20px',
    background: 'linear-gradient(180deg, #08090d 0%, #050608 52%, #030405 100%)',
  },

  stage: {
    position: 'relative',
    width: 'min(100%, 420px)',
    margin: '0 auto',
    padding: '18px 18px 20px',
    borderRadius: 32,
    background: 'linear-gradient(180deg, rgba(14,16,24,0.92) 0%, rgba(7,9,14,0.96) 100%)',
    border: '1px solid rgba(255,255,255,0.08)',
    boxShadow: '0 28px 80px rgba(0,0,0,0.45), inset 0 1px 0 rgba(255,255,255,0.05)',
    overflow: 'hidden',
    backdropFilter: 'blur(14px)',
  },

  deviceWrapper: {
    perspective: 1200,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    position: 'relative',
    zIndex: 1,
    padding: '8px 0 18px',
  },

  device: {
    position: 'relative',
    width: DEVICE_W,
    height: DEVICE_H,
    borderRadius: 52,
    background: 'linear-gradient(145deg, #3d3f47 0%, #21242d 16%, #0f1118 45%, #050608 100%)',
    boxShadow: '0 0 0 1.5px rgba(255,255,255,0.08), 0 0 0 3px #0a0a0c, 0 30px 75px rgba(0,0,0,0.62), 0 10px 28px rgba(0,0,0,0.32), inset 0 1px 0 rgba(255,255,255,0.07)',
  },

  btn: {
    position: 'absolute',
    background: 'linear-gradient(180deg, #414551, #232833)',
    borderRadius: 4,
    zIndex: 6,
  },

  bezelHighlight: {
    position: 'absolute',
    inset: 1,
    borderRadius: 50,
    background: 'linear-gradient(135deg, rgba(255,255,255,0.22) 0%, rgba(255,255,255,0.02) 18%, transparent 38%, transparent 72%, rgba(255,255,255,0.08) 100%)',
    pointerEvents: 'none',
    zIndex: 5,
    opacity: 0.55,
  },

  screen: {
    position: 'absolute',
    top: 12, left: 12, right: 12, bottom: 12,
    borderRadius: 40,
    overflow: 'hidden',
    background: '#07090e',
    boxShadow: 'inset 0 0 0 1px rgba(255,255,255,0.05)',
  },

  dynamicIsland: {
    position: 'absolute',
    top: 14,
    left: '50%',
    transform: 'translateX(-50%)',
    width: 118,
    height: 30,
    background: 'rgba(2,3,4,0.92)',
    borderRadius: 20,
    zIndex: 10,
    boxShadow: '0 0 0 1px rgba(255,255,255,0.04), 0 10px 18px rgba(0,0,0,0.45)',
  },

  screenSheen: {
    position: 'absolute',
    inset: 0,
    background: 'linear-gradient(180deg, rgba(255,255,255,0.08) 0%, transparent 16%, transparent 72%, rgba(255,255,255,0.03) 100%)',
    mixBlendMode: 'screen',
    pointerEvents: 'none',
    zIndex: 9,
  },

  screenImage: {
    position: 'absolute',
    inset: 0,
    overflow: 'hidden',
    pointerEvents: 'none',
  },

  /* ── Circle screen ── */
  circleScreen: {
    width: '100%',
    height: '100%',
    background: '#030405',
    display: 'flex',
    flexDirection: 'column',
    fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif",
    overflowY: 'auto',
    overflowX: 'hidden',
    color: '#fff',
    scrollbarWidth: 'none',
    position: 'relative',
  },

  ambientBg: {
    position: 'absolute',
    inset: 0,
    background: 'radial-gradient(ellipse 80% 50% at 50% 20%, rgba(129,230,217,0.06) 0%, transparent 60%), radial-gradient(ellipse 60% 40% at 30% 10%, rgba(167,139,250,0.05) 0%, transparent 50%)',
    pointerEvents: 'none',
    zIndex: 0,
  },

  closeBtn: {
    position: 'absolute',
    top: 14,
    left: 14,
    zIndex: 200,
    background: 'rgba(255,255,255,0.1)',
    backdropFilter: 'blur(12px)',
    border: '1px solid rgba(255,255,255,0.12)',
    borderRadius: '50%',
    width: 36,
    height: 36,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    color: 'rgba(255,255,255,0.8)',
  },

  addBtn: {
    position: 'absolute',
    top: 14,
    right: 14,
    zIndex: 200,
    background: 'rgba(255,255,255,0.1)',
    backdropFilter: 'blur(12px)',
    border: '1px solid rgba(255,255,255,0.12)',
    borderRadius: '50%',
    width: 36,
    height: 36,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    color: 'rgba(255,255,255,0.8)',
  },

  /* ── Orbital ── */
  orbitalSection: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    padding: '56px 0 8px',
    position: 'relative',
    zIndex: 1,
  },

  orbitalTitle: {
    fontSize: 11,
    fontWeight: 700,
    letterSpacing: '0.14em',
    textTransform: 'uppercase',
    color: 'rgba(255,255,255,0.6)',
    marginBottom: 16,
  },

  orbitalWrap: {
    position: 'relative',
    width: 320,
    height: 320,
  },

  orbitalCenter: {
    position: 'absolute',
    top: '50%',
    left: '50%',
    transform: 'translate(-50%, -50%)',
    zIndex: 3,
  },

  orbitalLabel: {
    fontSize: 13,
    color: 'rgba(255,255,255,0.5)',
    fontWeight: 500,
    marginTop: 8,
  },

  /* ── Friends header + actions ── */
  friendsHeader: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: '16px 16px 8px',
    position: 'relative',
    zIndex: 1,
  },

  friendsTitle: {
    fontSize: 18,
    fontWeight: 700,
    margin: 0,
  },

  actionBtn: {
    display: 'inline-flex',
    alignItems: 'center',
    gap: 5,
    padding: '6px 12px',
    borderRadius: 20,
    background: 'rgba(29,185,84,0.08)',
    border: '1px solid rgba(29,185,84,0.2)',
    color: '#4ade80',
    fontSize: 12,
    fontWeight: 600,
  },

  /* ── Filter tabs ── */
  filterRow: {
    display: 'flex',
    gap: 6,
    padding: '4px 16px 10px',
    position: 'relative',
    zIndex: 1,
  },

  filterBtn: {
    display: 'inline-flex',
    alignItems: 'center',
    gap: 4,
    padding: '5px 10px',
    borderRadius: 16,
    background: 'rgba(255,255,255,0.04)',
    border: '1px solid rgba(255,255,255,0.06)',
    color: 'rgba(255,255,255,0.45)',
    fontSize: 12,
    fontWeight: 600,
  },

  filterBtnActive: {
    background: 'rgba(255,255,255,0.1)',
    border: '1px solid rgba(255,255,255,0.15)',
    color: '#fff',
  },

  filterCount: {
    padding: '1px 6px',
    borderRadius: 10,
    background: 'rgba(255,255,255,0.1)',
    fontSize: 11,
    fontWeight: 700,
    color: 'rgba(255,255,255,0.7)',
  },

  /* ── Intros banner ── */
  introsBanner: {
    display: 'flex',
    alignItems: 'center',
    gap: 10,
    margin: '0 12px 8px',
    padding: '10px 12px',
    borderRadius: 14,
    background: 'rgba(29,185,84,0.06)',
    border: '1px solid rgba(29,185,84,0.15)',
    position: 'relative',
    zIndex: 1,
  },

  introsBannerIcon: {
    width: 36,
    height: 36,
    borderRadius: 10,
    background: 'rgba(29,185,84,0.12)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    color: '#4ade80',
    flexShrink: 0,
  },

  introsBannerContent: {
    flex: 1,
    display: 'flex',
    flexDirection: 'column',
    gap: 2,
    minWidth: 0,
  },

  introsBannerTitle: {
    fontSize: 12,
    fontWeight: 600,
    color: '#fff',
    whiteSpace: 'nowrap',
    overflow: 'hidden',
    textOverflow: 'ellipsis',
  },

  introsBannerDesc: {
    fontSize: 11,
    color: 'rgba(255,255,255,0.4)',
  },

  introsBadge: {
    padding: '2px 8px',
    borderRadius: 8,
    background: '#1DB954',
    color: '#fff',
    fontSize: 10,
    fontWeight: 700,
    textTransform: 'uppercase',
    letterSpacing: '0.04em',
    flexShrink: 0,
  },

  /* ── Friend row ── */
  friendRow: {
    display: 'flex',
    alignItems: 'center',
    gap: 10,
    padding: '8px 16px',
    position: 'relative',
    zIndex: 1,
  },

  friendAvatar: {
    width: 44,
    height: 44,
    borderRadius: '50%',
    objectFit: 'cover',
    border: '2px solid rgba(255,255,255,0.08)',
  },

  friendOnlineDot: {
    position: 'absolute',
    bottom: 1,
    right: 1,
    width: 10,
    height: 10,
    borderRadius: '50%',
    background: '#1DB954',
    border: '2px solid #030405',
    display: 'inline-block',
  },

  friendInfo: {
    flex: 1,
    display: 'flex',
    flexDirection: 'column',
    gap: 1,
    minWidth: 0,
  },

  friendName: {
    fontSize: 14,
    fontWeight: 600,
    color: '#fff',
  },

  friendUsername: {
    fontSize: 12,
    color: 'rgba(255,255,255,0.35)',
  },

  friendMeta: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'flex-end',
    gap: 4,
    flexShrink: 0,
  },

  unreadBadge: {
    padding: '2px 7px',
    borderRadius: 10,
    background: '#1DB954',
    color: '#fff',
    fontSize: 11,
    fontWeight: 700,
    minWidth: 20,
    textAlign: 'center',
  },

  friendTime: {
    fontSize: 11,
    color: 'rgba(255,255,255,0.3)',
    whiteSpace: 'nowrap',
  },

  /* ── Search bar ── */
  searchBar: {
    display: 'flex',
    alignItems: 'center',
    gap: 10,
    margin: '6px 12px 20px',
    padding: '10px 14px',
    borderRadius: 14,
    background: 'rgba(255,255,255,0.04)',
    border: '1px solid rgba(255,255,255,0.08)',
    position: 'relative',
    zIndex: 1,
  },

  searchClose: {
    width: 28,
    height: 28,
    borderRadius: '50%',
    background: 'rgba(255,255,255,0.06)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    color: 'rgba(255,255,255,0.4)',
    flexShrink: 0,
  },
}

export default PhoneCircleStandalone
