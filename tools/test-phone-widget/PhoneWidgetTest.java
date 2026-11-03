package app.wardpulse;

import java.time.ZoneId;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Locale;

/** Exercises production presentation, fit and navigation without an Android dependency. */
public final class PhoneWidgetTest {
    private static int assertions;

    private static void check(boolean value, String message) {
        assertions++;
        if (!value) throw new AssertionError(message);
    }

    /** Synthetic glyph boxes exercise the actual planner, not native-font acceptance. */
    private static PhoneWidgetLayout.Measurer metrics(float density) {
        return (text, style) -> {
            boolean supported = PhoneWidgetLayout.supportedText(text);
            int width;
            switch (style) {
                case PERCENT: case CREDIT: width = 70; break;
                case FAMILY: width = 60; break;
                case POOL: width = text.startsWith("Long") ? 500 : 110; break;
                case RESET: width = 95; break;
                case STALE: width = 34; break;
                default: width = 72;
            }
            int height = style == PhoneWidgetLayout.Style.CREDIT ? 24 : style.sizeDp;
            return new PhoneWidgetLayout.Glyphs(0,
                    text.isEmpty() || !supported ? 0 : -(int) Math.ceil(height * density),
                    text.isEmpty() || !supported ? 0 : (int) Math.ceil(width * density), 0,
                    -(int) Math.ceil(12 * density), (int) Math.ceil(3 * density), supported);
        };
    }

    private static PhoneWidgetLayout.Row row(String family, String pool, String percent,
            String credits, String reset) {
        return new PhoneWidgetLayout.Row(family + " · " + pool, family, pool,
                percent, credits, reset, 0xff91c4b1);
    }

    private static List<PhoneWidgetLayout.Row> referenceRows() {
        String reset = "Reset 10 Feb 09:15";
        return Arrays.asList(
                row("Codex", "Weekly plan", "50%", "42K", reset),
                row("Claude", "5-hour session", "0%", "", reset),
                row("Cursor", "Models", "75%", "", ""),
                row("Claude", "Weekly plan", "62%", "", reset),
                row("Codex", "5-hour session", "88%", "32K", reset),
                row("Cursor", "Other Models", "50%", "", reset));
    }

    private static PhoneWidgetLayout.Plan fit(int width, int height, boolean stale) {
        return PhoneWidgetLayout.fit(width, height, 1, referenceRows(), false, stale,
                metrics(1), PhoneWidgetLayout.MAX_BITMAP_BYTES, 0);
    }

    private static void checkBounds(PhoneWidgetLayout.Plan plan) {
        for (PhoneWidgetLayout.TextRun run : plan.text) {
            check(run.x >= 0 && run.y >= 0 && run.x + run.glyphs.width() <= plan.width
                            && run.y + run.glyphs.height() <= plan.height,
                    "Every complete text box stays within its allocation.");
            check(plan.card != null && run.x >= plan.card.left && run.y >= plan.card.top
                            && run.x + run.glyphs.width() <= plan.card.right
                            && run.y + run.glyphs.height() <= plan.card.bottom,
                    "Every visible glyph remains inside the intrinsic card.");
        }
        for (PhoneWidgetLayout.Bar bar : plan.bars) {
            check(bar.x >= 0 && bar.y >= 0 && bar.x + bar.width <= plan.width
                            && bar.y + bar.height <= plan.height,
                    "Complete accent bars stay within their allocation.");
        }
        check(plan.bitmapBytes() <= PhoneWidgetLayout.MAX_BITMAP_BYTES,
                "The whole bitmap set respects its byte budget.");
    }

