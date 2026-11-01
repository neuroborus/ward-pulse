package app.wardpulse;

import java.time.DateTimeException;
import java.time.Instant;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.StringJoiner;

/** Complete measured rows and columns shared by the native painter and JVM harness. */
public final class PhoneWidgetLayout {
    public static final int MAX_ROWS = 6;
    public static final int MAX_BITMAP_SIDE = 4096;
    public static final long MAX_BITMAP_BYTES = 8L * 1024 * 1024;
    public static final int MAX_TEXT_LENGTH = 256;

    public enum EmptyState { NONE, NO_METRICS, RESIZE }
    public enum Layer { PRIMARY, MUTED, STALE, ACCENT }
    public enum Style {
        PERCENT(30, true, Layer.PRIMARY), CREDIT(26, true, Layer.PRIMARY),
        FAMILY(18, true, Layer.PRIMARY), POOL(16, false, Layer.MUTED),
        RESET(11, false, Layer.MUTED), EMPTY(12, false, Layer.MUTED),
        STALE(11, true, Layer.STALE);

        public final int sizeDp;
        public final boolean bold;
        public final Layer layer;

        Style(int sizeDp, boolean bold, Layer layer) {
            this.sizeDp = sizeDp;
            this.bold = bold;
            this.layer = layer;
        }
    }

    /** Bounds include horizontal advance; line bounds retain native font padding. */
    public static final class Glyphs {
        public final int left, top, right, bottom, lineTop, lineBottom;
        public final boolean supported;

        public Glyphs(int left, int top, int right, int bottom,
                int lineTop, int lineBottom, boolean supported) {
            this.left = left;
            this.top = top;
            this.right = right;
            this.bottom = bottom;
            this.lineTop = lineTop;
            this.lineBottom = lineBottom;
            this.supported = supported;
        }

        public int width() { return right - left; }
        public int height() { return bottom - top; }
    }

    public interface Measurer { Glyphs measure(String text, Style style); }

    public static final class Row {
        public final String identity, family, pool, percent, credits, reset;
        public final int color;

        public Row(String identity, String family, String pool, String percent,
                String credits, String reset, int color) {
            this.identity = identity;
            this.family = family;
            this.pool = pool;
            this.percent = percent;
            this.credits = credits;
            this.reset = reset;
            this.color = color;
        }

        public static Row fromCache(String label, String family, String pool, String percent,
                String credits, String reset, ZoneId zone, int color) {
            if (family.isEmpty() || pool.isEmpty()) {
                family = "";
                pool = label;
                if (label.equals("Cursor Models")) {
                    family = "Cursor";
                    pool = "Models";
                } else {
                    int cut = label.indexOf(" · ");
                    if (cut > 0 && knownFamily(label.substring(0, cut))) {
                        family = label.substring(0, cut);
                        pool = label.substring(cut + 3);
                    }
                }
            }
            String identity = label;
            if (identity.isEmpty()) identity = family.isEmpty() ? pool
                    : pool.isEmpty() ? family : family + " · " + pool;
            return new Row(identity, family, pool, percentText(percent), creditsText(credits),
                    resetText(reset, zone), color);
        }
    }

    public static final class TextRun {
        public final String text;
        public final Style style;
        public final Glyphs glyphs;
        public final int x, y;

        TextRun(String text, Style style, Glyphs glyphs, int x, int y) {
            this.text = text;
            this.style = style;
            this.glyphs = glyphs;
            this.x = x;
            this.y = y;
        }
    }

    public static final class Bar {
        public final int x, y, width, height, color;

        Bar(int x, int y, int width, int height, int color) {
            this.x = x;
            this.y = y;
            this.width = width;
            this.height = height;
            this.color = color;
        }
    }

    public static final class VisibleRow {
        public final Row row;
        public final boolean labels, credits, reset;
        public final int top, height;

        VisibleRow(Row row, boolean labels, boolean credits, boolean reset, int top, int height) {
            this.row = row;
            this.labels = labels;
            this.credits = credits;
            this.reset = reset;
            this.top = top;
            this.height = height;
        }
    }

    public static final class Bounds {
        public final int left, top, right, bottom;

        Bounds(int left, int top, int right, int bottom) {
            this.left = left;
            this.top = top;
            this.right = right;
            this.bottom = bottom;
        }

        public int width() { return right - left; }
        public int height() { return bottom - top; }
    }

    public static final class Plan {
        public final int width, height, staleInset;
        public final EmptyState state;
        public final boolean mark;
        public final List<TextRun> text;
        public final List<Bar> bars;
        public final List<VisibleRow> rows;

