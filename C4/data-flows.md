## Data Flow Sequences

### Generate Identity Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    GENERATE IDENTITY - DATA FLOW                             │
└─────────────────────────────────────────────────────────────────────────────┘

  User                Flutter UI           Use Case          GoBridgeClient       Go Native Lib        Database
   │                      │                   │                   │                    │                   │
   │  Tap "I'm new"       │                   │                   │                    │                   │
   │─────────────────────>│                   │                   │                    │                   │
   │                      │                   │                   │                    │                   │
   │                      │  generateNew      │                   │                    │                   │
   │                      │  Identity()       │                   │                    │                   │
   │                      │──────────────────>│                   │                    │                   │
   │                      │                   │                   │                    │                   │
   │                      │                   │  callGenerate()   │                    │                   │
   │                      │                   │──────────────────>│                    │                   │
   │                      │                   │                   │                    │                   │
   │                      │                   │                   │  MethodChannel     │                   │
   │                      │                   │                   │  generateIdentity  │                   │
   │                      │                   │                   │───────────────────>│                   │
   │                      │                   │                   │                    │                   │
   │                      │                   │                   │                    │  bip39.generate() │
   │                      │                   │                   │                    │  ed25519.keypair()│
   │                      │                   │                   │                    │  mlkem768.keygen()│
   │                      │                   │                   │                    │  peerId.derive()  │
   │                      │                   │                   │                    │                   │
   │                      │                   │                   │  JSON response     │                   │
   │                      │                   │                   │  {ok, identity}    │                   │
   │                      │                   │                   │<───────────────────│                   │
   │                      │                   │                   │                    │                   │
   │                      │                   │  Map<identity>    │                    │                   │
   │                      │                   │<──────────────────│                    │                   │
   │                      │                   │                   │                    │                   │
   │                      │                   │  repo.save        │                    │                   │
   │                      │                   │  Identity()       │                    │                   │
   │                      │                   │─────────────────────────────────────────────────────────────>│
   │                      │                   │                   │                    │                   │
   │                      │                   │                   │                    │    INSERT OR      │
   │                      │                   │                   │                    │    REPLACE        │
   │                      │                   │                   │                    │    id=1           │
   │                      │                   │                   │                    │                   │
   │                      │  Result.success   │                   │                    │                   │
   │                      │<──────────────────│                   │                    │                   │
   │                      │                   │                   │                    │                   │
   │  Navigate to Home    │                   │                   │                    │                   │
   │<─────────────────────│                   │                   │                    │                   │
   │                      │                   │                   │                    │                   │
```

### QR Code Generation Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    QR CODE GENERATION - DATA FLOW                            │
└─────────────────────────────────────────────────────────────────────────────┘

  User                FTE Wired            Use Case          GoBridgeClient       Go Native Lib        Database
   │                      │                   │                   │                    │                   │
   │  Screen loads        │                   │                   │                    │                   │
   │─────────────────────>│                   │                   │                    │                   │
   │                      │                   │                   │                    │                   │
   │                      │  loadIdentity()   │                   │                    │                   │
   │                      │─────────────────────────────────────────────────────────────────────────────────>│
   │                      │                   │                   │                    │                   │
   │                      │  IdentityModel    │                   │                    │                   │
   │                      │<─────────────────────────────────────────────────────────────────────────────────│
   │                      │                   │                   │                    │                   │
   │                      │  buildQRPayload() │                   │                    │                   │
   │                      │──────────────────>│                   │                    │                   │
   │                      │                   │                   │                    │                   │
   │                      │                   │  Build unsigned   │                    │                   │
   │                      │                   │  payload JSON     │                    │                   │
   │                      │                   │  {ns,pk,rv,ts,un} │                    │                   │
   │                      │                   │                   │                    │                   │
   │                      │                   │  callSignPayload()│                    │                   │
   │                      │                   │──────────────────>│                    │                   │
   │                      │                   │                   │                    │                   │
   │                      │                   │                   │  MethodChannel     │                   │
   │                      │                   │                   │  signPayload       │                   │
   │                      │                   │                   │───────────────────>│                   │
   │                      │                   │                   │                    │                   │
   │                      │                   │                   │                    │  ed25519.sign()   │
   │                      │                   │                   │                    │                   │
   │                      │                   │                   │  {ok, signature}   │                   │
   │                      │                   │                   │<───────────────────│                   │
   │                      │                   │                   │                    │                   │
   │                      │                   │  Add sig to JSON  │                    │                   │
   │                      │                   │  Return final     │                    │                   │
   │                      │                   │                   │                    │                   │
   │                      │  QR JSON string   │                   │                    │                   │
   │                      │<──────────────────│                   │                    │                   │
   │                      │                   │                   │                    │                   │
   │  Display QR code     │                   │                   │                    │                   │
   │<─────────────────────│                   │                   │                    │                   │
   │                      │                   │                   │                    │                   │
```

