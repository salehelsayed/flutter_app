package com.mknoon.app.call

import android.content.Context
import android.content.res.Configuration
import android.graphics.*
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.*
import com.mknoon.app.R
import kotlin.math.max

/** Display-only counterpart of IncomingCallScreen / ActiveCallScreen. */
internal class MknoonLockedCallView(
    context: Context,
    onAnswer: () -> Unit,
    onEnd: () -> Unit,
    onMute: () -> Unit,
    onSpeaker: () -> Unit,
) : ScrollView(context) {
    private val column = LinearLayout(context)
    private val avatar = ImageView(context)
    private val name = label(28f)
    val status = label(16f)
    private val duration = label(18f)
    private val route = label(13f)
    private val actions = LinearLayout(context)
    val answer = action(R.string.call_notification_answer, "answer", onAnswer)
    val end = action(R.string.call_notification_decline, "end", onEnd)
    private val mute = action(R.string.call_screen_mute, "mic", onMute)
    private val speaker = action(R.string.call_screen_speaker, "speaker", onSpeaker)
    private var lastAvatar: ByteArray? = null
    private var shownActive: Boolean? = null
    private var metadata: MknoonLockedCallMetadata? = null

    init {
        isFillViewport = true
        isVerticalScrollBarEnabled = false
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        column.orientation = LinearLayout.VERTICAL
        column.gravity = Gravity.CENTER_HORIZONTAL
        column.setPadding(dp(24), dp(48), dp(24), dp(32))
        addView(column, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        column.addView(View(context), LinearLayout.LayoutParams(1, dp(24), 1f))
        avatar.importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        avatar.scaleType = ImageView.ScaleType.FIT_CENTER
        avatar.tag = "call_avatar"
        column.addView(avatar, LinearLayout.LayoutParams(dp(112), dp(112)))
        column.addView(name, fullWidth(24))
        name.maxLines = 1
        name.ellipsize = android.text.TextUtils.TruncateAt.END
        name.typeface = if (android.os.Build.VERSION.SDK_INT >= 28) Typeface.create(Typeface.SANS_SERIF, 600, false) else Typeface.create("sans-serif-medium", Typeface.NORMAL)
        column.addView(status, fullWidth(10))
        status.accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
        column.addView(duration, fullWidth(8))
        duration.typeface = Typeface.MONOSPACE
        column.addView(View(context), LinearLayout.LayoutParams(1, dp(24), 1f))
        column.addView(route, fullWidth(0))
        actions.gravity = Gravity.CENTER
        actions.orientation = LinearLayout.HORIZONTAL
        column.addView(actions, fullWidth(16))
        render(null, false, false, 0)
    }

    fun render(data: MknoonLockedCallMetadata?, accepted: Boolean, audioActive: Boolean, nowMs: Long) {
        metadata = data
        // The same authenticated call may reopen before onStop removes a
        // retired cover. Restore the action row as well as its child buttons.
        actions.visibility = VISIBLE
        // MainActivity handles locale/layoutDirection without recreation. A
        // retained call surface must rebind both its static labels and row
        // direction when the same call survives a configuration change.
        layoutDirection = resources.configuration.layoutDirection
        val light = data?.light == true
        val primary = if (light) 0xFF25222B.toInt() else 0xFFF8FAFC.toInt()
        val secondary = if (light) 0xFF56515E.toInt() else 0xFFCACDD1.toInt()
        val accent = if (light) 0xFF6045B6.toInt() else 0xFF1DB954.toInt()
        // The Flutter dark base is translucent; the keyguard cover must remain
        // fully opaque to preserve its privacy boundary.
        setBackgroundColor(if (light) 0xFFF4F0EA.toInt() else 0xFF0A0A0F.toInt())
        name.text = data?.displayName ?: context.getString(R.string.call_notification_title)
        name.setTextColor(primary)
        val connected = accepted && data?.state == "connected"
        status.setText(when {
            !accepted -> R.string.call_notification_incoming
            data?.state == "reconnecting" -> R.string.call_screen_reconnecting
            data?.state == "ending" -> R.string.call_screen_ended
            connected -> R.string.call_screen_connected
            // Audio activation alone never proves media connectivity.
            else -> R.string.call_screen_connecting
        })
        status.setTextColor(if (connected) { if (light) 0xFF236143.toInt() else accent } else secondary)
        val connectedAt = data?.connectedAtMs
        duration.visibility = if (accepted && connectedAt != null && data.state in setOf("connected", "reconnecting")) VISIBLE else GONE
        if (duration.visibility == VISIBLE) {
            val seconds = max(0L, (nowMs - connectedAt!!) / 1000)
            duration.text = if (seconds >= 3600) "%02d:%02d:%02d".format(seconds / 3600, seconds / 60 % 60, seconds % 60)
                else "%02d:%02d".format(seconds / 60, seconds % 60)
            duration.contentDescription = context.getString(R.string.call_screen_duration, duration.text)
        }
        duration.setTextColor(primary)
        if (lastAvatar !== data?.avatarPng) {
            lastAvatar = data?.avatarPng
            val bitmap = data?.avatarPng?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
            if (bitmap != null) avatar.setImageBitmap(bitmap) else avatar.setImageDrawable(null)
        }
        if (data?.avatarPng == null) avatar.setImageDrawable(GenericAvatarDrawable(accent))
        if (shownActive != accepted) {
            actions.removeAllViews()
            if (accepted) { addAction(mute); addAction(speaker); addAction(end) }
            else { addAction(end); addAction(answer) }
            addActionSpacer()
            shownActive = accepted
        }
        answer.label(R.string.call_notification_answer)
        answer.paintColors(accent, Color.WHITE, secondary)
        answer.visibility = if (accepted) GONE else VISIBLE
        end.visibility = VISIBLE
        end.label(if (accepted) R.string.call_notification_end else R.string.call_notification_decline)
        end.paintColors(0xFFE5484D.toInt(), Color.WHITE, secondary)
        val raised = if (light) 0xFFFAF8F3.toInt() else 0xFF181A20.toInt()
        mute.label(if (data?.muted == true) R.string.call_screen_unmute else R.string.call_screen_mute)
        mute.icon = if (data?.muted == true) "mic_off" else "mic"
        mute.isEnabled = data?.muteAvailable == true && audioActive
        speaker.isEnabled = data?.speakerAvailable == true && audioActive
        speaker.label(R.string.call_screen_speaker)
        speaker.icon = if (data?.speakerOn == true) "speaker_on" else "speaker"
        mute.paintColors(if (data?.muted == true) accent else raised, if (data?.muted == true) Color.WHITE else primary, secondary)
        speaker.paintColors(if (data?.speakerOn == true) accent else raised, if (data?.speakerOn == true) Color.WHITE else primary, secondary)
        (actions.layoutParams as LinearLayout.LayoutParams).topMargin = if (accepted) dp(16) else 0
        route.text = data?.routeLabel
        route.setTextColor(secondary)
        route.visibility = if (accepted && !data?.routeLabel.isNullOrBlank()) VISIBLE else GONE
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        // MainActivity retains this view on fontScale changes. TextView stores
        // pixels, so reapply SP through the current platform conversion (which
        // also supports nonlinear font scaling) without rebinding call state.
        name.setTextSize(TypedValue.COMPLEX_UNIT_SP, 28f)
        status.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        duration.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
        route.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        for (action in listOf(answer, end, mute, speaker)) {
            action.caption.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        }
    }

    fun retire() {
        actions.visibility = GONE
        route.visibility = GONE
        duration.visibility = GONE
        status.setText(R.string.call_screen_ended)
    }

    private fun addAction(button: IconAction) {
        val group = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        (button.parent as? ViewGroup)?.removeView(button)
        group.addView(button, LinearLayout.LayoutParams(dp(68), dp(68)))
        (button.caption.parent as? ViewGroup)?.removeView(button.caption)
        group.addView(button.caption, LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply { topMargin = dp(10) })
        addActionSpacer()
        actions.addView(group, LinearLayout.LayoutParams(dp(68), LayoutParams.WRAP_CONTENT))
    }

    private fun addActionSpacer() {
        actions.addView(View(context), LinearLayout.LayoutParams(0, 1, 1f))
    }

    private fun label(size: Float) = TextView(context).apply {
        textSize = size
        gravity = Gravity.CENTER
        includeFontPadding = false
        textDirection = View.TEXT_DIRECTION_LOCALE
    }
    private fun fullWidth(top: Int) = LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply { topMargin = dp(top) }
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
    private fun action(resource: Int, icon: String, onClick: () -> Unit) = IconAction(context, icon).apply {
        label(resource)
        setOnClickListener { onClick() }
    }

    /** Keeps real Button semantics; visible text is below the circular icon. */
    internal class IconAction(context: Context, var icon: String) : Button(context) {
        val caption = TextView(context).apply {
            gravity = Gravity.CENTER
            textSize = 13f
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
            includeFontPadding = false
        }
        private val materialIcons = runCatching {
            Typeface.createFromAsset(context.assets, "flutter_assets/fonts/MaterialIcons-Regular.otf")
        }.getOrNull()
        private var ink = Color.WHITE
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        init { setPadding(0, 0, 0, 0); minWidth = 0; minHeight = 0 }
        fun label(resource: Int) { setText(resource); contentDescription = text; caption.text = text }
        fun paintColors(fill: Int, foreground: Int, labelColor: Int) {
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(fill) }
            ink = foreground
            caption.setTextColor(labelColor)
            alpha = if (isEnabled) 1f else 0.45f
            invalidate()
        }
        override fun onDraw(canvas: Canvas) {
            materialIcons?.let { font ->
                val glyph = when (icon) {
                    "answer" -> 0xf608
                    "end" -> 0xf602
                    "mic" -> 0xf8bb
                    "mic_off" -> 0xf8bc
                    "speaker_on" -> 0xf029a
                    else -> 0xf4a5
                }
                paint.color = ink
                paint.style = Paint.Style.FILL
                paint.typeface = font
                paint.textSize = 30 * resources.displayMetrics.density
                paint.textAlign = Paint.Align.CENTER
                val baseline = height / 2f - (paint.ascent() + paint.descent()) / 2f
                canvas.drawText(String(Character.toChars(glyph)), width / 2f, baseline, paint)
                return
            }
            canvas.save()
            canvas.translate(width / 2f - 15 * resources.displayMetrics.density, height / 2f - 15 * resources.displayMetrics.density)
            canvas.scale(30 * resources.displayMetrics.density / 24f, 30 * resources.displayMetrics.density / 24f)
            paint.color = ink; paint.style = Paint.Style.STROKE; paint.strokeWidth = 2f; paint.strokeCap = Paint.Cap.ROUND; paint.strokeJoin = Paint.Join.ROUND
            val path = Path()
            when (icon) {
                "mic", "mic_off" -> {
                    canvas.drawRoundRect(9f, 2f, 15f, 14f, 3f, 3f, paint)
                    canvas.drawArc(6f, 6f, 18f, 18f, 0f, 180f, false, paint)
                    canvas.drawLine(12f, 18f, 12f, 22f, paint)
                    canvas.drawLine(8f, 22f, 16f, 22f, paint)
                    if (icon == "mic_off") canvas.drawLine(3f, 2f, 22f, 21f, paint)
                }
                "speaker", "speaker_on" -> {
                    path.moveTo(3f, 9f); path.lineTo(7f, 9f); path.lineTo(12f, 5f); path.lineTo(12f, 19f); path.lineTo(7f, 15f); path.lineTo(3f, 15f); path.close(); canvas.drawPath(path, paint)
                    canvas.drawArc(9f, 3f, 23f, 21f, -55f, 110f, false, paint)
                    canvas.drawArc(12f, 7f, 19f, 17f, -65f, 130f, false, paint)
                }
                "end" -> {
                    path.moveTo(3f, 14f); path.cubicTo(7f, 8f, 17f, 8f, 21f, 14f); canvas.drawPath(path, paint)
                    paint.strokeWidth = 5f; canvas.drawLine(4f, 13f, 5f, 16f, paint); canvas.drawLine(20f, 13f, 19f, 16f, paint)
                }
                else -> {
                    path.moveTo(5f, 4f); path.cubicTo(3f, 12f, 12f, 21f, 20f, 19f); canvas.drawPath(path, paint)
                    paint.strokeWidth = 5f; canvas.drawLine(5f, 4f, 7f, 7f, paint); canvas.drawLine(17f, 17f, 20f, 19f, paint)
                }
            }
            canvas.restore()
        }
    }

    private class GenericAvatarDrawable(private val accent: Int) : android.graphics.drawable.Drawable() {
        override fun draw(canvas: Canvas) {
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = accent; style = Paint.Style.STROKE; strokeWidth = bounds.width() * .035f }
            val radius = bounds.width() / 2f
            canvas.drawCircle(bounds.centerX().toFloat(), bounds.centerY().toFloat(), radius * .9f, paint)
            canvas.drawCircle(bounds.centerX().toFloat(), bounds.centerY().toFloat(), radius * .6f, paint)
        }
        override fun setAlpha(alpha: Int) {}
        override fun setColorFilter(filter: ColorFilter?) {}
        @Deprecated("Deprecated in Java") override fun getOpacity() = PixelFormat.TRANSLUCENT
    }
}