        Plan(int width, int height, int staleInset, EmptyState state, boolean mark,
                List<TextRun> text, List<Bar> bars, List<VisibleRow> rows) {
            this.width = width;
            this.height = height;
            this.staleInset = staleInset;
            this.state = state;
            this.mark = mark;
            this.text = Collections.unmodifiableList(text);
            this.bars = Collections.unmodifiableList(bars);
            this.rows = Collections.unmodifiableList(rows);
        }

        public Bounds bounds(Layer layer) {
            int left = width, top = height, right = 0, bottom = 0;
            for (TextRun run : text) {
                if (run.style.layer != layer) continue;
                left = Math.min(left, run.x);
                top = Math.min(top, run.y);
                right = Math.max(right, run.x + run.glyphs.width());
                bottom = Math.max(bottom, run.y + run.glyphs.height());
            }
            if (layer == Layer.ACCENT) for (Bar bar : bars) {
                left = Math.min(left, bar.x - 1);
                top = Math.min(top, bar.y - 1);
                right = Math.max(right, bar.x + bar.width + 1);
                bottom = Math.max(bottom, bar.y + bar.height + 1);
            }
            return right <= left || bottom <= top ? null : new Bounds(left, top, right, bottom);
        }

        public long bitmapBytes() {
            long bytes = 0;
            for (Layer layer : Layer.values()) {
                Bounds bounds = bounds(layer);
                if (bounds == null) continue;
                long count = PhoneWidgetLayout.bitmapBytes(
                        bounds.width(), bounds.height(), layer != Layer.ACCENT);
                if (count == Long.MAX_VALUE) return count;
                bytes += count;
            }
            return bytes;
        }
    }

    private static final DateTimeFormatter RESET =
            DateTimeFormatter.ofPattern("'Reset' dd MMM HH:mm", Locale.ENGLISH);

    private PhoneWidgetLayout() {}

    private static boolean knownFamily(String name) {
        return name.equals("Claude") || name.equals("Codex") || name.equals("Cursor")
                || name.equals("OpenAI") || name.equals("OpenAI plan")
                || name.equals("OpenAI platform") || name.equals("Anthropic plan")
                || name.equals("Anthropic platform") || name.equals("Cursor plan")
                || name.equals("Cursor platform");
    }

    public static String percentText(String cached) {
        return cached.endsWith(" left")
                ? cached.substring(0, cached.length() - " left".length()) : cached;
    }

    public static String creditsText(String cached) {
        return cached.endsWith(" credits")
                ? cached.substring(0, cached.length() - " credits".length()) : cached;
    }

    /** Absolute provider boundary, with no clock, inference or rollover. */
    public static String resetText(String cached, ZoneId zone) {
        if (cached.isEmpty() || cached.length() > 64) return "";
        try {
            return RESET.withZone(zone).format(Instant.parse(cached));
        } catch (DateTimeException error) {
            return "";
        }
    }

    /** Only glyphs verified in BOTH pinned font files may enter native Paint. */
    public static boolean supportedText(String text) {
        if (text.length() > MAX_TEXT_LENGTH) return false;
        for (int i = 0; i < text.length(); i++) {
            char value = text.charAt(i);
            if ((value < 0x20 || value > 0x7e) && value != '\u00b7'
                    && value != '\u2013' && value != '\u2014' && value != '\u2019') return false;
        }
        return true;
    }

    public static String rowDescription(
            String label, String remainingPercent, String purchasedCredits, boolean showCredits) {
        StringJoiner description = new StringJoiner(", ");
        if (!label.isEmpty()) description.add(label);
        if (!remainingPercent.isEmpty()) description.add(remainingPercent);
        if (showCredits && !purchasedCredits.isEmpty()) description.add(purchasedCredits);
        return description.toString();
    }

    public static String rowDescription(VisibleRow visible) {
        Row row = visible.row;
        String result = rowDescription(row.identity, row.percent + " remaining",
                row.credits.isEmpty() ? "" : row.credits + " purchased credits", visible.credits);
        return visible.reset ? result + ", " + row.reset : result;
    }

    /** Conservative stride padding, checked before any allocation, for four fixed layers. */
    public static long bitmapBytes(int width, int height, boolean alphaOnly) {
        if (width <= 0 || height <= 0 || width > MAX_BITMAP_SIDE || height > MAX_BITMAP_SIDE)
            return Long.MAX_VALUE;
        long stride = ((width * (alphaOnly ? 1L : 4L) + 63) / 64) * 64;
        return stride * height;
    }

