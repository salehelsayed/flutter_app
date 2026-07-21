# Flutter intentionally omits dev plugins from release registration. PB266
# opts integration_test into one disposable release APK; keep its app-side
# MethodChannel plugin and the JUnit/instrumentation classes referenced from
# the separately packaged Android test APK.
-keep class dev.flutter.plugins.integration_test.** { *; }
-keep class androidx.test.** { *; }
-keep class org.junit.** { *; }
-keep class com.google.common.** { *; }