    private static void layoutCases() {
        PhoneWidgetLayout.Plan full = fit(360, 344, false);
        check(full.rows.size() == 6, "Six complete ordinary rows remain supported.");
        check(full.rows.get(0).labels && full.rows.get(0).credits && full.rows.get(0).reset,
                "Measured full width retains labels, balance and real reset.");
        check(PhoneWidgetLayout.rowDescription(full.rows.get(0)).equals(
                        "Codex · Weekly plan, 50% remaining, 42K purchased credits, Reset 10 Feb 09:15"),
                "Only displayed credit/reset details contribute their full accessible meaning.");
        check(full.text.stream().anyMatch(run -> run.text.equals("Models")
                        && run.style == PhoneWidgetLayout.Style.POOL),
                "Cursor Models uses the complete second label line.");
        checkBounds(full);
        check(full.card.width() == 331 && full.card.height() == 339
                        && full.card.left == (full.width - full.card.width()) / 2
                        && full.card.top == (full.height - full.card.height()) / 2,
                "Measured content plus header and padding defines a centered intrinsic card.");
        PhoneWidgetLayout.Plan labels = fit(266, 184, false);
        check(labels.rows.size() == 3 && labels.rows.get(0).labels
                        && !labels.rows.get(0).credits && !labels.rows.get(0).reset,
                "Reduced allocation drops details and complete trailing rows.");
        checkBounds(labels);
        PhoneWidgetLayout.Plan narrow = fit(150, 184, false);
        check(narrow.rows.size() == 3 && !narrow.rows.get(0).labels,
                "Narrow allocation retains complete percentages without labels.");
        check(PhoneWidgetLayout.rowDescription(narrow.rows.get(1))
                        .equals("Claude · 5-hour session, 0% remaining"),
                "Hidden labels retain full identity, but hidden details are not announced.");
        checkBounds(narrow);
        check(fit(331, 184, false).rows.get(0).reset, "Exact measured reset width fits.");
        PhoneWidgetLayout.VisibleRow crowded = fit(330, 184, false).rows.get(0);
        check(crowded.credits && !crowded.reset, "Drop a crowded reset before a valid balance.");
        check(!PhoneWidgetLayout.rowDescription(crowded).contains("Reset"),
                "Omitted resets are not announced.");
        check(fit(306, 184, false).rows.get(0).credits, "Exact balance width fits.");
        check(!fit(305, 184, false).rows.get(0).credits, "Drop the entire detail column.");
        check(fit(230, 184, false).rows.get(0).labels, "Exact label width fits.");
        check(!fit(229, 184, false).rows.get(0).labels, "Drop the entire label column.");
        check(fit(114, 184, false).rows.size() == 3, "Exact primary width fits.");
        check(fit(113, 184, false).state == PhoneWidgetLayout.EmptyState.RESIZE,
                "Do not clip a primary token below its measured width.");
        check(fit(360, 183, false).rows.size() == 3, "Exact three-row height fits.");
        check(fit(360, 182, false).rows.size() == 2, "Omit a complete trailing row.");
        PhoneWidgetLayout.Plan stale = fit(360, 183, true);
        check(stale.rows.size() == 3 && stale.staleInset == 0,
                "Stale and mark share the measured header without adding another inset.");
        check(fit(360, 182, true).rows.size() == 2, "Shared-header height boundary stays complete.");
        check(fit(360, 339, true).rows.size() == 6,
                "All six stale rows fit when the shared header and row block fit.");
        PhoneWidgetLayout.TextRun badge = stale.text.stream()
                .filter(run -> run.style == PhoneWidgetLayout.Style.STALE).findFirst().orElseThrow();
        check(badge.y - badge.glyphs.top + badge.glyphs.lineBottom + 2 <= stale.rows.get(0).top,
                "Painted badge font padding clears the first row.");
        check(fit(360, 200, false).staleInset == 0, "Fresh updates remove badge clearance.");
        int resetLine = -1;
        for (int i = 0; i < full.rows.size(); i++) {
            PhoneWidgetLayout.VisibleRow visible = full.rows.get(i);
            if (!visible.reset) continue;
            final int rowTop = visible.top;
            PhoneWidgetLayout.TextRun reset = full.text.stream()
                    .filter(run -> run.style == PhoneWidgetLayout.Style.RESET
                            && run.y >= rowTop && run.y < rowTop + visible.height)
                    .findFirst().orElseThrow();
            if (resetLine < 0) resetLine = reset.y - rowTop;
            check(reset.y - rowTop == resetLine, "All resets share their row's lower line.");
        }
        List<PhoneWidgetLayout.Row> longLabel = Collections.singletonList(
                row("Cursor", "Long complete label", "100%", "42K", ""));
        PhoneWidgetLayout.Plan longPlan = PhoneWidgetLayout.fit(360, 184, 1, longLabel,
                false, false, metrics(1), PhoneWidgetLayout.MAX_BITMAP_BYTES, 0);
        check(!longPlan.rows.get(0).labels && !longPlan.rows.get(0).credits,
                "Long labels use complete-column omission, never abbreviation.");
        check(PhoneWidgetLayout.rowDescription(longPlan.rows.get(0)).contains("Long complete label"),
                "Omitted long labels retain complete accessible identity.");
        check(!PhoneWidgetLayout.supportedText("Unknown \ud83d\ude00")
                        && !PhoneWidgetLayout.supportedText("Line\nbreak"),
                "Unsupported glyphs and controls never reach system-font fallback.");
        PhoneWidgetLayout.Plan tiny = fit(80, 20, true);
        check(tiny.state == PhoneWidgetLayout.EmptyState.RESIZE && !tiny.mark
                        && tiny.text.size() == 1
                        && tiny.text.get(0).style == PhoneWidgetLayout.Style.EMPTY,
                "A complete bundled-12 fallback takes priority over decoration.");
        checkBounds(tiny);
        PhoneWidgetLayout.Plan noFit = fit(20, 3, true);
        check(noFit.state == PhoneWidgetLayout.EmptyState.RESIZE && noFit.text.isEmpty(),
                "Exceptionally tiny hosts retain an accessible state without cropped text.");
        PhoneWidgetLayout.Plan empty = PhoneWidgetLayout.fit(150, 80, 1,
                Collections.emptyList(), true, false, metrics(1),
                PhoneWidgetLayout.MAX_BITMAP_BYTES, 0);
        check(empty.state == PhoneWidgetLayout.EmptyState.NO_METRICS
                        && empty.text.get(0).text.equals("No metrics"),
                "Empty data stays distinct from insufficient room.");
        PhoneWidgetLayout.Plan capped = PhoneWidgetLayout.fit(360, 344, 1, referenceRows(),
                false, false, metrics(1), 0, 0);
        check(capped.rows.isEmpty() && capped.text.isEmpty() && capped.bitmapBytes() == 0,
                "A zero byte budget allocates no bitmaps or misleading rows.");
        check(PhoneWidgetLayout.bitmapBytes(4097, 1, true) == Long.MAX_VALUE
                        && PhoneWidgetLayout.bitmapBytes(1, Integer.MAX_VALUE, false) == Long.MAX_VALUE,
                "Dimension and overflow bounds precede allocation.");
        PhoneWidgetLayout.Plan dense = PhoneWidgetLayout.fit(946, 903, 2.625f, referenceRows(),
                false, false, metrics(2.625f), PhoneWidgetLayout.MAX_BITMAP_BYTES / 2, 0);
        check(dense.rows.size() == 6 && dense.bitmapBytes() * 2 <= PhoneWidgetLayout.MAX_BITMAP_BYTES,
                "Two bounded density-specific variants retain the reference rows.");
        checkBounds(dense);
    }

