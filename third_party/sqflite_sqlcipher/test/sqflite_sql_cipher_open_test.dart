import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

const channel = MethodChannel('com.davidmartos96.sqflite_sqlcipher');

class MockMethodCall {
  String? expectedMethod;
  dynamic expectedArguments;
  dynamic response;

  @override
  String toString() => '$expectedMethod $expectedArguments $response';
}

class MockScenario {
  MockScenario(List<List> data) {
    methodsCalls = data
        .map((list) => MockMethodCall()
          ..expectedMethod = list[0]?.toString()
          ..expectedArguments = list[1]
          ..response = list[2])
        .toList(growable: false);
  }

  late List<MockMethodCall> methodsCalls;
  var index = 0;
  dynamic exception;

  void end() {
    expect(exception, isNull, reason: '$exception');
    expect(index, methodsCalls.length);
  }
}

MockScenario startScenario(List<List> data) {
  final scenario = MockScenario(data);

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,
      (MethodCall methodCall) async {
    final index = scenario.index++;
    // devPrint('$index ${scenario.methodsCalls[index]}');
    final item = scenario.methodsCalls[index];
    try {
      expect(methodCall.method, item.expectedMethod);
      expect(methodCall.arguments, item.expectedArguments);
    } catch (e) {
      scenario.exception ??= '$e $index';
    }
    return item.response;
  });
  return scenario;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('sqflite_sql_cipher', () {
    test('open no password', () async {
      final scenario = startScenario([
        [
          'openDatabase',
          {'path': ':memory:', 'singleInstance': false},
          1
        ],
        [
          'closeDatabase',
          {'id': 1},
          null
        ],
      ]);
      final db = await openDatabase(inMemoryDatabasePath);
      await db.close();
      scenario.end();
    });
    test('passes the native transaction ID through subsequent calls', () async {
      const timeout = Duration(seconds: 2);
      final scenario = startScenario([
        [
          'openDatabase',
          {'path': ':memory:', 'singleInstance': false},
          1,
        ],
        [
          'execute',
          {
            'sql': 'BEGIN IMMEDIATE',
            'id': 1,
            'transactionId': null,
            'inTransaction': true,
          },
          {'transactionId': 7},
        ],
        [
          'insert',
          {
            'sql': 'INSERT INTO marker VALUES (?)',
            'arguments': [1],
            'id': 1,
            'transactionId': 7,
          },
          1,
        ],
        [
          'execute',
          {
            'sql': 'COMMIT',
            'id': 1,
            'transactionId': 7,
            'inTransaction': false,
          },
          null,
        ],
        [
          'closeDatabase',
          {'id': 1},
          null,
        ],
      ]);
      final db = await openDatabase(inMemoryDatabasePath).timeout(timeout);
      try {
        await db.transaction((txn) async {
          final rowId = await txn
              .rawInsert('INSERT INTO marker VALUES (?)', [1])
              .timeout(timeout);
          expect(rowId, 1);
        }).timeout(timeout);
      } finally {
        await db.close().timeout(timeout);
      }
      scenario.end();
    });
    test('open with version and password', () async {
      final scenario = startScenario([
        [
          'openDatabase',
          {'path': ':memory:', 'singleInstance': false, 'password': 'my_password'},
          1
        ],
        [
          'query',
          {'sql': 'PRAGMA user_version', 'id': 1},
          {}
        ],
        [
          'execute',
          {'sql': 'BEGIN EXCLUSIVE', 'id': 1, 'transactionId': null, 'inTransaction': true},
          null
        ],
        [
          'query',
          {'sql': 'PRAGMA user_version', 'id': 1},
          {}
        ],
        [
          'execute',
          {'sql': 'PRAGMA user_version = 1', 'id': 1},
          null
        ],
        [
          'execute',
          {'sql': 'COMMIT', 'id': 1, 'inTransaction': false},
          null
        ],
        [
          'closeDatabase',
          {'id': 1},
          null
        ],
      ]);
      final db =
          await openDatabase(inMemoryDatabasePath, password: 'my_password', version: 1, onCreate: (db, version) {});
      await db.close();
      scenario.end();
    });
  });
}
