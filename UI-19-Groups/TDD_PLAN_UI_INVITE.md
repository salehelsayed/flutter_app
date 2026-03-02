# TDD Plan: Group Member Invite UI

## Overview

Add the ability for group admins to invite contacts as new members from the
group info screen. The flow is:

1. Admin taps "Add Member" button on `GroupInfoScreen`
2. A contact picker screen appears showing contacts (excluding existing members)
3. Admin selects a contact and sees a confirmation dialog
4. On confirm, the `addGroupMember` use case is called
5. Success/error feedback is shown via a SnackBar

This plan covers **only the UI layer** -- the `addGroupMember` use case and
`GroupRepository`/`ContactRepository` already exist.

---

## Architecture Recap

```
GroupInfoScreen (pure StatelessWidget)
    |
    v callbacks
GroupInfoWired (StatefulWidget -- orchestrates state + navigation)
    |
    v navigates to
ContactPickerScreen (pure StatelessWidget -- new)
    |
    v callbacks
ContactPickerWired (StatefulWidget -- new, loads contacts, filters members)
    |
    v calls
addGroupMember()  (existing use case)
```

**Key repositories involved:**
- `ContactRepository.getActiveContacts()` -- fetch all non-archived contacts
- `GroupRepository.getMembers(groupId)` -- fetch current members for filtering
- `addGroupMember(...)` -- existing use case in `lib/features/groups/application/add_group_member_use_case.dart`

---

## File Inventory

### New Files

| File | Purpose |
|------|---------|
| `lib/features/groups/presentation/screens/contact_picker_screen.dart` | Pure UI: header, search field, contact list, empty state |
| `lib/features/groups/presentation/screens/contact_picker_wired.dart` | Wired: loads contacts, filters out existing members, handles selection + invite |
| `lib/features/groups/presentation/widgets/contact_picker_row.dart` | Single row widget for a contact in the picker list |
| `test/features/groups/presentation/contact_picker_screen_test.dart` | Widget tests for the pure screen |
| `test/features/groups/presentation/contact_picker_wired_test.dart` | Widget tests for the wired widget |

### Modified Files

| File | Change |
|------|--------|
| `lib/features/groups/presentation/screens/group_info_screen.dart` | Add `onAddMember` callback, render "Add Member" button |
| `lib/features/groups/presentation/screens/group_info_wired.dart` | Add `ContactRepository` dependency, navigate to `ContactPickerWired` |
| `lib/features/groups/presentation/screens/group_conversation_wired.dart` | Thread `ContactRepository` to `GroupInfoWired` |
| `lib/features/groups/presentation/screens/group_list_wired.dart` | Thread `ContactRepository` to `GroupConversationWired` |
| `test/features/groups/presentation/group_info_screen_test.dart` | Add tests for the new "Add Member" button |

### DI Chain Updates

The `ContactRepository` must reach `GroupInfoWired`. The existing navigation
chain is:

```
GroupListWired -> GroupConversationWired -> GroupInfoWired
```

- `GroupListWired` already has access to many repos (passed from `OrbitWired`
  or wherever it is constructed). It needs to accept and forward a
  `ContactRepository`.
- `GroupConversationWired` forwards it to `GroupInfoWired`.
- `GroupInfoWired` uses it to construct `ContactPickerWired`.

This mirrors how `IdentityRepository` is already threaded through the same
chain.

---

## Fakes / Mocks Strategy

All tests use **in-memory fakes** (no mocking frameworks). This is consistent
with every existing test in the codebase.

| Dependency | Fake | Location |
|------------|------|----------|
| `ContactRepository` | `InMemoryContactRepository` | `test/shared/fakes/in_memory_contact_repository.dart` (existing) |
| `GroupRepository` | `InMemoryGroupRepository` | `test/shared/fakes/in_memory_group_repository.dart` (existing) |
| `Bridge` | `FakeBridge` | `test/core/bridge/fake_bridge.dart` (existing) |
| `IdentityRepository` | Inline stub or simple class returning a fixed `IdentityModel` | Created in test file |

---

## TDD Steps

