package app.wardpulse.wear.ui

/**
 * Provider-family stroke colors for watch rings
 * (`docs/product/WATCH_RING_DESIGN.md`).
 */
object RingFamily {
    const val CODEX = 0xFF65D78A.toInt()
    const val CLAUDE = 0xFFE8915A.toInt()
    const val CURSOR = 0xFF67E8D4.toInt()
    const val BUDGET = 0xFF8AB4F8.toInt()
    const val FALLBACK = BUDGET

    /** ARGB for WFF [COMPLICATION.RANGED_VALUE_COLORS] / Compose strokes. */
    fun colorArgb(ringId: String): Int =
        when {
            ringId.startsWith("allowance.codex") ||
                ringId.contains(".codex.") ||
                ringId.startsWith("allowance.openai") ||
                ringId.contains(".openai.") -> CODEX
            ringId.startsWith("allowance.claude") || ringId.contains(".claude.") -> CLAUDE
            ringId.startsWith("allowance.cursor") || ringId.contains(".cursor.") -> CURSOR
            ringId.startsWith("budget.") -> BUDGET
            else -> FALLBACK
        }
}