    private static PhoneWidgetLayout.Row budget(String percent, String spent, String cap,
            String capCurrency) {
        return PhoneWidgetLayout.Row.fromCache("OpenAI platform · Today", "OpenAI", "Today",
                percent, "", "2028-02-10T09:15:00Z", ZoneId.of("UTC"), 0xff65d78a,
                "budget", spent, "USD", cap, capCurrency, "", "", "", "");
    }

    private static PhoneWidgetLayout.Plan fitRow(PhoneWidgetLayout.Row row, int width) {
        return PhoneWidgetLayout.fit(width, 184, 1, Collections.singletonList(row), false, false,
                metrics(1), PhoneWidgetLayout.MAX_BITMAP_BYTES, 0);
    }

    private static void dataAndMoneyCases() {
        check(PhoneWidgetLayout.moneyText("-9007199254740993", "EUR")
                        .equals("-EUR 90071992547409.93"),
                "Money preserves signs, codes and cents beyond double precision.");
        check(PhoneWidgetLayout.moneyText("-9223372036854775808", "USD")
                        .equals("-USD 92233720368547758.08"),
                "The minimum signed integer is formatted without abs overflow.");
        PhoneWidgetLayout.Row capped = budget("50% left", "1234", "10000", "USD");
        PhoneWidgetLayout.VisibleRow full = fitRow(capped, 500).rows.get(0);
        check(PhoneWidgetLayout.rowDescription(full).equals(
                        "OpenAI platform · Today, 50% remaining, USD 12.34 spent, Cap USD 100.00"),
                "Capped budgets describe actual spending and cap, never purchased credits.");
        check(!full.reset && capped.reset.isEmpty(), "Budget cache resets are never inferred or reused.");
        PhoneWidgetLayout.Row uncapped = budget("", "0", "", "");
        check(PhoneWidgetLayout.rowDescription(fitRow(uncapped, 500).rows.get(0))
                        .equals("OpenAI platform · Today, USD 0.00 spent, No cap"),
                "Known zero and no cap retain their independent meaning.");
        PhoneWidgetLayout.Row unknown = budget("80% left", "", "10000", "USD");
        check(unknown.percent.isEmpty() && unknown.primary(true).equals("—")
                        && unknown.lower.equals("Unavailable"),
                "Incomplete new budget caches never fall back to a stale percentage.");
        check(budget("50%", "1234", "0", "USD").lower.equals("Cap unavailable")
                        && budget("50%", "1234", "10000", "EUR").percent.isEmpty(),
                "Unusable and mismatched caps do not invent a percentage.");
        check(budget("", "1234", "10000", "USD").lower
                        .equals("Cap USD 100.00 · Percentage unavailable"),
                "A usable cap without a reported percentage has a distinct state.");
        PhoneWidgetLayout.Row legacy = PhoneWidgetLayout.Row.fromCache("Legacy", "", "", "50% left",
                "", "", ZoneId.of("UTC"), 0, "", "1234", "USD", "", "", "", "", "", "");
        check(!legacy.budget && legacy.percent.equals("50%"),
                "Missing discriminator preserves legacy decoding even with leftover optional fields.");
        PhoneWidgetLayout.Row extra = PhoneWidgetLayout.Row.fromCache("Claude · Extra usage", "Claude",
                "Extra usage", "80%", "", "2028-02-10T09:15:00Z", ZoneId.of("UTC"), 0,
                "allowance", "", "", "", "", "12.50", "Credits", "", "");
        String extraSpeech = PhoneWidgetLayout.rowDescription(fitRow(extra, 500).rows.get(0));
        check(extraSpeech.contains("12.50 Credits used, Cap unavailable")
                        && !extraSpeech.contains("purchased") && extraSpeech.contains("Reset"),
                "Extra usage keeps real used units and reset without inventing its missing cap.");
        PhoneWidgetLayout.Row capOnly = PhoneWidgetLayout.Row.fromCache("Extra", "Claude", "Extra",
                "80%", "", "", ZoneId.of("UTC"), 0, "allowance", "", "", "", "",
                "", "", "50", "Credits");
        check(capOnly.detailDescription.equals("Used unavailable, 50 Credits cap"),
                "A known Extra cap survives a missing used amount independently.");
        PhoneWidgetLayout.Row both = PhoneWidgetLayout.Row.fromCache("Extra", "Claude", "Extra",
                "80%", "", "", ZoneId.of("UTC"), 0, "allowance", "", "", "", "",
                "12.50", "Credits", "50", "Credits");
        check(both.detail.equals("12.50 / 50 Credits")
                        && both.detailStyle == PhoneWidgetLayout.Style.FAMILY
                        && PhoneWidgetLayout.rowDescription(fitRow(both, 500).rows.get(0))
                                .contains("12.50 Credits used, 50 Credits cap"),
                "Extra uses one 18 Bold actual-unit line with distinct used/cap meaning.");

        PhoneWidgetLayout.Measurer moneyMetrics = (text, style) -> {
            PhoneWidgetLayout.Glyphs base = metrics(1).measure(text, style);
            if (!text.startsWith("USD ")) return base;
            int width = style == PhoneWidgetLayout.Style.PERCENT ? 180
                    : style == PhoneWidgetLayout.Style.CREDIT ? 150 : 110;
            return new PhoneWidgetLayout.Glyphs(0, base.top, width, base.bottom,
                    base.lineTop, base.lineBottom, true);
        };
        for (int width : new int[] {260, 224, 223, 194, 193}) {
            PhoneWidgetLayout.Plan plan = PhoneWidgetLayout.fit(width, 184, 1,
                    Collections.singletonList(capped), false, false, moneyMetrics,
                    PhoneWidgetLayout.MAX_BITMAP_BYTES, 0);
            if (width < 194) {
                check(plan.state == PhoneWidgetLayout.EmptyState.RESIZE,
                        "A complete Money token that cannot fit at 26 retains honest NoFit.");
            } else {
                PhoneWidgetLayout.TextRun value = plan.text.stream()
                        .filter(run -> run.text.equals("USD 12.34")).findFirst().orElseThrow();
                check(value.style == (width >= 224 ? PhoneWidgetLayout.Style.PERCENT
                                : PhoneWidgetLayout.Style.CREDIT),
                        "Release whole omitted columns before using only the approved 30/26 sizes.");
                checkBounds(plan);
            }
        }
        PhoneWidgetLayout.Plan fractional = PhoneWidgetLayout.fit(229, 184, 1.1f,
                Collections.singletonList(capped), false, false, moneyMetrics,
                PhoneWidgetLayout.MAX_BITMAP_BYTES, 0);
        check(fractional.text.stream().anyMatch(run -> run.text.equals("USD 12.34")
                        && run.style == PhoneWidgetLayout.Style.CREDIT),
                "Fractional-density padding uses the same rounded components as actual layout.");
        checkBounds(fractional);
        PhoneWidgetLayout.Plan unfitTail = PhoneWidgetLayout.fit(193, 184, 1,
                Arrays.asList(row("Claude", "5h", "50%", "", ""), capped), false, false,
                moneyMetrics, PhoneWidgetLayout.MAX_BITMAP_BYTES, 0);
        check(unfitTail.rows.isEmpty(), "Trailing-row fallback cannot hide a width-unfit Money row.");
    }

