package app.wardpulse.wear.watchface

import android.content.Context
import android.util.Xml
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.File
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.xmlpull.v1.XmlPullParser

@RunWith(AndroidJUnit4::class)
class WatchFaceConsentStoreTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()
    private val preferencesName = "watch_face_consent_test_${System.nanoTime()}"
    private val preferences = context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)

    @After
    fun cleanUp() {
        context.deleteSharedPreferences(preferencesName)
    }

    @Test
    fun freshStoreAllowsAnExplicitUseAction() {
        assertEquals(WatchFaceConsent.Eligible, WatchFaceConsentStore(preferences).read())
    }

    @Test
    fun permissionAndActivationHistoryIsDurableBeforeWriteReturns() {
        val store = WatchFaceConsentStore(preferences)
        for (history in listOf(
            WatchFaceConsent.PermissionPending,
            WatchFaceConsent.PermissionDeclined,
            WatchFaceConsent.ActivationAttempted,
        )) {
            assertTrue(store.write(history))
            assertEquals(history, WatchFaceConsentStore(preferences).read())
            // Reopening preferences alone reads Android's memory cache. Inspect disk as well:
            // the marker must survive process death before permission/activation can proceed.
            assertEquals(history.name, persistedHistory())
        }
    }

    @Test
    fun unrecognizedHistoryCannotRestoreConsentEligibility() {
        assertTrue(preferences.edit().putString("history", "unrecognized").commit())

        assertEquals(WatchFaceConsent.ActivationAttempted, WatchFaceConsentStore(preferences).read())
    }

    private fun persistedHistory(): String? {
        val file = File(context.applicationInfo.dataDir, "shared_prefs/$preferencesName.xml")
        return file.inputStream().use { input ->
            val parser = Xml.newPullParser()
            parser.setInput(input, "UTF-8")
            while (parser.next() != XmlPullParser.END_DOCUMENT) {
                if (parser.eventType == XmlPullParser.START_TAG && parser.name == "string" &&
                    parser.getAttributeValue(null, "name") == "history"
                ) {
                    return@use parser.nextText()
                }
            }
            null
        }
    }
}
