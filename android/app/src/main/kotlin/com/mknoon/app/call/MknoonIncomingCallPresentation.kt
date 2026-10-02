package com.mknoon.app.call

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.WindowInsets
import android.view.accessibility.AccessibilityEvent
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.annotation.RequiresApi
import com.mknoon.app.R
import com.mknoon.app.BuildConfig
import java.util.UUID

internal interface MknoonIncomingCallPresentationSource : MknoonCallActionHandler {
    fun snapshot(): PendingNativeCallDescriptor?
    fun isCleanupPending(nativeCallId: UUID): Boolean
    fun isAudioActive(nativeCallId: UUID): Boolean
    fun presentation(nativeCallId: UUID): MknoonLockedCallMetadata? = null
    fun mute(nativeCallId: UUID, muted: Boolean): Boolean = false
    fun route(nativeCallId: UUID, route: String): Boolean = false
}

/**
 * Only this opaque, authenticated call surface may make MainActivity visible above
 * keyguard. Flutter keeps booting underneath to adopt the native call, but its
 * restored routes and private content are hidden until the user unlocks.
 *
 * Observation is activity-owned and bounded to one queued callback while a
 * call is bound. It deliberately does not bind the single-owner Flutter relay.
 */
internal class MknoonIncomingCallPresentation(
    private val activity: Activity,
    private val source: MknoonIncomingCallPresentationSource = runtimeSource(activity),
    private val nowMs: () -> Long = System::currentTimeMillis,
    private val isLocked: () -> Boolean = {
        activity.getSystemService(KeyguardManager::class.java).isKeyguardLocked
    },
    private val handler: Handler = Handler(Looper.getMainLooper()),
) {
    // Installed once while MainActivity is creating its content, before a
    // call can arrive. Flutter may change its own accessibility properties;
    // this native-owned ancestor remains the boundary for its virtual nodes.
    private val protectedContent = installProtectedContent()
    private var nativeCallId: UUID? = null
    private var cover: FrameLayout? = null
    private var coveredCallId: UUID? = null
    private var stateLabel: TextView? = null
    private var screen: MknoonLockedCallView? = null
    private var answerButton: Button? = null
    private var endButton: Button? = null
    private var protectedChildren = emptyList<ProtectedChild>()
    private var unregisterBack: (() -> Unit)? = null
    private var previousSystemIconAppearance: SystemIconAppearance? = null
    private var windowEnabled = false
    private var screenWakeEnabled = false
    private var disposed = false
    private var stopped = false
    private var intentSequence = 0
    private val observation = Runnable { refresh() }

    private fun installProtectedContent(): FrameLayout {
        val content = activity.findViewById<ViewGroup>(android.R.id.content)
        (0 until content.childCount).forEach {
            val child = content.getChildAt(it)
            if (child is ProtectedContentLayout && child.tag == CONTENT_TAG) return child
        }
        val children = (0 until content.childCount).map(content::getChildAt)
        val container = ProtectedContentLayout(activity).apply { tag = CONTENT_TAG }
        children.forEach { child ->
            val parameters = child.layoutParams
            content.removeView(child)
            container.addView(child, parameters)
        }
        content.addView(
            container,
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        return container
    }

    fun onIntent(intent: Intent?, answerFromIntent: Boolean) {
        if (disposed) return
        nativeCallId = callId(intent)
        intentSequence++
        stopped = false
        trace("intent", "action=${intentAction(intent)}")
        refresh()
        if (answerFromIntent && intent?.action == MknoonCallActionReceiver.ACTION_ANSWER) {
            nativeCallId?.let(::answer)
        }
    }

    fun onResume() {
        stopped = false
        trace("resume")
        refresh()
    }

    fun onStop() {
        trace("stop")
        stopped = true
        handler.removeCallbacks(observation)
        setWindowEnabled(false)
        // onStop establishes that the window is no longer visible; it is now
        // safe to remove a cover retained during asynchronous flag revocation.
        removeCover()
    }

    fun dispose() {
        trace("dispose")
        disposed = true
        nativeCallId = null
        handler.removeCallbacks(observation)
        setWindowEnabled(false)
        removeCover()
    }

    /** Also used by the activity before forwarding Back to Flutter. */
    fun handleBack(): Boolean {
        if (cover == null) return false
        activity.moveTaskToBack(true)
        return true
    }

    private fun descriptor(): PendingNativeCallDescriptor? {
        val expected = nativeCallId ?: return null
        return runCatching {
            source.snapshot()?.takeIf {
                it.nativeCallId == expected &&
                    it.direction == PendingNativeCallDirection.INCOMING &&
                    it.terminalEvent == null &&
                    !source.isCleanupPending(expected) &&
                    (it.answerRequested || it.expiresAtMs > nowMs())
            }
        }.getOrNull()
    }

    private fun refresh() {
        handler.removeCallbacks(observation)
        if (disposed || stopped) return
        val descriptor = descriptor()
        val locked = isLocked()
        if (descriptor == null) {
            nativeCallId = null
            setWindowEnabled(false)
            if (cover != null && locked) {
                // Clearing showWhenLocked is asynchronous in WindowManager.
                // Keep the cover opaque until onStop or actual unlock.
                answerButton?.visibility = View.GONE
                endButton?.visibility = View.GONE
                screen?.retire()
                activity.moveTaskToBack(true)
                handler.postDelayed(observation, OBSERVE_MS)
            } else {
                removeCover()
            }
            return
        }
        if (locked) {
            ensureCover(descriptor.nativeCallId)
            render(descriptor)
            // Never grant visibility before private Flutter content is covered.
            setWindowEnabled(true)
        } else {
            setWindowEnabled(false)
            removeCover()
        }
        setScreenWakeEnabled(locked || !descriptor.answerRequested)
        handler.postDelayed(observation, OBSERVE_MS)
    }

    private fun answer(expectedCallId: UUID) {
        if (nativeCallId != expectedCallId) return
        val descriptor = descriptor() ?: return refresh()
        if (!descriptor.answerRequested) {
            runCatching { source.answer(descriptor.nativeCallId) }
        }
        refresh()
    }

    private fun end(expectedCallId: UUID) {
        if (nativeCallId != expectedCallId) return
        val descriptor = descriptor() ?: return refresh()
        runCatching {
            source.terminate(
                descriptor.nativeCallId,
                if (descriptor.answerRequested) PendingNativeCallEventType.END_REQUESTED
                else PendingNativeCallEventType.DECLINE_REQUESTED,
            )
        }
        refresh()
    }

    private fun ensureCover(expectedCallId: UUID) {
        if (cover != null && coveredCallId == expectedCallId) return
        val content = activity.findViewById<ViewGroup>(android.R.id.content)
        val previousCover = cover
        if (previousCover == null) {
            protectedChildren = listOf(ProtectedChild(protectedContent))
            // FlutterActivity's SurfaceView first-frame gate cancels drawing
            // for this entire window until Flutter paints. Making FlutterView
            // invisible prevents that first frame and leaves even these native
            // controls black and untouchable. Allow that first frame beneath
            // the opaque cover, then hide the native ancestor as soon as the
            // cover draws. Already-rendered activities can hide immediately.
            protectedChildren.forEach(ProtectedChild::protect)
        }
        val background = object : FrameLayout(activity) {
            private var firstDraw = true
            private var statusInsetTop = 0
            private val windowPosition = IntArray(2)
            private val statusContrast = Paint().apply { color = 0xFF0A0A0F.toInt() }

            @Suppress("DEPRECATION")
            private fun rememberStatusInset(insets: WindowInsets) {
                statusInsetTop = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    Api30.statusInsetTop(insets)
                } else insets.systemWindowInsetTop
                invalidate()
            }

            override fun onAttachedToWindow() {
                super.onAttachedToWindow()
                rootWindowInsets?.let(::rememberStatusInset)
                requestApplyInsets()
            }

            override fun onApplyWindowInsets(insets: WindowInsets): WindowInsets {
                rememberStatusInset(insets)
                return super.onApplyWindowInsets(insets)
            }

            override fun dispatchDraw(canvas: Canvas) {
                super.dispatchDraw(canvas)
                // SystemUI may retain white status icons over a keyguard-
                // occluding window despite its requested light appearance.
                // Paint contrast inside the actual status inset; the Light
                // call body and navigation region keep their own palette.
                getLocationInWindow(windowPosition)
                val bandBottom = (statusInsetTop - windowPosition[1]).coerceIn(0, height)
                if (bandBottom > 0) {
                    canvas.drawRect(0f, 0f, width.toFloat(), bandBottom.toFloat(), statusContrast)
                }
                // The global Flutter pre-draw gate has now opened and removed
                // itself. An invisible ancestor also fences cached virtual-node
                // requests/actions, which bypass accessibility importance.
                if (cover === this) {
                    if (firstDraw) trace("cover_first_draw")
                    protectedChildren.forEach(ProtectedChild::hide)
                    if (firstDraw) {
                        firstDraw = false
                        trace("cover_hidden_flutter")
                    }
                }
            }
        }.apply {
            setBackgroundColor(Color.rgb(15, 23, 42))
            isClickable = true
            isFocusable = true
            isFocusableInTouchMode = true
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
            fitsSystemWindows = true
            tag = COVER_TAG
        }
        val controls = MknoonLockedCallView(activity,
            onAnswer = { answer(expectedCallId) },
            onEnd = { end(expectedCallId) },
            onMute = {
                descriptor()?.takeIf { it.nativeCallId == expectedCallId && it.answerRequested }?.let {
                    val data = source.presentation(expectedCallId)
                    if (data?.muteAvailable == true) source.mute(expectedCallId, !data.muted)
                }
            },
            onSpeaker = {
                descriptor()?.takeIf { it.nativeCallId == expectedCallId && it.answerRequested }?.let {
                    val data = source.presentation(expectedCallId)
                    if (data?.speakerAvailable == true) source.route(expectedCallId, if (data.speakerOn) "system_default" else "speaker")
                }
            },
        )
        screen = controls
        stateLabel = controls.status
        answerButton = controls.answer
        endButton = controls.end
        background.addView(
            controls,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        content.addView(
            background,
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        // Replace a previous call atomically under its opaque cover. Old
        // controls retain their UUID and cannot act on this successor call.
        previousCover?.let(content::removeView)
        cover = background
        coveredCallId = expectedCallId
        background.requestFocus()
        unregisterBack?.invoke()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            unregisterBack = Api33.registerBack(activity) { handleBack() }
        }
    }

    private fun render(descriptor: PendingNativeCallDescriptor) {
        val data = source.presentation(descriptor.nativeCallId)
        val light = data?.light == true
        cover?.setBackgroundColor(if (light) 0xFFF4F0EA.toInt() else 0xFF0A0A0F.toInt())
        applySystemIconAppearance(light)
        screen?.render(
            data, descriptor.answerRequested,
            runCatching { source.isAudioActive(descriptor.nativeCallId) }.getOrDefault(false), nowMs(),
        )
    }

    private fun removeCover() {
        if (cover != null) trace("cover_removed")
        unregisterBack?.invoke()
        unregisterBack = null
        cover?.let { (it.parent as? ViewGroup)?.removeView(it) }
        cover = null
        coveredCallId = null
        stateLabel = null
        screen = null
        answerButton = null
        endButton = null
        restoreSystemIconAppearance()
        protectedChildren.forEach(ProtectedChild::restore)
        protectedChildren = emptyList()
    }

    private data class SystemIconAppearance(val legacy: Int, val modern: Int?)

    @Suppress("DEPRECATION")
    private fun systemIconMask(): Int = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR else 0

    @Suppress("DEPRECATION")
    private fun applySystemIconAppearance(light: Boolean) {
        val decor = activity.window.decorView
        val mask = systemIconMask()
        if (previousSystemIconAppearance == null) {
            previousSystemIconAppearance = SystemIconAppearance(
                decor.systemUiVisibility and mask,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) Api30.iconAppearance(activity) else null,
            )
        }
        val navigation = if (light && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
        } else 0
        val desired = (decor.systemUiVisibility and mask.inv()) or navigation
        if (decor.systemUiVisibility != desired) decor.systemUiVisibility = desired
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Api30.setIconAppearance(activity, if (light) android.view.WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS else 0)
        }
    }

    @Suppress("DEPRECATION")
    private fun restoreSystemIconAppearance() {
        val previous = previousSystemIconAppearance ?: return
        previousSystemIconAppearance = null
        val decor = activity.window.decorView
        decor.systemUiVisibility = (decor.systemUiVisibility and systemIconMask().inv()) or previous.legacy
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            previous.modern?.let { Api30.setIconAppearance(activity, it) }
        }
    }

    private class ProtectedChild(private val view: View) {
        private val visibility = view.visibility
        private val accessibility = view.importantForAccessibility
        private val focusable = view.isFocusable
        private val focusableInTouchMode = view.isFocusableInTouchMode
        private val descendantFocusability = (view as? ViewGroup)?.descendantFocusability

        fun protect() {
            view.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            (view as? ViewGroup)?.descendantFocusability = ViewGroup.FOCUS_BLOCK_DESCENDANTS
            view.clearFocus()
            view.isFocusableInTouchMode = false
            view.isFocusable = false
            if ((view as? ProtectedContentLayout)?.hasDrawn == true) hide()
        }

        fun hide() {
            view.visibility = View.INVISIBLE
        }

        fun restore() {
            view.importantForAccessibility = accessibility
            descendantFocusability?.let { (view as ViewGroup).descendantFocusability = it }
            view.isFocusable = focusable
            view.isFocusableInTouchMode = focusableInTouchMode
            view.visibility = visibility
        }
    }

    private class ProtectedContentLayout(context: Context) : FrameLayout(context) {
        var hasDrawn = false
            private set

        override fun dispatchDraw(canvas: Canvas) {
            super.dispatchDraw(canvas)
            hasDrawn = true
        }

        override fun addChildrenForAccessibility(outChildren: ArrayList<View>) {
            // Uncompressed accessibility fetches explicitly ignore importance.
            // Keep private providers out of traversal while Flutter produces
            // its first frame, before the whole ancestor can become invisible.
            if (importantForAccessibility != View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS) {
                super.addChildrenForAccessibility(outChildren)
            }
        }

        override fun onRequestSendAccessibilityEvent(child: View, event: AccessibilityEvent): Boolean =
            importantForAccessibility != View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS &&
                super.onRequestSendAccessibilityEvent(child, event)
    }

    private fun setWindowEnabled(enabled: Boolean) {
        if (windowEnabled == enabled) {
            if (!enabled) setScreenWakeEnabled(false)
            return
        }
        windowEnabled = enabled
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            activity.setShowWhenLocked(enabled)
            setScreenWakeEnabled(enabled)
        } else {
            @Suppress("DEPRECATION")
            val flags = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
            if (enabled) activity.window.addFlags(flags) else activity.window.clearFlags(flags)
            setScreenWakeEnabled(enabled)
        }
    }

    private fun setScreenWakeEnabled(enabled: Boolean) {
        if (screenWakeEnabled == enabled) return
        screenWakeEnabled = enabled
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            activity.setTurnScreenOn(enabled)
        } else {
            @Suppress("DEPRECATION")
            val flags = WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            if (enabled) activity.window.addFlags(flags) else activity.window.clearFlags(flags)
        }
    }

    private fun dp(value: Int): Int = (value * activity.resources.displayMetrics.density).toInt()

    private fun buttonLayout() = LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        ViewGroup.LayoutParams.WRAP_CONTENT,
    ).apply { topMargin = dp(16) }

    private fun trace(phase: String, detail: String = "") {
        if (!BuildConfig.DEBUG) return
        runCatching {
            debugSplash(phase, activity,
                "presentation=${System.identityHashCode(this)} intentSequence=$intentSequence " +
                    "locked=${isLocked()} bound=${nativeCallId != null} validIncoming=${descriptor() != null} " +
                    "cover=${cover != null} protectedDrawn=${(protectedContent as ProtectedContentLayout).hasDrawn} " +
                    "protectedShown=${protectedContent.isShown} $detail")
        }
    }

    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    private object Api33 {
        fun registerBack(activity: Activity, action: () -> Unit): () -> Unit {
            val callback = android.window.OnBackInvokedCallback { action() }
            // Flutter's predictive-back callback bypasses onBackPressed on
            // recent Android. Keep Back owned by the visible native surface.
            activity.onBackInvokedDispatcher.registerOnBackInvokedCallback(
                android.window.OnBackInvokedDispatcher.PRIORITY_OVERLAY,
                callback,
            )
            return { activity.onBackInvokedDispatcher.unregisterOnBackInvokedCallback(callback) }
        }
    }

    @RequiresApi(Build.VERSION_CODES.S)
    private object Api31 {
        fun installCallSplashExit(activity: Activity) {
            activity.splashScreen.setOnExitAnimationListener { splash ->
                debugSplash("exit_received", activity, "attached=${splash.isAttachedToWindow} visibility=${splash.visibility}")
                splash.remove()
                debugSplash("exit_removed", activity, "attached=${splash.isAttachedToWindow} visibility=${splash.visibility}")
            }
        }
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private object Api30 {
        const val ICON_MASK = android.view.WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or
            android.view.WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS

        fun statusInsetTop(insets: WindowInsets): Int = insets.getInsets(WindowInsets.Type.statusBars()).top

        fun iconAppearance(activity: Activity): Int? =
            activity.window.insetsController?.systemBarsAppearance?.and(ICON_MASK)

        fun setIconAppearance(activity: Activity, appearance: Int) {
            val controller = activity.window.insetsController ?: return
            if (controller.systemBarsAppearance and ICON_MASK != appearance) {
                controller.setSystemBarsAppearance(appearance, ICON_MASK)
            }
        }
    }

    companion object {
        internal const val COVER_TAG = "mknoon_locked_call"
        internal const val CONTENT_TAG = "mknoon_call_protected_content"
        private const val OBSERVE_MS = 250L

        /** Register before FlutterActivity.onCreate, including ordinary restores.
         * The callback only removes a splash Android has handed over after draw
         * readiness. It never grants keyguard visibility or bypasses Flutter's
         * pre-draw fence; those remain owned by the validated call surface.
         */
        internal fun installSplashExit(activity: Activity) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
            Api31.installCallSplashExit(activity)
            debugSplash("listener_installed", activity, "scope=activityCreate")
        }

        private fun intentAction(intent: Intent?): String = when (intent?.action) {
            AndroidMknoonCallPendingIntentFactory.ACTION_OPEN_INCOMING_CALL -> "openIncoming"
            MknoonCallActionReceiver.ACTION_ANSWER -> "answer"
            Intent.ACTION_MAIN -> "main"
            null -> "none"
            else -> "other"
        }

        private fun debugSplash(phase: String, activity: Activity, detail: String) {
            if (!BuildConfig.DEBUG) return
            runCatching {
                android.util.Log.i("MknoonCallSplash",
                    "CALL_ANDROID_SPLASH phase=$phase activity=${System.identityHashCode(activity)} " +
                        "uptimeMs=${android.os.SystemClock.uptimeMillis()} $detail")
            }
        }

        private fun callId(intent: Intent?): UUID? {
            if (intent?.action != AndroidMknoonCallPendingIntentFactory.ACTION_OPEN_INCOMING_CALL &&
                intent?.action != MknoonCallActionReceiver.ACTION_ANSWER
            ) return null
            val raw = intent.getStringExtra(MknoonCallActionReceiver.EXTRA_NATIVE_CALL_ID) ?: return null
            return runCatching { UUID.fromString(raw) }.getOrNull()
                ?.takeIf { it.toString().equals(raw, ignoreCase = true) }
        }

        private fun runtimeSource(activity: Activity): MknoonIncomingCallPresentationSource =
            object : MknoonIncomingCallPresentationSource {
                private val controller get() = MknoonCallRuntime.get(activity).controller
                override fun snapshot() = controller.snapshot()
                override fun isCleanupPending(nativeCallId: UUID) =
                    controller.isCleanupPending(nativeCallId)
                override fun isAudioActive(nativeCallId: UUID) =
                    controller.audioState(nativeCallId)?.active == true
                override fun presentation(nativeCallId: UUID) = controller.presentation(nativeCallId)
                override fun mute(nativeCallId: UUID, muted: Boolean) = controller.onMuteChanged(nativeCallId, muted)
                override fun route(nativeCallId: UUID, route: String) = controller.requestRoute(nativeCallId, route)
                override fun answer(nativeCallId: UUID) = controller.answer(nativeCallId)
                override fun terminate(nativeCallId: UUID, type: PendingNativeCallEventType) =
                    controller.terminate(nativeCallId, type)
            }
    }
}