Each step follows Red-Green-Refactor:
1. **RED**: Write the test. It fails because the production code does not exist.
2. **GREEN**: Write the minimum production code to make the test pass.
3. **REFACTOR**: Clean up if needed (extract widgets, rename, etc.).

---

### Phase 1: ContactPickerRow Widget

A small, self-contained widget that renders a single contact in the picker
list. Build this first since the screen will compose it.

#### Step 1.1 -- ContactPickerRow renders contact username

**Test** (`test/features/groups/presentation/contact_picker_screen_test.dart`):
```
testWidgets('ContactPickerRow renders username', ...)
```
- Build a `ContactPickerRow` with a `ContactModel(username: 'Alice', ...)`.
- Assert: `find.text('Alice')` finds one widget.

**Implementation** (`lib/features/groups/presentation/widgets/contact_picker_row.dart`):
```dart
class ContactPickerRow extends StatelessWidget {
  final ContactModel contact;
  final VoidCallback onTap;

  const ContactPickerRow({
    super.key,
    required this.contact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Row with avatar placeholder (initial letter), username, truncated peerId,
    // and a tappable area. Visual style matches GroupMemberRow / FriendRow.
  }
}
```

**Widget tree:**
```
GestureDetector(onTap)
  Padding(h:16, v:8)
    Row
      Container(36x36 circle, initial letter)
      SizedBox(w:12)
      Expanded
        Column
          Text(contact.username)  // 14sp, w500, white
          Text(truncatedPeerId)   // 12sp, white.withOpacity(0.4)
      Icon(Icons.add_circle_outline)  // 20, white.withOpacity(0.4)
```

#### Step 1.2 -- ContactPickerRow calls onTap when tapped

**Test:**
```
testWidgets('ContactPickerRow calls onTap when tapped', ...)
```
- Capture a boolean `tapped`.
- Tap the row.
- Assert: `tapped` is true.

**Implementation:** Already covered by the `GestureDetector(onTap)` wrapper.

---

### Phase 2: ContactPickerScreen (Pure UI)

The full-screen contact picker. Stateless -- all data and callbacks are props.

#### Step 2.1 -- renders header with "Add Member" title and back button

**Test** (`test/features/groups/presentation/contact_picker_screen_test.dart`):
```
testWidgets('renders header with title and back button', ...)
```
- Build `ContactPickerScreen(contacts: [], onSelect: (_){}, onBack: (){})`.
- Assert: `find.text('Add Member')` finds one widget.
- Assert: `find.byIcon(Icons.arrow_back_ios_new)` finds one widget.

**Implementation** (`lib/features/groups/presentation/screens/contact_picker_screen.dart`):

```dart
class ContactPickerScreen extends StatefulWidget {
  final List<ContactModel> contacts;
  final bool isInviting;
  final ValueChanged<ContactModel> onSelect;
  final VoidCallback onBack;

  const ContactPickerScreen({
    super.key,
    required this.contacts,
    this.isInviting = false,
    required this.onSelect,
    required this.onBack,
  });

  @override
  State<ContactPickerScreen> createState() => _ContactPickerScreenState();
}
```

Note: `StatefulWidget` because it manages a local search filter
`TextEditingController`. All data still comes from props -- the only local
state is the search query text.

**Widget tree:**
```
AmbientBackground
  Scaffold(backgroundColor: transparent)
    SafeArea
      Column
        _buildHeader()       // Back button + "Add Member" title
        _buildSearchField()  // TextField for filtering by name
        Expanded
          contacts.isEmpty ? _buildEmptyState() : _buildContactList()
```

#### Step 2.2 -- renders list of contacts

**Test:**
```
testWidgets('renders list of contacts', ...)
```
- Build with `contacts: [alice, bob]`.
- Assert: `find.text('Alice')` finds one widget.
- Assert: `find.text('Bob')` finds one widget.

**Implementation:** `_buildContactList()` uses `ListView.builder` rendering
`ContactPickerRow` for each contact.

#### Step 2.3 -- shows empty state when contacts list is empty

**Test:**
```
testWidgets('shows empty state when no contacts available', ...)
```
- Build with `contacts: []`.
- Assert: `find.text('No contacts available')` finds one widget.

**Implementation:** `_buildEmptyState()` renders a centered column with
an icon and "No contacts available" text, matching the pattern in
`GroupListScreen._buildEmptyState()`.