    public static EmptyState emptyState(int storedCount, boolean payloadEmpty, int shownRows) {
        if (payloadEmpty || storedCount <= 0) return EmptyState.NO_METRICS;
        return shownRows <= 0 ? EmptyState.RESIZE : EmptyState.NONE;
    }

    private static int dp(float density, int size) { return (int) Math.ceil(density * size); }

    private static final class Measured {
        final Row row;
        final Glyphs percent, family, pool, credits, reset;

        Measured(Row row, Measurer measurer) {
            this.row = row;
            percent = measurer.measure(row.percent, Style.PERCENT);
            family = measurer.measure(row.family, Style.FAMILY);
            pool = measurer.measure(row.pool, Style.POOL);
            credits = measurer.measure(row.credits, Style.CREDIT);
            reset = measurer.measure(row.reset, Style.RESET);
        }
    }

    /** Width/height are host pixels. Typography stays density-based at every fit boundary. */
    public static Plan fit(int width, int height, float density, List<Row> rows,
            boolean payloadEmpty, boolean stale, Measurer measurer, long byteBudget, int markBytes) {
        if (width <= 0 || height <= 0 || width > 16384 || height > 16384
                || !Float.isFinite(density) || density <= 0 || density > 8
                || byteBudget < 0 || markBytes < 0) {
            throw new IllegalArgumentException("Invalid widget display geometry or byte budget.");
        }
        long budget = Math.min(byteBudget, MAX_BITMAP_BYTES);
        boolean mark = width >= dp(density, 68) && height >= dp(density, 19);
        int top = dp(density, mark ? 19 : 16);
        Glyphs badge = measurer.measure("STALE", Style.STALE);
        boolean showBadge = stale && badge.supported
                && badge.width() <= width - dp(density, 32)
                && badge.lineBottom - badge.lineTop <= height - top - dp(density, 16);
        int inset = showBadge ? badge.lineBottom - badge.lineTop + dp(density, 2) : 0;
        List<Measured> measured = new ArrayList<>();
        if (!payloadEmpty) for (int i = 0; i < Math.min(rows.size(), MAX_ROWS); i++) {
            measured.add(new Measured(rows.get(i), measurer));
        }
        for (int count = measured.size(); count > 0; count--) {
            // Geometry first; memory uses the same complete-column fallbacks.
            for (int columns = 3; columns > 0; columns--) {
                Plan plan = rows(width, height, density, measured.subList(0, count),
                        columns, top, inset, mark);
                if (plan == null) continue;
                List<TextRun> text = new ArrayList<>(plan.text);
                if (showBadge) text.add(new TextRun("STALE", Style.STALE, badge,
                        dp(density, 16), top + badge.top - badge.lineTop));
                Plan result = new Plan(width, height, inset, EmptyState.NONE, mark,
                        text, plan.bars, plan.rows);
                if (fitsBytes(result, budget, markBytes)) return result;
            }
        }
        EmptyState state = emptyState(rows.size(), payloadEmpty, 0);
        String message = state == EmptyState.NO_METRICS ? "No metrics" : "Resize widget";
        Glyphs glyphs = measurer.measure(message, Style.EMPTY);
        // Prefer a complete message over decoration on short/tiny hosts.
        for (int mode = 0; mode < 3; mode++) {
            int pad = dp(density, mode == 2 ? 2 : 16);
            int start = mode == 2 ? pad : top + (mode == 0 ? inset : 0);
            List<TextRun> text = new ArrayList<>();
            if (glyphs.supported && glyphs.width() <= width - 2 * pad
                    && glyphs.height() <= height - start - pad) {
                text.add(new TextRun(message, Style.EMPTY, glyphs,
                        (width - glyphs.width()) / 2,
                        start + (height - start - pad - glyphs.height()) / 2));
                if (mode == 0 && showBadge) text.add(new TextRun("STALE", Style.STALE, badge,
                        dp(density, 16), top + badge.top - badge.lineTop));
                Plan plan = new Plan(width, height, mode == 0 ? inset : 0, state,
                        mode < 2 && mark, text, Collections.emptyList(), Collections.emptyList());
                if (fitsBytes(plan, budget, markBytes)) return plan;
            }
        }
        return new Plan(width, height, 0, state, false,
                Collections.emptyList(), Collections.emptyList(), Collections.emptyList());
    }

    private static boolean fitsBytes(Plan plan, long budget, int markBytes) {
        long bytes = plan.bitmapBytes();
        return bytes != Long.MAX_VALUE && bytes + (plan.mark ? markBytes : 0L) <= budget;
    }

