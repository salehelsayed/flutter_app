#import "SqfliteSqlCipherPlugin.h"

// Include files differs on iOS and macOS
#if TARGET_OS_IPHONE
#import <fmdb/FMDB.h>
#import <UIKit/UIKit.h>
#else
#import <FMDB/FMDB.h>
#endif

#import <sqlite3.h>
#import "SqfliteSqlCipherOperation.h"

static NSString *const _channelName = @"com.davidmartos96.sqflite_sqlcipher";
static NSString *const _inMemoryPath = @":memory:";

static NSString *const _methodGetPlatformVersion = @"getPlatformVersion";
static NSString *const _methodGetDatabasesPath = @"getDatabasesPath";
static NSString *const _methodDebugMode = @"debugMode";
static NSString *const _methodDebug = @"debug";
static NSString *const _methodOptions = @"options";
static NSString *const _methodOpenDatabase = @"openDatabase";
static NSString *const _methodCloseDatabase = @"closeDatabase";
static NSString *const _methodDeleteDatabase = @"deleteDatabase";
static NSString *const _methodExecute = @"execute";
static NSString *const _methodInsert = @"insert";
static NSString *const _methodUpdate = @"update";
static NSString *const _methodQuery = @"query";
static NSString *const _methodBatch = @"batch";

// For open
static NSString *const _paramReadOnly = @"readOnly";
static NSString *const _paramSingleInstance = @"singleInstance";
// Open result
static NSString *const _paramRecovered = @"recovered";
static NSString *const _paramRecoveredInTransaction = @"recoveredInTransaction";

// For batch
static NSString *const _paramOperations = @"operations";
// For each batch operation
static NSString *const _paramPath = @"path";
static NSString *const _paramPassword = @"password";
static NSString *const _paramId = @"id";
static NSString *const _paramTransactionId = @"transactionId";
static NSString *const _paramTable = @"table";
static NSString *const _paramValues = @"values";

static NSString *const _sqliteErrorCode = @"sqlite_error";
static NSString *const _errorBadParam = @"bad_param"; // internal only
static NSString *const _errorOpenFailed = @"open_failed";
static NSString *const _errorDatabaseClosed = @"database_closed";

// options
static NSString *const _paramQueryAsMapList = @"queryAsMapList";

// debug
static NSString *const _paramDatabases = @"databases";
static NSString *const _paramLogLevel = @"logLevel";
static NSString *const _paramCmd = @"cmd";
static NSString *const _paramCmdGet = @"get";

// Shared
NSString *const SqfliteSqlCipherParamSql = @"sql";
NSString *const SqfliteSqlCipherParamSqlArguments = @"arguments";
NSString *const SqfliteSqlCipherParamInTransaction = @"inTransaction"; // true, false or null
NSString *const SqfliteSqlCipherParamNoResult = @"noResult";
NSString *const SqfliteSqlCipherParamContinueOnError = @"continueOnError";
NSString *const SqfliteSqlCipherParamMethod = @"method";
// For each operation in a batch, we have either a result or an error
NSString *const SqfliteSqlCipherParamResult = @"result";
NSString *const SqfliteSqlCipherParamError = @"error";
NSString *const SqfliteSqlCipherParamErrorCode = @"code";
NSString *const SqfliteSqlCipherParamErrorMessage = @"message";
NSString *const SqfliteSqlCipherParamErrorData = @"data";


static NSString *const _errorGrantUnavailable = @"background_grant_unavailable";
static NSString *const _errorTransactionAborted = @"transaction_aborted";
// Leave the configured five-second SQLite busy wait and a cleanup margin.
static NSTimeInterval const _backgroundDrainMargin = 7;
static int64_t const _expirationDrainNanos = 2 * NSEC_PER_SEC;

@interface SqfliteSuspensionLease : NSObject
@property (atomic, getter=isRevoked) BOOL revoked;
@property (nonatomic) UIBackgroundTaskIdentifier identifier;
@property (nonatomic) NSUInteger pending;
@property (nonatomic) BOOL draining;
@property (nonatomic, strong) dispatch_block_t deadline;
@property (nonatomic, readonly, strong) dispatch_group_t drain;
- (BOOL)beginSQLite:(sqlite3 *)handle;
- (void)finishSQLite;
- (void)revoke;
@end

@implementation SqfliteSuspensionLease {
    sqlite3 *_workingHandle;
}

static int sqliteSuspensionProgress(void *context) {
    return [(__bridge SqfliteSuspensionLease *)context isRevoked];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _identifier = UIBackgroundTaskInvalid;
        _drain = dispatch_group_create();
    }
    return self;
}

- (BOOL)beginSQLite:(sqlite3 *)handle {
    @synchronized (self) {
        if (self.revoked || handle == NULL) {
            return NO;
        }
        _workingHandle = handle;
        sqlite3_progress_handler(handle, 1000, sqliteSuspensionProgress, (__bridge void *)self);
        return YES;
    }
}

- (void)finishSQLite {
    @synchronized (self) {
        sqlite3_progress_handler(_workingHandle, 0, NULL, NULL);
        _workingHandle = NULL;
    }
}

- (void)revoke {
    @synchronized (self) {
        self.revoked = YES;
        if (_workingHandle != NULL) {
            sqlite3_interrupt(_workingHandle);
        }
    }
}
@end

@interface SqfliteSqlCipherDatabase : NSObject

