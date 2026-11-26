package app.wardpulse.watchsync

import android.content.Context
import android.content.SharedPreferences

/** One flat-cache publication; a failed disk commit does not roll back memory. */
class PhoneWidgetPublicationStore(private val preferences: SharedPreferences) {
    fun publish(publication: Map<*, *>, mode: Mode? = null): Boolean {
        val editor = stage(publication, mode, null, false)
        return synchronized(monitor) { editor.commit() }
    }

    /**
     * Commits only while [ticket] and what it was issued against are current; null otherwise.
     * [proven] rows reach each widget first only while that authority holds (see [Mode.deliverIfCurrent]).
     */
    fun publish(publication: Map<*, *>, mode: Mode?, ticket: Long, engine: ConnectionCacheEngine,
        proven: Boolean = true): Boolean? {
        val editor = stage(publication, mode, ticket, proven)
        return engine.commitWidgetPublication(ticket, mode?.generation) {
            synchronized(monitor) {
                editor.commit().also { committed ->
                    // Memory keeps the flags after a failed disk write; unconfirmed rows are not
                    // established, and the disk may still hold a renewal flag that memory lacks.
                    if (!committed) {
                        renewalUnconfirmed = true
                        preferences.edit().remove(COMPLETE).commit()
                    }
                }
            }
        }
    }

    private fun stage(publication: Map<*, *>, mode: Mode?, ticket: Long?, proven: Boolean): SharedPreferences.Editor {
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
        // Only a full ticketed publication represents the saved settings; STALE keeps the flag as is.
        if (ticket != null) editor.putLong(SEQUENCE, ticket).putBoolean(COMPLETE, true)
        else editor.remove(SEQUENCE).remove(COMPLETE)
        // Durable, so a restart that loses the authority cannot hand undelivered rows to a widget.
        if (proven) editor.putStringSet(DELIVERED, emptySet()).putStringSet(FRAMED, emptySet())
            .putBoolean(RENEWABLE, true)
        else editor.remove(DELIVERED).remove(FRAMED).remove(RENEWABLE)
        return editor
    }

    /** Null means initial/empty data: no write and no redraw are needed. */
    fun markStale(mode: Mode? = null): Boolean? = markStale(mode, null)

    /**
     * Marks only the committed rows a failed load [observed]; null when they were replaced, a newer
     * publication is pending, or no rows exist.
     */
    fun markStale(mode: Mode?, observed: Long, engine: ConnectionCacheEngine): Boolean? =
        engine.markWidgetStale(observed, mode?.generation, { sequence() ?: 0L }) { ticket -> markStale(mode, ticket) }

    private fun markStale(mode: Mode?, ticket: Long?): Boolean? = synchronized(monitor) {
        val snapshot = preferences.all.let { mode?.eligibleRows(it) ?: it }
        val count = (snapshot["row_count"] as? Number)?.toInt() ?: 0
        if (count <= 0 || snapshot["empty"] == "1") null
        else {
            val editor = preferences.edit()
            editor.putString("stale", "1")
            if (ticket != null) editor.putLong(SEQUENCE, ticket)
            editor.commit()
        }
    }

    /** The stored publication's ticket; null for legacy or unordered rows. */
    fun sequence(): Long? = sequenceOf(preferences.all)

    /**
     * Whether the current mode already owns a full ticketed publication of the saved settings,
     * including an explicit empty one, and each of the installed [widgets] holds a frame of it.
     * Durable, so it survives a restart; a widget still owed a frame needs a fresh publication.
     */
    fun established(mode: Mode, widgets: Collection<String> = emptyList()): Boolean {
        val cache = preferences.all
        return mode.installId == null || (cache[INSTALL] == mode.installId &&
            cache[GENERATION] == mode.generation && cache[COMPLETE] == true &&
            (cache[FRAMED] as? Set<*>)?.containsAll(widgets) != false)
    }

    /**
     * Records that a settings save began, so the stored rows no longer represent the saved
     * settings until a full publication replaces them, even if the process dies first.
     */
    fun retireSettings(): Boolean = synchronized(monitor) { preferences.edit().remove(COMPLETE).commit() }

