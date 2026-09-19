package com.mknoon.app.call

/** Display-only seed returned by an authenticated headless admission. */
internal data class MknoonIncomingCallDisplay(
    val displayName: String,
    val avatarPng: ByteArray?,
    val light: Boolean,
) {
    fun toRingingMetadata() = MknoonLockedCallMetadata(
        displayName = displayName,
        avatarPng = avatarPng?.clone(),
        state = "ringing",
        connectedAtMs = null,
        light = light,
        muted = false,
        muteAvailable = false,
        speakerOn = false,
        speakerAvailable = false,
        routeLabel = "",
    )

    companion object {
        private val fields = setOf("displayName", "avatarPng", "light")
        private val pngSignature = byteArrayOf(-119, 80, 78, 71, 13, 10, 26, 10)

        fun parse(value: Any?): MknoonIncomingCallDisplay? {
            val map = value as? Map<*, *> ?: return null
            if (map.keys != fields) return null
            val name = map["displayName"] as? String ?: return null
            if (name.isBlank() || name.length > 128) return null
            val light = map["light"] as? Boolean ?: return null
            val avatar = map["avatarPng"]
            if (avatar != null && (avatar !is ByteArray || !boundedPng(avatar))) return null
            return MknoonIncomingCallDisplay(name, (avatar as? ByteArray)?.clone(), light)
        }

        private fun boundedPng(bytes: ByteArray): Boolean {
            if (bytes.size !in 33..512 * 1024 ||
                !bytes.copyOfRange(0, 8).contentEquals(pngSignature) ||
                !bytes.copyOfRange(12, 16).contentEquals(byteArrayOf(73, 72, 68, 82))) return false
            fun integer(offset: Int): Long = (offset until offset + 4).fold(0L) { result, index ->
                (result shl 8) or (bytes[index].toLong() and 0xffL)
            }
            // The producer renders a small avatar. Bound decoded allocation as
            // well as compressed bytes before the visible view decodes it.
            return integer(8) == 13L && integer(16) in 1L..2048L && integer(20) in 1L..2048L
        }
    }
}

/** In-memory, authenticated presentation only. No transport hints or persistence. */
internal data class MknoonLockedCallMetadata(
    val displayName: String,
    val avatarPng: ByteArray?,
    val state: String,
    val connectedAtMs: Long?,
    val light: Boolean,
    val muted: Boolean,
    val muteAvailable: Boolean,
    val speakerOn: Boolean,
    val speakerAvailable: Boolean,
    val routeLabel: String,
) {
    companion object {
        val fields = setOf("displayName", "avatarPng", "state", "connectedAtMs", "light", "muted", "muteAvailable", "speakerOn", "speakerAvailable", "routeLabel")
        fun parse(map: Map<*, *>): MknoonLockedCallMetadata? {
            val name = map["displayName"] as? String ?: return null
            val state = map["state"] as? String ?: return null
            val route = map["routeLabel"] as? String ?: return null
            if (name.isBlank() || name.length > 128 || route.length > 160 ||
                state !in setOf("preparing", "inviting", "ringing", "accepted", "negotiating", "connected", "reconnecting", "ending")) return null
            val avatar = map["avatarPng"]
            if (avatar != null && (avatar !is ByteArray || avatar.size > 512 * 1024)) return null
            val connected = map["connectedAtMs"]
            if (connected != null && connected !is Long && connected !is Int) return null
            return MknoonLockedCallMetadata(name, (avatar as? ByteArray)?.clone(), state,
                (connected as? Number)?.toLong()?.takeIf { it > 0 },
                map["light"] as? Boolean ?: return null,
                map["muted"] as? Boolean ?: return null,
                map["muteAvailable"] as? Boolean ?: return null,
                map["speakerOn"] as? Boolean ?: return null,
                map["speakerAvailable"] as? Boolean ?: return null, route)
        }
    }
}