### QR Scan → Add Contact → Send Request Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│              QR SCAN + CONTACT REQUEST - DATA FLOW                           │
└─────────────────────────────────────────────────────────────────────────────┘

  User          Scanner Wired     parseQR UC      addContact UC    sendRequest UC     P2PService
   │                 │                │                │                 │                 │
   │  Scan QR code   │                │                │                 │                 │
   │────────────────>│                │                │                 │                 │
   │                 │                │                │                 │                 │
   │                 │  parseQR       │                │                 │                 │
   │                 │  Payload()     │                │                 │                 │
   │                 │───────────────>│                │                 │                 │
   │                 │                │                │                 │                 │
   │                 │                │  Validate JSON │                 │                 │
   │                 │                │  Check fields  │                 │                 │
   │                 │                │  Check expiry  │                 │                 │
   │                 │                │  Verify sig    │                 │                 │
   │                 │                │  Check self    │                 │                 │
   │                 │                │                │                 │                 │
   │                 │  (success,     │                │                 │                 │
   │                 │   ContactModel)│                │                 │                 │
   │                 │<───────────────│                │                 │                 │
   │                 │                │                │                 │                 │
   │                 │  addContact()  │                │                 │                 │
   │                 │───────────────────────────────>│                 │                 │
   │                 │                │                │                 │                 │
   │                 │  success       │                │                 │                 │
   │                 │<───────────────────────────────│                 │                 │
   │                 │                │                │                 │                 │
   │  Show success   │                │                │                 │                 │
   │<────────────────│                │                │                 │                 │
   │                 │                │                │                 │                 │
   │                 │  sendContactRequest() (background)               │                 │
   │                 │─────────────────────────────────────────────────>│                 │
   │                 │                │                │                 │                 │
   │                 │                │                │                 │  Build payload  │
   │                 │                │                │                 │  Sign via Go    │
   │                 │                │                │                 │  Discover peer  │
   │                 │                │                │                 │───────────────>│
   │                 │                │                │                 │  (3x retry)    │
   │                 │                │                │                 │                 │
   │                 │                │                │                 │  Dial peer      │
   │                 │                │                │                 │───────────────>│
   │                 │                │                │                 │                 │
   │                 │                │                │                 │  Send message   │
   │                 │                │                │                 │───────────────>│
   │                 │                │                │                 │                 │
```

### Incoming Contact Request Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│              INCOMING CONTACT REQUEST - DATA FLOW                            │
└─────────────────────────────────────────────────────────────────────────────┘

  P2PService      CR Listener       handleMsg UC     CR Repository      FTE Wired        User
   │                   │                │                 │                 │                │
   │  messageStream    │                │                 │                 │                │
   │  (ChatMessage)    │                │                 │                 │                │
   │──────────────────>│                │                 │                 │                │
   │                   │                │                 │                 │                │
   │                   │  handleIncoming│                 │                 │                │
   │                   │  Message()     │                 │                 │                │
   │                   │───────────────>│                 │                 │                │
   │                   │                │                 │                 │                │
   │                   │                │  Parse JSON     │                 │                │
   │                   │                │  Check type =   │                 │                │
   │                   │                │  contact_request│                 │                │
   │                   │                │  Validate fields│                 │                │
   │                   │                │  Verify sig     │                 │                │
   │                   │                │  Check not self │                 │                │
   │                   │                │  Check not dup  │                 │                │
   │                   │                │                 │                 │                │
   │                   │                │  Store request  │                 │                │
   │                   │                │────────────────>│                 │                │
   │                   │                │                 │                 │                │
   │                   │  (contactReq,  │                 │                 │                │
   │                   │   Model)       │                 │                 │                │
   │                   │<───────────────│                 │                 │                │
   │                   │                │                 │                 │                │
   │                   │  requestStream │                 │                 │                │
   │                   │  .add(model)   │                 │                 │                │
   │                   │───────────────────────────────────────────────────>│                │
   │                   │                │                 │                 │                │
   │                   │                │                 │                 │  Show dialog   │
   │                   │                │                 │                 │  (Accept/      │
   │                   │                │                 │                 │   Decline)     │
   │                   │                │                 │                 │───────────────>│
   │                   │                │                 │                 │                │
   │                   │                │                 │                 │  User taps     │
   │                   │                │                 │                 │  Accept        │
   │                   │                │                 │                 │<───────────────│
   │                   │                │                 │                 │                │
   │                   │                │                 │  acceptCR()     │                │
   │                   │                │                 │<────────────────│                │
   │                   │                │                 │                 │                │
   │                   │                │                 │  → Contact      │                │
   │                   │                │                 │  → status=      │                │
   │                   │                │                 │    accepted     │                │
   │                   │                │                 │                 │                │
```