#### Step 2.4 -- calls onSelect when a contact row is tapped

**Test:**
```
testWidgets('calls onSelect when contact is tapped', ...)
```
- Capture `ContactModel? selected`.
- Tap Alice's row.
- Assert: `selected?.username == 'Alice'`.

**Implementation:** Each `ContactPickerRow(onTap: () => onSelect(contact))`.

#### Step 2.5 -- calls onBack when back button is tapped

**Test:**
```
testWidgets('calls onBack when back button is tapped', ...)
```
- Capture `backCalled`.
- Tap the back `IconButton`.
- Assert: `backCalled` is true.

**Implementation:** Already wired in the header's `IconButton(onPressed: onBack)`.

#### Step 2.6 -- search field filters contacts by username

**Test:**
```
testWidgets('search filters contacts by username', ...)
```
- Build with `contacts: [alice, bob, charlie]`.
- Enter "ali" into the search `TextField`.
- Pump.
- Assert: `find.text('Alice')` finds one widget.
- Assert: `find.text('Bob')` finds nothing.
- Assert: `find.text('Charlie')` finds nothing.

**Implementation:** `_ContactPickerScreenState` holds `_searchQuery`. The
displayed list filters `widget.contacts` by
`c.username.toLowerCase().contains(_searchQuery.toLowerCase())`.

#### Step 2.7 -- shows loading indicator when isInviting is true

**Test:**
```
testWidgets('shows loading indicator when isInviting', ...)
```
- Build with `isInviting: true, contacts: [alice]`.
- Assert: `find.byType(CircularProgressIndicator)` finds one widget.

**Implementation:** When `isInviting` is true, overlay a centered
`CircularProgressIndicator` and disable taps (via `AbsorbPointer` or
`IgnorePointer`).

---

### Phase 3: Modify GroupInfoScreen -- Add "Add Member" Button

#### Step 3.1 -- shows "Add Member" button when isAdmin is true

**Test** (`test/features/groups/presentation/group_info_screen_test.dart`):
```
testWidgets('shows Add Member button when isAdmin', ...)
```
- Build `GroupInfoScreen(isAdmin: true, onAddMember: (){}, ...)`.
- Assert: `find.text('Add Member')` finds one widget.

**Implementation** (`lib/features/groups/presentation/screens/group_info_screen.dart`):
- Add `VoidCallback? onAddMember` to the constructor.
- In `_buildMembersSection()`, add an "Add Member" button above the member
  list when `isAdmin && onAddMember != null`.

**Constructor changes:**
```dart
class GroupInfoScreen extends StatelessWidget {
  final GroupModel group;
  final List<GroupMember> members;
  final bool isAdmin;
  final VoidCallback onBack;
  final VoidCallback onLeave;
  final ValueChanged<GroupMember>? onRemoveMember;
  final VoidCallback? onAddMember;  // NEW

  const GroupInfoScreen({
    super.key,
    required this.group,
    required this.members,
    required this.isAdmin,
    required this.onBack,
    required this.onLeave,
    this.onRemoveMember,
    this.onAddMember,  // NEW
  });
}
```

**Button placement in widget tree:**
```
_buildMembersSection()
  Column
    Padding  // "Members" label
    SizedBox(h:8)
    if (isAdmin && onAddMember != null)
      _buildAddMemberButton()   // NEW
    ...members.map(GroupMemberRow(...))
```

**Button widget tree:**
```
Padding(h:16, v:4)
  GestureDetector(onTap: onAddMember)
    Container(decoration: dashed-border-style or subtle bg)
      Row
        Icon(Icons.person_add_outlined, 20, Color(0xFF64B5F6))
        SizedBox(w:8)
        Text('Add Member', 14sp, Color(0xFF64B5F6))
```

#### Step 3.2 -- hides "Add Member" button when isAdmin is false

**Test:**
```
testWidgets('hides Add Member button when not admin', ...)
```
- Build with `isAdmin: false`.
- Assert: `find.text('Add Member')` finds nothing.

**Implementation:** The conditional `if (isAdmin && onAddMember != null)`
already handles this.

#### Step 3.3 -- calls onAddMember when Add Member button is tapped

