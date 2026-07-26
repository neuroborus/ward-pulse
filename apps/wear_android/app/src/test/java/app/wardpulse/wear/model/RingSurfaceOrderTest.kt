package app.wardpulse.wear.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RingSurfaceOrderTest {
    @Test
    fun mapsOuterSlotsToTightestFirstPayload() {
        assertEquals(0, RingSurfaceOrder.payloadIndexForOuterSlot(1, 0))
        assertEquals(1, RingSurfaceOrder.payloadIndexForOuterSlot(2, 0))
        assertEquals(0, RingSurfaceOrder.payloadIndexForOuterSlot(2, 1))
        assertEquals(2, RingSurfaceOrder.payloadIndexForOuterSlot(3, 0))
        assertEquals(1, RingSurfaceOrder.payloadIndexForOuterSlot(3, 1))
        assertEquals(0, RingSurfaceOrder.payloadIndexForOuterSlot(3, 2))
    }

    @Test
    fun invertsPayloadIndexToOuterSlot() {
        assertEquals(2, RingSurfaceOrder.outerSlotForPayloadIndex(3, 0))
        assertEquals(0, RingSurfaceOrder.outerSlotForPayloadIndex(3, 2))
        assertEquals(
            0,
            RingSurfaceOrder.payloadIndexForOuterSlot(
                3,
                requireNotNull(RingSurfaceOrder.outerSlotForPayloadIndex(3, 0)),
            ),
        )
    }

    @Test
    fun rejectsOutOfRangeSlots() {
        assertNull(RingSurfaceOrder.payloadIndexForOuterSlot(0, 0))
        assertNull(RingSurfaceOrder.payloadIndexForOuterSlot(2, 2))
        assertNull(RingSurfaceOrder.payloadIndexForOuterSlot(2, -1))
        assertNull(RingSurfaceOrder.outerSlotForPayloadIndex(2, 2))
    }
}
