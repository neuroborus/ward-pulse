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
    fun write(consent: WatchFaceConsent): Boolean
}

class WatchFaceConsentStore internal constructor(
    private val preferences: SharedPreferences,
) : WatchFaceConsentHistory {
    constructor(context: Context) : this(
        context.applicationContext.getSharedPreferences("watch_face_consent", Context.MODE_PRIVATE),
    )

    override fun read(): WatchFaceConsent {
        val saved = preferences.getString("history", null) ?: return WatchFaceConsent.Eligible
        // Unknown history must never restore a consumed permission or activation opportunity.
        return WatchFaceConsent.entries.firstOrNull { it.name == saved }
            ?: WatchFaceConsent.ActivationAttempted
    }

    override fun write(consent: WatchFaceConsent): Boolean =
        preferences.edit().putString("history", consent.name).commit()
}