**Test:**
```
testWidgets('calls onAddMember callback when tapped', ...)
```
- Capture `addMemberCalled`.
- Tap "Add Member".
- Assert: `addMemberCalled` is true.

**Implementation:** `GestureDetector(onTap: onAddMember)`.

---

### Phase 4: ContactPickerWired (Wired Widget)

The wired widget that orchestrates loading contacts, filtering out existing
group members, handling selection with a confirmation dialog, and calling the
`addGroupMember` use case.

#### Step 4.1 -- loads contacts excluding existing group members

**Test** (`test/features/groups/presentation/contact_picker_wired_test.dart`):
```
testWidgets('shows contacts excluding existing group members', ...)
```
- Set up:
  - `InMemoryContactRepository` with 3 contacts: Alice (peer-a), Bob (peer-b), Charlie (peer-c).
  - `InMemoryGroupRepository` with a group, member list containing peer-b (Bob is already a member).
  - `FakeBridge`.
  - Stub `IdentityRepository` returning identity with `peerId: 'peer-self'`.
- Build `ContactPickerWired(groupId: ..., groupRepo: ..., contactRepo: ..., bridge: ..., identityRepo: ...)`.
- `pumpAndSettle()`.
- Assert: `find.text('Alice')` finds one widget.
- Assert: `find.text('Charlie')` finds one widget.
- Assert: `find.text('Bob')` finds nothing (already a member).

**Implementation** (`lib/features/groups/presentation/screens/contact_picker_wired.dart`):

```dart
class ContactPickerWired extends StatefulWidget {
  final String groupId;
  final GroupRepository groupRepo;
  final ContactRepository contactRepo;
  final Bridge bridge;
  final IdentityRepository identityRepo;

  const ContactPickerWired({
    super.key,
    required this.groupId,
    required this.groupRepo,
    required this.contactRepo,
    required this.bridge,
    required this.identityRepo,
  });

  @override
  State<ContactPickerWired> createState() => _ContactPickerWiredState();
}

class _ContactPickerWiredState extends State<ContactPickerWired> {
  List<ContactModel> _availableContacts = [];
  bool _isInviting = false;

  @override
  void initState() {
    super.initState();
    _loadAvailableContacts();
  }

  Future<void> _loadAvailableContacts() async {
    final allContacts = await widget.contactRepo.getActiveContacts();
    final members = await widget.groupRepo.getMembers(widget.groupId);
    final memberPeerIds = members.map((m) => m.peerId).toSet();

    if (!mounted) return;
    setState(() {
      _availableContacts = allContacts
          .where((c) => !memberPeerIds.contains(c.peerId))
          .toList();
    });
  }

  // ... onSelect, onBack, build ...
}
```

**Filtering logic:** Fetch all active contacts, fetch group members, build a
`Set<String>` of member peer IDs, filter contacts where peerId is NOT in the
set.

#### Step 4.2 -- also excludes self (own peerId) from the contact list

**Test:**
```
testWidgets('excludes self from contact list', ...)
```
- Contact list includes a contact with peerId matching identity's peerId.
- Assert that contact does not appear.

**Implementation:** Add identity peerId to the exclusion set:
```dart
final identity = await widget.identityRepo.loadIdentity();
final excludePeerIds = {...memberPeerIds};
if (identity != null) excludePeerIds.add(identity.peerId);
```

#### Step 4.3 -- shows confirmation dialog when contact is selected

**Test:**
```
testWidgets('shows confirmation dialog on contact selection', ...)
```
- Build with available contacts.
- Tap Alice's row.
- Assert: `find.text('Invite Alice?')` finds one widget.
- Assert: `find.text('Cancel')` finds one widget.
- Assert: `find.text('Invite')` finds one widget.

**Implementation:** In `_onSelect(ContactModel contact)`:
```dart
Future<void> _onSelect(ContactModel contact) async {
  final confirmed = await showConfirmationDialog(
    context: context,
    title: 'Invite ${contact.username}?',
    description:
        'They will be added as a member of this group.',
    confirmLabel: 'Invite',
  );
  if (!confirmed || !mounted) return;
  _inviteMember(contact);
}
```