    private static void cacheAndCalendarCases() {
        ZoneId utc = ZoneId.of("UTC");
        PhoneWidgetLayout.Row legacy = PhoneWidgetLayout.Row.fromCache("Cursor Models", "", "",
                "0% left", "32K credits", "", utc, 0);
        check(legacy.family.equals("Cursor") && legacy.pool.equals("Models")
                        && legacy.percent.equals("0%") && legacy.credits.equals("32K")
                        && legacy.reset.isEmpty(), "Flat caches retain tokens and full Cursor identity.");
        PhoneWidgetLayout.Row named = PhoneWidgetLayout.Row.fromCache("Claude · Weekly · Special",
                "", "", "25%", "", "bad reset", utc, 0);
        check(named.family.equals("Claude") && named.pool.equals("Weekly · Special")
                        && named.reset.isEmpty(), "Only the known family delimiter is split.");
        PhoneWidgetLayout.Row structured = PhoneWidgetLayout.Row.fromCache("Full identity",
                "Codex", "Weekly · Special", "25%", "", "2028-02-10T09:15:00Z", utc, 0);
        check(structured.pool.equals("Weekly · Special") && structured.identity.equals("Full identity"),
                "Explicit structured labels are authoritative and remain whole.");
        Locale original = Locale.getDefault();
        try {
            Locale.setDefault(Locale.FRENCH);
            check(PhoneWidgetLayout.resetText("2028-02-29T23:30:00Z", ZoneId.of("Europe/Paris"))
                            .equals("Reset 01 Mar 00:30"), "Leap-day conversion uses local English dates.");
            check(PhoneWidgetLayout.resetText("2028-03-12T06:59:00Z", ZoneId.of("America/New_York"))
                            .equals("Reset 12 Mar 01:59"), "Before the DST boundary.");
            check(PhoneWidgetLayout.resetText("2028-03-12T07:00:00Z", ZoneId.of("America/New_York"))
                            .equals("Reset 12 Mar 03:00"), "After the DST boundary, without a 24-hour guess.");
            check(PhoneWidgetLayout.resetText("2028-12-31T23:30:00Z", ZoneId.of("Asia/Tokyo"))
                            .equals("Reset 01 Jan 08:30"), "Year rollover retains zero-padded days.");
            check(PhoneWidgetLayout.resetText("2020-01-02T03:04:00Z", utc)
                            .equals("Reset 02 Jan 03:04"), "Past boundaries are never fabricated forward.");
        } finally {
            Locale.setDefault(original);
        }
    }