    /**
     * Records, before a newer load is accepted, that a restart cannot renew the stored rows'
     * authority. False when the disk write is unconfirmed; the next call retries it even though
     * memory already lacks the flag after it or a failed publication (a commit rewrites the file
     * while an earlier write failed).
     */
    fun retireRenewal(): Boolean {
        synchronized(monitor) {
            if (!renewalUnconfirmed && !preferences.contains(RENEWABLE)) return true
            renewalUnconfirmed = !preferences.edit().remove(RENEWABLE).commit()
            return !renewalUnconfirmed
        }
    }

    data class Mode(val installId: String?, val generation: Long?, val source: String?) {
        fun eligible(cache: Map<String, *>): Boolean = if (INSTALL in cache || GENERATION in cache) {
            installId != null && generation != null &&
                installId == cache[INSTALL] && generation == cache[GENERATION]
        } else {
            // Legacy untagged rows can be retained before initialization or in initial Live.
            installId == null || (generation == 0L && source == "live")
        }

        fun eligibleRows(cache: Map<String, *>): Map<String, *> = if (eligible(cache)) cache else emptyMap<String, Any>()

        /**
         * Delivers [widget]'s views rendered from the publication with [sequence] only while it is
         * still stored in [data]. When the submitted views show its own content ([rows]: metric
         * rows or its explicit empty result) and the widget has not shown it yet, that
         * publication's authority must also still hold; a newer publication's own redraw replaces
         * them. After a restart, synthetic rows renew it from the durable full-publication flag
         * unless a newer load was accepted before the restart, and until one is accepted after it. A refused widget is owed a frame, so the publication is no
         * longer established.
         */
        fun deliverIfCurrent(context: Context, data: SharedPreferences, widget: Int, sequence: Long?,
            rows: Boolean, deliver: () -> Unit) {
            val id = widget.toString()
            // Legacy and unordered rows carry no delivery sets and need no proof.
            engine(context).deliverWidgetIfCurrent(installId, generation, sequence, rows, { sequenceOf(data.all) },
                { data.getStringSet(DELIVERED, null)?.contains(id) != false },
                { data.all.let { it[COMPLETE] == true && it[RENEWABLE] == true } }, {
                    deliver()
                    track(data, id, true, rows)
                }) { track(data, id, false, false) }
        }
    }

    companion object {
        /** The process-wide authority that orders publications and their launcher delivery. */
        fun engine(context: Context): ConnectionCacheEngine = ConnectionCacheChannel.engine(context.applicationContext)

        fun currentMode(context: Context): Mode = modeFrom(engine(context).readMode())

        internal fun modeFrom(record: Map<String, Any>) = Mode(
            record["installId"] as? String, record["generation"] as? Long, record["mode"] as? String,
        )

        fun sequenceOf(cache: Map<String, *>): Long? = cache[SEQUENCE] as? Long

        /** Records whether [id] holds a frame of the stored proven rows, and whether it shows them. */
        private fun track(data: SharedPreferences, id: String, framed: Boolean, shown: Boolean) {
            synchronized(monitor) {
                val frames = data.getStringSet(FRAMED, null) ?: return
                val delivered = data.getStringSet(DELIVERED, null).orEmpty()
                val next = if (framed) frames + id else frames - id
                if (next == frames && (!shown || id in delivered)) return
                val editor = data.edit().putStringSet(FRAMED, next)
                if (shown) editor.putStringSet(DELIVERED, delivered + id)
                editor.commit()
            }
        }

        private const val INSTALL = "publication_install"
        private const val GENERATION = "publication_generation"
        private const val SEQUENCE = "publication_sequence"
        private const val COMPLETE = "publication_complete"
        // Set by a proven commit; a newer accepted load clears it before its acceptance is visible.
        private const val RENEWABLE = "publication_renewable"
        // Widget ids that showed the stored ticketed rows; absent for rows that need no proof.
        private const val DELIVERED = "publication_delivered"
        // Widget ids holding any frame of them, rows or none; the rest are owed one.
        private const val FRAMED = "publication_framed"
        private val monitor = Any()
        // A failed renewal retirement or publication, guarded by [monitor]: the disk may still hold the flag.
        private var renewalUnconfirmed = false
        private val FIELDS = listOf("kind", "spent_minor", "spent_currency", "cap_minor", "cap_currency",
            "extra_used_value", "extra_used_unit", "extra_cap_value", "extra_cap_unit",
            "percent", "credits", "label", "family", "pool", "resets_at", "color")
    }
}