@property (atomic, retain) FMDatabaseQueue *fmDatabaseQueue;
@property (atomic, retain) NSNumber *databaseId;
@property (atomic, retain) NSString* path;
@property (nonatomic) bool singleInstance;
@property (nonatomic) bool inTransaction;
@property (nonatomic, strong) NSNumber *transactionId;
@property (nonatomic) BOOL rawTransactionAborted;
@property (nonatomic) int logLevel;

@end

@interface SqfliteSqlCipherPlugin ()

@property (atomic, retain) NSMutableDictionary<NSNumber*, SqfliteSqlCipherDatabase*>* databaseMap;
@property (atomic, retain) NSMutableDictionary<NSString*, SqfliteSqlCipherDatabase*>* singleInstanceDatabaseMap;
@property (atomic, retain) NSObject* mapLock;
// UIKit admission and end run on main. SQLite state and every file operation
// belong to operationQueue, and the lease pins its interruptible handle.
@property (nonatomic, strong) dispatch_queue_t operationQueue;
@property (nonatomic, strong) SqfliteSuspensionLease *backgroundLease;
@property (nonatomic, strong) SqfliteSuspensionLease *executingLease;
@property (nonatomic) NSInteger lastTransactionId;
@property (nonatomic) NSInteger lastDatabaseId;
- (void)handleDatabaseCall:(FlutterMethodCall *)call result:(FlutterResult)result;
- (void)closeDatabase:(SqfliteSqlCipherDatabase *)database;

@end

@implementation SqfliteSqlCipherDatabase

@synthesize databaseId;
@synthesize fmDatabaseQueue;

@end

@implementation SqfliteSqlCipherPlugin

@synthesize databaseMap;
@synthesize mapLock;

static _Atomic(bool) _queryAsMapList = false;
static const int logLevelNone = 0;
static const int logLevelSql = 1;
static const int logLevelVerbose = 2;

static _Atomic(int) logLevel = 0;

// True for basic debugging (open/close and sql)
static bool hasSqlLogLevel(int logLevel) {
    return logLevel >= logLevelSql;
}

// True for verbose debugging
static bool hasVerboseLogLevel(int logLevel) {
    return logLevel >= logLevelVerbose;
}

// static BOOL _log = false;
static BOOL _extra_log = false;

static BOOL __extra_log = false; // to set to true for type debugging

static BOOL isRollback(NSString *sql) {
    return sql != nil &&
        [[sql stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
            caseInsensitiveCompare:@"ROLLBACK"] == NSOrderedSame;
}

static FlutterError *suspensionError(NSString *message) {
    return [FlutterError errorWithCode:_sqliteErrorCode message:message details:nil];
}


+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    FlutterMethodChannel* channel = [FlutterMethodChannel
                                     methodChannelWithName:_channelName
                                     binaryMessenger:[registrar messenger]];
    SqfliteSqlCipherPlugin* instance = [[SqfliteSqlCipherPlugin alloc] init];
    [registrar addMethodCallDelegate:instance channel:channel];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.databaseMap = [NSMutableDictionary new];
        self.singleInstanceDatabaseMap = [NSMutableDictionary new];
        self.mapLock = [NSObject new];
        self.operationQueue = dispatch_queue_create("com.mknoon.sqlcipher", DISPATCH_QUEUE_SERIAL);
        [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(applicationDidEnterBackground:)
            name:UIApplicationDidEnterBackgroundNotification
            object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)finishLease:(SqfliteSuspensionLease *)lease {
    if (self.backgroundLease == lease) {
        self.backgroundLease = nil;
    }
    if (lease.deadline != nil) {
        dispatch_block_cancel(lease.deadline);
        lease.deadline = nil;
    }
    UIBackgroundTaskIdentifier identifier = lease.identifier;
    lease.identifier = UIBackgroundTaskInvalid;
    if (identifier != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:identifier];
    }
}

- (void)drainLease:(SqfliteSuspensionLease *)lease {
    if (lease.draining) {
        return;
    }
    [lease revoke];
    lease.draining = YES;
    dispatch_group_enter(lease.drain);
    dispatch_async(self.operationQueue, ^{
        for (SqfliteSqlCipherDatabase *database in self.databaseMap.allValues) {
            if (!database.inTransaction) {
                continue;
            }
            [database.fmDatabaseQueue inDatabase:^(FMDatabase *db) {
                sqlite3 *handle = db.sqliteHandle;
                if (handle == NULL) {
                    return;
                }
                [db closeOpenResultSets];
                if (!sqlite3_get_autocommit(handle)) {
                    [db executeUpdate:@"ROLLBACK"];
                }
                database.inTransaction = !sqlite3_get_autocommit(handle);
            }];
            if (database.inTransaction) {
                // Retire a connection that could not roll back.
                [self closeDatabase:database];
            } else {
                database.rawTransactionAborted = database.transactionId == nil;
                database.transactionId = nil;
            }
        }
        dispatch_group_leave(lease.drain);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self finishLease:lease];
        });
    });
}

