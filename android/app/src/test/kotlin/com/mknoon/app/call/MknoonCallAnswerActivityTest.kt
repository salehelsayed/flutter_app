package com.mknoon.app.call

import android.Manifest
import android.app.Activity
import android.app.Application
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.widget.FrameLayout
import com.mknoon.app.MainActivity
import io.flutter.embedding.android.FlutterActivity
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.annotation.LooperMode
import org.robolectric.annotation.RealObject
import org.robolectric.shadow.api.Shadow
import org.robolectric.shadows.ShadowActivity
import org.robolectric.util.ReflectionHelpers
import org.robolectric.util.ReflectionHelpers.ClassParameter

@RunWith(RobolectricTestRunner::class)
@Config(
    sdk = [28],
    shadows = [AnswerBoundaryFlutterActivityShadow::class],
    instrumentedPackages = ["io.flutter.embedding.android"],
)
@LooperMode(LooperMode.Mode.PAUSED)
class MknoonCallAnswerActivityTest {
    private lateinit var application: Application
    private lateinit var rig: LifecycleRig
    private lateinit var controller: MknoonCallLifecycleController
    private lateinit var payload: CallWakePayload

    @Before
    fun ringingCallWithMicrophonePermission() {
        application = RuntimeEnvironment.getApplication()
        shadowOf(application).grantPermissions(Manifest.permission.RECORD_AUDIO)
        assertEquals(
            PackageManager.PERMISSION_GRANTED,
            application.checkSelfPermission(Manifest.permission.RECORD_AUDIO),
        )
        ReflectionHelpers.setStaticField(MknoonCallRuntime::class.java, "instance", null)
        rig = LifecycleRig()
        val now = System.currentTimeMillis()
        payload = callPayload().copy(receivedAtMs = now, expiresAtMs = now + 40_000L)
        controller = MknoonCallLifecycleController(
            store = rig.store,
            platform = rig.platform,
            eventSink = rig.eventSink,
            capabilityEnabled = { true },
            recordAudioPermissionGranted = {
                application.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
                    PackageManager.PERMISSION_GRANTED
            },
            nowMs = System::currentTimeMillis,
        )
        ReflectionHelpers.setField(MknoonCallRuntime.get(application), "controller", controller)
        assertEquals(MknoonCallPresentationResult.PRESENTED, controller.present(payload))
    }

    @After
    fun resetRuntime() {
        ReflectionHelpers.setStaticField(MknoonCallRuntime::class.java, "instance", null)
    }

    @Test
    fun `fresh public MainActivity cannot answer a forged valid ringing call intent`() {
        val activity = Robolectric.buildActivity(MainActivity::class.java, answerIntent()).create()
        try {
            assertNoAnswerOrMediaAuthorization()
        } finally {
            activity.destroy()
        }
    }

    @Test
    fun `warm public MainActivity cannot answer a forged valid ringing call intent`() {
        val activity = Robolectric.buildActivity(MainActivity::class.java, Intent()).create()
        try {
            activity.newIntent(answerIntent())
            assertNoAnswerOrMediaAuthorization()
        } finally {
            activity.destroy()
        }
    }