    public static void main(String[] ignored) {
        for (String percent : new String[] {"85%", "0%", "001.20%"}) {
            String compact = PhoneWidgetLayout.percentText(percent + " left");
            check(compact.equals(percent), "Legacy percent keeps its exact token: " + percent);
            check(PhoneWidgetLayout.percentText(compact).equals(percent),
                    "Bare percent cache is idempotent: " + percent);
        }
        for (String credits : new String[] {"59.5K", "1.20M", "7B", "0"}) {
            String compact = PhoneWidgetLayout.creditsText(credits + " credits");
            check(compact.equals(credits), "Legacy credits keep their exact token: " + credits);
            check(PhoneWidgetLayout.creditsText(compact).equals(credits),
                    "Bare credit cache is idempotent: " + credits);
        }
        check(PhoneWidgetLayout.percentText("").isEmpty(), "Missing percent stays missing.");
        check(PhoneWidgetLayout.creditsText("").isEmpty(), "Missing credits do not invent zero.");
        check(PhoneWidgetLayout.percentText("85% left unchanged").equals("85% left unchanged"),
                "Only a terminal percent suffix is omitted.");
        check(PhoneWidgetLayout.creditsText("59.5K credits unchanged")
                        .equals("59.5K credits unchanged"),
                "Only a terminal credit suffix is omitted.");

        check(PhoneWidgetLayout.rowDescription(
                        "Plan left · purchased credits", "85% remaining", "59.5K purchased credits", true)
                        .equals("Plan left · purchased credits, 85% remaining, 59.5K purchased credits"),
                "Full-row speech keeps metric identity verbatim and announces each value once.");
        check(PhoneWidgetLayout.rowDescription(
                        "Plan left · purchased credits", "85% remaining", "59.5K purchased credits", false)
                        .equals("Plan left · purchased credits, 85% remaining"),
                "Narrow layouts keep metric identity and remaining meaning without hidden credits.");
        check(PhoneWidgetLayout.rowDescription("Plan", "0% remaining", "", true)
                        .equals("Plan, 0% remaining"),
                "Known exhausted rows retain meaning without inventing absent credits.");
        check(PhoneWidgetLayout.rowDescription("Plan", "85% remaining", "0 purchased credits", true)
                        .equals("Plan, 85% remaining, 0 purchased credits"),
                "A known zero purchased balance remains distinct from an absent balance.");
        check(PhoneWidgetLayout.rowDescription("Plan", "", "", true).equals("Plan"),
                "Empty values do not acquire spoken units or invented numbers.");

        layoutCases();
        cacheAndCalendarCases();
        dataAndMoneyCases();
        check(PhoneWidgetLayout.emptyState(0, false, 0) == PhoneWidgetLayout.EmptyState.NO_METRICS,
                "Truly empty payload.");
        check(PhoneWidgetLayout.emptyState(3, true, 0) == PhoneWidgetLayout.EmptyState.NO_METRICS,
                "Explicit unavailable payload.");
        check(PhoneWidgetLayout.emptyState(3, false, 0) == PhoneWidgetLayout.EmptyState.RESIZE,
                "Configured metrics do not fit.");
        check(PhoneWidgetLayout.emptyState(3, false, 2) == PhoneWidgetLayout.EmptyState.NONE,
                "Visible rows have no empty copy.");

        DashboardLaunchRequest launch = new DashboardLaunchRequest();
        check(launch.record(DashboardLaunchRequest.ACTION), "Cold widget action recorded.");
        check(!launch.takeReadyRequest(), "Cold request waits for Dart.");
        launch.markReady();
        check(launch.takeReadyRequest(), "Readiness flushes cold request.");
        launch.markReady();
        check(!launch.takeReadyRequest(), "Repeated readiness cannot replay.");
        check(!launch.record(null), "Consumed intent has no action.");
        check(!launch.record("app.wardpulse.action.WATCH_REFRESH"), "Refresh action is separate.");
        check(!launch.takeReadyRequest(), "Unrelated actions cannot navigate.");
        check(launch.record(DashboardLaunchRequest.ACTION), "Ready warm action recorded.");
        check(launch.takeReadyRequest(), "Ready warm request dispatches.");
        check(!launch.takeReadyRequest(), "Warm request consumed once.");
        launch.reset();
        check(launch.record(DashboardLaunchRequest.ACTION), "Early warm action recorded.");
        check(!launch.takeReadyRequest(), "Early warm request remains pending.");
        launch.markReady();
        check(launch.takeReadyRequest(), "Early warm request eventually dispatches.");
        launch.record(DashboardLaunchRequest.ACTION);
        launch.reset();
        launch.markReady();
        check(!launch.takeReadyRequest(), "Cleanup clears stale navigation state.");
        System.out.println("Phone widget: " + assertions + " assertions passed.");
    }
}