- (void)scheduleDrain:(SqfliteSuspensionLease *)lease {
    UIApplication *application = [UIApplication sharedApplication];
    if (lease == nil || lease.draining || lease.deadline != nil ||
        application.applicationState != UIApplicationStateBackground) {
        return;
    }
    NSTimeInterval remaining = application.backgroundTimeRemaining;
    if (remaining <= _backgroundDrainMargin) {
        [self drainLease:lease];
        return;
    }
    // The reported deadline can be initially unbounded.
    NSTimeInterval delay = MIN(remaining - _backgroundDrainMargin, 1);
    __weak typeof(self) weakSelf = self;
    __weak SqfliteSuspensionLease *weakLease = lease;
    lease.deadline = dispatch_block_create(0, ^{
        SqfliteSqlCipherPlugin *plugin = weakSelf;
        SqfliteSuspensionLease *scheduledLease = weakLease;
        if (scheduledLease != nil && scheduledLease == plugin.backgroundLease) {
            scheduledLease.deadline = nil;
            [plugin scheduleDrain:scheduledLease];
        }
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), lease.deadline);
}

- (void)applicationDidEnterBackground:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self scheduleDrain:self.backgroundLease];
    });
}

- (void)performDatabaseCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    UIApplication *application = [UIApplication sharedApplication];
    SqfliteSuspensionLease *lease = self.backgroundLease;
    if (application.applicationState == UIApplicationStateBackground &&
        application.backgroundTimeRemaining <= _backgroundDrainMargin) {
        if (lease != nil) {
            [self drainLease:lease];
        }
        result(suspensionError(_errorGrantUnavailable));
        return;
    }
    if (lease == nil) {
        lease = [SqfliteSuspensionLease new];
        self.backgroundLease = lease;
        // UIKit retains this assertion's owner between transaction calls.
        SqfliteSuspensionLease *newLease = lease;
        lease.identifier = [application beginBackgroundTaskWithName:@"mknoon.sqlcipher"
            expirationHandler:^{
                if (self.backgroundLease != newLease) {
                    return;
                }
                [self drainLease:newLease];
                // The worker never synchronously calls main. A kernel I/O
                // call that fails to return cannot be interrupted here.
                dispatch_group_wait(newLease.drain,
                    dispatch_time(DISPATCH_TIME_NOW, _expirationDrainNanos));
                [self finishLease:newLease];
            }];
        if (lease.identifier == UIBackgroundTaskInvalid || lease.revoked) {
            [self finishLease:lease];
            result(suspensionError(_errorGrantUnavailable));
            return;
        }
        [self scheduleDrain:lease];
    }
    if (lease.revoked) {
        result(suspensionError(_errorGrantUnavailable));
        return;
    }
    lease.pending++;
    dispatch_async(self.operationQueue, ^{
        __block id output;
        SqfliteSqlCipherDatabase *database = nil;
        if (lease.revoked) {
            output = suspensionError(_errorGrantUnavailable);
        } else {
            NSNumber *databaseId = call.arguments[_paramId];
            if (databaseId != nil) {
                database = self.databaseMap[databaseId];
            }
            self.executingLease = lease;
            [self handleDatabaseCall:call result:^(id value) {
                output = value;
            }];
            self.executingLease = nil;
        }
        BOOL transactionStillOpen = database.inTransaction;
        BOOL anyTransaction = NO;
        for (SqfliteSqlCipherDatabase *handle in self.databaseMap.allValues) {
            if (handle.inTransaction) {
                anyTransaction = YES;
                break;
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            lease.pending--;
            if (!lease.draining && lease.pending == 0 && !anyTransaction) {
                [self finishLease:lease];
            }
            result(transactionStillOpen && lease.revoked
                ? suspensionError(_errorTransactionAborted) : output);
        });
    });
}

- (void)withDatabase:(SqfliteSqlCipherDatabase *)database
                 call:(FlutterMethodCall *)call
               result:(FlutterResult)result
                 work:(void (^)(FMDatabase *))work {
    SqfliteSuspensionLease *lease = self.executingLease;
    id requestedId = call.arguments[_paramTransactionId];
    BOOL rollback = [_methodExecute isEqualToString:call.method] &&
        isRollback(call.arguments[SqfliteSqlCipherParamSql]);
    BOOL managedBegin = requestedId == NSNull.null &&
        [_methodExecute isEqualToString:call.method] &&
        [call.arguments[SqfliteSqlCipherParamInTransaction] boolValue];
    BOOL forceRollback = rollback && [requestedId isEqual:@(-1)];
    if (database.rawTransactionAborted) {
        if (rollback) {
            database.rawTransactionAborted = NO;
            result(nil);
        } else {
            result(suspensionError(_errorTransactionAborted));
        }
        return;
    }
    BOOL matchingTransaction = database.transactionId != nil &&
        [database.transactionId isEqual:requestedId];
    if (!forceRollback &&
        ((database.transactionId != nil && !matchingTransaction) ||
         (database.transactionId == nil && requestedId != nil && !managedBegin))) {
        // A late ROLLBACK is cleanup for a retired transaction. A late
        // COMMIT or a continuation must never act on the live connection.
        result(rollback && !matchingTransaction && requestedId != nil
            ? nil : suspensionError(_errorTransactionAborted));
        return;
    }
    [database.fmDatabaseQueue inDatabase:^(FMDatabase *db) {
        sqlite3 *handle = db.sqliteHandle;
        if (![lease beginSQLite:handle]) {
            result(suspensionError(_errorGrantUnavailable));
            return;
        }
        BOOL rawTransaction = database.inTransaction && database.transactionId == nil;
        @try {
            work(db);
        } @finally {
            [lease finishSQLite];
            [db closeOpenResultSets];
            database.inTransaction = !sqlite3_get_autocommit(handle);
            if (!database.inTransaction) {
                if (rawTransaction && lease.revoked) {
                    database.rawTransactionAborted = YES;
                }
                database.transactionId = nil;
            }
        }
    }];
}

