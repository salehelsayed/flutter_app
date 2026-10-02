package com.mknoon.app.call

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Rect
import android.os.Build
import android.os.Looper
import android.util.TypedValue
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import android.view.WindowManager
import android.view.WindowInsets
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityNodeProvider
import android.widget.Button
import android.widget.TextView
import com.mknoon.app.R
import java.time.Duration
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.robolectric.annotation.LooperMode
import org.robolectric.util.ReflectionHelpers

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [24, 26, 27, 34])
@LooperMode(LooperMode.Mode.PAUSED)
class MknoonIncomingCallPresentationTest {
    private lateinit var activity: IncomingPresentationActivity
    private lateinit var privateContent: TextView
    private lateinit var source: PresentationSource
    private lateinit var presentation: MknoonIncomingCallPresentation
    private var locked = true
    private var now = 1_000L

    @Before
    fun setUp() {
        activity = Robolectric.buildActivity(IncomingPresentationActivity::class.java).setup().get()
        privateContent = TextView(activity).apply { text = "Private conversation" }
        activity.setContentView(privateContent)
        source = PresentationSource()
        presentation = presenter()
    }

    @After
    fun tearDown() {
        presentation.dispose()
    }

    @Test
    fun `unlocked ringing wakes the screen without granting lockscreen access`() {
        locked = false
        presentation.onIntent(openIntent(), answerFromIntent = false)
        assertWindowEnabled(false, expectedWake = true)
        assertNull(cover())
        presentation.onStop()
        assertWindowEnabled(false)
        presentation.onResume()
        assertWindowEnabled(false, expectedWake = true)
        source.current = null
        tick()
        assertWindowEnabled(false)
    }

    @Test
    fun `initial and warm call launch cover private routes and expose explicit answer and decline`() {
        presentation.onIntent(openIntent(), answerFromIntent = true)

        assertCovered()
        assertWindowEnabled(true)
        assertNotNull(button(R.string.call_notification_answer))
        assertNotNull(button(R.string.call_notification_decline))
        assertTrue(source.answers.isEmpty())

        presentation.onStop()
        assertWindowEnabled(false)
        assertNull(cover())
        presentation.onIntent(openIntent(), answerFromIntent = true)
        assertCovered()
        assertWindowEnabled(true)
        assertTrue(source.answers.isEmpty())
    }

