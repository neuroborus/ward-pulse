package app.wardpulse.watchsync

import android.content.SharedPreferences

/** One flat-cache publication; a failed disk commit does not roll back memory. */
class PhoneWidgetPublicationStore(private val preferences: SharedPreferences) {
    fun publish(publication: Map<*, *>): Boolean {
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
        return synchronized(monitor) { editor.commit() }
    }

    /** Null means initial/empty data: no write and no redraw are needed. */
    fun markStale(): Boolean? = synchronized(monitor) {
        val snapshot = preferences.all
        val count = (snapshot["row_count"] as? Number)?.toInt() ?: 0
        if (count <= 0 || snapshot["empty"] == "1") null
        else {
            val editor = preferences.edit()
            editor.putString("stale", "1")
            editor.commit()
        }
    }

    private companion object {
        val monitor = Any()
        val FIELDS = listOf("kind", "spent_minor", "spent_currency", "cap_minor", "cap_currency",
            "extra_used_value", "extra_used_unit", "extra_cap_value", "extra_cap_unit",
            "percent", "credits", "label", "family", "pool", "resets_at", "color")
    }
}
