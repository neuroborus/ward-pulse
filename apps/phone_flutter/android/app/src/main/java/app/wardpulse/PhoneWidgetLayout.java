package app.wardpulse;

import java.util.StringJoiner;

/** Launcher presentation and fitting rules, independent from Android rendering. */
public final class PhoneWidgetLayout {
    public static final int MAX_ROWS = 6;
    private static final int CHROME_PAD_V_DP = 12;
    private static final int ROW_CONTENT_DP = 31;
    private static final int ROW_GAP_DP = 5;
    private static final int FIT_SLACK_DP = 6;

    public enum EmptyState { NONE, NO_METRICS, RESIZE }

    private PhoneWidgetLayout() {}

    /** Accept both descriptive and compact caches without reformatting the numeric token. */
    public static String percentText(String cached) {
        return cached.endsWith(" left")
                ? cached.substring(0, cached.length() - " left".length()) : cached;
    }

    public static String creditsText(String cached) {
        return cached.endsWith(" credits")
                ? cached.substring(0, cached.length() - " credits".length()) : cached;
    }

    /** Metric identity accompanies its visible values even in percentage-only layouts. */
    public static String rowDescription(
            String label, String remainingPercent, String purchasedCredits, boolean showCredits) {
        StringJoiner description = new StringJoiner(", ");
        if (!label.isEmpty()) description.add(label);
        if (!remainingPercent.isEmpty()) description.add(remainingPercent);
        if (showCredits && !purchasedCredits.isEmpty()) description.add(purchasedCredits);
        return description.toString();
    }

    /** Two-line rows keep their existing geometry; the measured badge inset is pixels. */
    public static int completeRows(int availableHeightDp, float density, int staleInsetPx) {
        if (!Float.isFinite(density) || density <= 0 || staleInsetPx < 0) {
            throw new IllegalArgumentException("Invalid widget display geometry.");
        }
        double availablePx = Math.max(0, availableHeightDp) * (double) density;
        int rows = 0;
        while (rows < MAX_ROWS
                && heightNeededDp(rows + 1) * (double) density + staleInsetPx <= availablePx) {
            rows++;
        }
        return rows;
    }

    private static int heightNeededDp(int rows) {
        return CHROME_PAD_V_DP + ROW_CONTENT_DP
                + (rows - 1) * (ROW_CONTENT_DP + ROW_GAP_DP) + FIT_SLACK_DP;
    }

    public static EmptyState emptyState(int storedCount, boolean payloadEmpty, int shownRows) {
        if (payloadEmpty || storedCount <= 0) return EmptyState.NO_METRICS;
        return shownRows <= 0 ? EmptyState.RESIZE : EmptyState.NONE;
    }
}