### Send Chat Message Flow (with E2E Encryption + Offline Inbox)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│              SEND CHAT MESSAGE - DATA FLOW (v2 encrypted / v1 fallback)      │
└─────────────────────────────────────────────────────────────────────────────┘

  User          Conv Wired      sendChatMsg UC   GoBridge      MessageRepo     P2PService
   │                 │                │              │              │                │
   │  Type + Send    │                │              │              │                │
   │────────────────>│                │              │              │                │
   │                 │                │              │              │                │
   │  Optimistic UI  │  Build         │              │              │                │
   │  (status:       │  MessagePayload│              │              │                │
   │   sending)      │  {id,text,     │              │              │                │
   │<────────────────│  sender,ts}    │              │              │                │
   │                 │                │              │              │                │
   │                 │  sendChat      │              │              │                │
   │                 │  Message()     │              │              │                │
   │                 │───────────────>│              │              │                │
   │                 │                │              │              │                │
   │                 │                │  saveMessage()│              │                │
   │                 │                │  (status:sent)│              │                │
   │                 │                │──────────────────────────────>│                │
   │                 │                │              │              │                │
   │                 │                │  [if contact has ML-KEM key]  │                │
   │                 │                │  callEncrypt │              │                │
   │                 │                │  Message()   │              │                │
   │                 │                │─────────────>│              │                │
   │                 │                │              │  ML-KEM-768  │                │
   │                 │                │              │  encapsulate │                │
   │                 │                │              │  + AES-256-  │                │
   │                 │                │              │  GCM encrypt │                │
   │                 │                │  {kem,cipher │              │                │
   │                 │                │   text,nonce}│              │                │
   │                 │                │<─────────────│              │                │
   │                 │                │              │              │                │
   │                 │                │  Build v2 envelope            │                │
   │                 │                │  (encrypted)  │              │                │
   │                 │                │              │              │                │
   │                 │                │  [else: no ML-KEM key]       │                │
   │                 │                │  Build v1 envelope            │                │
   │                 │                │  (plaintext)  │              │                │
   │                 │                │              │              │                │
   │                 │                │  discoverPeer()               │                │
   │                 │                │──────────────────────────────────────────────>│
   │                 │                │  (3x retry)  │              │                │
   │                 │                │              │              │                │
   │                 │                │  dialPeer()  │              │                │
   │                 │                │──────────────────────────────────────────────>│
   │                 │                │              │              │                │
   │                 │                │  sendMessage()│              │                │
   │                 │                │  (JSON envelope)             │                │
   │                 │                │──────────────────────────────────────────────>│
   │                 │                │              │              │                │
   │                 │                │  [if send succeeds]          │                │
   │                 │                │  updateStatus()              │                │
   │                 │                │  (delivered) │              │                │
   │                 │                │──────────────────────────────>│                │
   │                 │                │              │              │                │
   │                 │                │  [if send fails after 3x retry]               │
   │                 │                │  storeInInbox()              │                │
   │                 │                │──────────────────────────────────────────────>│
   │                 │                │              │              │                │
   │                 │                │  [if inbox store succeeds]   │                │
   │                 │                │  updateStatus()              │                │
   │                 │                │  (delivered) │              │                │
   │                 │                │──────────────────────────────>│                │
   │                 │                │              │              │                │
   │                 │  Result +      │              │              │                │
   │                 │  status update │              │              │                │
   │                 │<───────────────│              │              │                │
   │                 │                │              │              │                │
   │  Update tick    │                │              │              │                │
   │  (delivered)    │                │              │              │                │
   │<────────────────│                │              │              │                │
   │                 │                │              │              │                │
```

### Incoming Chat Message Flow (with E2E Decryption)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│              INCOMING CHAT MESSAGE - DATA FLOW (v2 decrypt / v1 parse)        │
└─────────────────────────────────────────────────────────────────────────────┘

  P2PService     Msg Router     Chat Listener    handleMsg UC    GoBridge     Conv Wired     User
   │                │                │                │              │            │           │
   │  messageStream │                │                │              │            │           │
   │  (ChatMessage) │                │                │              │            │           │
   │───────────────>│                │                │              │            │           │
   │                │                │                │              │            │           │
   │                │  _route():     │                │              │            │           │
   │                │  type=chat_msg │                │              │            │           │
   │                │  chatMessage   │                │              │            │           │
   │                │  Stream.add()  │                │              │            │           │
   │                │───────────────>│                │              │            │           │
   │                │                │                │              │            │           │
   │                │                │  Resolve own   │              │            │           │
   │                │                │  ML-KEM secret │              │            │           │
   │                │                │  key from repo │              │            │           │
   │                │                │                │              │            │           │
   │                │                │  handleIncoming│              │            │           │
   │                │                │  ChatMessage() │              │            │           │
   │                │                │───────────────>│              │            │           │
   │                │                │                │              │            │           │
   │                │                │                │  Detect v2?  │            │           │
   │                │                │                │  parseEncrypt│            │           │
   │                │                │                │  edEnvelope()│            │           │
   │                │                │                │              │            │           │
   │                │                │                │  [if v2 encrypted]        │           │
   │                │                │                │  callDecrypt              │           │
   │                │                │                │  Message()   │            │           │
   │                │                │                │─────────────>│            │           │
   │                │                │                │              │ ML-KEM-768 │           │
   │                │                │                │              │ decapsulate│           │
   │                │                │                │              │ + AES-256- │           │
   │                │                │                │              │ GCM decrypt│           │
   │                │                │                │  {plaintext} │            │           │
   │                │                │                │<─────────────│            │           │
   │                │                │                │              │            │           │
   │                │                │                │  fromDecrypt │            │           │
   │                │                │                │  edJson()    │            │           │
   │                │                │                │              │            │           │
   │                │                │                │  [else: v1 plaintext]     │           │
   │                │                │                │  fromJson()  │            │           │
   │                │                │                │              │            │           │
   │                │                │                │  Validate    │            │           │
   │                │                │                │  sender is   │            │           │
   │                │                │                │  contact     │            │           │
   │                │                │                │  Check dup   │            │           │
   │                │                │                │  Detect name │            │           │
   │                │                │                │  change      │            │           │
   │                │                │                │  Save message│            │           │
   │                │                │                │              │            │           │
   │                │                │  (chatMessage, │              │            │           │
   │                │                │   Model)       │              │            │           │
   │                │                │<───────────────│              │            │           │
   │                │                │                │              │            │           │
   │                │                │  incoming      │              │            │           │
   │                │                │  MessageStream │              │            │           │
   │                │                │  .add(msg)     │              │            │           │
   │                │                │──────────────────────────────────────────>│           │
   │                │                │                │              │            │           │
   │                │                │                │              │            │  New       │
   │                │                │                │              │            │  letter    │
   │                │                │                │              │            │  card      │
   │                │                │                │              │            │──────────>│
   │                │                │                │              │            │           │
```

