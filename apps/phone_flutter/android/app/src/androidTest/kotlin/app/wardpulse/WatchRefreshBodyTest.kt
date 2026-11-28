package app.wardpulse

import android.test.InstrumentationTestCase
import app.wardpulse.watchsync.WatchHeldOrder
import app.wardpulse.watchsync.WatchOwnerRequest
import app.wardpulse.watchsync.orderedRefresh
import app.wardpulse.watchsync.ownerRequest
import junit.framework.Assert.assertEquals
import junit.framework.Assert.assertNull

/**
 * The v10 refresh body over the platform's strict JSON reader: only one complete object with
 * exactly one install and one generation, in valid UTF-8 and JSON string syntax, is an ordered
 * refresh; anything else is resend-only. Wear's owner request is read the same way.
 */
@Suppress("DEPRECATION")
class WatchRefreshBodyTest : InstrumentationTestCase() {
    fun testOneCompleteObjectIsAnOrderedRefresh() {
        assertEquals(INSTALL to 3L, parse("""{"installId":"$INSTALL","generation":3}"""))
        assertEquals(INSTALL to 0L, parse(""" {"generation":0,"installId":"$INSTALL"} """))
    }

    fun testTrailingContentIsResendOnly() {
        for (trailing in listOf("{}", "x", ",", """{"installId":"$INSTALL","generation":4}""")) {
            assertNull(trailing, parse("""{"installId":"$INSTALL","generation":3}$trailing"""))
        }
    }

    fun testDuplicateMembersAreResendOnly() {
        assertNull(parse("""{"installId":"$INSTALL","installId":"$INSTALL","generation":3}"""))
        assertNull(parse("""{"installId":"$INSTALL","generation":3,"generation":4}"""))
    }

    fun testOnlyJsonEscapesAreDecoded() {
        // A defined escape is the same member.
        assertEquals(INSTALL to 3L, parse("""{"\u0069nstallId":"$INSTALL","generation":3}"""))
        for (body in listOf(
            // Unsupported escapes, which a lenient decoder reads as the expected text.
            """{"\installId":"$INSTALL","generation":3}""",
            """{"installId":"\${INSTALL}","generation":3}""",
            """{"install\Id":"$INSTALL","generation":3}""",
            """{"\u+069nstallId":"$INSTALL","generation":3}""",
        )) {
            assertNull(body, parse(body))
        }
    }

    fun testAnOwnerRequestNonceInMalformedUtf8IsRejected() {
        // The free-text nonce is where a lenient decoder's replacement character would pass.
        val body = """{"nonce":"n-?","installId":"$INSTALL","generation":2,"sequence":5}"""
            .toByteArray(Charsets.UTF_8)
        // A lead byte without its continuation.
        body[body.indexOf('?'.code.toByte())] = 0xC3.toByte()
        assertNull(ownerRequest(body))
    }

    fun testOtherMembersAndValuesAreResendOnly() {
        for (body in listOf(
            """{"installId":"$INSTALL","generation":3,"sequence":1}""",
            """{"installId":"$INSTALL"}""",
            """{"generation":3}""",
            """{"installId":"$INSTALL","generation":-1}""",
            """{"installId":"$INSTALL","generation":3.0}""",
            """{"installId":"$INSTALL","generation":1e3}""",
            """{"installId":"$INSTALL","generation":"3"}""",
            """{"installId":"$INSTALL","generation":99999999999999999999}""",
            """{"installId":"${INSTALL.uppercase()}","generation":3}""",
            """{"installId":"not-an-install","generation":3}""",
            """{"installId":null,"generation":3}""",
            """[{"installId":"$INSTALL","generation":3}]""",
            """{installId:"$INSTALL",generation:3}""",
            "",
        )) {
            assertNull(body, parse(body))
        }
    }

    fun testAnOwnerRequestNamesItsHeldOrderStrictlyOrIsABareNonce() {
        val valid = """{"nonce":"n-1","installId":"$INSTALL","generation":2,"sequence":5}"""
        assertEquals(WatchOwnerRequest("n-1", WatchHeldOrder(INSTALL, 2L, 5L)), owner(valid))
        // An earlier Wear build's bare nonce is answered but names no held item.
        assertEquals(WatchOwnerRequest("n-1", null), owner("n-1"))
        for (body in listOf(
            "$valid{}",
            """{"nonce":"n-1","nonce":"n-2","installId":"$INSTALL","generation":2,"sequence":5}""",
            """{"nonce":"n-1","installId":"$INSTALL","generation":2}""",
            """{"nonce":"n-1","installId":"$INSTALL","generation":2,"sequence":5,"x":1}""",
            """{"nonce":"","installId":"$INSTALL","generation":2,"sequence":5}""",
            """{"nonce":"n-1","installId":"$INSTALL","generation":2,"sequence":0}""",
            """{"nonce":"n-1","installId":"$INSTALL","generation":-1,"sequence":5}""",
            """{"nonce":"n-1","installId":"$INSTALL","generation":2,"sequence":"5"}""",
            """{"nonce":"\q-1","installId":"$INSTALL","generation":2,"sequence":5}""",
            // A raw control character in the free-text nonce.
            "{\"nonce\":\"n\u0001\",\"installId\":\"$INSTALL\",\"generation\":2,\"sequence\":5}",
            "",
            "n".repeat(65),
        )) {
            assertNull(body, owner(body))
        }
    }

    private fun parse(body: String) = orderedRefresh(body.toByteArray(Charsets.UTF_8))

    private fun owner(body: String) = ownerRequest(body.toByteArray(Charsets.UTF_8))

    private companion object {
        const val INSTALL = "0f8fad5b-d9cb-469f-a165-70867728950e"
    }
}
