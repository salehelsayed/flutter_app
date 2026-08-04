package com.davidmartos96.sqflite_sqlcipher;

import android.content.Context;
import android.database.Cursor;

import android.database.SQLException;
import android.database.sqlite.SQLiteCantOpenDatabaseException;
import android.database.sqlite.SQLiteException;
import android.os.Handler;
import android.os.Looper;
import android.os.Process;
import android.util.Log;

import com.davidmartos96.sqflite_sqlcipher.dev.Debug;
import com.davidmartos96.sqflite_sqlcipher.operation.BatchOperation;
import com.davidmartos96.sqflite_sqlcipher.operation.ExecuteOperation;
import com.davidmartos96.sqflite_sqlcipher.operation.MethodCallOperation;
import com.davidmartos96.sqflite_sqlcipher.operation.Operation;
import com.davidmartos96.sqflite_sqlcipher.operation.SqlErrorInfo;

import java.io.File;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

import static com.davidmartos96.sqflite_sqlcipher.Constant.CMD_GET;
import static com.davidmartos96.sqflite_sqlcipher.Constant.ERROR_BAD_PARAM;
import static com.davidmartos96.sqflite_sqlcipher.Constant.MEMORY_DATABASE_PATH;
import static com.davidmartos96.sqflite_sqlcipher.Constant.METHOD_BATCH;
import static com.davidmartos96.sqflite_sqlcipher.Constant.METHOD_CLOSE_DATABASE;
import static com.davidmartos96.sqflite_sqlcipher.Constant.METHOD_DEBUG;
import static com.davidmartos96.sqflite_sqlcipher.Constant.METHOD_DEBUG_MODE;
import static com.davidmartos96.sqflite_sqlcipher.Constant.METHOD_DELETE_DATABASE;
import static com.davidmartos96.sqflite_sqlcipher.Constant.METHOD_EXECUTE;
import static com.davidmartos96.sqflite_sqlcipher.Constant.METHOD_GET_DATABASES_PATH;
import static com.davidmartos96.sqflite_sqlcipher.Constant.METHOD_GET_PLATFORM_VERSION;
import static com.davidmartos96.sqflite_sqlcipher.Constant.METHOD_INSERT;
import static com.davidmartos96.sqflite_sqlcipher.Constant.METHOD_OPEN_DATABASE;
import static com.davidmartos96.sqflite_sqlcipher.Constant.METHOD_OPTIONS;
import static com.davidmartos96.sqflite_sqlcipher.Constant.METHOD_QUERY;
import static com.davidmartos96.sqflite_sqlcipher.Constant.METHOD_UPDATE;
import static com.davidmartos96.sqflite_sqlcipher.Constant.PARAM_CMD;
import static com.davidmartos96.sqflite_sqlcipher.Constant.PARAM_ID;
import static com.davidmartos96.sqflite_sqlcipher.Constant.PARAM_IN_TRANSACTION;
import static com.davidmartos96.sqflite_sqlcipher.Constant.PARAM_LOG_LEVEL;
import static com.davidmartos96.sqflite_sqlcipher.Constant.PARAM_OPERATIONS;
import static com.davidmartos96.sqflite_sqlcipher.Constant.PARAM_PASSWORD;
import static com.davidmartos96.sqflite_sqlcipher.Constant.PARAM_PATH;
import static com.davidmartos96.sqflite_sqlcipher.Constant.PARAM_READ_ONLY;
import static com.davidmartos96.sqflite_sqlcipher.Constant.PARAM_RECOVERED;
import static com.davidmartos96.sqflite_sqlcipher.Constant.PARAM_RECOVERED_IN_TRANSACTION;
import static com.davidmartos96.sqflite_sqlcipher.Constant.PARAM_SINGLE_INSTANCE;
import static com.davidmartos96.sqflite_sqlcipher.Constant.PARAM_SQL;
import static com.davidmartos96.sqflite_sqlcipher.Constant.PARAM_SQL_ARGUMENTS;
import static com.davidmartos96.sqflite_sqlcipher.Constant.TAG;

import net.zetetic.database.sqlcipher.SQLiteDatabase;