### Avatar Upload Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    AVATAR UPLOAD - DATA FLOW                                 │
│              (No file written to disk — avatar stored as BLOB in DB)         │
└─────────────────────────────────────────────────────────────────────────────┘

  User                FTE Wired           ImagePicker          SQLCipher Database
   │                      │                   │                       │
   │  Tap camera button   │                   │                       │
   │─────────────────────>│                   │                       │
   │                      │                   │                       │
   │                      │  Show bottom      │                       │
   │                      │  sheet picker     │                       │
   │                      │                   │                       │
   │  Select "Gallery"    │                   │                       │
   │─────────────────────>│                   │                       │
   │                      │                   │                       │
   │                      │  pickImage()      │                       │
   │                      │──────────────────>│                       │
   │                      │                   │                       │
   │  Select photo        │                   │                       │
   │─────────────────────>│                   │                       │
   │                      │                   │                       │
   │                      │  XFile (temp)     │                       │
   │                      │<──────────────────│                       │
   │                      │                   │                       │
   │                      │  Read bytes       │                       │
   │                      │  (Uint8List)      │                       │
   │                      │                   │                       │
   │                      │  Update identity with avatarBlob          │
   │                      │  saveIdentity()                           │
   │                      │  (BLOB stored in encrypted DB)            │
   │                      │──────────────────────────────────────────>│
   │                      │                   │                       │
   │                      │  setState()       │                       │
   │                      │  Image.memory()   │                       │
   │                      │                   │                       │
   │  Display avatar      │                   │                       │
   │<─────────────────────│                   │                       │
   │                      │                   │                       │