Reuses the existing `showConfirmationDialog` from
`lib/features/orbit/presentation/widgets/confirmation_dialog.dart`.

Note on dialog reuse: The existing `showConfirmationDialog` uses red/danger
styling for the confirm button. For an invite action, we have two options:
(a) reuse as-is (acceptable for MVP), or (b) create a variant with a blue
confirm button. The TDD plan uses option (a) for simplicity. A refactor step
can introduce a `confirmColor` parameter later.

#### Step 4.4 -- cancelling confirmation dialog does NOT call use case

**Test:**
```
testWidgets('cancelling confirmation does not invoke use case', ...)
```
- Tap Alice, then tap "Cancel" in the dialog.
- Assert: `FakeBridge.sendCallCount == 0` (no bridge call was made).
- Assert: No new members in the group repo.

**Implementation:** Already handled -- `showConfirmationDialog` returns
`false`, the guard `if (!confirmed) return;` prevents further action.

#### Step 4.5 -- confirming invite calls addGroupMember and pops

**Test:**
```
testWidgets('confirming invite adds member and pops screen', ...)
```
- Use a `Navigator` observer or check `Navigator` stack.
- Tap Alice, then tap "Invite" in the dialog.
- `pumpAndSettle()`.
- Assert: the contact picker screen is popped (e.g., verify by checking a
  page beneath is now visible).
- Assert: `groupRepo.getMembers(groupId)` now includes Alice's peerId.

**Implementation:**
```dart
Future<void> _inviteMember(ContactModel contact) async {
  setState(() => _isInviting = true);

  try {
    final identity = await widget.identityRepo.loadIdentity();
    if (identity == null) throw StateError('No identity found');

    final newMember = GroupMember(
      groupId: widget.groupId,
      peerId: contact.peerId,
      username: contact.username,
      role: MemberRole.writer,
      publicKey: contact.publicKey,
      mlKemPublicKey: contact.mlKemPublicKey,
      joinedAt: DateTime.now().toUtc(),
    );

    await addGroupMember(
      bridge: widget.bridge,
      groupRepo: widget.groupRepo,
      groupId: widget.groupId,
      newMember: newMember,
      selfPeerId: identity.peerId,
    );

    if (!mounted) return;
    Navigator.of(context).pop(true);  // pop with success result
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACT_PICKER_FL_INVITE_ERROR',
      details: {'error': e.toString()},
    );
    if (mounted) {
      setState(() => _isInviting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to invite member')),
      );
    }
  }
}
```

#### Step 4.6 -- shows error SnackBar when invite fails

**Test:**
```
testWidgets('shows error snackbar when invite fails', ...)
```
- Set `FakeBridge.throwOnSend = true` (or set up groupRepo to have
  `myRole: GroupRole.member` so the use case throws `StateError`).
- Tap Alice, confirm.
- `pumpAndSettle()`.
- Assert: `find.text('Failed to invite member')` finds one widget.
- Assert: screen is NOT popped (still on picker).

**Implementation:** The catch block in `_inviteMember` already shows the
SnackBar and does not pop.

#### Step 4.7 -- navigating back calls onBack / pops

**Test:**
```
testWidgets('back button pops the screen', ...)
```
- Tap the back button.
- Assert: screen is popped.

**Implementation:**
```dart
void _onBack() {
  Navigator.of(context).pop(false);  // pop with no-change result
}
```

---

### Phase 5: Wire GroupInfoWired to ContactPickerWired

#### Step 5.1 -- GroupInfoWired navigates to ContactPickerWired on add member

**Test** (`test/features/groups/presentation/group_info_screen_test.dart` or a
new wired test):
```
testWidgets('onAddMember navigates to ContactPickerWired', ...)
```
- Build `GroupInfoWired` inside a `MaterialApp` with a `Navigator`.
- Set the group to have `myRole: GroupRole.admin`.
- Supply `InMemoryContactRepository` with some contacts.
- Tap "Add Member".
- Assert: `find.byType(ContactPickerScreen)` finds one widget
  (the `ContactPickerWired` pushed a route containing `ContactPickerScreen`).

**Implementation** (`lib/features/groups/presentation/screens/group_info_wired.dart`):

