package app.wardpulse.watchsync

import android.content.Context
import android.content.SharedPreferences

/** One flat-cache publication; a failed disk commit does not roll back memory. */
class PhoneWidgetPublicationStore(private val preferences: SharedPreferences) {
    fun publish(publication: Map<*, *>, mode: Mode? = null): Boolean {
        val count = publication["row_count"] as? Int
        require(count != null && count in 0..6) { "Invalid widget row count." }
        require(publication["empty"] == if (count == 0) "1" else "0")
        require(publication["stale"] in listOf("0", "1"))
        val values = linkedMapOf<String, Any>("row_count" to count,
            "empty" to publication["empty"] as String, "stale" to publication["stale"] as String)
        for (slot in 0 until 6) for (field in FIELDS) {
            val key = "row_${slot}_$field"
            val value = publication[key]
            require(value is String && (slot < count || value.isEmpty())) { "Invalid widget field." }
            values[key] = value
        }
        // Validate everything before opening/staging the editor. Staging is private
        // and may overlap another full publication; only commit needs the monitor.
        val editor = preferences.edit()
        for ((key, value) in values) {
            if (value is Int) editor.putInt(key, value) else editor.putString(key, value as String)
        }
        if (mode?.installId != null && mode.generation != null) {
            editor.putString(INSTALL, mode.installId)
            editor.putLong(GENERATION, mode.generation)
        } else {
            editor.remove(INSTALL).remove(GENERATION)
        }
        return synchronized(monitor) { editor.commit() }
    }

    /** Null means initial/empty data: no write and no redraw are needed. */
    fun markStale(mode: Mode? = null): Boolean? = synchronized(monitor) {
        val snapshot = preferences.all.let { mode?.eligibleRows(it) ?: it }
        val count = (snapshot["row_count"] as? Number)?.toInt() ?: 0
        if (count <= 0 || snapshot["empty"] == "1") null
        else {
            val editor = preferences.edit()
            editor.putString("stale", "1")
            editor.commit()
        }
    }

    data class Mode(val installId: String?, val generation: Long?, val source: String?) {
        fun eligibleRows(cache: Map<String, *>): Map<String, *> {
            val eligible = if (INSTALL in cache || GENERATION in cache) {
                installId != null && generation != null &&
                    installId == cache[INSTALL] && generation == cache[GENERATION]
            } else {
                // Legacy untagged rows can be retained before initialization or in initial Live.
                installId == null || (generation == 0L && source == "live")
            }
            return if (eligible) cache else emptyMap<String, Any>()
        }

        fun deliverIfCurrent(context: Context, deliver: () -> Unit) {
            ConnectionCacheChannel.engine(context.applicationContext)
                .deliverWidgetIfModeCurrent(installId, generation) { deliver() }
        }
    }

    companion object {
        fun currentMode(context: Context): Mode = modeFrom(
            ConnectionCacheChannel.engine(context.applicationContext).readMode(),
        )

        internal fun modeFrom(record: Map<String, Any>) = Mode(
            record["installId"] as? String, record["generation"] as? Long, record["mode"] as? String,
        )

        private const val INSTALL = "publication_install"
        private const val GENERATION = "publication_generation"
        private val monitor = Any()
        private val FIELDS = listOf("kind", "spent_minor", "spent_currency", "cap_minor", "cap_currency",
            "extra_used_value", "extra_used_unit", "extra_cap_value", "extra_cap_unit",
            "percent", "credits", "label", "family", "pool", "resets_at", "color")
    }
}
