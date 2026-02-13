/// Smoke test for messages database layer.
/// Run with: flutter run -t lib/smoke_test_messages.dart
///
/// Opens database, runs migrations, inserts messages, queries, verifies round-trip.

import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/migrations/002_messages_table.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  print('\n========================================');
  print('SMOKE TEST: Messages Database Layer');
  print('========================================\n');

  try {
    // Initialize FFI for desktop
    if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    // Step 1: Open database with both migrations
    print('[SMOKE] Step 1: Initialize database...');
    final db = await openDatabase(
      'smoke_test_messages.db',
      version: 2,
      onCreate: (db, version) async {
        await runIdentityTableMigration(db);
        await runMessagesTableMigration(db);
      },
    );
    print('[SMOKE] Database initialized');

    // Step 2: Verify table exists
    print('[SMOKE] Step 2: Verify messages table exists...');
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='messages'",
    );
    assert(tables.isNotEmpty, 'messages table not found');
    print('[SMOKE] PASS: messages table exists');

    // Step 3: Insert a message
    print('[SMOKE] Step 3: Insert test message...');
    final row = {
      'id': 'smoke-msg-001',
      'contact_peer_id': '12D3KooWSmokeContact',
      'sender_peer_id': '12D3KooWSmokeSender',
      'text': 'Hello from smoke test!',
      'timestamp': '2026-02-09T15:30:00.000Z',
      'status': 'sent',
      'is_incoming': 0,
      'created_at': '2026-02-09T15:30:01.000Z',
    };
    await dbInsertMessage(db, row);
    print('[SMOKE] PASS: Message inserted');

    // Step 4: Insert a second message for the same contact
    print('[SMOKE] Step 4: Insert second message...');
    final row2 = {
      'id': 'smoke-msg-002',
      'contact_peer_id': '12D3KooWSmokeContact',
      'sender_peer_id': '12D3KooWSmokeContact',
      'text': 'Reply from contact!',
      'timestamp': '2026-02-09T15:31:00.000Z',
      'status': 'delivered',
      'is_incoming': 1,
      'created_at': '2026-02-09T15:31:01.000Z',
    };
    await dbInsertMessage(db, row2);
    print('[SMOKE] PASS: Second message inserted');

    // Step 5: Load messages for contact
    print('[SMOKE] Step 5: Load messages for contact...');
    final messages =
        await dbLoadMessagesForContact(db, '12D3KooWSmokeContact');
    assert(messages.length == 2, 'Expected 2 messages, got ${messages.length}');
    assert(messages[0]['id'] == 'smoke-msg-001', 'First message should be msg-001 (ASC order)');
    assert(messages[1]['id'] == 'smoke-msg-002', 'Second message should be msg-002 (ASC order)');
    print('[SMOKE] PASS: ${messages.length} messages loaded in correct order');

    // Step 6: Load latest message
    print('[SMOKE] Step 6: Load latest message...');
    final latest =
        await dbLoadLatestMessageForContact(db, '12D3KooWSmokeContact');
    assert(latest != null, 'Latest message should not be null');
    assert(latest!['id'] == 'smoke-msg-002', 'Latest should be msg-002');
    print('[SMOKE] PASS: Latest message is ${latest['id']}');

    // Step 7: Update status
    print('[SMOKE] Step 7: Update message status...');
    await dbUpdateMessageStatus(db, 'smoke-msg-001', 'delivered');
    final updated = await dbLoadMessage(db, 'smoke-msg-001');
    assert(updated != null, 'Updated message should exist');
    assert(updated!['status'] == 'delivered', 'Status should be delivered');
    print('[SMOKE] PASS: Status updated to ${updated['status']}');

    // Step 8: Get message count
    print('[SMOKE] Step 8: Get message count...');
    final count = await dbGetMessageCount(db);
    assert(count == 2, 'Expected count 2, got $count');
    print('[SMOKE] PASS: Count is $count');

    // Step 9: Load single message
    print('[SMOKE] Step 9: Load single message by ID...');
    final single = await dbLoadMessage(db, 'smoke-msg-001');
    assert(single != null, 'Should find message by ID');
    assert(single!['text'] == 'Hello from smoke test!', 'Text should match');
    print('[SMOKE] PASS: Loaded message with text: "${single['text']}"');

    // Step 10: Load non-existent
    print('[SMOKE] Step 10: Load non-existent message...');
    final notFound = await dbLoadMessage(db, 'nonexistent');
    assert(notFound == null, 'Should return null for missing ID');
    print('[SMOKE] PASS: Non-existent returns null');

    // Cleanup
    await db.close();

    print('\n========================================');
    print('ALL SMOKE TESTS PASSED');
    print('========================================\n');
  } catch (e, stack) {
    print('\n========================================');
    print('SMOKE TEST FAILED:');
    print('========================================');
    print('Error: $e');
    print('Stack: $stack');
  }

  runApp(const _SmokeTestApp());
}

class _SmokeTestApp extends StatelessWidget {
  const _SmokeTestApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Messages DB Smoke Test'),
          backgroundColor: Colors.green,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 100),
              SizedBox(height: 20),
              Text(
                'Check console logs',
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