Add `ContactRepository contactRepo` to the constructor:

```dart
class GroupInfoWired extends StatefulWidget {
  final GroupModel group;
  final GroupRepository groupRepo;
  final ContactRepository contactRepo;  // NEW
  final Bridge bridge;
  final IdentityRepository identityRepo;

  const GroupInfoWired({
    super.key,
    required this.group,
    required this.groupRepo,
    required this.contactRepo,  // NEW
    required this.bridge,
    required this.identityRepo,
  });
  // ...
}
```

Add the navigation method:
```dart
void _onAddMember() {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ContactPickerWired(
        groupId: widget.group.id,
        groupRepo: widget.groupRepo,
        contactRepo: widget.contactRepo,
        bridge: widget.bridge,
        identityRepo: widget.identityRepo,
      ),
    ),
  ).then((added) {
    if (added == true) {
      _loadMembers();  // refresh member list
    }
  });
}
```

Update the `build` method to pass the callback:
```dart
@override
Widget build(BuildContext context) {
  return GroupInfoScreen(
    group: widget.group,
    members: _members,
    isAdmin: widget.group.myRole == GroupRole.admin,
    onBack: _onBack,
    onLeave: _onLeave,
    onRemoveMember: widget.group.myRole == GroupRole.admin
        ? _onRemoveMember
        : null,
    onAddMember: widget.group.myRole == GroupRole.admin  // NEW
        ? _onAddMember
        : null,
  );
}
```

#### Step 5.2 -- GroupInfoWired refreshes member list after successful invite

**Test:**
```
testWidgets('member list refreshes after successful invite', ...)
```
- Build `GroupInfoWired` with a group that has 1 member.
- Tap "Add Member", select a contact, confirm.
- After pop, assert that the new member now appears in the member list on
  the info screen.

**Implementation:** The `.then((added) { if (added == true) _loadMembers(); })`
in the navigation handler reloads the members from the repo.

---

### Phase 6: Thread ContactRepository Through DI Chain

#### Step 6.1 -- GroupConversationWired passes ContactRepository to GroupInfoWired

**File:** `lib/features/groups/presentation/screens/group_conversation_wired.dart`

**Change:** Add `ContactRepository contactRepo` parameter, forward it in `_onInfo()`:

```dart
class GroupConversationWired extends StatefulWidget {
  final GroupModel group;
  final GroupRepository groupRepo;
  final GroupMessageRepository msgRepo;
  final GroupMessageListener groupMessageListener;
  final Bridge bridge;
  final IdentityRepository identityRepo;
  final ContactRepository contactRepo;  // NEW
  // ...
}
```

```dart
void _onInfo() {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => GroupInfoWired(
        group: widget.group,
        groupRepo: widget.groupRepo,
        contactRepo: widget.contactRepo,  // NEW
        bridge: widget.bridge,
        identityRepo: widget.identityRepo,
      ),
    ),
  );
}
```

#### Step 6.2 -- GroupListWired passes ContactRepository to GroupConversationWired

**File:** `lib/features/groups/presentation/screens/group_list_wired.dart`

**Change:** Add `ContactRepository contactRepo` parameter, forward it:

```dart
class GroupListWired extends StatefulWidget {
  final GroupRepository groupRepo;
  final GroupMessageRepository msgRepo;
  final GroupMessageListener groupMessageListener;
  final Bridge bridge;
  final IdentityRepository identityRepo;
  final ContactRepository contactRepo;  // NEW
  // ...
}
```

```dart
void _onGroupTap(GroupModel group) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => GroupConversationWired(
        group: group,
        groupRepo: widget.groupRepo,
        msgRepo: widget.msgRepo,
        groupMessageListener: widget.groupMessageListener,
        bridge: widget.bridge,
        identityRepo: widget.identityRepo,
        contactRepo: widget.contactRepo,  // NEW
      ),
    ),
  ).then((_) => _loadGroups());
}
```

#### Step 6.3 -- Update all call sites that construct GroupListWired

Search the codebase for every place `GroupListWired(` is constructed and add
the `contactRepo:` argument. Based on the existing code, this is likely in:
- `OrbitWired` or `FeedWired` or wherever the groups tab navigates from
- Possibly `StartupRouter` or nav bar

