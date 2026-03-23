import { useState, useEffect, useRef } from 'react'
import { colorThemes, currentUser, useScrollNavVisibility, RingBrandedAvatar } from './App'

// Generate 100 mock friends for Circle 2
export const manyFriends = (() => {
  const firstNames = ['Sarah','Mike','Emma','James','Olivia','Alex','Zoe','Liam','Mia','Noah','Ava','Ethan','Isla','Lucas','Chloe','Mason','Lily','Logan','Aria','Jack','Ella','Ben','Luna','Leo','Nora','Owen','Iris','Kai','Ruby','Finn','Maya','Cole','Ivy','Jude','Sage','Theo','Piper','Axel','Hazel','Remy','Freya','Dean','Willow','Cruz','Stella','Reid','Clara','Nash','Vera','Beau','Dara','Troy','Faye','Wade','Nell','Kurt','Tess','Hugh','Wren','Seth','Lena','Dale','Rosa','Vince','Beth','Grant','Eve','Clyde','Pearl','Roy','Ada','Frank','June','Walt','Fern','Hank','Opal','Glenn','Thea','Max','Sky','Blake','Drew','Jade','Ray','Nina','Sean','Tara','Paul','Gwen','Mark','Hope','Doug','Kate','Sam','Rory','Tom','Lara','Jake','Demi']
  const colors = ['#1DB954','#4ecdc4','#a855f7','#f59e0b','#10b981','#3b82f6','#ef4444','#ec4899','#8b5cf6','#06b6d4','#f97316','#84cc16','#14b8a6','#e11d48','#7c3aed','#0ea5e9']
  const activities = ['Sent you a voice note','Shared a memory','Thinking of you','From Tokyo','Checking in','Liked your moment','Sent a photo','Started a thread','Shared a song','Posted a story','Sent a reaction','Mentioned you','Shared a link','Updated status','Dropped a pin','Left a note']
  const times = ['Active now','2m ago','5m ago','15m ago','30m ago','1h ago','2h ago','3h ago','5h ago','8h ago','12h ago','1d ago','2d ago','3d ago','5d ago','1w ago']
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
    'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=200&h=200&fit=crop&crop=face',
    'https://images.unsplash.com/photo-1580489944761-15a19d654956?w=200&h=200&fit=crop&crop=face',
    'https://images.unsplash.com/photo-1519345182560-3f2917c472ef?w=200&h=200&fit=crop&crop=face',
    'https://images.unsplash.com/photo-1529626455594-4ff0802cfb7e?w=200&h=200&fit=crop&crop=face',
    'https://images.unsplash.com/photo-1552058544-f2b08422138a?w=200&h=200&fit=crop&crop=face',
    'https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?w=200&h=200&fit=crop&crop=face',
    'https://images.unsplash.com/photo-1546961342-ea5f71b193f3?w=200&h=200&fit=crop&crop=face',
    null, null, null, null, null,
  ]
  // Indices that get unread counts (roughly 15 friends scattered across the list)
  const unreadMap = { 0: 5, 2: 3, 4: 1, 7: 8, 11: 2, 15: 12, 19: 4, 24: 1, 30: 6, 38: 3, 45: 2, 55: 9, 63: 1, 78: 7, 91: 4 }
  return Array.from({ length: 100 }, (_, i) => ({
    id: i + 100,
    name: firstNames[i],
    username: firstNames[i].toLowerCase() + '_' + (i + 1),
    peerId: '12D3KooW' + firstNames[i].toLowerCase() + i + 'friendconnectionmknoon',
    avatar: avatarUrls[i % avatarUrls.length],
    color: colors[i % colors.length],
    status: i < 8 || i % 7 === 0 ? 'online' : 'offline',
    lastActivity: activities[i % activities.length],
    lastSeen: times[Math.min(i, times.length - 1)],
    unreadCount: unreadMap[i] || 0,
  }))
})()

// Mock introduction groups (User-B receiving intros)
const mockIntroGroups = [
  {
    sender: { name: 'Noor', avatar: manyFriends[10].avatar, color: manyFriends[10].color },
    people: [manyFriends[50], manyFriends[51], manyFriends[52]],
  },
  {
    sender: { name: 'Kai', avatar: manyFriends[27].avatar, color: manyFriends[27].color },
    people: [manyFriends[60], manyFriends[61]],
  },
]

// Ring layout: 2 curated tiers
const orbitRings = [
  { count: 5,  radius: 62,  avatarSize: 38 },
  { count: 8,  radius: 108, avatarSize: 30 },
]

const INNER_CIRCLE_COUNT = orbitRings.reduce((s, r) => s + r.count, 0)

const kbRows = [
  ['q','w','e','r','t','y','u','i','o','p'],
  ['a','s','d','f','g','h','j','k','l'],
  ['shift','z','x','c','v','b','n','m','del'],
]