    @Test
    fun `immutable private Answer pending intent answers once and opens display only`() {
        val pendingIntent = AndroidMknoonCallPendingIntentFactory(application)
            .answerActivity(payload.nativeCallId)
        val pending = shadowOf(pendingIntent)
        val target = pending.savedIntent.component
        assertEquals(ComponentName(application, PRIVATE_ANSWER_ACTIVITY), target)
        assertTrue(pending.isImmutable)
        @Suppress("DEPRECATION")
        val info = application.packageManager.getActivityInfo(target!!, 0)
        assertFalse("The Answer entry must not accept external activity launches", info.exported)

        // The real PendingIntent delivers the exact-call intent. Only Flutter's
        // superclass lifecycle is shadowed; the private entry and MainActivity
        // execute their production lifecycle and presentation/controller code.
        repeat(2) {
            pendingIntent.send()
            val delivered = shadowOf(application).nextStartedActivity
            assertNotNull(delivered)
            @Suppress("UNCHECKED_CAST")
            val entryClass = Class.forName(PRIVATE_ANSWER_ACTIVITY) as Class<out Activity>
            val entry = Robolectric.buildActivity(entryClass, delivered).create()
            try {
                assertTrue(entry.get().isFinishing)
                val display = shadowOf(entry.get()).nextStartedActivity
                assertNotNull(display)
                assertEquals(ComponentName(application, MainActivity::class.java), display.component)
                assertEquals(AndroidMknoonCallPendingIntentFactory.ACTION_OPEN_INCOMING_CALL, display.action)
                assertEquals(payload.nativeCallId.toString(), display.getStringExtra(MknoonCallActionReceiver.EXTRA_NATIVE_CALL_ID))
                val main = Robolectric.buildActivity(MainActivity::class.java, display).create()
                main.destroy()
            } finally {
                entry.destroy()
            }
        }
        assertEquals(1, answerEvents())
        assertEquals(1, rig.platform.answerCalls)
        assertFalse(controller.audioState().active)
        assertEquals(0, rig.platform.requestAudioFocusCalls)
        assertEquals(0, rig.platform.startMicrophoneCalls)
    }

    @Test
    fun `private Answer pending intent cannot answer another current call`() {
        val stale = AndroidMknoonCallPendingIntentFactory(application)
            .answerActivity(UUID.fromString(OTHER_CALL_ID))
        val target = shadowOf(stale).savedIntent.component
        assertEquals(ComponentName(application, PRIVATE_ANSWER_ACTIVITY), target)
        stale.send()
        @Suppress("UNCHECKED_CAST")
        val entryClass = Class.forName(PRIVATE_ANSWER_ACTIVITY) as Class<out Activity>
        val entry = Robolectric.buildActivity(entryClass, shadowOf(application).nextStartedActivity).create()
        try {
            assertNoAnswerOrMediaAuthorization()
        } finally {
            entry.destroy()
        }
    }

    private fun answerIntent() = Intent(application, MainActivity::class.java)
        .setAction(MknoonCallActionReceiver.ACTION_ANSWER)
        .putExtra(MknoonCallActionReceiver.EXTRA_NATIVE_CALL_ID, payload.nativeCallId.toString())

    private fun answerEvents() = rig.store.snapshot()!!.events.count {
        it.type == PendingNativeCallEventType.ANSWER_REQUESTED
    }

    private fun assertNoAnswerOrMediaAuthorization() {
        assertEquals("Public or stale activity intents must not authorize Answer", 0, answerEvents())
        assertEquals(0, rig.platform.answerCalls)
        assertFalse(controller.audioState().active)
        assertEquals(0, rig.platform.requestAudioFocusCalls)
        assertEquals(0, rig.platform.startMicrophoneCalls)
    }

    companion object {
        private const val PRIVATE_ANSWER_ACTIVITY = "com.mknoon.app.call.MknoonCallAnswerActivity"
    }
}

/** Keep the real app lifecycle while excluding Flutter/Go JNI from this JVM test. */
@Implements(FlutterActivity::class, isInAndroidSdk = false)
class AnswerBoundaryFlutterActivityShadow : ShadowActivity() {
    @RealObject private lateinit var flutterActivity: FlutterActivity

    @Implementation
    protected fun onCreate(savedInstanceState: Bundle?) {
        Shadow.directlyOn<Void>(
            flutterActivity, Activity::class.java.name, "onCreate",
            ClassParameter.from(Bundle::class.java, savedInstanceState),
        )
        flutterActivity.setContentView(FrameLayout(flutterActivity))
    }

    @Implementation
    protected fun onNewIntent(intent: Intent) = Unit

    @Implementation
    override fun onDestroy() {
        Shadow.directlyOn<Void>(flutterActivity, Activity::class.java.name, "onDestroy")
    }
}
