const String feedAverageBuildAssertionId = 'feed.scroll.average_build';
const String feedP99BuildAssertionId = 'feed.scroll.p99_build';
const String feedWorstBuildAssertionId = 'feed.scroll.worst_build';
const String bridgeP99AssertionId = 'bridge.node_status.p99';
const String androidFrameTimingMeasurementSource = 'android.engine.FrameTiming';
const String androidGoBridgeMeasurementSource =
    'android.MethodChannel.GoBridgeClient';
const int androidCriticalPerformanceAssertionCount = 4;

const double androidFeedAverageBuildBudgetMs = 8;
const double androidFeedP99BuildBudgetMs = 24;
const double androidFeedWorstBuildBudgetMs = 100;
const double androidBridgeP99BudgetMs = 50;
const int androidBridgeMinimumSamples = 100;