const SimKeyboard = ({ onKey }) => (
  <div className="sim-keyboard">
    {kbRows.map((row, ri) => (
      <div key={ri} className="sim-kb-row">
        {row.map(k => (
          <button
            key={k}
            className={`sim-kb-key ${k === 'shift' || k === 'del' ? 'sim-kb-key--fn' : ''}`}
            onClick={() => onKey(k)}
          >
            {k === 'del' ? (
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M21 4H8l-7 8 7 8h13a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2z"/>
                <line x1="18" y1="9" x2="12" y2="15"/>
                <line x1="12" y1="9" x2="18" y2="15"/>
              </svg>
            ) : k === 'shift' ? (
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M12 3l9 9h-6v8H9v-8H3z"/>
              </svg>
            ) : k}
          </button>
        ))}
      </div>
    ))}
    <div className="sim-kb-row sim-kb-row--bottom">
      <button className="sim-kb-key sim-kb-key--fn" onClick={() => onKey('shift')}>123</button>
      <button className="sim-kb-key sim-kb-key--space" onClick={() => onKey('space')}>space</button>
      <button className="sim-kb-key sim-kb-key--fn sim-kb-key--go" onClick={() => onKey('go')}>go</button>
    </div>
  </div>
)

// ── Swipeable Friend Row ─────────────────────────────────
const SwipeableFriendRow = ({
  friend,
  children,
  onArchive,
  onUnarchive,
  onBlock,
  onUnblock,
  isArchived,
  isBlocked,
  isArchiving
}) => {
  const rowRef = useRef(null)
  const wrapperRef = useRef(null)
  const startX = useRef(0)
  const currentX = useRef(0)
  const isOpen = useRef(false)
  const shouldSuppressTap = useRef(false)
  const ACTION_WIDTH = isArchived ? 132 : 218
  const [pendingConfirm, setPendingConfirm] = useState(null)

  const setActionRevealFromTranslate = (x) => {
    if (!wrapperRef.current) return
    const reveal = Math.max(0, Math.min(ACTION_WIDTH, -x))
    wrapperRef.current.style.setProperty('--swipe-actions-offset', `${ACTION_WIDTH - reveal}px`)
  }

  // Trigger collapse animation when archiving
  useEffect(() => {
    if (isArchiving && wrapperRef.current) {
      // Force a layout read so the browser registers the initial state
      wrapperRef.current.offsetHeight
      wrapperRef.current.classList.add('archive-out')
    }
  }, [isArchiving])

  const dragging = useRef(false)

  const onDragStart = (clientX) => {
    startX.current = clientX
    currentX.current = isOpen.current ? -ACTION_WIDTH : 0
    dragging.current = true
    shouldSuppressTap.current = false
    if (wrapperRef.current) {
      wrapperRef.current.classList.add('dragging')
    }
    if (isOpen.current) {
      wrapperRef.current?.classList.add('swiping')
    }
    setActionRevealFromTranslate(currentX.current)
    if (rowRef.current) {
      rowRef.current.style.transition = 'none'
    }
  }

  const onDragMove = (clientX) => {
    if (!dragging.current) return
    const dx = clientX - startX.current
    const base = isOpen.current ? -ACTION_WIDTH : 0
    let x = base + dx
    x = Math.min(0, Math.max(-(ACTION_WIDTH + 40), x))
    if (x < -ACTION_WIDTH) {
      const over = -x - ACTION_WIDTH
      x = -(ACTION_WIDTH + over * 0.3)
    }
    currentX.current = x
    setActionRevealFromTranslate(x)
    if (Math.abs(dx) > 8) {
      shouldSuppressTap.current = true
      if (x < 0) wrapperRef.current?.classList.add('swiping')
    }
    if (x >= 0 && !isOpen.current) {
      wrapperRef.current?.classList.remove('swiping')
    }
    if (rowRef.current) {
      rowRef.current.style.transform = `translateX(${x}px)`
    }
  }

  const onDragEnd = () => {
    if (!dragging.current) return
    dragging.current = false
    if (wrapperRef.current) {
      wrapperRef.current.classList.remove('dragging')
    }
    if (!rowRef.current) return
    rowRef.current.style.transition = 'transform 0.3s cubic-bezier(0.25, 0.46, 0.45, 0.94)'
    const threshold = ACTION_WIDTH / 2
    if (currentX.current < -threshold) {
      rowRef.current.style.transform = `translateX(${-ACTION_WIDTH}px)`
      setActionRevealFromTranslate(-ACTION_WIDTH)
      isOpen.current = true
      wrapperRef.current?.classList.add('swiping')
    } else {
      rowRef.current.style.transform = 'translateX(0px)'
      setActionRevealFromTranslate(0)
      isOpen.current = false
      wrapperRef.current?.classList.remove('swiping')
    }
  }

  // Touch handlers
  const handleTouchStart = (e) => onDragStart(e.touches[0].clientX)
  const handleTouchMove = (e) => onDragMove(e.touches[0].clientX)
  const handleTouchEnd = () => onDragEnd()

  // Mouse handlers (for desktop testing)
  const handleMouseDown = (e) => { e.preventDefault(); onDragStart(e.clientX) }
  const handleMouseMove = (e) => onDragMove(e.clientX)
  const handleMouseUp = () => onDragEnd()
  const handleMouseLeave = () => { if (dragging.current) onDragEnd() }

  const snapClosed = () => {
    if (rowRef.current) {
      rowRef.current.style.transition = 'transform 0.3s cubic-bezier(0.25, 0.46, 0.45, 0.94)'
      rowRef.current.style.transform = 'translateX(0px)'
    }
    setActionRevealFromTranslate(0)
    isOpen.current = false
    if (wrapperRef.current) {
      wrapperRef.current.classList.remove('dragging')
      wrapperRef.current.classList.remove('swiping')
    }
  }

  const handleRowClickCapture = (e) => {
    // If this pointer sequence was a swipe, suppress the synthetic click.
    if (shouldSuppressTap.current) {
      e.preventDefault()
      e.stopPropagation()
      shouldSuppressTap.current = false
      return
    }

    // If actions are open, tap closes them first instead of navigating.
    if (isOpen.current) {
      e.preventDefault()
      e.stopPropagation()
      snapClosed()
    }
  }

  const requestConfirm = (action) => {
    if (action === 'delete') {
      setPendingConfirm({
        action,
        title: 'Delete chat?',
        description: `This will remove your chat with ${friend.name} from your list only. ${friend.name} can still send you messages, and you will still receive them.`,
        confirmLabel: 'Delete',
        tone: 'danger'
      })
      return
    }

    if (action === 'block') {
      setPendingConfirm({
        action,
        title: 'Block contact?',
        description: `${friend.name} will no longer be able to message you until you unblock them.`,
        confirmLabel: 'Block',
        tone: 'danger'
      })
    }
  }

  const closeConfirm = () => {
    setPendingConfirm(null)
  }

  const handleConfirmAction = () => {
    if (!pendingConfirm) return

    const { action } = pendingConfirm
    if (action === 'block') {
      onBlock?.(friend.id)
    }
    if (action === 'delete') {
      // Placeholder: no delete persistence wired yet.
    }

    setPendingConfirm(null)
    snapClosed()
  }

  return (
    <div
      ref={wrapperRef}
      className={`swipe-row-wrapper${isArchiving ? ' archiving' : ''}`}
      style={{
        '--swipe-actions-width': `${ACTION_WIDTH}px`
      }}
    >
      {/* Left swipe actions (revealed on right side) */}
      <div className="swipe-row-actions">
        {isArchived ? (
          <button
            className="swipe-action-btn swipe-action-btn--unarchive"
            onClick={() => { snapClosed(); onUnarchive?.(friend.id) }}
          >
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <polyline points="9 14 4 9 9 4"/>
              <path d="M20 20v-7a4 4 0 0 0-4-4H4"/>
            </svg>
            Unarchive
          </button>
        ) : (
          <>
            <button
              className={`swipe-action-btn ${isBlocked ? 'swipe-action-btn--unblock' : 'swipe-action-btn--block'}`}
              onClick={() => {
                if (isBlocked) {
                  snapClosed()
                  onUnblock?.(friend.id)
                } else {
                  requestConfirm('block')
                }
              }}
            >
              {isBlocked ? (
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <polyline points="9 14 4 9 9 4"/>
                  <path d="M20 20v-7a4 4 0 0 0-4-4H4"/>
                </svg>
              ) : (
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <circle cx="12" cy="12" r="9"/>
                  <line x1="6" y1="18" x2="18" y2="6"/>
                </svg>
              )}
              {isBlocked ? 'Unblock' : 'Block'}
            </button>
            <button
              className="swipe-action-btn swipe-action-btn--delete"
              onClick={() => requestConfirm('delete')}
            >
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <polyline points="3 6 5 6 21 6"/>
                <path d="M19 6l-1 14H6L5 6"/>
                <path d="M10 11v6"/>
                <path d="M14 11v6"/>
                <path d="M9 6V4h6v2"/>
              </svg>
              Delete
            </button>
            <button
              className="swipe-action-btn swipe-action-btn--archive"
              onClick={() => { snapClosed(); onArchive?.(friend.id) }}
            >
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <polyline points="21 8 21 21 3 21 3 8"/>
                <rect x="1" y="3" width="22" height="5" rx="1"/>
                <line x1="10" y1="12" x2="14" y2="12"/>
              </svg>
              Archive
            </button>
          </>
        )}
      </div>
      {/* Swipeable content layer */}
      <div
        ref={rowRef}
        className="swipe-row-content"
        onClickCapture={handleRowClickCapture}
        onTouchStart={handleTouchStart}
        onTouchMove={handleTouchMove}
        onTouchEnd={handleTouchEnd}
        onMouseDown={handleMouseDown}
        onMouseMove={handleMouseMove}
        onMouseUp={handleMouseUp}
        onMouseLeave={handleMouseLeave}
      >
        {children}
      </div>
      {pendingConfirm && (
        <div className="swipe-confirm-overlay" onClick={closeConfirm}>
          <div className="swipe-confirm-card" onClick={(e) => e.stopPropagation()}>
            <h4 className="swipe-confirm-title">{pendingConfirm.title}</h4>
            <p className="swipe-confirm-text">{pendingConfirm.description}</p>
            <div className="swipe-confirm-actions">
              <button
                className="swipe-confirm-btn swipe-confirm-btn--cancel"
                onClick={closeConfirm}
              >
                Cancel
              </button>
              <button
                className={`swipe-confirm-btn ${pendingConfirm.tone === 'danger' ? 'swipe-confirm-btn--danger' : 'swipe-confirm-btn--accent'}`}
                onClick={handleConfirmAction}
              >
                {pendingConfirm.confirmLabel}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

const CircleScreen2 = ({
  onSwitchView,
  theme = colorThemes[0],
  blockedIds = new Set(),
  onBlockFriend,
  onUnblockFriend
}) => {
  const { isNavVisible, containerRef } = useScrollNavVisibility()
  const [searchActive, setSearchActive] = useState(false)
  const [searchQuery, setSearchQuery] = useState('')
  const searchInputRef = useRef(null)
  const [archivedIds, setArchivedIds] = useState(new Set())
  const [listFilter, setListFilter] = useState('all') // 'all' | 'archived' | 'intros'
  const [archivingId, setArchivingId] = useState(null)
  const [introStatuses, setIntroStatuses] = useState({}) // { [friendId]: 'pending' | 'accepted' | 'passed' }

  const allIntroPeople = mockIntroGroups.flatMap(g => g.people)
  const pendingIntrosCount = allIntroPeople.filter(p => (introStatuses[p.id] || 'pending') === 'pending').length

  const handleAcceptIntro = (id) => {
    setIntroStatuses(prev => ({ ...prev, [id]: 'accepted' }))
  }

  const handlePassIntro = (id) => {
    setIntroStatuses(prev => ({ ...prev, [id]: 'passed' }))
  }

  const handleArchive = (friendId) => {
    setArchivingId(friendId)
    // Delay the actual state change so the CSS animation plays first
    setTimeout(() => {
      setArchivedIds(prev => new Set([...prev, friendId]))
      setArchivingId(null)
    }, 380)
  }

  const handleUnarchive = (friendId) => {
    setArchivedIds(prev => {
      const next = new Set(prev)
      next.delete(friendId)
      return next
    })
  }

  const themeStyles = {
    '--theme-bg': theme.bg,
    '--theme-accent1': theme.accent1,
    '--theme-accent2': theme.accent2,
    '--theme-text': theme.text,
    '--theme-text-muted': theme.textMuted,
    '--theme-glass-bg': theme.glassBg,
    '--theme-glass-border': theme.glassBorder,
  }

  const frameStyles = {
    position: 'relative',
    width: '100%',
    height: '100%',
    overflow: 'hidden'
  }

  // Distribute friends across rings
  let friendIdx = 0
  const ringData = orbitRings.map((ring) => {
    const friends = manyFriends.slice(friendIdx, friendIdx + ring.count)
    friendIdx += ring.count
    return { ...ring, friends }
  })

  // Filter friends: search + archive filter
  const query = searchQuery.toLowerCase().trim()
  const archivedCount = archivedIds.size
  const activeFriends = manyFriends.filter(f => !archivedIds.has(f.id))
  const archivedFriends = manyFriends.filter(f => archivedIds.has(f.id))

  const baseList = listFilter === 'archived' ? archivedFriends : activeFriends
  const displayedFriends = query
    ? baseList.filter(f =>
        f.name.toLowerCase().includes(query) ||
        f.username.toLowerCase().includes(query)
      )
    : baseList

  const handleKey = (key) => {
    if (key === 'del') {
      setSearchQuery(prev => prev.slice(0, -1))
    } else if (key === 'shift') {
      // no-op for demo
    } else if (key === 'go') {
      searchInputRef.current?.blur()
    } else if (key === 'space') {
      setSearchQuery(prev => prev + ' ')
    } else {
      setSearchQuery(prev => prev + key)
    }
    searchInputRef.current?.focus()
  }

  const openSearch = () => {
    setSearchActive(true)
    requestAnimationFrame(() => {
      searchInputRef.current?.focus()
    })
  }

  const closeSearch = () => {
    setSearchActive(false)
    setSearchQuery('')
  }

  return (
    <div className={`screen-frame theme-${theme.id} circle-screen-frame`} style={{...themeStyles, ...frameStyles}}>
      <div
        ref={containerRef}
        className="app-container circle-app-container"
        style={{ height: '100%', overflowY: 'auto' }}
      >
        <div className="ambient-bg ambient-bg--circle2" />

        {/* Close button - sticky at top */}
        <div style={{ position: 'sticky', top: 0, zIndex: 200, pointerEvents: 'none', height: 0 }}>
          <button
            onClick={() => onSwitchView('feedC')}
            style={{
              position: 'relative',
              top: '14px',
              left: '14px',
              pointerEvents: 'auto',
              background: 'rgba(255,255,255,0.1)',
              backdropFilter: 'blur(12px)',
              WebkitBackdropFilter: 'blur(12px)',
              border: '1px solid rgba(255,255,255,0.12)',
              borderRadius: '50%',
              width: '36px',
              height: '36px',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              cursor: 'pointer',
              color: 'rgba(255,255,255,0.8)',
            }}
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round">
              <line x1="18" y1="6" x2="6" y2="18"/>
              <line x1="6" y1="6" x2="18" y2="18"/>
            </svg>
          </button>
        </div>

        {/* Header + Orbital — collapses when searching */}
        <div className={`circle-collapsible-shell ${searchActive ? 'circle-collapsible-shell--hidden' : ''}`}>
          <div className={`circle-collapsible ${searchActive ? 'circle-collapsible--hidden' : ''}`}>
            <header className="header-minimal circle-topbar">
              <button
                className="circle-quick-add"
                aria-label="Add friend"
                onClick={() => onSwitchView('scanQR')}
              >
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round">
                  <line x1="12" y1="6" x2="12" y2="18" />
                  <line x1="6" y1="12" x2="18" y2="12" />
                </svg>
              </button>
            </header>

            <div className="circle-orbital-section">
              <h2>Your Inner Circle</h2>
              <div className="circle-orbital circle-orbital-large">
                <div className="orbital-rings">
                  {ringData.map((ring, i) => (
                    <div
                      key={i}
                      className="orbital-ring"
                      style={{ inset: `${160 - ring.radius}px` }}
                    />
                  ))}
                </div>
                <div className="orbital-center">
                  <img src="https://images.unsplash.com/photo-1603415526960-f7e0328c63b1?w=200&h=200&fit=crop&crop=face" alt="You" style={{ width: 48, height: 48, borderRadius: '50%', objectFit: 'cover' }} />
                </div>
                {ringData.map((ring, ringIndex) =>
                  ring.friends.map((friend, i) => {
                    const offset = ringIndex * 15
                    const angle = (i * (360 / ring.count) + offset - 90) * (Math.PI / 180)
                    const x = Math.cos(angle) * ring.radius
                    const y = Math.sin(angle) * ring.radius
                    const globalIdx = orbitRings.slice(0, ringIndex).reduce((s, r) => s + r.count, 0) + i
                    return (
                      <div
                        key={friend.id}
                        className="orbital-friend"
                        data-ring={ringIndex}
                        style={{
                          '--x': `${x}px`,
                          '--y': `${y}px`,
                          '--friend-color': friend.color,
                          animationDelay: `${globalIdx * 0.04}s`,
                        }}
                      >
                        {friend.avatar ? (
                          <img
                            src={friend.avatar}
                            alt={friend.name}
                            className="orbital-friend-img"
                            style={{ width: ring.avatarSize, height: ring.avatarSize }}
                          />
                        ) : (
                          <RingBrandedAvatar peerId={friend.peerId} size={ring.avatarSize} />
                        )}
                        {friend.status === 'online' && ringIndex < 2 && (
                          <span
                            className="orbital-online-dot"
                            style={ringIndex > 0 ? { width: 7, height: 7 } : undefined}
                          />
                        )}
                      </div>
                    )
                  })
                )}
                {(() => {
                  const shown = orbitRings.reduce((s, r) => s + r.count, 0)
                  const remaining = manyFriends.length - shown
                  if (remaining <= 0) return null
                  const angle = (orbitRings[orbitRings.length - 1].count * (360 / orbitRings[orbitRings.length - 1].count) + 15 - 90) * (Math.PI / 180)
                  const x = Math.cos(angle) * (orbitRings[orbitRings.length - 1].radius)
                  const y = Math.sin(angle) * (orbitRings[orbitRings.length - 1].radius)
                  return (
                    <div
                      className="orbital-overflow"
                      style={{
                        '--x': `${x}px`,
                        '--y': `${y}px`,
                        '--badge-size': '28px',
                        animationDelay: '1s',
                      }}
                    >
                      +{remaining}
                    </div>
                  )
                })()}
              </div>
              <p className="circle-count">Close Friends</p>
            </div>
          </div>
        </div>

        <main className={`circle-feed circle-feed--search-dock ${searchActive ? 'circle-feed--search-active' : ''}`}>
          {/* Friend List — always visible, filters when searching */}
          <div className="circle-friends-list">
            <div className="circle-list-header">
              <h3>Friends</h3>
              {!searchActive && (
                <div style={{ display: 'flex', gap: '8px' }}>
                  <button className="circle-add-btn" onClick={() => onSwitchView('qrCode')}>
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                      <rect x="3" y="3" width="7" height="7" rx="1"/>
                      <rect x="14" y="3" width="7" height="7" rx="1"/>
                      <rect x="3" y="14" width="7" height="7" rx="1"/>
                      <rect x="14" y="14" width="3" height="3"/>
                      <line x1="21" y1="14" x2="21" y2="17.5"/>
                      <line x1="17" y1="21" x2="21" y2="21"/>
                    </svg>
                    <span>My QR</span>
                  </button>
                  <button className="circle-add-btn" onClick={() => onSwitchView('scanQR')}>
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                      <path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"/>
                      <circle cx="12" cy="13" r="4"/>
                    </svg>
                    <span>Scan</span>
                  </button>
                </div>
              )}
            </div>

            {/* Filter toggle: All / Intros / Archived */}
            {!searchActive && (
              <div className="friends-filter-toggle">
                <button
                  className={`friends-filter-btn${listFilter === 'all' ? ' friends-filter-btn--active' : ''}`}
                  onClick={() => setListFilter('all')}
                >
                  All
                  <span className="friends-filter-count">{activeFriends.length}</span>
                </button>
                <button
                  className={`friends-filter-btn${listFilter === 'intros' ? ' friends-filter-btn--active friends-filter-btn--intros' : ''}${pendingIntrosCount > 0 ? ' friends-filter-btn--has-intros' : ''}`}
                  onClick={() => setListFilter('intros')}
                >
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ marginRight: '3px', verticalAlign: '-2px' }}>
                    <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" />
                    <circle cx="9" cy="7" r="4" />
                    <path d="M23 21v-2a4 4 0 0 0-3-3.87" />
                    <path d="M16 3.13a4 4 0 0 1 0 7.75" />
                  </svg>
                  Intros
                  {pendingIntrosCount > 0 && (
                    <span className="friends-filter-count friends-filter-count--intros">{pendingIntrosCount}</span>
                  )}
                </button>
                <button
                  className={`friends-filter-btn${listFilter === 'archived' ? ' friends-filter-btn--active' : ''}`}
                  onClick={() => setListFilter('archived')}
                >
                  Archived
                  {archivedCount > 0 && (
                    <span className="friends-filter-count">{archivedCount}</span>
                  )}
                </button>
              </div>
            )}

            {/* Incoming introductions banner (User-B / Lina's view) */}
            {!searchActive && listFilter === 'all' && pendingIntrosCount > 0 && (
              <button
                className="incoming-intros-banner"
                onClick={() => setListFilter('intros')}
              >
                <div className="incoming-intros-icon">
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" />
                    <circle cx="9" cy="7" r="4" />
                    <path d="M23 21v-2a4 4 0 0 0-3-3.87" />
                    <path d="M16 3.13a4 4 0 0 1 0 7.75" />
                  </svg>
                </div>
                <div className="incoming-intros-content">
                  <span className="incoming-intros-title">{pendingIntrosCount} introduction{pendingIntrosCount !== 1 ? 's' : ''} from {mockIntroGroups.map(g => g.sender.name).join(' & ')}</span>
                  <span className="incoming-intros-desc">Review and accept to start chatting</span>
                </div>
                <div className="incoming-intros-badge">New</div>
                <svg className="incoming-intros-chevron" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <polyline points="9 18 15 12 9 6"/>
                </svg>
              </button>
            )}

            {/* No results */}
            {searchActive && query && displayedFriends.length === 0 && (
              <div className="search-overlay-empty">
                <span className="search-overlay-empty-icon">
                  <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round">
                    <circle cx="11" cy="11" r="8"/>
                    <line x1="21" y1="21" x2="16.65" y2="16.65"/>
                  </svg>
                </span>
                <p>No friends matching &ldquo;{searchQuery}&rdquo;</p>
              </div>
            )}

            {/* Archived empty state */}
            {listFilter === 'archived' && displayedFriends.length === 0 && !query && (
              <div className="archived-empty">
                <div className="archived-empty-icon">
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                    <polyline points="21 8 21 21 3 21 3 8"/>
                    <rect x="1" y="3" width="22" height="5" rx="1"/>
                    <line x1="10" y1="12" x2="14" y2="12"/>
                  </svg>
                </div>
                <p>No archived friends yet.<br/>Swipe left on a friend to archive them.</p>
              </div>
            )}

            {/* Intros tab content */}
            {listFilter === 'intros' && (
              <>
                {allIntroPeople.length > 0 ? (
                  <div className="intros-tab-content">
                    {/* Intro context — shown once at the top */}
                    <p className="intros-tab-context">
                      These are people your friends know well. Once you both accept, you can start chatting.
                    </p>

                    {mockIntroGroups.map((group, gi) => (
                      <div key={gi} className="intros-group">
                        <div className="intros-group-header">
                          <div className="intros-group-sender-avatar">
                            {group.sender.avatar ? (
                              <img src={group.sender.avatar} alt={group.sender.name} />
                            ) : (
                              <div className="intros-group-sender-initial" style={{ background: group.sender.color }}>
                                {group.sender.name[0]}
                              </div>
                            )}
                          </div>
                          <span className="intros-group-sender-name">From {group.sender.name}</span>
                          <span className="intros-group-count">{group.people.length} {group.people.length === 1 ? 'person' : 'people'}</span>
                        </div>

                        <div className="intros-group-list">
                          {group.people.map(person => {
                            const status = introStatuses[person.id] || 'pending'
                            return (
                              <div key={person.id} className={`intro-recv-row${status !== 'pending' ? ` intro-recv-row--${status}` : ''}`}>
                                <div className="intro-recv-avatar">
                                  {person.avatar ? (
                                    <img src={person.avatar} alt={person.name} />
                                  ) : (
                                    <RingBrandedAvatar peerId={person.peerId} size={48} />
                                  )}
                                  {person.status === 'online' && <span className="intro-recv-online" />}
                                </div>
                                <div className="intro-recv-info">
                                  <span className="intro-recv-name">{person.name}</span>
                                  <span className="intro-recv-via">Introduced by {group.sender.name}</span>
                                </div>
                                {status === 'pending' ? (
                                  <div className="intro-recv-actions">
                                    <button className="intro-recv-btn intro-recv-btn--accept" onClick={() => handleAcceptIntro(person.id)}>
                                      Accept
                                    </button>
                                  </div>
                                ) : status === 'accepted' ? (
                                  <div className="intro-recv-status intro-recv-status--accepted">
                                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                                      <polyline points="20 6 9 17 4 12"/>
                                    </svg>
                                    Accepted
                                  </div>
                                ) : (
                                  <div className="intro-recv-status intro-recv-status--passed">
                                    Passed
                                  </div>
                                )}
                              </div>
                            )
                          })}
                        </div>
                      </div>
                    ))}
                  </div>
                ) : (
                  <div className="intros-empty">
                    <div className="intros-empty-icon">
                      <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                        <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" />
                        <circle cx="9" cy="7" r="4" />
                        <path d="M23 21v-2a4 4 0 0 0-3-3.87" />
                        <path d="M16 3.13a4 4 0 0 1 0 7.75" />
                      </svg>
                    </div>
                    <p>No introductions yet.<br/>When friends introduce people to you, they'll appear here.</p>
                  </div>
                )}
              </>
            )}

            {/* Friend list — only when not on intros tab */}
            {listFilter !== 'intros' && displayedFriends.map((friend, index) => {
              const isInnerCircle = manyFriends.indexOf(friend) < INNER_CIRCLE_COUNT
              const isCurrentlyArchived = listFilter === 'archived'
              const isCurrentlyBlocked = blockedIds.has(friend.id)
              return (
                <SwipeableFriendRow
                  key={friend.id}
                  friend={friend}
                  isArchived={isCurrentlyArchived}
                  isBlocked={isCurrentlyBlocked}
                  onArchive={handleArchive}
                  onUnarchive={handleUnarchive}
                  onBlock={onBlockFriend}
                  onUnblock={onUnblockFriend}
                  isArchiving={archivingId === friend.id}
                >
                  <button
                    className="circle-friend-row"
                    onClick={() => onSwitchView('conversation')}
                    style={{
                      '--friend-color': friend.color,
                      animationDelay: `${index * 0.02}s`
                    }}
                  >
                    <div className="circle-friend-avatar">
                      {friend.avatar ? (
                        <img src={friend.avatar} alt={friend.name} className="circle-friend-img" />
                      ) : (
                        <RingBrandedAvatar peerId={friend.peerId} size={48} />
                      )}
                      {friend.status === 'online' && <span className="circle-online-dot" />}
                    </div>
                    <div className="circle-friend-info">
                      <span className="circle-friend-name">
                        {friend.name}
                        {searchActive && isInnerCircle && <span className="search-inner-badge">Inner Circle</span>}
                      </span>
                      <span className="circle-friend-username">@{friend.username}</span>
                      <span className="circle-friend-activity">{friend.lastActivity}</span>
                    </div>
                    <div className="circle-friend-meta">
                      {friend.unreadCount > 0 && !isCurrentlyArchived ? (
                        <>
                          <span className="friend-unread-badge">{friend.unreadCount}</span>
                          <span className="circle-friend-time">{friend.lastSeen}</span>
                        </>
                      ) : (
                        <>
                          <span className="circle-friend-time">{friend.lastSeen}</span>
                          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                            <polyline points="9 18 15 12 9 6"/>
                          </svg>
                        </>
                      )}
                    </div>
                  </button>
                </SwipeableFriendRow>
              )
            })}
          </div>

          {/* QR actions — hidden during search and intros tab */}
          {!searchActive && listFilter !== 'intros' && (
            <div style={{ display: 'flex', gap: '10px' }}>
              <div className="circle-add-card" style={{ flex: 1 }} onClick={() => onSwitchView('qrCode')}>
                <div className="circle-add-icon">
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                    <rect x="3" y="3" width="7" height="7" rx="1"/>
                    <rect x="14" y="3" width="7" height="7" rx="1"/>
                    <rect x="3" y="14" width="7" height="7" rx="1"/>
                    <rect x="14" y="14" width="3" height="3"/>
                    <line x1="21" y1="14" x2="21" y2="17.5"/>
                    <line x1="17" y1="21" x2="21" y2="21"/>
                  </svg>
                </div>
                <div className="circle-add-text">
                  <span className="circle-add-title">My QR Code</span>
                  <span className="circle-add-subtitle">Share to add friends</span>
                </div>
              </div>
              <div className="circle-add-card" style={{ flex: 1 }} onClick={() => onSwitchView('scanQR')}>
                <div className="circle-add-icon">
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"/>
                    <circle cx="12" cy="13" r="4"/>
                  </svg>
                </div>
                <div className="circle-add-text">
                  <span className="circle-add-title">Scan QR</span>
                  <span className="circle-add-subtitle">Add a friend instantly</span>
                </div>
              </div>
            </div>
          )}
        </main>
      </div>

      {/* Bottom bar: search + keyboard (docked) */}
      <div className={`search-bottom-dock ${searchActive ? 'search-bottom-dock--active' : ''}`}>
        <div className="search-bottom-bar">
          <div className="search-overlay-input-wrap">
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" style={{ opacity: 0.4, flexShrink: 0 }}>
              <circle cx="11" cy="11" r="8"/>
              <line x1="21" y1="21" x2="16.65" y2="16.65"/>
            </svg>
            <input
              ref={searchInputRef}
              type="text"
              className="search-overlay-input"
              placeholder="Search friends..."
              value={searchQuery}
              onChange={e => setSearchQuery(e.target.value)}
            />
            {searchQuery && (
              <button className="search-overlay-clear" onClick={() => { setSearchQuery(''); searchInputRef.current?.focus() }}>
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                  <line x1="18" y1="6" x2="6" y2="18"/>
                  <line x1="6" y1="6" x2="18" y2="18"/>
                </svg>
              </button>
            )}
          </div>
          <button className="search-overlay-close" onClick={closeSearch}>
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round">
              <line x1="18" y1="6" x2="6" y2="18" />
              <line x1="6" y1="6" x2="18" y2="18" />
            </svg>
          </button>
        </div>
        <SimKeyboard onKey={handleKey} />
      </div>

      {/* Floating search trigger — hidden when search is active */}
      <div className={`circle-search-trigger ${!searchActive && isNavVisible ? 'circle-search-trigger--visible' : ''}`}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
          <button
            onClick={openSearch}
            style={{
              flex: 1,
              display: 'flex',
              alignItems: 'center',
              gap: '10px',
              padding: '10px 16px',
              background: 'rgba(30,30,35,0.85)',
              backdropFilter: 'blur(20px)',
              WebkitBackdropFilter: 'blur(20px)',
              border: '1px solid rgba(255,255,255,0.1)',
              borderRadius: '24px',
              color: 'rgba(255,255,255,0.35)',
              fontSize: '14px',
              cursor: 'pointer',
              textAlign: 'left',
              minWidth: 0,
            }}
          >
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" style={{ opacity: 0.5, flexShrink: 0 }}>
              <circle cx="11" cy="11" r="8"/>
              <line x1="21" y1="21" x2="16.65" y2="16.65"/>
            </svg>
            Search friends...
          </button>

          <button
            aria-label="Close circle"
            onClick={() => onSwitchView('feedC')}
            style={{
              width: '38px',
              height: '38px',
              borderRadius: '50%',
              border: '1px solid rgba(255,255,255,0.14)',
              background: 'rgba(30,30,35,0.9)',
              backdropFilter: 'blur(20px)',
              WebkitBackdropFilter: 'blur(20px)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              color: 'rgba(255,255,255,0.72)',
              cursor: 'pointer',
              flexShrink: 0,
            }}
          >
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round">
              <line x1="18" y1="6" x2="6" y2="18" />
              <line x1="6" y1="6" x2="18" y2="18" />
            </svg>
          </button>
        </div>
      </div>
    </div>
  )
}

export default CircleScreen2