- (SqfliteSqlCipherDatabase *)getDatabaseOrError:(FlutterMethodCall*)call result:(FlutterResult)result {
    NSNumber* databaseId = call.arguments[_paramId];
    SqfliteSqlCipherDatabase* database = self.databaseMap[databaseId];
    if (database == nil) {
        NSLog(@"db not found.");
        result([FlutterError errorWithCode:_sqliteErrorCode
                                   message: _errorDatabaseClosed
                                   details:nil]);
        
    }
    return database;
}

- (BOOL)handleError:(FMDatabase*)db result:(FlutterResult)result {
    // handle error
    if ([db hadError]) {
        result([FlutterError errorWithCode:_sqliteErrorCode
                                   message:[NSString stringWithFormat:@"%@", [db lastError]]
                                   details:nil]);
        return YES;
    }
    return NO;
}

- (BOOL)handleError:(FMDatabase*)db operation:(SqfliteSqlCipherOperation*)operation {
    // handle error
    if ([db hadError]) {
        NSMutableDictionary* details = nil;
        NSString* sql = [operation getSql];
        if (sql != nil) {
            details = [NSMutableDictionary new];
            [details setObject:sql forKey:SqfliteSqlCipherParamSql];
            NSArray* sqlArguments = [operation getSqlArguments];
            if (sqlArguments != nil) {
                [details setObject:sqlArguments forKey:SqfliteSqlCipherParamSqlArguments];
            }
        }
        
        [operation error:([FlutterError errorWithCode:_sqliteErrorCode
                                              message:[NSString stringWithFormat:@"%@", [db lastError]]
                                              details:details])];
        return YES;
    }
    return NO;
}

+ (NSObject*)toSqlValue:(NSObject*)value {
    if (_extra_log) {
        NSLog(@"value type %@ %@", [value class], value);
    }
    if (value == nil) {
        return nil;
    } else if ([value isKindOfClass:[FlutterStandardTypedData class]]) {
        FlutterStandardTypedData* typedData = (FlutterStandardTypedData*)value;
        return [typedData data];
    } else if ([value isKindOfClass:[NSArray class]]) {
        // Assume array of number
        // slow...to optimize
        NSArray* array = (NSArray*)value;
        NSMutableData* data = [NSMutableData new];
        for (int i = 0; i < [array count]; i++) {
            uint8_t byte = [((NSNumber *)[array objectAtIndex:i]) intValue];
            [data appendBytes:&byte length:1];
        }
        return data;
    } else {
        return value;
    }
}

+ (NSObject*)fromSqlValue:(NSObject*)sqlValue {
    if (_extra_log) {
        NSLog(@"sql value type %@ %@", [sqlValue class], sqlValue);
    }
    if (sqlValue == nil) {
        return [NSNull null];
    } else if ([sqlValue isKindOfClass:[NSData class]]) {
        return [FlutterStandardTypedData typedDataWithBytes:(NSData*)sqlValue];
    } else {
        return sqlValue;
    }
}

+ (bool)arrayIsEmpy:(NSArray*)array {
    return (array == nil || array == (id)[NSNull null] || [array count] == 0);
}

+ (NSArray*)toSqlArguments:(NSArray*)rawArguments {
    NSMutableArray* array = [NSMutableArray new];
    if (![SqfliteSqlCipherPlugin arrayIsEmpy:rawArguments]) {
        for (int i = 0; i < [rawArguments count]; i++) {
            [array addObject:[SqfliteSqlCipherPlugin toSqlValue:[rawArguments objectAtIndex:i]]];
        }
    }
    return array;
}

+ (NSDictionary*)fromSqlDictionary:(NSDictionary*)sqlDictionary {
    NSMutableDictionary* dictionary = [NSMutableDictionary new];
    [sqlDictionary enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull value, BOOL * _Nonnull stop) {
        [dictionary setObject:[SqfliteSqlCipherPlugin fromSqlValue:value] forKey:key];
    }];
    return dictionary;
}

- (bool)executeOrError:(SqfliteSqlCipherDatabase*)database fmdb:(FMDatabase*)db call:(FlutterMethodCall*)call result:(FlutterResult)result {
    NSString* sql = call.arguments[SqfliteSqlCipherParamSql];
    NSArray* arguments = call.arguments[SqfliteSqlCipherParamSqlArguments];
    NSArray* sqlArguments = [SqfliteSqlCipherPlugin toSqlArguments:arguments];
    BOOL argumentsEmpty = [SqfliteSqlCipherPlugin arrayIsEmpy:arguments];
    if (hasSqlLogLevel(database.logLevel)) {
        NSLog(@"%@ %@", sql, argumentsEmpty ? @"" : sqlArguments);
    }
    
    if (!argumentsEmpty) {
        [db executeUpdate: sql withArgumentsInArray: sqlArguments];
    } else {
        [db executeUpdate: sql];
    }
    
    // handle error
    if ([self handleError:db result:result]) {
        return false;
    }
    
    return true;
}