    @Test
    @Config(sdk = [31, 34])
    fun `early splash exit covers ordinary restore without granting call or keyguard access`() {
        // Robolectric's default RoboSplashScreen intentionally discards exit
        // listeners. Record this platform boundary so we can deliver the real
        // callback and verify removal without pretending to run Shell WM.
        var registered: android.window.SplashScreen.OnExitAnimationListener? = null
        val splashScreen = object : android.window.SplashScreen {
            override fun setOnExitAnimationListener(listener: android.window.SplashScreen.OnExitAnimationListener) { registered = listener }
            override fun clearOnExitAnimationListener() { registered = null }
            override fun setSplashScreenTheme(themeId: Int) = Unit
        }
        ReflectionHelpers.setField(shadowOf(activity), "splashScreen", splashScreen)
        fun listener() = registered
        assertNull(listener())
        MknoonIncomingCallPresentation.installSplashExit(activity)
        val exit = requireNotNull(listener())
        presentation.onIntent(Intent(Intent.ACTION_MAIN), answerFromIntent = false)
        assertTrue(exit === listener())
        assertNull(cover())
        assertWindowEnabled(false)
        val ordinarySplash = ReflectionHelpers.callConstructor(
            android.window.SplashScreenView::class.java,
            ReflectionHelpers.ClassParameter.from(android.content.Context::class.java, activity),
        )
        exit.onSplashScreenExit(ordinarySplash)
        assertEquals(View.GONE, ordinarySplash.visibility)
        assertNull(cover())
        assertWindowEnabled(false)
        assertTrue(source.answers.isEmpty())
        presentation.onIntent(openIntent(OTHER_ID), answerFromIntent = false)
        assertTrue(exit === listener())
        assertNull(cover())
        assertWindowEnabled(false)
        source.current = source.current!!.copy(direction = PendingNativeCallDirection.OUTGOING)
        presentation.onIntent(openIntent(), answerFromIntent = false)
        assertTrue(exit === listener())
        assertNull(cover())
        assertWindowEnabled(false)
        source.current = source.current!!.copy(direction = PendingNativeCallDirection.INCOMING)
        locked = false
        presentation.onIntent(openIntent(), answerFromIntent = false)
        assertTrue(exit === listener())
        assertNull(cover())
        assertWindowEnabled(false, expectedWake = true)
        locked = true
        presentation.onResume()
        assertTrue(exit === listener())
        assertCovered()
        assertWindowEnabled(true)
        // Merely installing the callback cannot hide Flutter or release the
        // first-frame draw fence. Only Android invokes exit after readiness.
        assertTrue(privateContent.isShown)
        val splash = ReflectionHelpers.callConstructor(
            android.window.SplashScreenView::class.java,
            ReflectionHelpers.ClassParameter.from(android.content.Context::class.java, activity),
        )
        assertEquals(View.VISIBLE, splash.visibility)
        val content = activity.findViewById<ViewGroup>(android.R.id.content)
        content.measure(View.MeasureSpec.makeMeasureSpec(480, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(800, View.MeasureSpec.EXACTLY))
        content.layout(0, 0, 480, 800)
        drawContent()
        assertEquals(View.INVISIBLE, protectedContent().visibility)
        exit.onSplashScreenExit(splash)
        assertEquals("the handed-over starting surface cannot remain above native controls", View.GONE, splash.visibility)
        assertCovered()
        assertWindowEnabled(true)
        assertTrue(source.answers.isEmpty())
        tick()
        assertTrue("observation does not install another splash callback", exit === listener())
    }

    @Test
    @Config(sdk = [24, 26, 27])
    fun `early splash registration leaves pre Android 12 startup and lock flags unchanged`() {
        val flags = activity.window.attributes.flags
        MknoonIncomingCallPresentation.installSplashExit(activity)
        assertEquals(flags, activity.window.attributes.flags)
        presentation.onIntent(Intent(Intent.ACTION_MAIN), answerFromIntent = false)
        assertNull(cover())
        assertWindowEnabled(false)
    }

    @Test
    fun `native cover keeps the renderer drawable behind first-frame gate and restores interaction after unlock`() {
        privateContent.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
        privateContent.isFocusableInTouchMode = true
        privateContent.requestFocus()
        // Flutter's surface renderer cannot produce its first frame when its
        // view is hidden. Its pre-draw listener then cancels the entire shared
        // window, including sibling native controls. Model that prerequisite
        // here so hiding the renderer fails even though controls exist in XML.
        val observer = privateContent.viewTreeObserver
        var flutterHasRendered = false
        lateinit var firstFrameGate: ViewTreeObserver.OnPreDrawListener
        firstFrameGate = ViewTreeObserver.OnPreDrawListener {
            if (flutterHasRendered) observer.removeOnPreDrawListener(firstFrameGate)
            flutterHasRendered
        }
        observer.addOnPreDrawListener(firstFrameGate)
        try {
            presentation.onIntent(openIntent(), answerFromIntent = true)
            assertCovered()
            assertTrue("Flutter must remain shown to produce its first frame", privateContent.isShown)
            assertTrue("window waits for the first Flutter frame", observer.dispatchOnPreDraw())
            flutterHasRendered = privateContent.isShown
            assertFalse("native window drawing must not be canceled", observer.dispatchOnPreDraw())
            assertFalse(privateContent.requestFocus())
            assertFalse(privateContent.hasFocus())
            val content = activity.findViewById<ViewGroup>(android.R.id.content)
            assertTrue(content.indexOfChild(cover()) > content.indexOfChild(protectedContent()))
            content.measure(
                View.MeasureSpec.makeMeasureSpec(480, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(800, View.MeasureSpec.EXACTLY),
            )
            content.layout(0, 0, 480, 800)
            val opaqueCover = requireNotNull(cover())
            assertEquals(0, opaqueCover.left)
            assertEquals(0, opaqueCover.top)
            assertEquals(content.width, opaqueCover.width)
            assertEquals(content.height, opaqueCover.height)
            drawContent()
            assertEquals(View.INVISIBLE, protectedContent().visibility)
            assertFalse("cached Flutter accessibility hosts are no longer shown", privateContent.isShown)
            assertFalse("hiding after the first frame must not close the draw gate", observer.dispatchOnPreDraw())
            drawContent()
            assertEquals(View.INVISIBLE, protectedContent().visibility)

            locked = false
            tick()
            assertWindowEnabled(false, expectedWake = true)
            assertNull(cover())
            assertEquals(View.IMPORTANT_FOR_ACCESSIBILITY_YES, privateContent.importantForAccessibility)
            assertTrue(privateContent.isFocusable)
            assertTrue(privateContent.isFocusableInTouchMode)
            assertEquals(View.VISIBLE, privateContent.visibility)
            assertEquals(View.VISIBLE, protectedContent().visibility)
            assertTrue(privateContent.isShown)

            locked = true
            source.current = source.current!!.copy(nativeCallId = OTHER_ID)
            presentation.onIntent(openIntent(OTHER_ID), answerFromIntent = true)
            assertFalse("warm successor hides cached hosts before any new draw", privateContent.isShown)
            drawContent()
            assertFalse("successor call also hides cached Flutter hosts", privateContent.isShown)
            presentation.onStop()
            assertEquals(View.VISIBLE, protectedContent().visibility)
        } finally {
            observer.removeOnPreDrawListener(firstFrameGate)
        }
    }

    @Test
    fun `debug splash timing records only categorical ownership without call identity payloads`() {
        val privateAction = "private-action-sentinel"
        presentation.onIntent(Intent(privateAction).putExtra("private", "private-payload-sentinel"), false)
        presentation.onIntent(openIntent(), false)
        presentation.onResume()
        val content = activity.findViewById<ViewGroup>(android.R.id.content)
        content.measure(View.MeasureSpec.makeMeasureSpec(480, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(800, View.MeasureSpec.EXACTLY))
        content.layout(0, 0, 480, 800)
        drawContent()
        val messages = org.robolectric.shadows.ShadowLog.getLogsForTag("MknoonCallSplash").map { it.msg }
        assertTrue(messages.any { "phase=intent" in it && "action=other" in it })
        assertTrue(messages.any { "phase=intent" in it && "action=openIncoming" in it && "validIncoming=true" in it })
        assertTrue(messages.any { "phase=cover_first_draw" in it })
        assertTrue(messages.any { "phase=cover_hidden_flutter" in it && "protectedShown=false" in it })
        val combined = messages.joinToString("\n")
        for (secret in listOf(privateAction, "private-payload-sentinel", "private-wake-handle", CALL_ID.toString(), OTHER_ID.toString())) {
            assertFalse("diagnostics exclude payload and call identifiers", secret in combined)
        }
    }

    @Test
    fun `Flutter semantics changes cannot expose private descendants through native protection ancestor`() {
        val content = activity.findViewById<ViewGroup>(android.R.id.content)
        val initialParent = privateContent.parent
        presentation.onIntent(openIntent(), answerFromIntent = true)
        // Flutter's virtual-node bridge can make its view important again
        // after attachment/resume. The native ancestor must remain decisive.
        privateContent.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
        privateContent.isFocusableInTouchMode = true
        val accessible = arrayListOf<View>()
        content.addChildrenForAccessibility(accessible)
        assertFalse(accessible.contains(privateContent))
        assertFalse(accessible.contains(protectedContent()))
        assertTrue(accessible.contains(requireNotNull(cover())))
        assertFalse(privateContent.requestFocus())
        val event = AccessibilityEvent.obtain(AccessibilityEvent.TYPE_VIEW_ACCESSIBILITY_FOCUSED)
        assertFalse(protectedContent().requestSendAccessibilityEvent(privateContent, event))
        assertEquals(View.VISIBLE, privateContent.visibility)

        locked = false
        tick()
        accessible.clear()
        content.addChildrenForAccessibility(accessible)
        assertTrue(accessible.contains(privateContent))
        assertTrue(privateContent.requestFocus())
        assertEquals(initialParent, privateContent.parent)
        locked = true
        tick()
        assertEquals(initialParent, privateContent.parent)
        assertCovered()
    }

    @Test
    fun `previously rendered activity fences cached hosts immediately and retired cover cannot hide restored content`() {
        drawContent()
        presentation.onIntent(openIntent(), answerFromIntent = true)
        val retiredCover = requireNotNull(cover())
        assertFalse(privateContent.isShown)
        drawView(retiredCover)
        presentation.onStop()
        assertEquals(View.VISIBLE, protectedContent().visibility)
        drawView(retiredCover)
        assertEquals("retired draw callbacks must not hide restored content", View.VISIBLE, protectedContent().visibility)

        presentation.onResume()
        assertFalse(privateContent.isShown)
        drawContent()
        button(R.string.call_notification_answer)!!.performClick()
        assertEquals(listOf(CALL_ID), source.answers)
        locked = false
        tick()
        assertEquals(View.VISIBLE, protectedContent().visibility)
        drawView(retiredCover)
        assertTrue(privateContent.isShown)
    }

    @Test
    fun `uncompressed accessibility fetch cannot traverse into visible Flutter virtual provider while covered`() {
        val content = activity.findViewById<ViewGroup>(android.R.id.content)
        val virtualView = object : View(activity) {
            var queries = 0
            private val provider = object : AccessibilityNodeProvider() {
                override fun createAccessibilityNodeInfo(virtualViewId: Int): AccessibilityNodeInfo {
                    queries += 1
                    return AccessibilityNodeInfo.obtain().apply {
                        text = "Private Flutter conversation"
                        isVisibleToUser = true
                    }
                }
            }
            override fun getAccessibilityNodeProvider(): AccessibilityNodeProvider = provider
        }
        protectedContent().addView(virtualView)
        // UiAutomator's uncompressed fetch requests non-important views. The
        // platform then bypasses NO_HIDE_DESCENDANTS in includeForAccessibility,
        // and prefetch calls addChildrenForAccessibility directly on each host.
        val attachInfo = ReflectionHelpers.getField<Any>(content, "mAttachInfo")
        val oldFlags = ReflectionHelpers.getField<Int>(attachInfo, "mAccessibilityFetchFlags")
        val includeAll = ReflectionHelpers.getStaticField<Int>(
            AccessibilityNodeInfo::class.java,
            if (Build.VERSION.SDK_INT >= 34) "FLAG_SERVICE_REQUESTS_INCLUDE_NOT_IMPORTANT_VIEWS"
            else "FLAG_INCLUDE_NOT_IMPORTANT_VIEWS",
        )
        ReflectionHelpers.setField(attachInfo, "mAccessibilityFetchFlags", oldFlags or includeAll)
        fun traverse(view: View) {
            val provider = view.accessibilityNodeProvider
            if (provider != null) {
                provider.createAccessibilityNodeInfo(AccessibilityNodeProvider.HOST_VIEW_ID)
            } else if (view is ViewGroup) {
                val children = arrayListOf<View>()
                view.addChildrenForAccessibility(children)
                children.forEach(::traverse)
            }
        }
        try {
            presentation.onIntent(openIntent(), answerFromIntent = true)
            assertCovered()
            assertEquals(View.VISIBLE, virtualView.visibility)
            traverse(content)
            assertEquals("private virtual provider must not be queried", 0, virtualView.queries)
            val hostChildren = arrayListOf<View>()
            protectedContent().addChildrenForAccessibility(hostChildren)
            assertTrue(hostChildren.isEmpty())
            drawContent()
            assertFalse("framework cached-ID requests reject hosts that are not shown", virtualView.isShown)
            assertEquals(View.INVISIBLE, protectedContent().visibility)

            locked = false
            tick()
            traverse(content)
            assertEquals("unlock restores the existing virtual provider", 1, virtualView.queries)
            protectedContent().addChildrenForAccessibility(hostChildren)
            assertTrue(hostChildren.contains(virtualView))
            locked = true
            presentation.onIntent(openIntent(), answerFromIntent = true)
            virtualView.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
            virtualView.visibility = View.VISIBLE
            assertFalse("cached virtual IDs are fenced before a warm cover draws", virtualView.isShown)
            traverse(content)
            assertEquals("warm cover must not query the cached provider", 1, virtualView.queries)
        } finally {
            ReflectionHelpers.setField(attachInfo, "mAccessibilityFetchFlags", oldFlags)
        }
    }

    @Test
    fun `answer uses the exact native lifecycle and accepted cover offers end through expiry`() {
        presentation.onIntent(openIntent(), answerFromIntent = true)
        button(R.string.call_notification_answer)!!.performClick()

        assertEquals(listOf(CALL_ID), source.answers)
        assertNull(button(R.string.call_notification_answer))
        assertNotNull(button(R.string.call_notification_end))
        assertTrue(texts().contains(activity.getString(R.string.call_screen_connecting)))
        now = 90_000L
        source.audioActive = true
        source.metadata = metadata(state = "connected", connectedAtMs = 2_000L)
        tick()
        assertCovered()
        assertWindowEnabled(true)
        assertTrue(texts().contains(activity.getString(R.string.call_screen_connected)))

        button(R.string.call_notification_end)!!.performClick()
        assertEquals(listOf(CALL_ID to PendingNativeCallEventType.END_REQUESTED), source.terminals)
        assertRetiredWhileLocked()
    }

    @Test
    fun `canonical metadata drives identity active status timer and exact audio actions`() {
        source.metadata = metadata()
        presentation.onIntent(openIntent(), answerFromIntent = false)
        assertTrue(texts().contains("Authenticated contact"))
        val avatar = descendants(cover()).first { it.tag == "call_avatar" }
        assertEquals((112 * activity.resources.displayMetrics.density).toInt(), avatar.layoutParams.width)
        val answer = button(R.string.call_notification_answer)!!
        assertEquals((68 * activity.resources.displayMetrics.density).toInt(), answer.layoutParams.width)
        assertEquals(answer.text, answer.contentDescription)
        val accessibleActions = arrayListOf<View>()
        (answer.parent as ViewGroup).addChildrenForAccessibility(accessibleActions)
        assertEquals("normal accessibility exposes one labeled action, not its visual caption", listOf(answer), accessibleActions)
        val content = activity.findViewById<ViewGroup>(android.R.id.content)
        content.measure(View.MeasureSpec.makeMeasureSpec(480, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(800, View.MeasureSpec.EXACTLY))
        content.layout(0, 0, 480, 800)
        val row = (answer.parent.parent as ViewGroup)
        val children = (0 until row.childCount).map(row::getChildAt)
        val spacers = children.filter { it.javaClass == View::class.java }
        assertEquals(3, spacers.size)
        assertTrue("the Flutter spaceEvenly gaps differ by at most one rounded pixel", spacers.maxOf { it.width } - spacers.minOf { it.width } <= 1)
        answer.performClick()
        source.audioActive = true
        tick()
        assertTrue("native audio activation alone is not Connected", texts().contains(activity.getString(R.string.call_screen_connecting)))
        source.metadata = metadata(state = "connected", connectedAtMs = 1_000L)
        now = 66_000L
        tick()
        assertTrue(texts().contains("01:05"))
        button(R.string.call_screen_mute)!!.performClick()
        button(R.string.call_screen_speaker)!!.performClick()
        assertEquals(listOf(CALL_ID to true), source.mutes)
        assertEquals(listOf(CALL_ID to "speaker"), source.routes)
        val staleMute = button(R.string.call_screen_mute)!!
        source.current = source.current!!.copy(nativeCallId = OTHER_ID)
        presentation.onIntent(openIntent(OTHER_ID), answerFromIntent = false)
        staleMute.performClick()
        assertEquals(1, source.mutes.size)
    }

    @Test
    @Suppress("DEPRECATION")
    fun `native light and dark surfaces own system icon contrast only while covering Flutter`() {
        val decor = activity.window.decorView
        val navigationFlag = if (Build.VERSION.SDK_INT >= 26) View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR else 0
        val lightFlags = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or navigationFlag
        decor.systemUiVisibility = View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or lightFlags
        if (Build.VERSION.SDK_INT >= 30) {
            activity.window.insetsController!!.setSystemBarsAppearance(
                android.view.WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or
                    android.view.WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS,
                android.view.WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or
                    android.view.WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS,
            )
        }
        source.metadata = metadata().copy(light = true)
        presentation.onIntent(openIntent(), answerFromIntent = false)
        assertEquals(navigationFlag, decor.systemUiVisibility and lightFlags)
        assertSystemIconContrast(light = true)
        assertCovered()

        source.metadata = metadata().copy(light = false)
        tick()
        assertEquals(0, decor.systemUiVisibility and lightFlags)
        assertSystemIconContrast(light = false)

        source.metadata = metadata().copy(light = true)
        tick()
        // A concurrent owner may change unrelated layout bits. Removing the
        // native cover must restore only the icon appearance it temporarily owns.
        decor.systemUiVisibility = decor.systemUiVisibility or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
        locked = false
        tick()
        assertNull(cover())
        assertEquals(lightFlags, decor.systemUiVisibility and lightFlags)
        assertTrue(decor.systemUiVisibility and View.SYSTEM_UI_FLAG_LAYOUT_STABLE != 0)
        assertTrue(decor.systemUiVisibility and View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN != 0)
        if (Build.VERSION.SDK_INT >= 30) {
            val appearance = activity.window.insetsController!!.systemBarsAppearance
            assertTrue(appearance and android.view.WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS != 0)
            assertTrue(appearance and android.view.WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS != 0)
        }
    }

    @Test
    @Suppress("DEPRECATION")
    fun `terminal light cover retains readable system icons until stop and stale intents cannot style the app`() {
        val original = activity.window.decorView.systemUiVisibility
        presentation.onIntent(openIntent(OTHER_ID), answerFromIntent = false)
        assertEquals(original, activity.window.decorView.systemUiVisibility)
        source.metadata = metadata().copy(light = true)
        presentation.onIntent(openIntent(), answerFromIntent = false)
        assertSystemIconContrast(light = true)
        source.current = source.current!!.copy(terminalEvent = terminalEvent())
        tick()
        assertRetiredWhileLocked()
        assertSystemIconContrast(light = true)
        presentation.onStop()
        assertEquals(original, activity.window.decorView.systemUiVisibility)
        assertNull(cover())
    }

    @Suppress("DEPRECATION")
    private fun assertSystemIconContrast(light: Boolean) {
        val flags = activity.window.decorView.systemUiVisibility
        assertFalse("the inset contrast band always uses white status icons", flags and View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR != 0)
        if (Build.VERSION.SDK_INT >= 26) {
            assertEquals(light, flags and View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR != 0)
        }
        if (Build.VERSION.SDK_INT >= 30) {
            val appearance = activity.window.insetsController!!.systemBarsAppearance
            assertEquals(0, appearance and android.view.WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS)
            assertEquals(light, appearance and android.view.WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS != 0)
        }
    }

    @Test
    @Config(sdk = [26, 34])
    @GraphicsMode(GraphicsMode.Mode.NATIVE)
    fun `status contrast band paints actual inset and retained terminal without changing light body or navigation`() {
        source.metadata = metadata().copy(light = true)
        presentation.onIntent(openIntent(), answerFromIntent = false)
        val surface = requireNotNull(cover())
        surface.dispatchApplyWindowInsets(statusInsets(top = 80, bottom = 120))
        drawPixels(surface) { pixels ->
            assertEquals("status region has contrast beneath OS-owned white icons", 0xFF0A0A0F.toInt(), pixels.getPixel(1, 1))
            assertEquals(0xFF0A0A0F.toInt(), pixels.getPixel(1, 79))
            assertEquals("call body remains Light below the actual status inset", 0xFFF4F0EA.toInt(), pixels.getPixel(1, 80))
            assertEquals("navigation region keeps the Light surface", 0xFFF4F0EA.toInt(), pixels.getPixel(1, 799))
        }
        assertFalse("first draw still hides the private renderer", privateContent.isShown)
        assertSystemIconContrast(light = true)

        // A changed inset on the same cover must change painted geometry, not
        // leave a guessed status-bar height behind after rotation.
        surface.dispatchApplyWindowInsets(statusInsets(top = 32, bottom = 40))
        drawPixels(surface, width = 800, height = 480) { pixels ->
            assertEquals(0xFF0A0A0F.toInt(), pixels.getPixel(1, 31))
            assertEquals(0xFFF4F0EA.toInt(), pixels.getPixel(1, 32))
        }
        source.current = source.current!!.copy(terminalEvent = terminalEvent())
        tick()
        assertTrue("terminal privacy retains the same cover", surface === cover())
        drawPixels(surface) { pixels -> assertEquals(0xFF0A0A0F.toInt(), pixels.getPixel(1, 1)) }
        assertSystemIconContrast(light = true)
        presentation.onStop()
        assertNull(cover())
    }

    @Test
    @Config(sdk = [26, 34])
    @GraphicsMode(GraphicsMode.Mode.NATIVE)
    fun `status contrast band never guesses missing insets or paints outside window overlap`() {
        source.metadata = metadata().copy(light = true)
        presentation.onIntent(openIntent(), answerFromIntent = false)
        val surface = requireNotNull(cover())
        surface.dispatchApplyWindowInsets(statusInsets(top = 0, bottom = 120))
        drawPixels(surface) { pixels -> assertEquals(0xFFF4F0EA.toInt(), pixels.getPixel(1, 1)) }

        surface.dispatchApplyWindowInsets(statusInsets(top = 80, bottom = 120))
        drawPixels(surface, windowY = 100) { pixels ->
            assertEquals("an already-inset cover must not paint a second band", 0xFFF4F0EA.toInt(), pixels.getPixel(1, 1))
        }
        surface.dispatchApplyWindowInsets(statusInsets(top = 900, bottom = 0))
        drawPixels(surface) { pixels -> assertEquals(0xFF0A0A0F.toInt(), pixels.getPixel(1, 799)) }
    }

    @Suppress("DEPRECATION")
    private fun statusInsets(top: Int, bottom: Int): WindowInsets =
        if (Build.VERSION.SDK_INT >= 30) WindowInsets.Builder()
            .setInsets(WindowInsets.Type.statusBars(), android.graphics.Insets.of(0, top, 0, 0))
            .setInsets(WindowInsets.Type.navigationBars(), android.graphics.Insets.of(0, 0, 0, bottom))
            .build()
        else ReflectionHelpers.callConstructor(WindowInsets::class.java,
            ReflectionHelpers.ClassParameter.from(Rect::class.java, Rect(0, top, 0, bottom)))

    private fun drawPixels(view: View, width: Int = 480, height: Int = 800, windowY: Int = 0, assertPixels: (Bitmap) -> Unit) {
        view.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY))
        view.layout(0, 0, width, height)
        // Robolectric's default Activity content is below its status bar.
        // Explicitly model the candidate's edge-to-edge origin, or the
        // already-inset fixture requested by the overlap regression.
        val position = IntArray(2)
        view.getLocationInWindow(position)
        view.translationY += (windowY - position[1]).toFloat()
        view.getLocationInWindow(position)
        assertEquals(windowY, position[1])
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        try {
            view.draw(Canvas(bitmap))
            assertPixels(bitmap)
        } finally {
            bitmap.recycle()
        }
    }

    @Test
    @Config(qualifiers = "ar-rSA-ldrtl")
    fun `light arabic large text remains scrollable with localized named controls`() {
        org.robolectric.RuntimeEnvironment.setFontScale(2f)
        source.metadata = metadata().copy(displayName = "اسم المتصل الطويل للاختبار", light = true)
        presentation.onIntent(openIntent(), answerFromIntent = false)
        val scroll = descendants(cover()).filterIsInstance<android.widget.ScrollView>().single()
        assertTrue(scroll.isFillViewport)
        val color = (requireNotNull(cover()).background as android.graphics.drawable.ColorDrawable).color
        assertEquals(0xFFF4F0EA.toInt(), color)
        assertEquals(activity.getString(R.string.call_notification_answer), button(R.string.call_notification_answer)!!.contentDescription)
        val content = activity.findViewById<ViewGroup>(android.R.id.content)
        content.measure(View.MeasureSpec.makeMeasureSpec(320, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(480, View.MeasureSpec.EXACTLY))
        content.layout(0, 0, 320, 480)
        assertTrue(scroll.getChildAt(0).height >= scroll.height)
        assertEquals(View.LAYOUT_DIRECTION_RTL, scroll.layoutDirection)
        assertTrue(button(R.string.call_notification_answer)!!.textSize > 16 * activity.resources.displayMetrics.density)
        assertCovered()
    }

    @Test
    fun `retained ringing and active labels resize and restore without replacing call controls`() {
        val originalScale = activity.resources.configuration.fontScale
        org.robolectric.RuntimeEnvironment.setFontScale(1f)
        source.metadata = metadata()
        presentation.onIntent(openIntent(), answerFromIntent = false)
        val retainedCover = requireNotNull(cover())
        val screen = descendants(retainedCover).filterIsInstance<MknoonLockedCallView>().single()
        drawContent()
        fun text(value: String) = descendants(screen).filterIsInstance<TextView>()
            .single { it !is Button && it.text.toString() == value }
        fun resizeAndRestore(labels: List<Pair<TextView, Float>>, controls: List<Button>) {
            val initialSizes = labels.map { it.first.textSize }
            val initialTexts = labels.map { it.first.text.toString() }
            val descriptions = controls.map { it.contentDescription.toString() }
            val enabled = controls.map { it.isEnabled }
            for (scale in listOf(1.6f, 1f)) {
                org.robolectric.RuntimeEnvironment.setFontScale(scale)
                retainedCover.dispatchConfigurationChanged(activity.resources.configuration)
                drawContent()
                assertTrue("font changes retain the exact opaque call cover", retainedCover === cover())
                assertTrue(screen === descendants(cover()).filterIsInstance<MknoonLockedCallView>().single())
                labels.forEachIndexed { index, (label, sp) ->
                    val expected = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, sp, activity.resources.displayMetrics)
                    assertEquals("current SP conversion for ${initialTexts[index]}", expected, label.textSize, 0.01f)
                    if (scale > 1f) assertTrue("visible label grows", label.textSize > initialSizes[index])
                    else assertEquals("restored size", initialSizes[index], label.textSize, 0.01f)
                    assertEquals("configuration does not reset identity, state, or elapsed time", initialTexts[index], label.text.toString())
                }
                assertEquals(descriptions, controls.map { it.contentDescription.toString() })
                assertEquals(enabled, controls.map { it.isEnabled })
                assertTrue(controls.all { it.isShown })
                assertTrue(screen.isFillViewport)
                assertTrue(screen.getChildAt(0).height >= screen.height)
                assertCovered()
                assertWindowEnabled(true)
                assertFalse("private Flutter content stays hidden", privateContent.isShown)
            }
        }
        try {
            val answer = button(R.string.call_notification_answer)!!
            val decline = button(R.string.call_notification_decline)!!
            val identity = text("Authenticated contact")
            resizeAndRestore(listOf(
                identity to 28f, screen.status to 16f,
                screen.answer.caption to 13f, screen.end.caption to 13f,
            ), listOf(answer, decline))
            assertTrue(source.answers.isEmpty())
            answer.performClick()
            source.audioActive = true
            source.metadata = metadata(state = "connected", connectedAtMs = 1_000L)
            now = 66_000L
            tick()
            val mute = button(R.string.call_screen_mute)!!
            val speaker = button(R.string.call_screen_speaker)!!
            val end = button(R.string.call_notification_end)!!
            val elapsed = text("01:05")
            resizeAndRestore(listOf(
                identity to 28f, screen.status to 16f, elapsed to 18f,
                text("Audio output: Earpiece") to 13f,
                text(activity.getString(R.string.call_screen_mute)) to 13f,
                text(activity.getString(R.string.call_screen_speaker)) to 13f,
                screen.end.caption to 13f,
            ), listOf(mute, speaker, end))
            now = 67_000L
            tick()
            assertEquals("01:06", elapsed.text.toString())
            mute.performClick()
            speaker.performClick()
            end.performClick()
            assertEquals(listOf(CALL_ID), source.answers)
            assertEquals(listOf(CALL_ID to true), source.mutes)
            assertEquals(listOf(CALL_ID to "speaker"), source.routes)
            assertEquals(listOf(CALL_ID to PendingNativeCallEventType.END_REQUESTED), source.terminals)
            assertRetiredWhileLocked()
        } finally {
            org.robolectric.RuntimeEnvironment.setFontScale(originalScale)
            retainedCover.dispatchConfigurationChanged(activity.resources.configuration)
        }
    }

    @Test
    fun `retained call rebinds localized actions and mirrors layout after locale changes`() {
        source.metadata = metadata()
        presentation.onIntent(openIntent(), answerFromIntent = false)
        val retained = cover()
        fun changeLocale(language: String) {
            val configuration = android.content.res.Configuration(activity.resources.configuration)
            configuration.setLocale(java.util.Locale.forLanguageTag(language))
            @Suppress("DEPRECATION")
            activity.resources.updateConfiguration(configuration, activity.resources.displayMetrics)
            tick()
            assertTrue("locale changes retain the exact call surface", retained === cover())
        }
        changeLocale("de")
        val answer = button(R.string.call_notification_answer)!!
        assertEquals("Annehmen", answer.contentDescription)
        answer.performClick()
        source.audioActive = true
        source.metadata = metadata(state = "connected", connectedAtMs = 1_000L)
        for (language in listOf("en", "de", "ar", "en")) {
            changeLocale(language)
            val speaker = button(R.string.call_screen_speaker)!!
            val mute = button(R.string.call_screen_mute)!!
            val end = button(R.string.call_notification_end)!!
            assertEquals(activity.getString(R.string.call_screen_speaker), speaker.contentDescription)
            val caption = (speaker.parent as ViewGroup).getChildAt(1) as TextView
            assertEquals(speaker.contentDescription, caption.text)
            val content = activity.findViewById<ViewGroup>(android.R.id.content)
            content.measure(View.MeasureSpec.makeMeasureSpec(480, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(800, View.MeasureSpec.EXACTLY))
            content.layout(0, 0, 480, 800)
            val scroll = descendants(cover()).filterIsInstance<android.widget.ScrollView>().single()
            assertEquals(if (language == "ar") View.LAYOUT_DIRECTION_RTL else View.LAYOUT_DIRECTION_LTR, scroll.layoutDirection)
            assertEquals("control order follows current locale", language == "ar", (mute.parent as View).left > (end.parent as View).left)
            assertCovered()
        }
        button(R.string.call_screen_speaker)!!.performClick()
        assertEquals(listOf(CALL_ID to "speaker"), source.routes)
        assertEquals(listOf(CALL_ID), source.answers)
    }

    @Test
    fun `ongoing notification restores native accepted surface after ordinary launch and rejects retired call`() {
        source.current = source.current!!.copy(answerRequested = true)
        source.metadata = metadata(state = "connected", connectedAtMs = 1_000L)
        source.audioActive = true
        presentation.onIntent(openIntent(), answerFromIntent = false)
        locked = false
        tick()
        presentation.onIntent(Intent(Intent.ACTION_MAIN), answerFromIntent = false)
        locked = true
        presentation.onResume()
        assertNull(cover())
        assertWindowEnabled(false)
        val notification = MknoonCallNotificationFactory(activity).createOngoing(CALL_ID)
        val open = shadowOf(notification.contentIntent).savedIntent
        presentation.onIntent(open, answerFromIntent = true)
        assertCovered()
        assertWindowEnabled(true)
        assertNotNull(button(R.string.call_notification_end))
        assertNull(button(R.string.call_notification_answer))
        assertTrue(source.answers.isEmpty())
        presentation.onStop()
        source.current = source.current!!.copy(nativeCallId = OTHER_ID)
        presentation.onIntent(open, answerFromIntent = true)
        assertNull(cover())
        assertWindowEnabled(false)
        assertTrue(source.answers.isEmpty())
        assertTrue(source.terminals.isEmpty())
    }

    @Test
    fun `ringing notification restores visible exact call actions after locked scope revocation before stop`() {
        presentation.onIntent(openIntent(), answerFromIntent = false)
        drawContent()
        val retained = cover()
        assertTrue(button(R.string.call_notification_answer)!!.isShown)

        presentation.onIntent(Intent(Intent.ACTION_MAIN), answerFromIntent = false)
        assertRetiredWhileLocked()
        val notification = MknoonCallNotificationFactory(activity).createIncoming(CALL_ID)
        val open = shadowOf(notification.contentIntent).savedIntent
        presentation.onIntent(open, answerFromIntent = true)

        assertTrue("the exact call reuses its still-opaque cover", retained === cover())
        assertCovered()
        assertWindowEnabled(true)
        assertFalse("private cached accessibility hosts remain hidden", privateContent.isShown)
        assertTrue(source.answers.isEmpty())
        val answer = button(R.string.call_notification_answer)!!
        assertTrue("Answer must be visible through its parent action row", answer.isShown)
        assertTrue(button(R.string.call_notification_decline)!!.isShown)
        answer.performClick()
        assertEquals(listOf(CALL_ID), source.answers)
        assertTrue(source.terminals.isEmpty())
    }

    @Test
    fun `ongoing notification restores visible exact call controls after locked scope revocation before stop`() {
        source.current = source.current!!.copy(answerRequested = true)
        source.metadata = metadata(state = "connected", connectedAtMs = 1_000L)
        source.audioActive = true
        presentation.onIntent(openIntent(), answerFromIntent = false)
        drawContent()
        val retained = cover()
        assertTrue(button(R.string.call_notification_end)!!.isShown)

        presentation.onIntent(Intent(Intent.ACTION_MAIN), answerFromIntent = false)
        assertRetiredWhileLocked()
        val notification = MknoonCallNotificationFactory(activity).createOngoing(CALL_ID)
        val open = shadowOf(notification.contentIntent).savedIntent
        presentation.onIntent(open, answerFromIntent = true)

        assertTrue("the exact call reuses its still-opaque cover", retained === cover())
        assertCovered()
        assertWindowEnabled(true)
        assertFalse("private cached accessibility hosts remain hidden", privateContent.isShown)
        assertNull(button(R.string.call_notification_answer))
        assertTrue("opening an accepted call must not replay Answer", source.answers.isEmpty())
        val mute = button(R.string.call_screen_mute)!!
        val speaker = button(R.string.call_screen_speaker)!!
        val end = button(R.string.call_notification_end)!!
        listOf(mute, speaker, end).forEach {
            assertTrue("active control ${it.text} must be visible through its parent action row", it.isShown)
            assertTrue(it.isEnabled)
        }
        mute.performClick()
        speaker.performClick()
        assertEquals(listOf(CALL_ID to true), source.mutes)
        assertEquals(listOf(CALL_ID to "speaker"), source.routes)
        end.performClick()
        assertEquals(listOf(CALL_ID to PendingNativeCallEventType.END_REQUESTED), source.terminals)
        assertRetiredWhileLocked()
    }

    @Test
    fun `decline dispatches exact native terminal action and preserves privacy until stopped`() {
        presentation.onIntent(openIntent(), answerFromIntent = true)
        button(R.string.call_notification_decline)!!.performClick()

        assertEquals(listOf(CALL_ID to PendingNativeCallEventType.DECLINE_REQUESTED), source.terminals)
        assertRetiredWhileLocked()
        presentation.onStop()
        assertNull(cover())
        assertEquals(View.VISIBLE, privateContent.visibility)
        presentation.onResume()
        assertWindowEnabled(false)
        assertNull(cover())
    }

    @Test
    fun `notification answer is explicit once and recreation does not replay the action`() {
        val answerIntent = openIntent().setAction(MknoonCallActionReceiver.ACTION_ANSWER)
        presentation.onIntent(answerIntent, answerFromIntent = true)
        assertEquals(listOf(CALL_ID), source.answers)
        assertCovered()
        presentation.dispose()
        presentation = presenter()
        presentation.onIntent(answerIntent, answerFromIntent = false)
        assertEquals(listOf(CALL_ID), source.answers)
        assertCovered()
        assertNotNull(button(R.string.call_notification_end))
    }

    @Test
    fun `unlock clears flags before restoring app and later lock restores only scoped call`() {
        presentation.onIntent(openIntent(), answerFromIntent = true)
        locked = false
        tick()
        assertWindowEnabled(false, expectedWake = true)
        assertNull(cover())
        assertEquals(View.VISIBLE, privateContent.visibility)
        locked = true
        tick()
        assertCovered()
        assertWindowEnabled(true)
    }

    @Test
    fun `ringing scope survives natural unlocked stop resume and relock without a new launch intent`() {
        presentation.onIntent(openIntent(), answerFromIntent = true)
        locked = false
        tick()
        presentation.onStop()
        presentation.onResume()
        assertNull(cover())
        assertWindowEnabled(false, expectedWake = true)
        assertEquals(View.VISIBLE, privateContent.visibility)
        locked = true
        tick()
        assertCovered()
        assertWindowEnabled(true)
        assertNotNull(button(R.string.call_notification_answer))
        assertNotNull(button(R.string.call_notification_decline))
        assertTrue(source.answers.isEmpty())
    }

    @Test
    fun `natural return cannot carry a stopped ringing scope into a different call`() {
        presentation.onIntent(openIntent(), answerFromIntent = true)
        presentation.onStop()
        source.current = source.current!!.copy(nativeCallId = OTHER_ID)
        presentation.onResume()
        assertNull(cover())
        assertWindowEnabled(false)
        assertTrue(source.answers.isEmpty())
    }

    @Test
    fun `unlocked incoming launch keeps Flutter visible and never grants lockscreen flags`() {
        locked = false
        presentation.onIntent(openIntent(), answerFromIntent = true)
        assertWindowEnabled(false, expectedWake = true)
        assertNull(cover())
        assertEquals(View.VISIBLE, privateContent.visibility)
        assertTrue(source.answers.isEmpty())
    }

    @Test
    fun `ordinary intent revokes call scope and resume cannot reauthorize it`() {
        presentation.onIntent(openIntent(), answerFromIntent = true)
        presentation.onIntent(Intent(Intent.ACTION_MAIN), answerFromIntent = true)
        assertRetiredWhileLocked()
        presentation.onStop()
        presentation.onResume()
        assertWindowEnabled(false)
        assertNull(cover())
        assertTrue(source.answers.isEmpty())
    }

    @Test
    fun `stale malformed outgoing expired and terminal intents cannot expose or answer private app`() {
        val valid = source.current!!
        val terminal = terminalEvent()
        val cases = listOf(
            valid.copy(nativeCallId = OTHER_ID),
            valid.copy(direction = PendingNativeCallDirection.OUTGOING),
            valid.copy(expiresAtMs = now),
            valid.copy(terminalEvent = terminal),
            null,
        )
        cases.forEach { descriptor ->
            source.current = descriptor
            presentation.onIntent(
                openIntent().setAction(MknoonCallActionReceiver.ACTION_ANSWER),
                answerFromIntent = true,
            )
            assertWindowEnabled(false)
            assertNull(cover())
            assertTrue(source.answers.isEmpty())
        }
        source.current = valid
        listOf("invalid", "0-0-4-8-1").forEach { raw ->
            presentation.onIntent(
                openIntent().putExtra(MknoonCallActionReceiver.EXTRA_NATIVE_CALL_ID, raw),
                answerFromIntent = true,
            )
            assertWindowEnabled(false)
            assertNull(cover())
        }
    }

    @Test
    fun `cleanup and remote terminal retire a visible cover within one observation without relay ownership`() {
        presentation.onIntent(openIntent(), answerFromIntent = true)
        source.cleanup = true
        tick()
        assertRetiredWhileLocked()
        presentation.onStop()
        source.cleanup = false
        presentation.onIntent(openIntent(), answerFromIntent = true)
        source.current = source.current!!.copy(terminalEvent = terminalEvent())
        tick()
        assertRetiredWhileLocked()
    }

    @Test
    fun `ring expiry and snapshot read failure revoke presentation without allowing stale controls`() {
        presentation.onIntent(openIntent(), answerFromIntent = true)
        val staleAnswer = button(R.string.call_notification_answer)!!
        now = source.current!!.expiresAtMs
        staleAnswer.performClick()
        assertTrue(source.answers.isEmpty())
        assertRetiredWhileLocked()
        presentation.onStop()
        now = 1_000L
        presentation.onIntent(openIntent(), answerFromIntent = true)
        source.failRead = true
        tick()
        assertRetiredWhileLocked()
    }

    @Test
    fun `new exact call intent replaces scope and queued previous controls cannot act on successor`() {
        presentation.onIntent(openIntent(), answerFromIntent = true)
        val staleAnswer = button(R.string.call_notification_answer)!!
        val staleDecline = button(R.string.call_notification_decline)!!
        source.current = source.current!!.copy(nativeCallId = OTHER_ID)
        presentation.onIntent(openIntent(OTHER_ID), answerFromIntent = true)
        staleAnswer.performClick()
        staleDecline.performClick()
        assertTrue(source.answers.isEmpty())
        assertTrue(source.terminals.isEmpty())
        button(R.string.call_notification_answer)!!.performClick()
        assertEquals(listOf(OTHER_ID), source.answers)
    }

    @Test
    fun `back backgrounds opaque call surface and destroy cancels future observation`() {
        presentation.onIntent(openIntent(), answerFromIntent = true)
        assertTrue(presentation.handleBack())
        assertTrue(activity.backgroundRequests > 0)
        assertCovered()
        presentation.dispose()
        tick()
        assertWindowEnabled(false)
        assertNull(cover())
        assertFalse(presentation.handleBack())
    }

    private fun presenter() = MknoonIncomingCallPresentation(
        activity = activity,
        source = source,
        nowMs = { now },
        isLocked = { locked },
    )

    private fun tick() = shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(250))

    private fun drawContent() = drawView(activity.findViewById<ViewGroup>(android.R.id.content))

    private fun drawView(view: View) {
        view.measure(
            View.MeasureSpec.makeMeasureSpec(480, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(800, View.MeasureSpec.EXACTLY),
        )
        view.layout(0, 0, 480, 800)
        val bitmap = Bitmap.createBitmap(480, 800, Bitmap.Config.ARGB_8888)
        try {
            view.draw(Canvas(bitmap))
        } finally {
            bitmap.recycle()
        }
    }

    private fun cover(): ViewGroup? = activity.findViewById<ViewGroup>(android.R.id.content)
        .findViewWithTag(MknoonIncomingCallPresentation.COVER_TAG)

    private fun protectedContent(): ViewGroup = activity.findViewById<ViewGroup>(android.R.id.content)
        .findViewWithTag(MknoonIncomingCallPresentation.CONTENT_TAG)

    private fun assertCovered() {
        val cover = requireNotNull(cover())
        assertEquals(View.VISIBLE, privateContent.visibility)
        assertEquals(
            View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS,
            protectedContent().importantForAccessibility,
        )
        assertEquals(ViewGroup.FOCUS_BLOCK_DESCENDANTS, protectedContent().descendantFocusability)
        assertTrue(cover.isClickable)
        assertEquals(1f, cover.alpha, 0f)
        assertEquals(255, Color.alpha((cover.background as android.graphics.drawable.ColorDrawable).color))
    }

    private fun assertRetiredWhileLocked() {
        assertWindowEnabled(false)
        assertCovered()
        assertTrue(activity.backgroundRequests > 0)
        assertTrue(texts().contains(activity.getString(R.string.call_screen_ended)))
        assertNull(button(R.string.call_notification_answer))
        assertNull(button(R.string.call_notification_decline))
        assertNull(button(R.string.call_notification_end))
    }

    private fun assertWindowEnabled(expected: Boolean, expectedWake: Boolean = expected) {
        assertEquals("Lockscreen access must follow the opaque cover", 0, activity.unsafeGrants)
        if (Build.VERSION.SDK_INT >= 27) {
            assertEquals(expected, shadowOf(activity).showWhenLocked)
            assertEquals(expectedWake, shadowOf(activity).turnScreenOn)
        } else {
            @Suppress("DEPRECATION")
            val lockFlag = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
            val wakeFlag = WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            assertEquals(if (expected) lockFlag else 0, activity.window.attributes.flags and lockFlag)
            assertEquals(if (expectedWake) wakeFlag else 0, activity.window.attributes.flags and wakeFlag)
        }
    }

    private fun descendants(view: View?): List<View> = when (view) {
        null -> emptyList()
        is ViewGroup -> listOf(view) + (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) }
        else -> listOf(view)
    }

    private fun texts() = descendants(cover()).filterIsInstance<TextView>()
        .filter { it.visibility == View.VISIBLE }.map { it.text.toString() }

    private fun button(resource: Int) = descendants(cover()).filterIsInstance<Button>()
        .firstOrNull { it.visibility == View.VISIBLE && it.text == activity.getString(resource) }

    private fun openIntent(id: UUID = CALL_ID) =
        Intent(AndroidMknoonCallPendingIntentFactory.ACTION_OPEN_INCOMING_CALL)
            .putExtra(MknoonCallActionReceiver.EXTRA_NATIVE_CALL_ID, id.toString())

    private class PresentationSource : MknoonIncomingCallPresentationSource {
        var current: PendingNativeCallDescriptor? = PendingNativeCallDescriptor(
            nativeCallId = CALL_ID,
            callHandle = CALL_ID.toString(),
            wakeHandle = "private-wake-handle",
            receivedAtMs = 1_000L,
            expiresAtMs = 60_000L,
            highestSequence = 1L,
            terminalEvent = null,
            events = emptyList(),
            phase = PendingNativeCallPhase.JOURNAL,
        )
        var metadata: MknoonLockedCallMetadata? = null
        val mutes = mutableListOf<Pair<UUID, Boolean>>()
        val routes = mutableListOf<Pair<UUID, String>>()
        override fun presentation(nativeCallId: UUID) = metadata
        override fun mute(nativeCallId: UUID, muted: Boolean): Boolean { mutes += nativeCallId to muted; return true }
        override fun route(nativeCallId: UUID, route: String): Boolean { routes += nativeCallId to route; return true }
        var cleanup = false
        var audioActive = false
        var failRead = false
        val answers = mutableListOf<UUID>()
        val terminals = mutableListOf<Pair<UUID, PendingNativeCallEventType>>()
        override fun snapshot(): PendingNativeCallDescriptor? {
            check(!failRead)
            return current
        }
        override fun isCleanupPending(nativeCallId: UUID) = cleanup
        override fun isAudioActive(nativeCallId: UUID) = audioActive
        override fun answer(nativeCallId: UUID): Boolean {
            answers += nativeCallId
            current = current?.copy(answerRequested = true)
            return true
        }
        override fun terminate(nativeCallId: UUID, type: PendingNativeCallEventType): Boolean {
            terminals += nativeCallId to type
            current = current?.copy(terminalEvent = terminalEvent().copy(type = type))
            return true
        }
    }

    companion object {
        private val CALL_ID = UUID.fromString("00000000-0000-4000-8000-000000000501")
        private val OTHER_ID = UUID.fromString("00000000-0000-4000-8000-000000000502")
        private fun metadata(state: String = "ringing", connectedAtMs: Long? = null) = MknoonLockedCallMetadata(
            "Authenticated contact", null, state, connectedAtMs, false, false, true, false, true, "Audio output: Earpiece",
        )
        private fun terminalEvent() = PendingNativeCallEvent(
            nativeCallId = CALL_ID,
            sequence = 2L,
            eventId = OTHER_ID,
            type = PendingNativeCallEventType.REMOTE_CANCELLED,
        )
    }
}

class IncomingPresentationActivity : Activity() {
    var backgroundRequests = 0
    var unsafeGrants = 0

    override fun moveTaskToBack(nonRoot: Boolean): Boolean {
        backgroundRequests += 1
        return true
    }

    override fun setShowWhenLocked(showWhenLocked: Boolean) {
        if (showWhenLocked) recordGrant()
        super.setShowWhenLocked(showWhenLocked)
    }

    override fun onWindowAttributesChanged(params: WindowManager.LayoutParams) {
        @Suppress("DEPRECATION")
        if (params.flags and WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED != 0) recordGrant()
        super.onWindowAttributesChanged(params)
    }

    private fun recordGrant() {
        val content = findViewById<ViewGroup>(android.R.id.content)
        val cover = content?.findViewWithTag<View>(MknoonIncomingCallPresentation.COVER_TAG)
        val covered = content != null && (0 until content.childCount).all {
            val view = content.getChildAt(it)
            view === cover ||
                (view.importantForAccessibility == View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS &&
                    !view.isFocusable)
        } && cover != null &&
            content.getChildAt(content.childCount - 1) === cover &&
            cover.visibility == View.VISIBLE && cover.alpha == 1f &&
            Color.alpha((cover.background as android.graphics.drawable.ColorDrawable).color) == 255 &&
            cover.layoutParams.width == ViewGroup.LayoutParams.MATCH_PARENT &&
            cover.layoutParams.height == ViewGroup.LayoutParams.MATCH_PARENT
        if (!covered) unsafeGrants += 1
    }
}