```

### Orbit Navigation Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│              ORBIT NAVIGATION - DATA FLOW                                    │
└─────────────────────────────────────────────────────────────────────────────┘

  User          FeedWired       OrbitWired       loadOrbit UCs      MessageRepo     ContactRepo    GroupRepo
   │                │                │                │                │               │              │
   │  Tap "Orbit"   │                │                │                │               │              │
   │  in nav bar    │                │                │                │               │              │
   │───────────────>│                │                │                │               │              │
   │                │                │                │                │               │              │
   │                │  Navigator     │                │                │               │              │
   │                │  .push(        │                │                │               │              │
   │                │  OrbitWired)   │                │                │               │              │
   │                │───────────────>│                │                │               │              │
   │                │                │                │                │               │              │
   │                │                │  loadOrbit     │                │               │              │
   │                │                │  Data()        │                │               │              │
   │                │                │───────────────>│                │               │              │
   │                │                │                │                │               │              │
   │                │                │                │  getAllContacts()               │              │
   │                │                │                │───────────────────────────────>│              │
   │                │                │                │                │               │              │
   │                │                │                │  List<Contact> │               │              │
   │                │                │                │<───────────────────────────────│              │
   │                │                │                │                │               │              │
   │                │                │                │  For each contact:             │              │
   │                │                │                │  getMessageCount               │              │
   │                │                │                │  ForContact()  │               │              │
   │                │                │                │───────────────>│               │              │
   │                │                │                │                │               │              │
   │                │                │                │  Sort by count desc            │              │
   │                │                │                │  build OrbitFriends            │              │
   │                │                │                │                │               │              │
   │                │                │  List<OrbitFriend>              │               │              │
   │                │                │<───────────────│                │               │              │
   │                │                │                │                │               │              │
   │                │                │  loadOrbit     │                │               │              │
   │                │                │  Groups()      │                │               │              │
   │                │                │───────────────>│                │               │              │
   │                │                │                │                │               │              │
   │                │                │                │  getActiveGroups()             │              │
   │                │                │                │────────────────────────────────────────────>│
   │                │                │                │                │               │              │
   │                │                │                │  For each group:               │              │
   │                │                │                │  getLatestMessage()            │              │
   │                │                │                │  getUnreadCount()              │              │
   │                │                │                │───────────────>│               │              │
   │                │                │                │                │               │              │
   │                │                │                │  Sort by last  │               │              │
   │                │                │                │  activity desc │               │              │
   │                │                │                │  build OrbitGroups             │              │
   │                │                │                │                │               │              │
   │                │                │  List<OrbitGroup>               │               │              │
   │                │                │<───────────────│                │               │              │
   │                │                │                │                │               │              │
   │  Show orbital  │                │  Render:       │                │               │              │
   │  visualization │                │  Ring 1 (top 5)│                │               │              │
   │  + friend list │                │  Ring 2 (next 8)               │               │              │
   │  + group list  │                │  Friend list   │                │               │              │
   │<────────────────────────────────│  Group list    │                │               │              │
   │                │                │                │                │               │              │
   │                │                │                │                │               │              │
   │  Tap friend    │                │                │                │               │              │
   │───────────────────────────────>│                │                │               │              │
   │                │                │                │                │               │              │
   │                │                │  Navigator.push│                │               │              │
   │                │                │  (ConvWired)   │                │               │              │
   │                │                │                │                │               │              │
   │                │                │                │                │               │              │
   │  Tap group     │                │                │                │               │              │
   │───────────────────────────────>│                │                │               │              │
   │                │                │                │                │               │              │
   │                │                │  Navigator.push│                │               │              │
   │                │                │  (GroupConv    │                │               │              │
   │                │                │   Wired)       │                │               │              │
   │                │                │                │                │               │              │
   │                │                │                │                │               │              │
   │  Type search   │                │                │                │               │              │
   │  query         │                │                │                │               │              │
   │───────────────────────────────>│                │                │               │              │
   │                │                │                │                │               │              │
   │                │                │  Filter        │                │               │              │
   │                │                │  _orbitFriends │                │               │              │
   │                │                │  by username   │                │               │              │
   │                │                │  match         │                │               │              │
   │                │                │                │                │               │              │
   │  Filtered list │                │                │                │               │              │
   │<────────────────────────────────│                │                │               │              │
   │                │                │                │                │               │              │
   │                │                │                │                │               │              │
   │  Tap X button  │                │                │                │               │              │
   │───────────────────────────────>│                │                │               │              │
   │                │                │                │                │               │              │
   │                │                │  Navigator     │                │               │              │
   │                │                │  .pop()        │                │               │              │
   │                │  <─────────────│                │                │               │              │
   │                │                │                │                │               │              │
   │  Back to Feed  │                │                │                │               │              │
   │<───────────────│                │                │                │               │              │
   │                │                │                │                │               │              │
```

### Create Group with Members Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│              CREATE GROUP WITH MEMBERS - DATA FLOW                           │
└─────────────────────────────────────────────────────────────────────────────┘

  User         PickerWired    createGroupWith   createGroup UC   GoBridge      GroupRepo      P2PService
   │                │          Members UC            │              │              │              │
   │  Select        │                │               │              │              │              │
   │  contacts +    │                │               │              │              │              │
   │  tap Create    │                │               │              │              │              │
   │───────────────>│                │               │              │              │              │
   │                │                │               │              │              │              │
   │                │  createGroup   │               │              │              │              │
   │                │  WithMembers() │               │              │              │              │
   │                │───────────────>│               │              │              │              │
   │                │                │               │              │              │              │
   │                │                │  createGroup()│              │              │              │
   │                │                │──────────────>│              │              │              │
   │                │                │               │              │              │              │
   │                │                │               │  group:create│              │              │
   │                │                │               │─────────────>│              │              │
   │                │                │               │              │              │              │
   │                │                │               │  {groupId,   │              │              │
   │                │                │               │   topicName, │              │              │
   │                │                │               │   groupKey}  │              │              │
   │                │                │               │<─────────────│              │              │
   │                │                │               │              │              │              │
   │                │                │               │  saveGroup() │              │              │
   │                │                │               │  saveMember(admin)           │              │
   │                │                │               │  saveKey()   │              │              │
   │                │                │               │─────────────────────────────>│              │
   │                │                │               │              │              │              │
   │                │                │  GroupModel    │              │              │              │
   │                │                │<──────────────│              │              │              │
   │                │                │               │              │              │              │
   │                │                │  For each selected contact:  │              │              │
   │                │                │  addGroupMember()            │              │              │
   │                │                │  → saveMember(writer)        │              │              │
   │                │                │─────────────────────────────>│              │              │
   │                │                │               │              │              │              │
   │                │                │  group:updateConfig          │              │              │
   │                │                │  (full member list)          │              │              │
   │                │                │─────────────────────────────>│              │              │
   │                │                │               │              │              │              │
   │                │                │  group:publish │              │              │              │
   │                │                │  (__sys: members_added)      │              │              │
   │                │                │─────────────────────────────>│              │              │
   │                │                │               │              │              │              │
   │                │                │  sendGroupInvitesInParallel()│              │              │
   │                │                │  For each contact in parallel:              │              │
   │                │                │  ┌──────────────────────────────────────────────────────┐  │
   │                │                │  │ 1. Build GroupInvitePayload                          │  │
   │                │                │  │ 2. Encrypt with ML-KEM (callEncryptMessage)          │  │
   │                │                │  │ 3. Build v2 envelope                                 │  │
   │                │                │  │ 4. p2pService.sendMessage() or storeInInbox()        │  │
   │                │                │  └──────────────────────────────────────────────────────┘  │
   │                │                │──────────────────────────────────────────────────────────>│
   │                │                │               │              │              │              │
   │                │  Result        │               │              │              │              │
   │                │  (group,       │               │              │              │              │
   │                │   membersAdded,│               │              │              │              │
   │                │   invitesSent) │               │              │              │              │
   │                │<───────────────│               │              │              │              │
   │                │                │               │              │              │              │
   │  Navigate to   │                │               │              │              │              │
   │  GroupConv     │                │               │              │              │              │
   │<───────────────│                │               │              │              │              │
   │                │                │               │              │              │              │