This is a compile-time check -- the Dart analyzer will surface missing
arguments. No separate test needed; existing tests will fail to compile until
fixed.

---

### Phase 7: Success Feedback on GroupInfoScreen

#### Step 7.1 -- GroupInfoWired shows success SnackBar after invite

**Test:**
```
testWidgets('shows success snackbar after member invited', ...)
```
- Build `GroupInfoWired` in a `Scaffold` inside a `MaterialApp`.
- Navigate to picker, select contact, confirm.
- After pop, assert: `find.text('Member invited')` is visible.

**Implementation:** In `_onAddMember()`:
```dart
.then((added) {
  if (added == true) {
    _loadMembers();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Member invited')),
      );
    }
  }
});
```

---

## Test Data Fixtures

Reuse across all tests:

```dart
// --- Contacts ---
final contactAlice = ContactModel(
  peerId: 'peer-alice',
  publicKey: 'pk-alice',
  rendezvous: '/dns4/relay/tcp/443/p2p/relay',
  username: 'Alice',
  signature: 'sig-alice',
  scannedAt: DateTime.now().toUtc().toIso8601String(),
  mlKemPublicKey: 'mlkem-pk-alice',
);

final contactBob = ContactModel(
  peerId: 'peer-bob',
  publicKey: 'pk-bob',
  rendezvous: '/dns4/relay/tcp/443/p2p/relay',
  username: 'Bob',
  signature: 'sig-bob',
  scannedAt: DateTime.now().toUtc().toIso8601String(),
  mlKemPublicKey: 'mlkem-pk-bob',
);

final contactCharlie = ContactModel(
  peerId: 'peer-charlie',
  publicKey: 'pk-charlie',
  rendezvous: '/dns4/relay/tcp/443/p2p/relay',
  username: 'Charlie',
  signature: 'sig-charlie',
  scannedAt: DateTime.now().toUtc().toIso8601String(),
  mlKemPublicKey: 'mlkem-pk-charlie',
);

// --- Group ---
final testGroup = GroupModel(
  id: 'group-1',
  name: 'Test Group',
  type: GroupType.chat,
  topicName: 'topic-1',
  description: 'A test group',
  createdAt: DateTime.now().toUtc(),
  createdBy: 'peer-admin',
  myRole: GroupRole.admin,
);

// --- Existing member (Bob) ---
final memberBob = GroupMember(
  groupId: 'group-1',
  peerId: 'peer-bob',
  username: 'Bob',
  role: MemberRole.writer,
  joinedAt: DateTime.now().toUtc(),
);

// --- Identity ---
final testIdentity = IdentityModel(
  peerId: 'peer-admin',
  publicKey: 'pk-admin',
  privateKey: 'sk-admin',
  mnemonic12: 'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
  mlKemPublicKey: 'mlkem-pk-admin',
  username: 'Admin',
  createdAt: DateTime.now().toUtc().toIso8601String(),
  updatedAt: DateTime.now().toUtc().toIso8601String(),
);
```

**FakeIdentityRepository** (inline in test files):
```dart
class FakeIdentityRepository implements IdentityRepository {
  IdentityModel? identity;
  FakeIdentityRepository({this.identity});

  @override
  Future<IdentityModel?> loadIdentity() async => identity;

  @override
  Future<void> saveIdentity(IdentityModel identity) async {
    this.identity = identity;
  }
}
```

---

## buildTestWidget Helpers

### ContactPickerScreen tests:
```dart
Widget buildTestWidget({
  List<ContactModel> contacts = const [],
  bool isInviting = false,
  ValueChanged<ContactModel>? onSelect,
  VoidCallback? onBack,
}) {
  return MaterialApp(
    home: ContactPickerScreen(
      contacts: contacts,
      isInviting: isInviting,
      onSelect: onSelect ?? (_) {},
      onBack: onBack ?? () {},
    ),
  );
}
```