- (bool)executeOrError:(SqfliteSqlCipherDatabase*)database fmdb:(FMDatabase*)db operation:(SqfliteSqlCipherOperation*)operation {
    NSString* sql = [operation getSql];
    NSArray* sqlArguments = [operation getSqlArguments];
    BOOL argumentsEmpty = [SqfliteSqlCipherPlugin arrayIsEmpy:sqlArguments];
    if (hasSqlLogLevel(database.logLevel)) {
        NSLog(@"%@ %@", sql, argumentsEmpty ? @"" : sqlArguments);
    }
    
    if (!argumentsEmpty) {
        [db executeUpdate: sql withArgumentsInArray: sqlArguments];
    } else {
        [db executeUpdate: sql];
    }
    
    return ![self handleError:db operation:operation];
}

//
// query
//
- (bool)query:(SqfliteSqlCipherDatabase*)database fmdb:(FMDatabase*)db operation:(SqfliteSqlCipherOperation*)operation {
    NSString* sql = [operation getSql];
    NSArray* sqlArguments = [operation getSqlArguments];
    BOOL argumentsEmpty = [SqfliteSqlCipherPlugin arrayIsEmpy:sqlArguments];
    if (hasSqlLogLevel(database.logLevel)) {
        NSLog(@"%@ %@", sql, argumentsEmpty ? @"" : sqlArguments);
    }
    
    FMResultSet *rs;
    if (!argumentsEmpty) {
        rs = [db executeQuery:sql withArgumentsInArray:sqlArguments];
    } else {
        rs = [db executeQuery:sql];
    }
    
    // handle error
    if ([self handleError:db operation:operation]) {
        [rs close];
        return false;
    }
    
    NSError *stepError = nil;
    bool queryAsMapList = _queryAsMapList;
    
    // NSLog(@"queryAsMapList %d", (int)queryAsMapList);
    if (queryAsMapList) {
        NSMutableArray* results = [NSMutableArray new];
        while ([rs nextWithError:&stepError]) {
            [results addObject:[SqfliteSqlCipherPlugin fromSqlDictionary:[rs resultDictionary]]];
        }
        if (stepError != nil) {
            [operation error:self.executingLease.revoked
                ? suspensionError(_errorTransactionAborted)
                : suspensionError(stepError.localizedDescription)];
            return false;
        }
        [operation success:results];
    } else {
        NSMutableDictionary* results = [NSMutableDictionary new];
        NSMutableArray* columns = nil;
        NSMutableArray* rows;
        int columnCount = 0;
        while ([rs nextWithError:&stepError]) {
            if (columns == nil) {
                columnCount = [rs columnCount];
                columns = [NSMutableArray new];
                rows = [NSMutableArray new];
                for (int i = 0; i < columnCount; i++) {
                    [columns addObject:[rs columnNameForIndex:i]];
                }
                [results setValue:columns forKey:@"columns"];
                [results setValue:rows forKey:@"rows"];
                
            }
            NSMutableArray* row = [NSMutableArray new];
            for (int i = 0; i < columnCount; i++) {
                [row addObject:[SqfliteSqlCipherPlugin fromSqlValue:[rs objectForColumnIndex:i]]];
            }
            [rows addObject:row];
        }
        
        if (hasVerboseLogLevel(database.logLevel)) {
            NSLog(@"columns %@ rows %@", columns, rows);
        }
        if (stepError != nil) {
            [operation error:self.executingLease.revoked
                ? suspensionError(_errorTransactionAborted)
                : suspensionError(stepError.localizedDescription)];
            return false;
        }
        [operation success:results];
    }
    return true;
}

- (void)handleQueryCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    SqfliteSqlCipherDatabase* database = [self getDatabaseOrError:call result:result];
    if (database == nil) {
        return;
    }
    [self withDatabase:database call:call result:result work:^(FMDatabase *db) {
        SqfliteSqlCipherMethodCallOperation* operation = [SqfliteSqlCipherMethodCallOperation newWithCall:call result:result];
        [self query:database fmdb:db operation:operation];
    }];
}

//
// insert
//
- (bool)insert:(SqfliteSqlCipherDatabase*)database fmdb:(FMDatabase*)db operation:(SqfliteSqlCipherOperation*)operation {
    if (![self executeOrError:database fmdb:db operation:operation]) {
        return false;
    }
    if ([operation getNoResult]) {
        [operation success:[NSNull null]];
        return true;
    }
    // handle ON CONFLICT IGNORE (issue #164) by checking the number of changes
    // before
    int changes = [db changes];
    if (changes == 0) {
        if (hasSqlLogLevel(database.logLevel)) {
            NSLog(@"no changes");
        }
        [operation success:[NSNull null]];
        return true;
    }
    sqlite_int64 insertedId = [db lastInsertRowId];
    if (hasSqlLogLevel(database.logLevel)) {
        NSLog(@"inserted %@", @(insertedId));
    }
    [operation success:(@(insertedId))];
    return true;
}

- (void)handleInsertCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    
    SqfliteSqlCipherDatabase* database = [self getDatabaseOrError:call result:result];
    if (database == nil) {
        return;
    }
    [self withDatabase:database call:call result:result work:^(FMDatabase *db) {
        SqfliteSqlCipherMethodCallOperation* operation = [SqfliteSqlCipherMethodCallOperation newWithCall:call result:result];
        [self insert:database fmdb:db operation:operation];
    }];
    
}

//
// update
//
- (bool)update:(SqfliteSqlCipherDatabase*)database fmdb:(FMDatabase*)db operation:(SqfliteSqlCipherOperation*)operation {
    if (![self executeOrError:database fmdb:db operation:operation]) {
        return false;
    }
    if ([operation getNoResult]) {
        [operation success:[NSNull null]];
        return true;
    }
    int changes = [db changes];
    if (hasSqlLogLevel(database.logLevel)) {
        NSLog(@"changed %@", @(changes));
    }
    [operation success:(@(changes))];
    return true;
}