```

### Incoming Group Invite Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│              INCOMING GROUP INVITE - DATA FLOW (via P2P)                     │
└─────────────────────────────────────────────────────────────────────────────┘

  P2PService   InviteListener   handleInvite UC   GoBridge      GroupRepo      ContactRepo
   │                │                │               │              │              │
   │  groupInvite   │                │               │              │              │
   │  Stream        │                │               │              │              │
   │  (ChatMessage) │                │               │              │              │
   │───────────────>│                │               │              │              │
   │                │                │               │              │              │
   │                │  Check sender  │               │              │              │
   │                │  not blocked   │               │              │              │
   │                │                │               │              │              │
   │                │  Get own ML-KEM│               │              │              │
   │                │  secret key    │               │              │              │
   │                │                │               │              │              │
   │                │  handleIncoming│               │              │              │
   │                │  GroupInvite() │               │              │              │
   │                │───────────────>│               │              │              │
   │                │                │               │              │              │
   │                │                │  Parse v2 encrypted envelope │              │
   │                │                │  callDecryptMessage()        │              │
   │                │                │──────────────>│              │              │
   │                │                │               │  ML-KEM-768  │              │
   │                │                │               │  decapsulate │              │
   │                │                │               │  + AES-256-  │              │
   │                │                │               │  GCM decrypt │              │
   │                │                │  {plaintext}  │              │              │
   │                │                │<──────────────│              │              │
   │                │                │               │              │              │
   │                │                │  fromInnerJson()             │              │
   │                │                │  → GroupInvitePayload        │              │
   │                │                │  (groupId, groupKey,         │              │
   │                │                │   keyEpoch, groupConfig)     │              │
   │                │                │               │              │              │
   │                │                │  Verify sender is contact    │              │
   │                │                │─────────────────────────────────────────────>│
   │                │                │               │              │              │
   │                │                │  Check duplicate group       │              │
   │                │                │──────────────────────────────>│              │
   │                │                │               │              │              │
   │                │                │  saveGroup(myRole=member)    │              │
   │                │                │  saveMember() for each member│              │
   │                │                │  saveKey(groupKey, keyEpoch) │              │
   │                │                │──────────────────────────────>│              │
   │                │                │               │              │              │
   │                │                │  group:join   │              │              │
   │                │                │  WithConfig() │              │              │
   │                │                │──────────────>│              │              │
   │                │                │               │              │              │
   │                │  (success,     │               │              │              │
   │                │   groupId)     │               │              │              │
   │                │<───────────────│               │              │              │
   │                │                │               │              │              │
   │                │  Drain offline │               │              │              │
   │                │  inbox for     │               │              │              │
   │                │  this group    │               │              │              │
   │                │  (retrieve +   │               │              │              │
   │                │   process each)│               │              │              │
   │                │                │               │              │              │
   │                │  groupJoined   │               │              │              │
   │                │  Stream.add()  │               │              │              │
   │                │  → UI updates  │               │              │              │
   │                │                │               │              │              │
```

