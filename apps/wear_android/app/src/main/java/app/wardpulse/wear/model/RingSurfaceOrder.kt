package app.wardpulse.wear.model

/**
 * Maps WFF/Compose face geometry to the phone watch payload.
 *
 * Payload order is **tightest-first** (index 0 = critical limit). Face geometry is
 * **outermost-first** for fixed arc slots, so slot 0 (largest diameter) binds
 * `rings[last]`, and the innermost active slot binds `rings[0]`.
 *
 * Strips and Glance use payload indices directly (index 0 nearest center / top).
 */
object RingSurfaceOrder {
    /**
     * Payload index for a face arc slot counted from the outside (0 = outermost).
     * Returns null when [outerSlotIndex] is outside `0 until ringCount`.
     */
    fun payloadIndexForOuterSlot(ringCount: Int, outerSlotIndex: Int): Int? =
        mirrorIndex(ringCount, outerSlotIndex)

    /**
     * Outer-slot index (0 = outermost diameter) for a tightest-first payload index.
     * Inverse of [payloadIndexForOuterSlot].
     */
    fun outerSlotForPayloadIndex(ringCount: Int, payloadIndex: Int): Int? =
        mirrorIndex(ringCount, payloadIndex)

    private fun mirrorIndex(ringCount: Int, index: Int): Int? {
        if (ringCount <= 0 || index !in 0 until ringCount) {
            return null
        }
        return ringCount - 1 - index
    }
}
