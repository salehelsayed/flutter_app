# Task Prompt: FL_XS_15 - Startup Routing

## Instructions for AI Agent

You are implementing a specific task for a Flutter/JS application. Follow the task specification exactly. Output complete, working code that can be directly used.

---

## Global Context

```
Milestone: M1 – Identity Initialization (First Run)

App Startup Behavior:
  - If DB has identity row → go directly to main app
  - If DB has no identity → show IdentityChoiceScreen (onboarding)

Existing components:
  - decideStartupRoute(): Returns StartupDecision enum
  - StartupDecision: { hasIdentity, needsIdentity }
  - IdentityChoiceWired: Onboarding screen
  - IdentityRepository: For checking identity existence
```

---

## Task Definition

```
[TASK FL_XS_15 – Startup routing to main vs onboarding]

Owner: Flutter

Goal:
  Use decideStartupRoute() to route from app startup to either main app or 
  IdentityChoice screen.

What to implement:
  - StartupRouter widget that:
      - On initialization, calls decideStartupRoute(repo)
      - Shows loading indicator while deciding
      - If hasIdentity → navigate to main app screen
      - If needsIdentity → navigate to IdentityChoiceWired screen
      - Uses pushReplacement to prevent back navigation to splash

Inputs:
  - IdentityRepository repo
  - JsBridgeClient (to pass to IdentityChoiceWired)
  - decideStartupRoute() function
  - Navigation context

Outputs:
  - On app start:
      - User lands in main app (if identity exists)
      - Or sees IdentityChoiceWired (if no identity)
  - Side-effects: navigation, transient loading state

Flow_events:
  - When startup routing begins:
      - layer: "FL"
      - event: "ID_STARTUP_FLOW_BEGIN"
      - details: { }
  - After receiving hasIdentity and routing to main:
      - layer: "FL"
      - event: "ID_STARTUP_ROUTE_MAIN"
      - details: { }
  - After receiving needsIdentity and routing to onboarding:
      - layer: "FL"
      - event: "ID_STARTUP_ROUTE_ONBOARDING"
      - details: { }

Constraints:
  - No identity generation/restore logic here; just routing
  - Use pushReplacement for clean navigation stack
  - Handle potential errors (show error screen or retry)

Deliverable:
  - StartupRouter widget for app initialization
```

---

## Output Requirements

1. **File:** `lib/features/identity/presentation/startup_router.dart`

2. **Must include:**
   - StatefulWidget with initialization logic
   - Loading indicator while checking
   - Navigation based on decision
   - Flow event emissions
   - Error handling

3. **Widget structure:**
```dart
class StartupRouter extends StatefulWidget {
  final IdentityRepository repository;
  final JsBridgeClient bridgeClient;

  const StartupRouter({
    super.key,
    required this.repository,
    required this.bridgeClient,
  });

  @override
  State<StartupRouter> createState() => _StartupRouterState();
}

class _StartupRouterState extends State<StartupRouter> {
  @override
  void initState() {
    super.initState();
    _routeBasedOnIdentity();
  }

  Future<void> _routeBasedOnIdentity() async {
    emitFlowEvent(
      layer: 'FL',
      event: 'ID_STARTUP_FLOW_BEGIN',
      details: {},
    );

    try {
      final decision = await decideStartupRoute(widget.repository);
      
      if (!mounted) return;

      switch (decision) {
        case StartupDecision.hasIdentity:
          emitFlowEvent(...);
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => MainAppScreen()),
          );
          break;
        case StartupDecision.needsIdentity:
          emitFlowEvent(...);
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => IdentityChoiceWired(
                repository: widget.repository,
                bridgeClient: widget.bridgeClient,
              ),
            ),
          );
          break;
      }
    } catch (e) {
      // Handle error - show error UI or retry
    }
  }

  @override
  Widget build(BuildContext context) {
    // Loading/splash screen
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock, size: 64),
            SizedBox(height: 24),
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading...'),
          ],
        ),
      ),
    );
  }
}
```

4. **MainAppScreen placeholder:**

For now, create a simple placeholder:
```dart
class MainAppScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Main App')),
      body: Center(child: Text('Welcome! Identity loaded.')),
    );
  }
}
```

---

## Flow Event Helper

Assume this helper exists:

```dart
void emitFlowEvent({
  required String layer,
  required String event,
  required Map<String, dynamic> details,
}) {
  print('[FLOW] $layer | $event | $details');
}
```

---

## Required Imports

```dart
import 'package:flutter/material.dart';
import '../application/startup_decision.dart';
import '../domain/repositories/identity_repository.dart';
import 'screens/identity_choice_wired.dart';
import '../../../../core/bridge/js_bridge_client.dart';
```

---

## Integration with main.dart

The StartupRouter should be used in main.dart like this:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize database
  final db = await openDatabase('app.db');
  await runIdentityTableMigration(db);
  
  // Create dependencies
  final repository = IdentityRepositoryImpl(
    dbLoadIdentityRow: () => dbLoadIdentityRow(db),
    dbUpsertIdentityRow: (row) => dbUpsertIdentityRow(db, row),
  );
  final bridgeClient = JsBridgeClient(JsBridgeImpl());
  
  runApp(MaterialApp(
    home: StartupRouter(
      repository: repository,
      bridgeClient: bridgeClient,
    ),
  ));
}
```

---

## Begin Implementation

Implement the complete router widget now. Output the full code for `startup_router.dart`, including a placeholder `MainAppScreen`.