- (void)handleUpdateCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    SqfliteSqlCipherDatabase* database = [self getDatabaseOrError:call result:result];
    if (database == nil) {
        return;
    }
    
    [self withDatabase:database call:call result:result work:^(FMDatabase *db) {
        SqfliteSqlCipherMethodCallOperation* operation = [SqfliteSqlCipherMethodCallOperation newWithCall:call result:result];
        [self update:database fmdb:db operation:operation];
    }];
}

//
// execute
//
- (bool)execute:(SqfliteSqlCipherDatabase*)database fmdb:(FMDatabase*)db operation:(SqfliteSqlCipherOperation*)operation {
    if (![self executeOrError:database fmdb:db operation:operation]) {
        return false;
    }
    [operation success:[NSNull null]];
    return true;
}

- (void)handleExecuteCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    SqfliteSqlCipherDatabase* database = [self getDatabaseOrError:call result:result];
    if (database == nil) {
        return;
    }
    [self withDatabase:database call:call result:result work:^(FMDatabase *db) {
        FlutterResult executeResult = result;
        if (sqlite3_get_autocommit(db.sqliteHandle) &&
            call.arguments[_paramTransactionId] == NSNull.null &&
            [call.arguments[SqfliteSqlCipherParamInTransaction] boolValue]) {
            executeResult = ^(id output) {
                if (![output isKindOfClass:FlutterError.class] &&
                    !sqlite3_get_autocommit(db.sqliteHandle)) {
                    database.transactionId = @(++self.lastTransactionId);
                    result(@{_paramTransactionId: database.transactionId});
                } else {
                    result(output);
                }
            };
        }
        SqfliteSqlCipherMethodCallOperation* operation = [SqfliteSqlCipherMethodCallOperation newWithCall:call result:executeResult];
        [self execute:database fmdb:db operation:operation];
    }];
    
}

//
// batch
//
- (void)handleBatchCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    SqfliteSqlCipherDatabase* database = [self getDatabaseOrError:call result:result];
    if (database == nil) {
        return;
    }
    [self withDatabase:database call:call result:result work:^(FMDatabase *db) {
            
            SqfliteSqlCipherMethodCallOperation* mainOperation = [SqfliteSqlCipherMethodCallOperation newWithCall:call result:result];
            bool noResult = [mainOperation getNoResult];
            bool continueOnError = [mainOperation getContinueOnError];
            
            NSArray* operations = call.arguments[_paramOperations];
            NSMutableArray* operationResults = [NSMutableArray new];
            for (NSDictionary* dictionary in operations) {
                if (self.executingLease.revoked) {
                    result(suspensionError(_errorTransactionAborted));
                    return;
                }
                // do something with object
                
                SqfliteSqlCipherBatchOperation* operation = [SqfliteSqlCipherBatchOperation new];
                operation.dictionary = dictionary;
                operation.noResult = noResult;
                
                NSString* method = [operation getMethod];
                if ([_methodInsert isEqualToString:method]) {
                    if ([self insert:database fmdb:db operation:operation]) {
                        [operation handleSuccess:operationResults];
                    } else if (continueOnError) {
                        [operation handleErrorContinue:operationResults];
                    } else {
                        [operation handleError:result];
                        return;
                    }
                } else if ([_methodUpdate isEqualToString:method]) {
                    if ([self update:database fmdb:db operation:operation]) {
                        [operation handleSuccess:operationResults];
                    } else if (continueOnError) {
                        [operation handleErrorContinue:operationResults];
                    } else {
                        [operation handleError:result];
                        return;
                    }
                } else if ([_methodExecute isEqualToString:method]) {
                    if ([self execute:database fmdb:db operation:operation]) {
                        [operation handleSuccess:operationResults];
                    } else if (continueOnError) {
                        [operation handleErrorContinue:operationResults];
                    } else {
                        [operation handleError:result];
                        return;
                    }
                } else if ([_methodQuery isEqualToString:method]) {
                    if ([self query:database fmdb:db operation:operation]) {
                        [operation handleSuccess:operationResults];
                    } else if (continueOnError) {
                        [operation handleErrorContinue:operationResults];
                    } else {
                        [operation handleError:result];
                        return;
                    }
                } else {
                    result([FlutterError errorWithCode:_errorBadParam
                                               message:[NSString stringWithFormat:@"Batch method '%@' not supported", method]
                                               details:nil]);
                    return;
                }
            }
            
            if (noResult) {
                result(nil);
            } else {
                result(operationResults);
            }
            
    }];
    
    
}

+ (bool)isInMemoryPath:(NSString*)path {
    if ([path isEqualToString:_inMemoryPath]) {
        return true;
    }
    return false;
}

+ (NSDictionary*)makeOpenResult:(NSNumber*)databaseId recovered:(bool)recovered recoveredInTransaction:(bool)recoveredInTransaction {
    NSMutableDictionary* result = [NSMutableDictionary new];
    [result setObject:databaseId forKey:_paramId];
    if (recovered) {
        [result setObject:[NSNumber numberWithBool:recovered] forKey:_paramRecovered];
    }
    if (recoveredInTransaction) {
        [result setObject:[NSNumber numberWithBool:recoveredInTransaction] forKey:_paramRecoveredInTransaction];
    }
    return result;
}

