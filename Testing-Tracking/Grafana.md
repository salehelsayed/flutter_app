 From your Mac, run:

  ssh -i se.pem -L 3000:localhost:3000 ubuntu@13.60.15.36

  Then open in your browser:
  - http://localhost:3000 — Grafana home (login: admin / admin)
  - http://localhost:3000/d/ec2-host-metrics — EC2 Host Metricsdashboard
  - http://localhost:3000/d/relay-server-overview — Relay Server Overview dashboard
  - http://localhost:3000/d/business-overview --> DAU/WAU/MAU numbers will start populating as users connect to the relay. The daily counters reset at midnight UTC automatically.


  ┌───────────────────────┬───────────────────────────────────────────────┐
  │       Dashboard       │                      URL                      │
  ├───────────────────────┼───────────────────────────────────────────────┤
  │ Business Overview     │ http://localhost:3000/d/business-overview     │
  ├───────────────────────┼───────────────────────────────────────────────┤
  │ EC2 Host Metrics      │ http://localhost:3000/d/ec2-host-metrics      │
  ├───────────────────────┼───────────────────────────────────────────────┤
  │ Redis                 │ http://localhost:3000/d/redis-overview        │
  ├───────────────────────┼───────────────────────────────────────────────┤
  │ Relay Server Overview │ http://localhost:3000/d/relay-server-overview │
  └───────────────────────┴───────────────────────────────────────────────┘





# Busniess Overview 
The dashboard is working and showing real data. Here's what
  each number means:

  Estimated DAU: 2 — 2 unique peers have connected to your
  relay server today. The red color is just because the
  threshold is set to turn green at 20+ users — it's not an
  error, just reflects early stage.

  Estimated WAU: 2 — Same 2 unique peers this week. Since the
  server was just restarted with v1.2.0, it only knows about
  peers that connected since the restart. This will accumulate
  over the week.

  Estimated MAU: 2 — Same logic, monthly window.

  Total Users: 0 — This reads relay_profile_count, which counts
   profile files in the in-memory index. The profile index is
  rebuilt from disk on startup, but looking at the code,
  NewProfileStore creates an empty map — it doesn't scan
  existing files on disk. So this shows 0 until someone uploads
   a profile after the restart. The 13 profile files are still
  on disk, they just aren't loaded into the index.

  Msgs / Active User: 0.0 — No messages have been sent since
  the restart (daily counter resets). Once users send messages
  today, this will show messages-per-user engagement.

  Platform Split: android 0, ios 0 — Push tokens are stored in
  memory and were lost on restart. Users need to re-register
  their push tokens (happens automatically when the app
  reconnects).


  ───────────────────────────────────────────────────────────────
❯ the disk usage is 54.1% . I want to know which directory
  from the media storage (messages/group
  chat/media/video/audio) that is not yet deleted so far.
  because according to our protocol, once the user receives
  the message/media it should be deleted from the relay. ssh
  to the relay and find out which directory that is still
  taking disk usage that is related to our app and help me
  findout why are they not yet deleted


why do I see (android=0) and (iphone=0) ?

are those numbers measuring the "Total Users" or what ?

what about the other grapphs. do we need to update anything after installing redis?

  How can we reset those business counters?

  What is "Activity Trend" mean?



  ==========

  # Redis Overview
   The Redis dashboard shows:
  - Redis Up — health status
  - Uptime — how long Redis has been running
  - Connected Clients — relay-server connections to Redis
  - Key Count — total keys stored (inbox, push tokens, rendezvous)
  - Memory Used — current vs 100MB limit (thresholds at 50MB yellow, 90MB red)
  - AOF Size — persistence file size
  - Commands/sec — Redis throughput over time
  - Memory Over Time — usage trend with limit line
  - Keys Over Time — key count trend
  - Network I/O — Redis network traffic

  Open http://localhost:3000/d/redis-overview in your browser to see it.


 Redis holds 4 things for your relay server:

  ┌────────────────┬────────────────┬──────────────────────┐
  │      Data      │   Redis Key    │ What happens without │
  │                │                │         Redis        │
  ├────────────────┼────────────────┼──────────────────────┤
  │                │                │ Users must re-open   │
  │ Push tokens    │ relay:push:*   │ the app to get       │
  │                │                │ notifications again  │
  ├────────────────┼────────────────┼──────────────────────┤
  │ Inbox messages │ relay:inbox:*  │ Offline users lose   │
  │                │                │ unread messages      │
  ├────────────────┼────────────────┼──────────────────────┤
  │ Group messages │ relay:ginbox:* │ Group history lost   │
  ├────────────────┼────────────────┼──────────────────────┤
  │ Rendezvous     │                │ Peers can't find     │
  │ registrations  │ relay:rz:*     │ each other until     │
  │                │                │ they re-register     │
  └────────────────┴────────────────┴──────────────────────┘

  