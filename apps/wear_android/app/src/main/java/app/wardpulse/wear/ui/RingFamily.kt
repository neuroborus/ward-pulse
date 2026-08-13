package app.wardpulse.wear.ui

/**
 * Provider-family stroke colors for watch rings
 * (`docs/product/WATCH_RING_DESIGN.md`).
 */
object RingFamily {
    const val CODEX = 0xFF65D78A.toInt()
    const val CLAUDE = 0xFFE8915A.toInt()

    /** Cursor, and its external models pool by extension. */
    const val CURSOR = 0xFF67E8D4.toInt()

    /** The Cursor plan's own models — the one pool that leaves the family colour. */
    const val CURSOR_OWN = 0xFF7E93B8.toInt()

    /** Deliberately colourless: an id that names no family should not ship. */
    const val FALLBACK = 0xFF8A968F.toInt()

    /** ARGB for WFF [COMPLICATION.RANGED_VALUE_COLORS] / Compose strokes. */
    fun colorArgb(ringId: String): Int =
        when {
            ringId.startsWith("allowance.codex") ||
                ringId.contains(".codex.") ||
                ringId.startsWith("allowance.openai") ||
                ringId.contains(".openai.") -> CODEX
            // One family, two names: allowances say `claude`, connection keys `anthropic`.
            ringId.startsWith("allowance.claude") ||
                ringId.contains(".claude.") ||
                ringId.contains(".anthropic.") -> CLAUDE
            // Before the family branch, or it would never be reached: the pool
            // name sits inside an `allowance.cursor.` id.
            ringId.contains("cursor-plan-models") -> CURSOR_OWN
            ringId.startsWith("allowance.cursor") || ringId.contains(".cursor.") -> CURSOR
            else -> FALLBACK
        }
}