/**
 * SqfliteSqlCipherPlugin Android implementation
 */
public class SqfliteSqlCipherPlugin implements FlutterPlugin, MethodCallHandler {

    private volatile boolean queryAsMapList = false;
    private volatile boolean extraLogVerbose = false;
    private volatile int threadPriority = Process.THREAD_PRIORITY_BACKGROUND;
    private volatile int logLevel = LogLevel.none;
    private String databasesPath;
    private Context context;
    private MethodChannel methodChannel;
    private volatile EngineState<Database> engineState;


    @Override
    public void onAttachedToEngine(FlutterPluginBinding binding) {
        onAttachedToEngine(binding.getApplicationContext(), binding.getBinaryMessenger());
    }

    private void onAttachedToEngine(Context applicationContext, BinaryMessenger messenger) {
        this.context = applicationContext;
        this.engineState = createEngineState();
        System.loadLibrary("sqlcipher");
        methodChannel = new MethodChannel(messenger, Constant.PLUGIN_KEY);
        methodChannel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(FlutterPluginBinding binding) {
        if (methodChannel != null) {
            methodChannel.setMethodCallHandler(null);
        }
        methodChannel = null;
        EngineState<Database> state = engineState;
        if (state != null) {
            state.detach(this::closeDatabaseHandle);
        }
        engineState = null;
        context = null;
    }

    EngineState<Database> createEngineState() {
        return new EngineState<>(
                new HandlerThreadEngineWorker(() -> threadPriority));
    }

    /** Aggregate H0 diagnostics without paths, keys, ids, or message content. */
    public static Map<String, Object> getDebugCensus() {
        return EngineDebugCensus.snapshot();
    }

    private static Object cursorValue(Cursor cursor, int index) {
        switch (cursor.getType(index)) {
            case Cursor.FIELD_TYPE_NULL:
                return null;
            case Cursor.FIELD_TYPE_INTEGER:
                return cursor.getLong(index);
            case Cursor.FIELD_TYPE_FLOAT:
                return cursor.getDouble(index);
            case Cursor.FIELD_TYPE_STRING:
                return cursor.getString(index);
            case Cursor.FIELD_TYPE_BLOB:
                return cursor.getBlob(index);
        }
        return null;
    }

    private List<Object> cursorRowToList(Cursor cursor, int length) {
        List<Object> list = new ArrayList<>(length);

        for (int i = 0; i < length; i++) {
            Object value = cursorValue(cursor, i);
            if (extraLogVerbose) {
                String type = null;
                if (value != null) {
                    if (value.getClass().isArray()) {
                        type = "array(" + value.getClass().getComponentType().getName() + ")";
                    } else {
                        type = value.getClass().getName();
                    }
                }
                Log.d(TAG, "column " + i + " " + cursor.getType(i) + ": " + value + (type == null ? "" : " (" + type + ")"));
            }
            list.add(value);
        }
        return list;
    }

    private Map<String, Object> cursorRowToMap(Cursor cursor) {
        Map<String, Object> map = new HashMap<>();
        String[] columns = cursor.getColumnNames();
        int length = columns.length;
        for (int i = 0; i < length; i++) {
            if (extraLogVerbose) {
                Log.d(TAG, "column " + i + " " + cursor.getType(i));
            }
            switch (cursor.getType(i)) {
                case Cursor.FIELD_TYPE_NULL:
                    map.put(columns[i], null);
                    break;
                case Cursor.FIELD_TYPE_INTEGER:
                    map.put(columns[i], cursor.getLong(i));
                    break;
                case Cursor.FIELD_TYPE_FLOAT:
                    map.put(columns[i], cursor.getDouble(i));
                    break;
                case Cursor.FIELD_TYPE_STRING:
                    map.put(columns[i], cursor.getString(i));
                    break;
                case Cursor.FIELD_TYPE_BLOB:
                    map.put(columns[i], cursor.getBlob(i));
                    break;
            }
        }
        return map;
    }

    static private Map<String, Object> fixMap(Map<Object, Object> map) {
        Map<String, Object> newMap = new HashMap<>();
        for (Map.Entry<Object, Object> entry : map.entrySet()) {
            Object value = entry.getValue();
            if (value instanceof Map) {
                @SuppressWarnings("unchecked")
                Map<Object, Object> mapValue = (Map<Object, Object>) value;
                value = fixMap(mapValue);
            } else {
                value = toString(value);
            }
            newMap.put(toString(entry.getKey()), value);
        }
        return newMap;
    }

    // Convert a value to a string
    // especially byte[]
    static private String toString(Object value) {
        if (value == null) {
            return null;
        } else if (value instanceof byte[]) {
            List<Integer> list = new ArrayList<>();
            for (byte _byte : (byte[]) value) {
                list.add((int) _byte);
            }
            return list.toString();
        } else if (value instanceof Map) {
            @SuppressWarnings("unchecked")
            Map<Object, Object> mapValue = (Map<Object, Object>) value;
            return fixMap(mapValue).toString();
        } else {
            return value.toString();
        }
    }

    static boolean isInMemoryPath(String path) {
        return (path == null || path.equals(MEMORY_DATABASE_PATH));
    }

    private Context getContext() {
        return context;
    }

    private EngineState<Database> captureEngineStateForAsyncCall() {
        EngineState<Database> state = engineState;
        if (state == null) {
            EngineDebugCensus.resultSuppressed();
        }
        return state;
    }

    private Database getDatabase(EngineState<Database> state, int databaseId) {
        return state.getHandle(databaseId);
    }

    private Database getDatabaseOrError(
            EngineState<Database> state,
            MethodCall call,
            Result result) {
        int databaseId = call.argument(PARAM_ID);
        Database database = getDatabase(state, databaseId);

        if (database != null) {
            return database;
        } else {
            result.error(Constant.SQLITE_ERROR, Constant.ERROR_DATABASE_CLOSED + " " + databaseId, null);
            return null;
        }
    }

    private SqlCommand getSqlCommand(MethodCall call) {
        String sql = call.argument(PARAM_SQL);
        List<Object> arguments = call.argument(PARAM_SQL_ARGUMENTS);
        return new SqlCommand(sql, arguments);
    }

    private Database executeOrError(Database database, MethodCall call, Result result) {
        SqlCommand command = getSqlCommand(call);
        Boolean inTransaction = call.argument(PARAM_IN_TRANSACTION);

        Operation operation = new ExecuteOperation(result, command, inTransaction);
        if (executeOrError(database, operation)) {
            return database;
        }
        return null;
    }

    // Called during batch, warning duplicated code!
    private boolean executeOrError(Database database, Operation operation) {
        SqlCommand command = operation.getSqlCommand();
        if (LogLevel.hasSqlLevel(database.logLevel)) {
            Log.d(TAG, database.getThreadLogPrefix() + command);
        }
        Boolean inTransaction = operation.getInTransaction();

        try {
            database.getWritableDatabase().execSQL(command.getSql(), command.getSqlArguments());

            // Success handle inTransaction change
            if (Boolean.TRUE.equals(inTransaction)) {
                database.inTransaction = true;
            }
            return true;
        } catch (Exception exception) {
            handleException(exception, operation, database);
            return false;
        } finally {
            // failure? ignore for false
            if (Boolean.FALSE.equals(inTransaction)) {
                database.inTransaction = false;
            }

        }
    }

    //
    // query
    //
    private void onQueryCall(final MethodCall call, Result result) {
        final EngineState<Database> state = captureEngineStateForAsyncCall();
        if (state == null) {
            return;
        }
        final BgResult bgResult = new BgResult(result, state);
        if (!state.post(() -> {
            Database database = getDatabaseOrError(state, call, bgResult);
            if (database == null) {
                return;
            }
            MethodCallOperation operation = new MethodCallOperation(call, bgResult);
            query(database, operation);
        })) {
            bgResult.suppress();
        }
    }

    //
    // Sqflite.batch
    //
    private void onBatchCall(final MethodCall call, Result result) {
        final EngineState<Database> state = captureEngineStateForAsyncCall();
        if (state == null) {
            return;
        }
        final BgResult bgResult = new BgResult(result, state);
        if (!state.post(() -> {
                Database database = getDatabaseOrError(state, call, bgResult);
                if (database == null) {
                    return;
                }

                MethodCallOperation mainOperation = new MethodCallOperation(call, bgResult);
                boolean noResult = mainOperation.getNoResult();
                boolean continueOnError = mainOperation.getContinueOnError();

                List<Map<String, Object>> operations = call.argument(PARAM_OPERATIONS);
                List<Map<String, Object>> results = new ArrayList<>();

                //devLog(TAG, "operations " + operations);
                for (Map<String, Object> map : operations) {
                    //devLog(TAG, "map " + map);
                    BatchOperation operation = new BatchOperation(map, noResult);
                    String method = operation.getMethod();
                    switch (method) {
                        case METHOD_EXECUTE:
                            if (execute(database, operation)) {
                                //devLog(TAG, "results: " + operation.getBatchResults());
                                operation.handleSuccess(results);
                            } else if (continueOnError) {
                                operation.handleErrorContinue(results);
                            } else {
                                // we stop at the first error
                                operation.handleError(bgResult);
                                return;
                            }
                            break;
                        case METHOD_INSERT:
                            if (insert(database, operation)) {
                                //devLog(TAG, "results: " + operation.getBatchResults());
                                operation.handleSuccess(results);
                            } else if (continueOnError) {
                                operation.handleErrorContinue(results);
                            } else {
                                // we stop at the first error
                                operation.handleError(bgResult);
                                return;
                            }
                            break;
                        case METHOD_QUERY:
                            if (query(database, operation)) {
                                //devLog(TAG, "results: " + operation.getBatchResults());
                                operation.handleSuccess(results);
                            } else if (continueOnError) {
                                operation.handleErrorContinue(results);
                            } else {
                                // we stop at the first error
                                operation.handleError(bgResult);
                                return;
                            }
                            break;
                        case METHOD_UPDATE:
                            if (update(database, operation)) {
                                //devLog(TAG, "results: " + operation.getBatchResults());
                                operation.handleSuccess(results);
                            } else if (continueOnError) {
                                operation.handleErrorContinue(results);
                            } else {
                                // we stop at the first error
                                operation.handleError(bgResult);
                                return;
                            }
                            break;
                        default:
                            bgResult.error(ERROR_BAD_PARAM, "Batch method '" + method + "' not supported", null);
                            return;
                    }
                }
                // Set the results of all operations
                // devLog(TAG, "results " + results);
                if (noResult) {
                    bgResult.success(null);
                } else {
                    bgResult.success(results);
                }
        })) {
            bgResult.suppress();
        }
    }

    // Return true on success
    private boolean execute(Database database, final Operation operation) {
        if (!executeOrError(database, operation)) {
            return false;
        }
        operation.success(null);
        return true;
    }

    // Return true on success
    private boolean insert(Database database, final Operation operation) {
        if (!executeOrError(database, operation)) {
            return false;
        }
        // don't get last id if not expected
        if (operation.getNoResult()) {
            operation.success(null);
            return true;
        }

        Cursor cursor = null;
        // Read both the changes and last insert row id in on sql call
        String sql = "SELECT changes(), last_insert_rowid()";

        // Handle ON CONFLICT but ignore error, issue #164
        // Read the number of changes before getting the inserted id
        try {
            SQLiteDatabase db = database.getWritableDatabase();

            cursor = db.rawQuery(sql, null);
            if (cursor != null && cursor.getCount() > 0 && cursor.moveToFirst()) {
                final int changed = cursor.getInt(0);

                // If the change count is 0, assume the insert failed
                // and return null
                if (changed == 0) {
                    if (LogLevel.hasSqlLevel(database.logLevel)) {
                        Log.d(TAG, database.getThreadLogPrefix() + "no changes (id was " + cursor.getLong(1) + ")");
                    }
                    operation.success(null);
                    return true;
                } else {
                    final long id = cursor.getLong(1);
                    if (LogLevel.hasSqlLevel(database.logLevel)) {
                        Log.d(TAG, database.getThreadLogPrefix() + "inserted " + id);
                    }
                    operation.success(id);
                    return true;
                }
            } else {
                Log.e(TAG, database.getThreadLogPrefix() + "fail to read changes for Insert");
            }
            operation.success(null);
            return true;
        } catch (Exception exception) {
            handleException(exception, operation, database);
            return false;
        } finally {
            if (cursor != null) {
                cursor.close();
            }
        }
    }

    // Return true on success
    private boolean query(Database database, final Operation operation) {
        SqlCommand command = operation.getSqlCommand();

        List<Map<String, Object>> results = new ArrayList<>();
        Map<String, Object> newResults = null;
        List<List<Object>> rows = null;
        int newColumnCount = 0;
        if (LogLevel.hasSqlLevel(database.logLevel)) {
            Log.d(TAG, database.getThreadLogPrefix() + command);
        }
        Cursor cursor = null;
        boolean queryAsMapList = this.queryAsMapList;
        try {
            // For query we sanitize as it only takes String which does not work
            // for references. Simply embed the int/long into the query itself
            command = command.sanitizeForQuery();

            cursor = database.getReadableDatabase().rawQuery(command.getSql(), command.getQuerySqlArguments());
            while (cursor.moveToNext()) {
                if (queryAsMapList) {
                    Map<String, Object> map = cursorRowToMap(cursor);
                    if (LogLevel.hasSqlLevel(database.logLevel)) {
                        Log.d(TAG, database.getThreadLogPrefix() + SqfliteSqlCipherPlugin.toString(map));
                    }
                    results.add(map);
                } else {
                    if (newResults == null) {
                        rows = new ArrayList<>();
                        newResults = new HashMap<>();
                        newColumnCount = cursor.getColumnCount();
                        newResults.put("columns", Arrays.asList(cursor.getColumnNames()));
                        newResults.put("rows", rows);
                    }
                    rows.add(cursorRowToList(cursor, newColumnCount));
                }
            }
            if (queryAsMapList) {
                operation.success(results);
            } else {
                // Handle empty
                if (newResults == null) {
                    newResults = new HashMap<>();
                }
                operation.success(newResults);
            }
            return true;

        } catch (Exception exception) {
            handleException(exception, operation, database);
            return false;
        } finally {
            if (cursor != null) {
                cursor.close();
            }
        }
    }

    //
    // Insert
    //
    private void onInsertCall(final MethodCall call, Result result) {
        final EngineState<Database> state = captureEngineStateForAsyncCall();
        if (state == null) {
            return;
        }
        final BgResult bgResult = new BgResult(result, state);
        if (!state.post(() -> {
            Database database = getDatabaseOrError(state, call, bgResult);
            if (database == null) {
                return;
            }
            MethodCallOperation operation = new MethodCallOperation(call, bgResult);
            insert(database, operation);
        })) {
            bgResult.suppress();
        }
    }

    //
    // Sqflite.execute
    //
    private void onExecuteCall(final MethodCall call, Result result) {
        final EngineState<Database> state = captureEngineStateForAsyncCall();
        if (state == null) {
            return;
        }
        final BgResult bgResult = new BgResult(result, state);
        if (!state.post(() -> {
            Database database = getDatabaseOrError(state, call, bgResult);
            if (database == null) {
                return;
            }
            if (executeOrError(database, call, bgResult) == null) {
                return;
            }
            bgResult.success(null);
        })) {
            bgResult.suppress();
        }
    }

    // Return true on success
    private boolean update(Database database, final Operation operation) {
        if (!executeOrError(database, operation)) {
            return false;
        }
        // don't get last id if not expected
        if (operation.getNoResult()) {
            operation.success(null);
            return true;
        }
        Cursor cursor = null;
        try {
            SQLiteDatabase db = database.getWritableDatabase();

            cursor = db.rawQuery("SELECT changes()", null);
            if (cursor != null && cursor.getCount() > 0 && cursor.moveToFirst()) {
                final int changed = cursor.getInt(0);
                if (LogLevel.hasSqlLevel(database.logLevel)) {
                    Log.d(TAG, database.getThreadLogPrefix() + "changed " + changed);
                }
                operation.success(changed);
                return true;
            } else {
                Log.e(TAG, database.getThreadLogPrefix() + "fail to read changes for Update/Delete");
            }
            operation.success(null);
            return true;
        } catch (Exception e) {
            handleException(e, operation, database);
            return false;
        } finally {
            if (cursor != null) {
                cursor.close();
            }
        }
    }

    //
    // Sqflite.update
    //
    private void onUpdateCall(final MethodCall call, Result result) {
        final EngineState<Database> state = captureEngineStateForAsyncCall();
        if (state == null) {
            return;
        }
        final BgResult bgResult = new BgResult(result, state);
        if (!state.post(() -> {
            Database database = getDatabaseOrError(state, call, bgResult);
            if (database == null) {
                return;
            }
            MethodCallOperation operation = new MethodCallOperation(call, bgResult);
            update(database, operation);
        })) {
            bgResult.suppress();
        }
    }

    private void handleException(Exception exception, Operation operation, Database database) {

        if (exception instanceof SQLiteCantOpenDatabaseException) {
            operation.error(Constant.SQLITE_ERROR, Constant.ERROR_OPEN_FAILED + " " + database.path, null);
            return;
        } else if(exception instanceof SQLiteException) {
            final String message = exception.getMessage();
            if (message != null) {
                final String lower = message.toLowerCase();
                if (lower.contains("could not open database") || lower.contains("file is not a database")) {
                    operation.error(Constant.SQLITE_ERROR, Constant.ERROR_OPEN_FAILED + " " + database.path, null);
                    return;
                }
            }
        }
        operation.error(Constant.SQLITE_ERROR, exception.getMessage(), SqlErrorInfo.getMap(operation));
    }

    // {
    // 'id': xxx
    // 'recovered': true // if recovered only for single instance
    // }
    static Map makeOpenResult(int databaseId, boolean recovered, boolean recoveredInTransaction) {
        Map<String, Object> result = new HashMap<>();
        result.put(PARAM_ID, databaseId);
        if (recovered) {
            result.put(PARAM_RECOVERED, true);
        }
        if (recoveredInTransaction) {
            result.put(PARAM_RECOVERED_IN_TRANSACTION, true);
        }
        return result;
    }

    private void onDebugCall(final MethodCall call, final Result result) {
        String cmd = call.argument(PARAM_CMD);
        Map<String, Object> map = new LinkedHashMap<>();

        if (CMD_GET.equals(cmd)) {
            if (logLevel > LogLevel.none) {
                map.put(PARAM_LOG_LEVEL, logLevel);
            }
            map.put("workerCensus", getDebugCensus());
        }
        result.success(map);
    }


    // Deprecated since 1.1.6
    private void onDebugModeCall(final MethodCall call, final Result result) {
        // Old / argument was just a boolean
        Object on = call.arguments();
        boolean debugLoggingEnabled = Boolean.TRUE.equals(on);
        extraLogVerbose = Debug.EXTRA_LOGV_ENABLED && debugLoggingEnabled;

        // set default logs to match existing
        if (debugLoggingEnabled) {
            if (extraLogVerbose) {
                logLevel = LogLevel.verbose;
            } else {
                logLevel = LogLevel.sql;
            }

        } else {
            logLevel = LogLevel.none;
        }
        result.success(null);
    }

    //
    // Sqflite.open
    //

    private void onOpenDatabaseCall(final MethodCall call, Result result) {
        final String path = call.argument(PARAM_PATH);
        final Boolean readOnly = call.argument(PARAM_READ_ONLY);
        final String password = call.argument(PARAM_PASSWORD);
        final boolean inMemory = isInMemoryPath(path);
        final boolean singleInstance = !Boolean.FALSE.equals(call.argument(PARAM_SINGLE_INSTANCE)) && !inMemory;
        final int openLogLevel = logLevel;
        final EngineState<Database> state = captureEngineStateForAsyncCall();
        if (state == null) {
            return;
        }
        final BgResult bgResult = new BgResult(result, state);

        if (!state.post(() -> {
            final Database[] attemptedDatabase = new Database[1];
            try {
                EngineState.OpenOutcome<Database> outcome = state.openOrReuse(
                        path,
                        singleInstance,
                        databaseId -> {
                            Database database = new Database(
                                    path,
                                    password,
                                    databaseId,
                                    singleInstance,
                                    openLogLevel);
                            attemptedDatabase[0] = database;

                            if (!inMemory) {
                                File directory = new File(path).getParentFile();
                                if (directory != null &&
                                        !directory.exists() &&
                                        !directory.mkdirs() &&
                                        !directory.exists()) {
                                    throw new SQLiteCantOpenDatabaseException(
                                            Constant.ERROR_OPEN_FAILED + " " + path);
                                }
                            }

                            if (Boolean.TRUE.equals(readOnly)) {
                                database.openReadOnly();
                            } else {
                                database.open();
                            }
                            return database;
                        },
                        database -> database.sqliteDatabase != null &&
                                database.sqliteDatabase.isOpen());

                Database database = outcome.handle;
                if (LogLevel.hasSqlLevel(database.logLevel)) {
                    String action = outcome.recovered
                            ? "re-opened single instance "
                            : "opened ";
                    Log.d(
                            TAG,
                            database.getThreadLogPrefix() +
                                    action +
                                    (outcome.recovered && database.inTransaction
                                            ? "(in transaction) "
                                            : "") +
                                    outcome.id + " " + path);
                }
                bgResult.success(makeOpenResult(
                        outcome.id,
                        outcome.recovered,
                        outcome.recovered && database.inTransaction));
            } catch (Exception error) {
                Database database = attemptedDatabase[0];
                if (database == null) {
                    database = new Database(
                            path,
                            password,
                            0,
                            singleInstance,
                            openLogLevel);
                } else if (database.sqliteDatabase != null) {
                    closeDatabaseHandle(database);
                }
                handleException(
                        error,
                        new MethodCallOperation(call, bgResult),
                        database);
            }
        })) {
            bgResult.suppress();
        }
    }

    //
    // Sqflite.close
    //
    private void onCloseDatabaseCall(MethodCall call, Result result) {
        final int databaseId = call.argument(PARAM_ID);
        final EngineState<Database> state = captureEngineStateForAsyncCall();
        if (state == null) {
            return;
        }
        final BgResult bgResult = new BgResult(result, state);
        if (!state.post(() -> {
            Database database = state.removeHandle(databaseId);
            if (database == null) {
                bgResult.error(
                        Constant.SQLITE_ERROR,
                        Constant.ERROR_DATABASE_CLOSED + " " + databaseId,
                        null);
                return;
            }
            if (LogLevel.hasSqlLevel(database.logLevel)) {
                Log.d(
                        TAG,
                        database.getThreadLogPrefix() +
                                "closing " + databaseId + " " + database.path);
            }
            if (!state.closeOwnedHandle(database, this::closeDatabaseHandle)) {
                bgResult.error(
                        Constant.SQLITE_ERROR,
                        "error closing database " + databaseId,
                        null);
                return;
            }
            bgResult.success(null);
        })) {
            bgResult.suppress();
        }
    }

    //
    // Sqflite.open
    //
    private void onDeleteDatabaseCall(final MethodCall call, Result result) {
        final String path = call.argument(PARAM_PATH);
        final EngineState<Database> state = captureEngineStateForAsyncCall();
        if (state == null) {
            return;
        }
        final BgResult bgResult = new BgResult(result, state);
        if (!state.post(() -> {
            boolean allClosed = true;
            for (Database database : state.removeHandlesForPath(path)) {
                if (!state.closeOwnedHandle(database, this::closeDatabaseHandle)) {
                    allClosed = false;
                }
            }
            if (!allClosed) {
                bgResult.error(
                        Constant.SQLITE_ERROR,
                        "error closing database before delete " + path,
                        null);
                return;
            }
            try {
                if (LogLevel.hasVerboseLevel(logLevel)) {
                    Log.d(Constant.TAG, "delete database " + path);
                }
                Database.deleteDatabase(path);
            } catch (Exception error) {
                Log.e(TAG, "error " + error + " while deleting database " + path);
                bgResult.error(
                        Constant.SQLITE_ERROR,
                        "error deleting database " + path,
                        null);
                return;
            }
            bgResult.success(null);
        })) {
            bgResult.suppress();
        }
    }

    private boolean closeDatabaseHandle(Database database) {
        try {
            if (LogLevel.hasSqlLevel(database.logLevel)) {
                Log.d(TAG, database.getThreadLogPrefix() + "closing database");
            }
            if (database.sqliteDatabase != null) {
                database.close();
            }
            return true;
        } catch (Exception error) {
            Log.e(
                    TAG,
                    "error " + error + " while closing database " + database.id);
            return false;
        }
    }

    @Override
    public void onMethodCall(MethodCall call, Result result) {
        switch (call.method) {
            // quick testing
            case METHOD_GET_PLATFORM_VERSION:
                result.success("Android " + android.os.Build.VERSION.RELEASE);
                break;

            case METHOD_CLOSE_DATABASE: {
                onCloseDatabaseCall(call, result);
                break;
            }
            case METHOD_QUERY: {
                onQueryCall(call, result);
                break;
            }
            case METHOD_INSERT: {
                onInsertCall(call, result);
                break;
            }
            case METHOD_UPDATE: {
                onUpdateCall(call, result);
                break;
            }
            case METHOD_EXECUTE: {
                onExecuteCall(call, result);
                break;
            }
            case METHOD_OPEN_DATABASE: {
                onOpenDatabaseCall(call, result);
                break;
            }
            case METHOD_BATCH: {
                onBatchCall(call, result);
                break;
            }
            case METHOD_OPTIONS: {
                onOptionsCall(call, result);
                break;
            }
            case METHOD_GET_DATABASES_PATH: {
                onGetDatabasesPathCall(call, result);
                break;
            }
            case METHOD_DELETE_DATABASE: {
                onDeleteDatabaseCall(call, result);
                break;
            }
            case METHOD_DEBUG: {
                onDebugCall(call, result);
                break;
            }
            // Obsolete
            case METHOD_DEBUG_MODE: {
                onDebugModeCall(call, result);
                break;
            }
            default:
                result.notImplemented();
                break;
        }
    }

    void onOptionsCall(final MethodCall call, Result result) {
        Object paramAsList = call.argument(Constant.PARAM_QUERY_AS_MAP_LIST);
        if (paramAsList != null) {
            queryAsMapList = Boolean.TRUE.equals(paramAsList);
        }
        Object threadPriority = call.argument(Constant.PARAM_THREAD_PRIORITY);
        if (threadPriority != null) {
            this.threadPriority = (Integer) threadPriority;
        }
        Integer logLevel = LogLevel.getLogLevel(call);
        if (logLevel != null) {
            this.logLevel = logLevel;
        }
        result.success(null);
    }

    //private static class Database

    void onGetDatabasesPathCall(final MethodCall call, Result result) {
        if (databasesPath == null) {
            String dummyDatabaseName = "tekartik_sqflite.db";
            File file = context.getDatabasePath(dummyDatabaseName);
            databasesPath = file.getParent();
        }
        result.success(databasesPath);
    }


    private class BgResult implements Result {
        // Caller handler
        final Handler handler = new Handler(Looper.getMainLooper());
        private final Result result;
        private final EngineState<Database> state;

        private BgResult(Result result, EngineState<Database> state) {
            this.result = result;
            this.state = state;
        }

        void suppress() {
            state.recordSuppressedResult();
        }

        private void postIfAttached(Runnable delivery) {
            handler.post(() -> {
                if (state.allowResultDelivery()) {
                    delivery.run();
                }
            });
        }

        // make sure to respond in the caller thread
        public void success(final Object results) {
            postIfAttached(() -> result.success(results));
        }

        public void error(final String errorCode, final String errorMessage, final Object data) {
            postIfAttached(() -> result.error(errorCode, errorMessage, data));
        }

        @Override
        public void notImplemented() {
            postIfAttached(result::notImplemented);
        }
    }
}
