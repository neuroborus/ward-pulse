package app.wardpulse.wear.watchface

import android.content.Context
import android.content.SharedPreferences

enum class WatchFaceConsent {
    Eligible,
    PermissionPending,
    PermissionDeclined,
    ActivationAttempted,
}

interface WatchFaceConsentHistory {
    fun read(): WatchFaceConsent
    fun compareAndSet(expected: WatchFaceConsent, consent: WatchFaceConsent): Boolean
}

class WatchFaceConsentStore internal constructor(
    private val preferences: SharedPreferences,
) : WatchFaceConsentHistory {
    constructor(context: Context) : this(
        context.applicationContext.getSharedPreferences("watch_face_consent", Context.MODE_PRIVATE),
    )

    override fun read(): WatchFaceConsent = synchronized(lock) {
        val saved = preferences.getString("history", null) ?: return@synchronized WatchFaceConsent.Eligible
        // Unknown history must never restore a consumed permission or activation opportunity.
        WatchFaceConsent.entries.firstOrNull { it.name == saved }
            ?: WatchFaceConsent.ActivationAttempted
    }

    override fun compareAndSet(expected: WatchFaceConsent, consent: WatchFaceConsent): Boolean = synchronized(lock) {
        if (read() != expected) return@synchronized false
        preferences.edit().putString("history", consent.name).commit()
    }

    private companion object {
        // Activity-owned controllers construct separate stores in the same application process.
        // Hold this shared lock through commit: only a durable winning claim authorizes an effect.
        val lock = Any()
    }
}
