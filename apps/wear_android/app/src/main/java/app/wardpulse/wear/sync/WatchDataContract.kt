package app.wardpulse.wear.sync

object WatchDataContract {
    const val PATH = "/wardpulse/watch-summary"

    /** The v9 projection older Wear apps read from the same Data Item. */
    const val PAYLOAD_KEY = "payload"

    /** The ordered v10 summary. When present, a malformed value never falls back to [PAYLOAD_KEY]. */
    const val SUMMARY_KEY = "summary"

    /**
     * Wear → phone: request a provider sync (phone owns cadence / rate limits). A v10 binding
     * sends its accepted install ID and generation; a v9-only binding sends an empty message.
     */
    const val REFRESH_PATH = "/wardpulse/refresh-request"

    /**
     * Wear → phone request with a nonce and the order of the v10 item Wear stores from that phone,
     * or the bare nonce without one; the reply names the phone's desired summary owner. An
     * accepted v10 commit names its new order in a further request, whose reply is not read.
     */
    const val OWNER_PATH = "/wardpulse/summary-owner"

    /** Advertised by the phone app (`wear.xml`); its reachability change is an observed reconnect. */
    const val PHONE_CAPABILITY = "wardpulse_phone"

    /**
     * Reconciliation diagnostics. `WardPulseSync` carries only the receipt marker the paired gate
     * reads, where any other message is a monitoring gap.
     */
    const val DIAGNOSTIC_TAG = "WardPulseWatch"
}