### Send Group Message Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│              SEND GROUP MESSAGE - DATA FLOW (GossipSub + Relay Inbox)       │
└─────────────────────────────────────────────────────────────────────────────┘

  User       GroupConvWired   sendGroupMsg UC    GoBridge      GroupMsgRepo    GroupRepo
   │                │                │              │              │              │
   │  Type + Send   │                │              │              │              │
   │───────────────>│                │              │              │              │
   │                │                │              │              │              │
   │                │  sendGroup     │              │              │              │
   │                │  Message()     │              │              │              │
   │                │───────────────>│              │              │              │
   │                │                │              │              │              │
   │                │                │  getGroup()  │              │              │
   │                │                │  (verify exists + auth)     │              │
   │                │                │──────────────────────────────────────────>│
   │                │                │              │              │              │
   │                │                │  [if announcement: check admin role]      │
   │                │                │              │              │              │
   │                │                │  CONCURRENT: │              │              │
   │                │                │  ┌────────────────────────────────────┐   │
   │                │                │  │ group:publish (GossipSub)         │   │
   │                │                │  │ Go encrypts + signs internally    │   │
   │                │                │  │ Fire-and-forget to all peers      │   │
   │                │                │  └────────────────────────────────────┘   │
   │                │                │─────────────>│              │              │
   │                │                │              │              │              │
   │                │                │  ┌────────────────────────────────────┐   │
   │                │                │  │ group:inboxStore (relay backup)   │   │
   │                │                │  │ Stores message for offline peers  │   │
   │                │                │  │ Failures silently caught          │   │
   │                │                │  └────────────────────────────────────┘   │
   │                │                │─────────────>│              │              │
   │                │                │              │              │              │
   │                │                │  [if publish ok]             │              │
   │                │                │  Save GroupMessage           │              │
   │                │                │  (isIncoming: false,         │              │
   │                │                │   status: 'sent')            │              │
   │                │                │──────────────────────────────>│              │
   │                │                │              │              │              │
   │                │  (success,     │              │              │              │
   │                │   GroupMessage) │              │              │              │
   │                │<───────────────│              │              │              │
   │                │                │              │              │              │
   │  Message       │                │              │              │              │
   │  appears in    │                │              │              │              │
   │  conversation  │                │              │              │              │
   │<───────────────│                │              │              │              │
   │                │                │              │              │              │
```

### Incoming Group Message Flow (GossipSub)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│              INCOMING GROUP MESSAGE - DATA FLOW (via GossipSub pubsub)       │
└─────────────────────────────────────────────────────────────────────────────┘

  Go PubSub    MsgRouter     GroupMsgListener   handleMsg UC    GroupRepo     GroupConvWired   User
   │               │                │                │              │              │           │
   │  GossipSub    │                │                │              │              │           │
   │  message      │                │                │              │              │           │
   │  (decrypted + │                │                │              │              │           │
   │   verified    │                │                │              │              │           │
   │   by Go)      │                │                │              │              │           │
   │──────────────>│                │                │              │              │           │
   │               │                │                │              │              │           │
   │               │  groupMessage  │                │              │              │           │
   │               │  Stream.add()  │                │              │              │           │
   │               │───────────────>│                │              │              │           │
   │               │                │                │              │              │           │
   │               │                │  [if __sys msg]│              │              │           │
   │               │                │  → handle      │              │              │           │
   │               │                │  system message│              │              │           │
   │               │                │  (see System   │              │              │           │
   │               │                │   Message flow)│              │              │           │
   │               │                │  return        │              │              │           │
   │               │                │                │              │              │           │
   │               │                │  handleIncoming│              │              │           │
   │               │                │  GroupMessage() │              │              │           │
   │               │                │───────────────>│              │              │           │
   │               │                │                │              │              │           │
   │               │                │                │  getGroup()  │              │           │
   │               │                │                │  (verify     │              │           │
   │               │                │                │   exists)    │              │           │
   │               │                │                │─────────────>│              │           │
   │               │                │                │              │              │           │
   │               │                │                │  getMember() │              │           │
   │               │                │                │  (verify     │              │           │
   │               │                │                │   sender)    │              │           │
   │               │                │                │─────────────>│              │           │
   │               │                │                │              │              │           │
   │               │                │                │  existsByContent()          │           │
   │               │                │                │  (dedup check)              │           │
   │               │                │                │              │              │           │
   │               │                │                │  saveMessage()              │           │
   │               │                │                │  (isIncoming: true,         │           │
   │               │                │                │   status: delivered)        │           │
   │               │                │                │              │              │           │
   │               │                │  GroupMessage   │              │              │           │
   │               │                │<───────────────│              │              │           │
   │               │                │                │              │              │           │
   │               │                │  groupMessage  │              │              │           │
   │               │                │  Stream.add()  │              │              │           │
   │               │                │──────────────────────────────────────────────>│           │
   │               │                │                │              │              │           │
   │               │                │  [if not self] │              │              │           │
   │               │                │  maybeShow     │              │              │           │
   │               │                │  Notification()│              │              │           │
   │               │                │                │              │              │           │
   │               │                │  [if has media]│              │              │  New msg  │
   │               │                │  autoDownload  │              │              │  card     │
   │               │                │  Media()       │              │              │──────────>│
   │               │                │  (fire-and-    │              │              │           │
   │               │                │   forget)      │              │              │           │
   │               │                │                │              │              │           │
```