//
// open
//
- (void)handleOpenDatabaseCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    NSString* path = call.arguments[_paramPath];
    NSString* password = call.arguments[_paramPassword];
    NSNumber* readOnlyValue = call.arguments[_paramReadOnly];
    bool readOnly = [readOnlyValue boolValue] == true;
    NSNumber* singleInstanceValue = call.arguments[_paramSingleInstance];
    bool inMemoryPath = [SqfliteSqlCipherPlugin isInMemoryPath:path];
    // A single instance must be a regular database
    bool singleInstance = [singleInstanceValue boolValue] != false && !inMemoryPath;
    
    bool _log = hasSqlLogLevel(logLevel);
    if (_log) {
        NSLog(@"opening %@ %@ %@", path, readOnly ? @" read-only" : @"", singleInstance ? @"" : @" new instance");
    }
    
    // Handle hot-restart for single instance
    // The dart code is killed but the native code remains
    if (singleInstance) {
        @synchronized (self.mapLock) {
            SqfliteSqlCipherDatabase* database = self.singleInstanceDatabaseMap[path];
            if (database != nil) {
                // Check if opened
                if (_log) {
                    NSLog(@"re-opened %@singleInstance %@ id %@", database.inTransaction ? @"(in transaction) ": @"", path, database.databaseId);
                }
                result([SqfliteSqlCipherPlugin makeOpenResult:database.databaseId
                    recovered:true recoveredInTransaction:database.inTransaction || database.rawTransactionAborted]);
                return;
            }
        }
    }
    
    // Make sure the directory exists
    if (!inMemoryPath && !readOnly) {
        NSError* error;
        NSString* parentDir = [path stringByDeletingLastPathComponent];
        if (![[NSFileManager defaultManager] fileExistsAtPath:parentDir]) {
            if (_log) {
                NSLog(@"Creating parent dir %@", parentDir);
            }
            [[NSFileManager defaultManager] createDirectoryAtPath:parentDir withIntermediateDirectories:YES attributes:nil error:&error];
            // Ignore the error, it will break later during open
        }
    }
    FMDatabaseQueue *queue = [FMDatabaseQueue databaseQueueWithPath:path flags:(readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE))];
    bool success = queue != nil;
    
    if (!success) {
        NSLog(@"Could not open db.");
        result([FlutterError errorWithCode:_sqliteErrorCode
                                   message:[NSString stringWithFormat:@"%@ %@", _errorOpenFailed, path]
                                   details:nil]);
        return;
    }

    __block BOOL verified = NO;
    SqfliteSuspensionLease *lease = self.executingLease;
    [queue inDatabase:^(FMDatabase *database) {
        if (![lease beginSQLite:database.sqliteHandle]) {
            return;
        }
        @try {
            [database setKey:password ?: @""];
            FMResultSet *probe = [database executeQuery:@"SELECT COUNT(*) FROM sqlite_schema"];
            verified = [probe next];
            [probe close];
        } @finally {
            [lease finishSQLite];
        }
    }];
    if (!verified || lease.revoked) {
        [queue close];
        result(lease.revoked ? suspensionError(_errorGrantUnavailable) :
            suspensionError([NSString stringWithFormat:@"%@ %@", _errorOpenFailed, path]));
        return;
    }

    NSNumber* databaseId;
    @synchronized (self.mapLock) {
        SqfliteSqlCipherDatabase* database = [SqfliteSqlCipherDatabase new];
        databaseId = @(++self.lastDatabaseId);
        database.inTransaction = false;
        database.fmDatabaseQueue = queue;
        database.singleInstance = singleInstance;
        database.databaseId = databaseId;
        database.path = path;
        database.logLevel = logLevel;
        self.databaseMap[databaseId] = database;
        // To handle hot-restart recovery
        if (singleInstance) {
            self.singleInstanceDatabaseMap[path] = database;
        }
        
    }
    
    result([SqfliteSqlCipherPlugin makeOpenResult: databaseId recovered:false recoveredInTransaction:false]);
}

//
// close
//
- (void)handleCloseDatabaseCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    SqfliteSqlCipherDatabase* database = [self getDatabaseOrError:call result:result];
    if (database == nil) {
        return;
    }
    
    if (hasSqlLogLevel(database.logLevel)) {
        NSLog(@"closing %@", database.path);
    }
    [self closeDatabase:database];
    result(nil);
}

//
// close action
//
- (void)closeDatabase:(SqfliteSqlCipherDatabase*)database {
    if (hasSqlLogLevel(database.logLevel)) {
        NSLog(@"closing %@", database.path);
    }
    [database.fmDatabaseQueue close];
    database.inTransaction = NO;
    database.transactionId = nil;
    
    @synchronized (self.mapLock) {
        [self.databaseMap removeObjectForKey:database.databaseId];
        if (database.singleInstance) {
            [self.singleInstanceDatabaseMap removeObjectForKey:database.path];
        }
    }
}