### ContactPickerWired tests:
```dart
Widget buildWiredTestWidget({
  required InMemoryGroupRepository groupRepo,
  required InMemoryContactRepository contactRepo,
  FakeBridge? bridge,
  FakeIdentityRepository? identityRepo,
  String groupId = 'group-1',
}) {
  return MaterialApp(
    home: Scaffold(
      body: ContactPickerWired(
        groupId: groupId,
        groupRepo: groupRepo,
        contactRepo: contactRepo,
        bridge: bridge ?? FakeBridge(),
        identityRepo: identityRepo ??
            FakeIdentityRepository(identity: testIdentity),
      ),
    ),
  );
}
```

---

## Callback Flow Summary

```
GroupInfoScreen
  onAddMember: VoidCallback?
    |
    v  (GroupInfoWired)
  Navigator.push -> ContactPickerWired
    |
    v  (loads contacts, filters members)
  ContactPickerScreen
    onSelect: ValueChanged<ContactModel>
      |
      v  (ContactPickerWired)
    showConfirmationDialog(title: 'Invite ${contact.username}?')
      |  confirmed
      v
    addGroupMember(use case)
      |  success
      v
    Navigator.pop(true)
      |
      v  (GroupInfoWired)
    _loadMembers()  // refresh
    SnackBar('Member invited')
```

---

## Contact Filtering Logic

```dart
Future<void> _loadAvailableContacts() async {
  // 1. Get all non-archived, non-blocked contacts
  final allContacts = await widget.contactRepo.getActiveContacts();

  // 2. Get current group members
  final members = await widget.groupRepo.getMembers(widget.groupId);
  final memberPeerIds = members.map((m) => m.peerId).toSet();

  // 3. Get own peerId to exclude self
  final identity = await widget.identityRepo.loadIdentity();
  if (identity != null) {
    memberPeerIds.add(identity.peerId);
  }

  // 4. Filter: only contacts NOT already in the group
  if (!mounted) return;
  setState(() {
    _availableContacts = allContacts
        .where((c) => !memberPeerIds.contains(c.peerId))
        .toList()
      ..sort((a, b) => a.username.compareTo(b.username));  // alphabetical
  });
}
```

---

## Execution Order

| Order | Phase | Tests | Files Created/Modified |
|-------|-------|-------|----------------------|
| 1 | ContactPickerRow widget | 2 | `contact_picker_row.dart`, `contact_picker_screen_test.dart` |
| 2 | ContactPickerScreen | 7 | `contact_picker_screen.dart` |
| 3 | GroupInfoScreen "Add Member" button | 3 | `group_info_screen.dart` (mod), `group_info_screen_test.dart` (mod) |
| 4 | ContactPickerWired | 7 | `contact_picker_wired.dart`, `contact_picker_wired_test.dart` |
| 5 | Wire GroupInfoWired | 2 | `group_info_wired.dart` (mod) |
| 6 | DI chain threading | 0 (compile) | `group_conversation_wired.dart` (mod), `group_list_wired.dart` (mod), call sites |
| 7 | Success feedback | 1 | `group_info_wired.dart` (mod) |
| **Total** | | **22 tests** | **4 new, 5+ modified** |

---

## Notes

- **No new use cases needed.** The existing `addGroupMember` use case handles
  the business logic (admin check, save member). The UI layer just needs to
  construct a `GroupMember` from the selected `ContactModel` and call it.

- **Confirmation dialog reuse.** The existing `showConfirmationDialog` uses a
  red/danger gradient for the confirm button. For a non-destructive action like
  "Invite", a blue gradient would be more appropriate. This is a visual
  refinement that can be done in a refactor step by adding an optional
  `confirmColor` parameter to the dialog. For the initial implementation, the
  red styling is acceptable.

- **Blocked contacts.** `getActiveContacts()` already excludes archived
  contacts. However, it does NOT exclude blocked contacts (blocked contacts
  can still be "active"). Consider adding a filter
  `.where((c) => !c.isBlocked)` in `_loadAvailableContacts`. This should be a
  test case if implemented.

- **Key distribution.** The `addGroupMember` use case doc comment says "Key
  distribution happens at a higher level via 1:1 ML-KEM encrypted messages."
  This UI plan does not address key distribution -- that is a separate concern
  handled outside the UI layer.

- **The contact picker could be reused** for future features (e.g., forwarding
  a message, creating a group with initial members). Placing it in the groups
  feature for now, but it could be extracted to a shared location later.