### Group System Message Flow (Member Added/Removed)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│              GROUP SYSTEM MESSAGE - DATA FLOW                                │
│              (member_added / member_removed via GossipSub)                   │
└─────────────────────────────────────────────────────────────────────────────┘

  Go PubSub    GroupMsgListener      GoBridge         GroupRepo        UI
   │                │                    │                │              │
   │  GossipSub     │                    │                │              │
   │  message with  │                    │                │              │
   │  {"__sys":...} │                    │                │              │
   │───────────────>│                    │                │              │
   │                │                    │                │              │
   │                │  [__sys = member_added]             │              │
   │                │  Parse member data │                │              │
   │                │  saveMember()      │                │              │
   │                │──────────────────────────────────>│              │
   │                │                    │                │              │
   │                │  group:updateConfig │                │              │
   │                │  (update Go topic  │                │              │
   │                │   validator)       │                │              │
   │                │───────────────────>│                │              │
   │                │                    │                │              │
   │                │  [__sys = member_removed]           │              │
   │                │                    │                │              │
   │                │  [if removed member is self]        │              │
   │                │  leaveGroup()      │                │              │
   │                │  → group:leave     │                │              │
   │                │───────────────────>│                │              │
   │                │  → delete group +  │                │              │
   │                │    members + key   │                │              │
   │                │──────────────────────────────────>│              │
   │                │                    │                │              │
   │                │  groupRemoved      │                │              │
   │                │  Stream.add()      │                │              │
   │                │──────────────────────────────────────────────────>│
   │                │                    │                │              │
   │                │  [if removed member is other]       │              │
   │                │  removeMember()    │                │              │
   │                │──────────────────────────────────>│              │
   │                │                    │                │              │
   │                │  group:updateConfig │                │              │
   │                │  (update Go topic  │                │              │
   │                │   validator)       │                │              │
   │                │───────────────────>│                │              │
   │                │                    │                │              │
```

### Rejoin Group Topics on Startup Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│              REJOIN GROUP TOPICS ON STARTUP - DATA FLOW                      │
└─────────────────────────────────────────────────────────────────────────────┘

  App Startup     rejoinGroupTopics UC    GroupRepo        GoBridge
   │                      │                   │               │
   │  P2P node started    │                   │               │
   │  (Go node is fresh,  │                   │               │
   │   no topics joined)  │                   │               │
   │─────────────────────>│                   │               │
   │                      │                   │               │
   │                      │  getAllGroups()    │               │
   │                      │  (includes        │               │
   │                      │   archived)       │               │
   │                      │──────────────────>│               │
   │                      │                   │               │
   │                      │  List<GroupModel>  │               │
   │                      │<──────────────────│               │
   │                      │                   │               │
   │                      │  For each group:  │               │
   │                      │                   │               │
   │                      │  getLatestKey()   │               │
   │                      │──────────────────>│               │
   │                      │                   │               │
   │                      │  [if no key: skip]│               │
   │                      │                   │               │
   │                      │  getMembers()     │               │
   │                      │──────────────────>│               │
   │                      │                   │               │
   │                      │  Build groupConfig│               │
   │                      │  from stored data │               │
   │                      │                   │               │
   │                      │  group:join       │               │
   │                      │  WithConfig()     │               │
   │                      │  (groupId,        │               │
   │                      │   groupConfig,    │               │
   │                      │   groupKey,       │               │
   │                      │   keyEpoch)       │               │
   │                      │──────────────────────────────────>│
   │                      │                   │               │
   │                      │                   │  Subscribe to │
   │                      │                   │  GossipSub    │
   │                      │                   │  topic with   │
   │                      │                   │  validator    │
   │                      │                   │               │
   │  All topics rejoined │                   │               │
   │<─────────────────────│                   │               │
   │                      │                   │               │
```

### Drain Group Offline Inbox on Startup Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│              DRAIN GROUP OFFLINE INBOX - DATA FLOW                           │
│              (retrieves store-and-forward messages from relay)               │
└─────────────────────────────────────────────────────────────────────────────┘

  App Startup    drainGroupOffline    GoBridge        handleMsg UC    GroupMsgRepo
   │              InboxUC                │                │               │
   │                │                    │                │               │
   │  After topics  │                    │                │               │
   │  rejoined      │                    │                │               │
   │───────────────>│                    │                │               │
   │                │                    │                │               │
   │                │  getAllGroups()     │                │               │
   │                │                    │                │               │
   │                │  For each group:   │                │               │
   │                │                    │                │               │
   │                │  group:inboxRetrieve                │               │
   │                │  (groupId,         │                │               │
   │                │   sinceTimestamp=0) │                │               │
   │                │───────────────────>│                │               │
   │                │                    │                │               │
   │                │                    │  Fetch from    │               │
   │                │                    │  relay server  │               │
   │                │                    │                │               │
   │                │  List<messages>    │                │               │
   │                │  [{from, message,  │                │               │
   │                │    timestamp}]     │                │               │
   │                │<───────────────────│                │               │
   │                │                    │                │               │
   │                │  For each message: │                │               │
   │                │  Decode inbox envelope              │               │
   │                │  (JSON-encoded     │                │               │
   │                │   message field)   │                │               │
   │                │                    │                │               │
   │                │  handleIncoming    │                │               │
   │                │  GroupMessage()    │                │               │
   │                │───────────────────────────────────>│               │
   │                │                    │                │               │
   │                │                    │                │  Check group  │
   │                │                    │                │  exists,      │
   │                │                    │                │  dedup,       │
   │                │                    │                │  save message │
   │                │                    │                │──────────────>│
   │                │                    │                │               │
   │  All inboxes   │                    │                │               │
   │  drained       │                    │                │               │
   │<───────────────│                    │                │               │
   │                │                    │                │               │
```

---

