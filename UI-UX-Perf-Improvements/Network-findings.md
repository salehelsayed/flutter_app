Root Cause

  The freeze is not coming from the loader widgets or from Feed navigation. It is coming from startup P2P warm-up, specifically the local mDNS/Bonjour startup path, overlapping Feed
  hydration.

  Relevant code:

  - P2PServiceImpl.startNode() / warmBackground():79
  - LocalP2PService.start():27
  - BonsoirDiscoveryService.startAdvertising():24
  - loadFeed():109
  - dbLoadActiveGroups():241

  Evidence

  I could not use true --profile on this iPhone simulator, so I used debug hot-restart traces plus simulator system logs.

  What the logs show:

  - Route push is fast. In the hot-restart trace from 2026-03-07 15:32, route_pushed happened at +341ms.
  - Feed itself is not inherently slow. In another run at 15:32:05, FEED_LOAD_SUCCESS landed about 315ms after FEED_LOAD_START.
  - The bad runs line up with warmBackground():
      - P2P_SERVICE_WARM_BACKGROUND_BEGIN at 14:32:16.815Z
      - LOCAL_WS_SERVER_STARTED at 14:32:16.820Z
      - LOCAL_MDNS_ADVERTISE_START at 14:32:22.879Z
      - P2P_SERVICE_INBOX_RETRIEVE_SUCCESS at 14:32:22.881Z
      - FEED_LOAD_SUCCESS at 14:32:22.942Z
  - I saw the same pattern with much worse delays too:
      - about 14.8s
      - about 43.6s
      - about 65.8s
  - The groups query is not the real problem. dbLoadActiveGroups():241 is a single simple SELECT. In one logged run it finished in about 13ms, and Feed still stayed loading for 43s.
  - warmTaskTimeout = Duration(seconds: 5):40 is not actually protecting this path. The stall exceeded 5s repeatedly, which means the timeout is not resolving on schedule during the
    hang.

  What This Means

  The spinner looks frozen because the app is getting stuck during startup warm-up. Any animated spinner would have the same problem in that window. The issue is the startup work, not
  the indicator widget.

  Most likely culprit:

  - BonsoirBroadcast.ready/start inside BonsoirDiscoveryService.startAdvertising():25

  Secondary overlapping suspect:

  - bridge inbox retrieval via callP2PInboxRetrieve():435 and GoBridgeClient.send():304

  Best Next Fix

  First fix I would make:

  - stop awaiting warmBackground() from startup
  - move local mDNS startup out of the Feed critical path
  - start local discovery after Feed is hydrated, or delay it a few seconds
  - add timing logs around _broadcast.ready, _broadcast.start, _discovery.ready, _discovery.start

  If you want, I can implement that next.