    private static Plan rows(int width, int height, float density, List<Measured> measured,
            int columns, int top, int inset, boolean mark) {
        int percentWidth = 0, labelWidth = 0;
        boolean labels = columns >= 2;
        for (Measured row : measured) {
            if (row.row.percent.isEmpty() || !row.percent.supported) return null;
            percentWidth = Math.max(percentWidth, row.percent.width());
            labelWidth = Math.max(labelWidth, Math.max(row.family.width(), row.pool.width()));
            labels &= row.family.supported && row.pool.supported;
        }
        int margin = dp(density, 16), gap = dp(density, 6), accent = dp(density, 12);
        int primary = accent + percentWidth;
        if (primary > width - margin * 2) return null;
        labels &= primary + gap + labelWidth <= width - margin * 2;
        int availableDetail = width - margin * 2 - primary - gap - labelWidth - gap;
        boolean details = columns == 3 && labels && availableDetail > 0;
        int detailWidth = 0;
        for (Measured row : measured) {
            if (!row.row.credits.isEmpty()) {
                details &= row.credits.supported && row.credits.width() <= availableDetail;
                detailWidth = Math.max(detailWidth, row.credits.width());
            }
            if (row.reset.supported && row.reset.width() <= availableDetail)
                detailWidth = Math.max(detailWidth, row.reset.width());
        }
        details &= detailWidth > 0;
        int rowHeight = dp(density, 44), resetTop = dp(density, 29);
        for (Measured row : measured) if (details && !row.row.credits.isEmpty())
            resetTop = Math.max(resetTop, row.credits.height() + dp(density, 3));
        for (Measured row : measured) {
            rowHeight = Math.max(rowHeight, row.percent.height());
            if (labels) rowHeight = Math.max(rowHeight, row.family.height()
                    + (row.row.family.isEmpty() ? 0 : dp(density, 3)) + row.pool.height());
            if (details) {
                rowHeight = Math.max(rowHeight, row.credits.height());
                if (!row.row.reset.isEmpty() && row.reset.supported
                        && row.reset.width() <= availableDetail)
                    rowHeight = Math.max(rowHeight, resetTop + row.reset.height());
            }
        }
        int blockHeight = rowHeight * measured.size() + dp(density, 8) * (measured.size() - 1);
        int availableHeight = height - top - inset - margin;
        if (blockHeight > availableHeight) return null;
        int blockWidth = primary + (labels ? gap + labelWidth : 0)
                + (details ? gap + detailWidth : 0);
        int x = (width - blockWidth) / 2;
        int y = top + inset + (availableHeight - blockHeight) / 2;
        int labelX = x + primary + gap, end = x + blockWidth;
        List<TextRun> text = new ArrayList<>();
        List<Bar> bars = new ArrayList<>();
        List<VisibleRow> visible = new ArrayList<>();
        for (Measured item : measured) {
            Row row = item.row;
            boolean credits = details && !row.credits.isEmpty();
            boolean reset = details && !row.reset.isEmpty() && item.reset.supported
                    && item.reset.width() <= availableDetail;
            text.add(new TextRun(row.percent, Style.PERCENT, item.percent,
                    x + accent, y + (rowHeight - item.percent.height()) / 2));
            bars.add(new Bar(x, y + dp(density, 2), dp(density, 3),
                    rowHeight - dp(density, 4), row.color));
            if (labels) {
                int lineGap = row.family.isEmpty() ? 0 : dp(density, 3);
                int labelY = y + (rowHeight - item.family.height() - lineGap
                        - item.pool.height()) / 2;
                if (!row.family.isEmpty()) text.add(new TextRun(row.family, Style.FAMILY,
                        item.family, labelX + (labelWidth - item.family.width()) / 2, labelY));
                if (!row.pool.isEmpty()) text.add(new TextRun(row.pool, Style.POOL, item.pool,
                        labelX + (labelWidth - item.pool.width()) / 2,
                        labelY + item.family.height() + lineGap));
            }
            if (credits) text.add(new TextRun(row.credits, Style.CREDIT, item.credits,
                    end - item.credits.width(), y + (reset
                            ? resetTop - dp(density, 3) - item.credits.height()
                            : (rowHeight - item.credits.height()) / 2)));
            if (reset) text.add(new TextRun(row.reset, Style.RESET, item.reset,
                    end - item.reset.width(), y + resetTop));
            visible.add(new VisibleRow(row, labels, credits, reset, y, rowHeight));
            y += rowHeight + dp(density, 8);
        }
        return new Plan(width, height, inset, EmptyState.NONE, mark, text, bars, visible);
    }
}
