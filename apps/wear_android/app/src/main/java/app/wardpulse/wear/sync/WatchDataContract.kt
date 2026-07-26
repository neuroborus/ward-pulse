package app.wardpulse.wear.sync

object WatchDataContract {
    const val PATH = "/wardpulse/watch-summary"
    const val PAYLOAD_KEY = "payload"

    /** Wear → phone: request a provider sync (phone owns cadence / rate limits). */
    const val REFRESH_PATH = "/wardpulse/refresh-request"
}