//
// delete
//
- (void)handleDeleteDatabaseCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    NSString* path = call.arguments[_paramPath];
    
    bool _log = hasSqlLogLevel(logLevel);
    
    // Handle hot-restart for single instance
    // The dart code is killed but the native code remains
    SqfliteSqlCipherDatabase* database = nil;
    @synchronized (self.mapLock) {
        database = self.singleInstanceDatabaseMap[path];
        if (database != nil) {
            // Check if openedŸ
            if (_log) {
                NSLog(@"Deleting opened %@ id %@", path, database.databaseId);
            }
        }
    }
    
    if (database != nil) {
        [self closeDatabase:database];
    }
    
    if (hasSqlLogLevel(database.logLevel)) {
        NSLog(@"Deleting %@", path);
    }
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
    result(nil);
}

//
// debug
//
- (void)handleDebugCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    NSMutableDictionary* info = [NSMutableDictionary new];
    
    NSString* cmd = call.arguments[_paramCmd];
    // NSLog(@"cmd %@", cmd);
    if ([_paramCmdGet isEqualToString:cmd]) {
        @synchronized (self.mapLock) {
            if ([self.databaseMap  count] > 0) {
                NSMutableDictionary* dbsInfo     = [NSMutableDictionary new];
                [self.databaseMap enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, SqfliteSqlCipherDatabase * _Nonnull db, BOOL * _Nonnull stop) {
                    NSMutableDictionary* dbInfo	 = [NSMutableDictionary new];
                    [dbInfo setObject:db.path forKey:_paramPath];
                    [dbInfo setObject:[NSNumber numberWithBool:db.singleInstance] forKey:_paramSingleInstance];
                    if (db.logLevel > logLevelNone) {
                        [dbInfo setObject:[NSNumber numberWithInteger:db.logLevel ] forKey:_paramLogLevel];
                    }
                    [dbsInfo setObject:dbInfo forKey:[key stringValue]];
                    [info setObject:dbsInfo forKey:_paramDatabases];
                }];
            }
        }
        if (logLevel > logLevelNone) {
            [info setObject:[NSNumber numberWithInteger:logLevel] forKey:_paramLogLevel];
        }
        
    }
    result(info);
}

//
// debug mode - trying deprecation since 1.1.6
//
- (void)handleDebugModeCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    NSNumber* on = (NSNumber*)call.arguments;
    bool _log = [on boolValue];
    NSLog(@"Debug mode %d", _log);
    _extra_log = __extra_log && _log;
    
    if (_log) {
        if (_extra_log) {
            logLevel = logLevelVerbose;
        } else {
            logLevel = logLevelSql;
        }
    } else {
        logLevel = logLevelNone;
    }
    result(nil);
}

//
// Options
//
- (void)handleOptionsCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    NSNumber* queryAsMapList = call.arguments[_paramQueryAsMapList];
    if (queryAsMapList) {
        _queryAsMapList = [queryAsMapList boolValue];
    }
    NSNumber* logLevelNumber = call.arguments[_paramLogLevel];
    
    if (logLevelNumber) {
        logLevel = [logLevelNumber intValue];
        NSLog(@"SqfliteSqlCipher: logLevel %d", logLevel);
    }
    result(nil);
}

//
// getDatabasesPath
// returns the Documents directory on iOS
//
- (void)handleGetDatabasesPath:(FlutterMethodCall*)call result:(FlutterResult)result {
    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    result(paths.firstObject);
}

- (void)handleDatabaseCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    if ([_methodOpenDatabase isEqualToString:call.method]) {
        [self handleOpenDatabaseCall:call result:result];
    } else if ([_methodInsert isEqualToString:call.method]) {
        [self handleInsertCall:call result:result];
    } else if ([_methodQuery isEqualToString:call.method]) {
        [self handleQueryCall:call result:result];
    } else if ([_methodUpdate isEqualToString:call.method]) {
        [self handleUpdateCall:call result:result];
    } else if ([_methodExecute isEqualToString:call.method]) {
        [self handleExecuteCall:call result:result];
    } else if ([_methodBatch isEqualToString:call.method]) {
        [self handleBatchCall:call result:result];
    } else if ([_methodCloseDatabase isEqualToString:call.method]) {
        [self handleCloseDatabaseCall:call result:result];
    } else if ([_methodDeleteDatabase isEqualToString:call.method]) {
        [self handleDeleteDatabaseCall:call result:result];
    } else {
        result(FlutterMethodNotImplemented);
    }
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self handleMethodCall:call result:result];
        });
        return;
    }
    if ([_methodGetPlatformVersion isEqualToString:call.method]) {
        result([@"iOS " stringByAppendingString:[[UIDevice currentDevice] systemVersion]]);
    } else if ([_methodGetDatabasesPath isEqualToString:call.method]) {
        [self handleGetDatabasesPath:call result:result];
    } else if ([_methodOptions isEqualToString:call.method]) {
        [self handleOptionsCall:call result:result];
    } else if ([_methodDebug isEqualToString:call.method]) {
        [self handleDebugCall:call result:result];
    } else if ([_methodDebugMode isEqualToString:call.method]) {
        [self handleDebugModeCall:call result:result];
    } else if ([_methodOpenDatabase isEqualToString:call.method] ||
               [_methodCloseDatabase isEqualToString:call.method] ||
               [_methodDeleteDatabase isEqualToString:call.method] ||
               [_methodInsert isEqualToString:call.method] ||
               [_methodUpdate isEqualToString:call.method] ||
               [_methodQuery isEqualToString:call.method] ||
               [_methodExecute isEqualToString:call.method] ||
               [_methodBatch isEqualToString:call.method]) {
        [self performDatabaseCall:call result:result];
    } else {
        result(FlutterMethodNotImplemented);
    }
}

@end
