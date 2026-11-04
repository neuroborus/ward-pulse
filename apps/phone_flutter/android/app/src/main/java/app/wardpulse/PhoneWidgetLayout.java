package app.wardpulse;

import java.math.BigInteger;
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
        public final String spent, spentDescription, detail, lower, detailDescription, lowerDescription;
        public final boolean budget;
        public final Style detailStyle;
        public final int color;

        public Row(String identity, String family, String pool, String percent,
                String credits, String reset, int color) {
            this(identity, family, pool, percent, credits, reset, color,
                    "", "", "", "", "", "", "", "", "");
        }

        private Row(String identity, String family, String pool, String percent,
                String credits, String reset, int color, String kind, String spentMinor,
                String spentCurrency, String capMinor, String capCurrency,
                String usedValue, String usedUnit, String capValue, String capUnit) {
            this.identity = identity;
            this.family = family;
            this.pool = pool;
            this.budget = kind.equals("budget");
            this.spent = moneyText(spentMinor, spentCurrency);
            this.spentDescription = formatMoney(spentMinor, spentCurrency, false);
            String cap = moneyText(capMinor, capCurrency);
            boolean capPresent = !capMinor.isEmpty() || !capCurrency.isEmpty();
            boolean usableCap = !cap.isEmpty() && spentCurrency.equals(capCurrency)
                    && new BigInteger(capMinor).signum() > 0;
            this.percent = (!kind.isEmpty() && !validPercent(percent))
                    || (budget && (spent.isEmpty() || !usableCap)) ? "" : percent;
            this.credits = credits;
            this.reset = budget ? "" : reset;
            this.color = color;
            String used = quantityText(usedValue, usedUnit);
            String extraCap = quantityText(capValue, capUnit);
            boolean extra = !used.isEmpty() || !extraCap.isEmpty();
            detailStyle = budget || extra ? Style.FAMILY : Style.CREDIT;
            if (budget) {
                detail = this.percent.isEmpty() ? "" : spent;
                detailDescription = detail.isEmpty() ? "" : spentDescription + " spent";
                lower = spent.isEmpty() ? "Unavailable"
                        : !capPresent ? "No cap" : !usableCap ? "Cap unavailable"
                        : "Cap " + cap + (this.percent.isEmpty() ? " · Percentage unavailable" : "");
                lowerDescription = usableCap && !spent.isEmpty()
                        ? "Cap " + formatMoney(capMinor, capCurrency, false)
                                + (this.percent.isEmpty() ? " · Percentage unavailable" : "")
                        : lower;
            } else {
                if (extra) {
                    detail = usedUnit.equals(capUnit) && !used.isEmpty() && !extraCap.isEmpty()
                            ? usedValue + " / " + capValue + " " + usedUnit
                            : (used.isEmpty() ? "—" : used) + " / "
                                    + (extraCap.isEmpty() ? "—" : extraCap);
                    detailDescription = (used.isEmpty() ? "Used unavailable" : used + " used")
                            + ", " + (extraCap.isEmpty() ? "Cap unavailable" : extraCap + " cap");
                } else {
                    detail = credits;
                    detailDescription = credits.isEmpty() ? "" : credits + " purchased credits";
                }
                lower = reset;
                lowerDescription = reset;
            }
        }

        String primary(boolean details) {
            return budget && (!details || percent.isEmpty())
                    ? spent.isEmpty() ? "—" : spent : percent;
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

        public static Row fromCache(String label, String family, String pool, String percent,
                String credits, String reset, ZoneId zone, int color, String kind,
                String spentMinor, String spentCurrency, String capMinor, String capCurrency,
                String usedValue, String usedUnit, String capValue, String capUnit) {
            Row legacy = fromCache(label, family, pool, percent, credits, reset, zone, color);
            if (kind.isEmpty()) return legacy;
            return new Row(legacy.identity, legacy.family, legacy.pool, legacy.percent,
                    legacy.credits, legacy.reset, color, kind, spentMinor, spentCurrency,
                    capMinor, capCurrency, usedValue, usedUnit, capValue, capUnit);
        }
    }

    /** Integer minor units are never routed through floating point. */
    public static String moneyText(String minor, String currency) {
        return formatMoney(minor, currency, true);
    }

    private static String formatMoney(String minor, String currency, boolean compact) {
        if (minor.length() > 64 || !minor.matches("-?[0-9]+")
                || !currency.matches("[A-Za-z]{3}")) return "";
        BigInteger amount = new BigInteger(minor);
        BigInteger magnitude = amount.abs();
        String prefix = (amount.signum() < 0 ? "-" : "")
                + (compact && currency.equals("USD") ? "$"
                        : compact && currency.equals("EUR") ? "€" : currency + " ");
        BigInteger unit = BigInteger.valueOf(100_000);
        if (!compact || magnitude.compareTo(unit) < 0) {
            BigInteger[] parts = magnitude.divideAndRemainder(BigInteger.valueOf(100));
            String cents = parts[1].toString();
            return prefix + parts[0] + "." + (cents.length() == 1 ? "0" : "") + cents;
        }
        String suffixes = "KMBT";
        BigInteger thousand = BigInteger.valueOf(1000);
        int suffix = 0;
        while (suffix < suffixes.length() - 1
                && magnitude.compareTo(unit.multiply(thousand)) >= 0) {
            unit = unit.multiply(thousand);
            suffix++;
        }
        BigInteger[] parts = magnitude.multiply(BigInteger.TEN).divideAndRemainder(unit);
        BigInteger tenths = parts[0];
        if (parts[1].multiply(BigInteger.valueOf(2)).compareTo(unit) >= 0) {
            tenths = tenths.add(BigInteger.ONE);
        }
        if (suffix < suffixes.length() - 1 && tenths.equals(BigInteger.valueOf(10_000))) {
            return prefix + "1" + suffixes.charAt(suffix + 1);
        }
        BigInteger[] coefficient = tenths.divideAndRemainder(BigInteger.TEN);
        return prefix + coefficient[0]
                + (coefficient[1].signum() == 0 ? "" : "." + coefficient[1])
                + suffixes.charAt(suffix);
    }

    private static String quantityText(String value, String unit) {
        return value.length() <= MAX_TEXT_LENGTH
                && value.matches("[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?")
                && !unit.isEmpty() && unit.length() <= MAX_TEXT_LENGTH ? value + " " + unit : "";
    }

    private static boolean validPercent(String text) {
        if (text.length() > 32 || !text.matches("[0-9]+(?:\\.[0-9]+)?%")) return false;
        double value = Double.parseDouble(text.substring(0, text.length() - 1));
        return Double.isFinite(value) && value >= 0 && value <= 100;
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
        public final boolean labels, credits, reset, lower;
        public final String primary;
        public final int top, height;

        VisibleRow(Row row, boolean labels, boolean credits, boolean lower,
                String primary, int top, int height) {
            this.row = row;
            this.labels = labels;
            this.credits = credits;
            this.lower = lower;
            this.reset = lower && !row.budget;
            this.primary = primary;
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
        public final Bounds card;
        public final EmptyState state;
        public final boolean mark;
        public final List<TextRun> text;
        public final List<Bar> bars;
        public final List<VisibleRow> rows;

        Plan(int width, int height, int staleInset, EmptyState state, boolean mark,
                List<TextRun> text, List<Bar> bars, List<VisibleRow> rows, Bounds card) {
            this.width = width;
            this.height = height;
            this.staleInset = staleInset;
            this.state = state;
            this.mark = mark;
            this.text = Collections.unmodifiableList(text);
            this.bars = Collections.unmodifiableList(bars);
            this.rows = Collections.unmodifiableList(rows);
            this.card = card;
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
                    && value != '\u2013' && value != '\u2014' && value != '\u2019'
                    && value != '\u20ac') return false;
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
        String value = row.budget && !visible.primary.equals(row.percent)
                ? row.spent.isEmpty() ? "Unavailable" : row.spentDescription + " spent"
                : visible.primary + " remaining";
        String result = rowDescription(row.identity, value, row.detailDescription, visible.credits);
        return visible.lower ? result + ", " + row.lowerDescription : result;
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
        final Glyphs percent, money, smallMoney, family, pool, detail, lower;

        Measured(Row row, Measurer measurer) {
            this.row = row;
            percent = measurer.measure(row.percent, Style.PERCENT);
            String amount = row.spent.isEmpty() ? "—" : row.spent;
            money = measurer.measure(amount, Style.PERCENT);
            smallMoney = measurer.measure(amount, Style.CREDIT);
            family = measurer.measure(row.family, Style.FAMILY);
            pool = measurer.measure(row.pool, Style.POOL);
            detail = measurer.measure(row.detail, row.detailStyle);
            lower = measurer.measure(row.lower, Style.RESET);
        }

        Glyphs primary(boolean details, boolean small) {
            return row.budget && (!details || row.percent.isEmpty())
                    ? small ? smallMoney : money : percent;
        }
    }

    /** Width/height are host pixels; the intrinsic card never changes host allocation. */
    public static Plan fit(int width, int height, float density, List<Row> rows,
            boolean payloadEmpty, boolean stale, Measurer measurer, long byteBudget, int markBytes) {
        if (width <= 0 || height <= 0 || width > 16384 || height > 16384
                || !Float.isFinite(density) || density <= 0 || density > 8
                || byteBudget < 0 || markBytes < 0) {
            throw new IllegalArgumentException("Invalid widget display geometry or byte budget.");
        }
        long budget = Math.min(byteBudget, MAX_BITMAP_BYTES);
        Glyphs badge = measurer.measure("STALE", Style.STALE);
        List<Measured> measured = new ArrayList<>();
        int primaryRoom = width - 2 * dp(density, 16) - dp(density, 12);
        if (!payloadEmpty) for (int i = 0; i < Math.min(rows.size(), MAX_ROWS); i++) {
            Measured item = new Measured(rows.get(i), measurer);
            measured.add(item);
        }
        // Qualify the complete selection's width independently of height/memory fallback.
        // A capped row may still fit as percent plus spent/cap details; test actual columns.
        boolean widthFit = measured.stream().noneMatch(item -> item.row.budget);
        if (!widthFit) for (boolean small : new boolean[] {false, true}) {
            for (int columns = 3; columns > 0; columns--)
                widthFit |= rows(width, 16384, density, measured, columns, small,
                        stale, badge) != null;
        }
        if (widthFit) for (int count = measured.size(); count > 0; count--) {
            List<Measured> retained = measured.subList(0, count);
            for (boolean small : new boolean[] {false, true}) {
                if (small && retained.stream().noneMatch(item -> item.row.budget
                        && item.money.width() > primaryRoom)) continue;
                for (int columns = 3; columns > 0; columns--) {
                    Plan plan = rows(width, height, density, retained, columns, small,
                            stale, badge);
                    if (plan != null && fitsBytes(plan, budget, markBytes)) return plan;
                }
            }
        }
        EmptyState state = emptyState(rows.size(), payloadEmpty, 0);
        String message = state == EmptyState.NO_METRICS ? "No metrics" : "Resize widget";
        Glyphs glyphs = measurer.measure(message, Style.EMPTY);
        // Tiny hosts prioritize complete copy over a header or decoration.
        for (int mode = 0; mode < 3; mode++) {
            int margin = dp(density, mode == 2 ? 2 : 16);
            boolean mark = mode < 2 && width >= dp(density, 68);
            boolean showBadge = mode == 0 && stale && badge.supported;
            int header = mode == 2 ? 0 : dp(density, 19);
            if (showBadge) header = Math.max(header,
                    badge.lineBottom - badge.lineTop + dp(density, 2));
            int headerWidth = headerWidth(density, mark, showBadge, badge);
            int cardWidth = Math.max(glyphs.width() + 2 * margin, headerWidth);
            int cardHeight = header + glyphs.height() + margin;
            if (!glyphs.supported || cardWidth > width || cardHeight > height) continue;
            Bounds card = centered(width, height, cardWidth, cardHeight);
            List<TextRun> text = new ArrayList<>();
            text.add(new TextRun(message, Style.EMPTY, glyphs,
                    card.left + (cardWidth - glyphs.width()) / 2, card.top + header));
            if (showBadge) addBadge(text, badge, card, density, header);
            Plan plan = new Plan(width, height, 0, state, mark, text,
                    Collections.emptyList(), Collections.emptyList(), card);
            if (fitsBytes(plan, budget, markBytes)) return plan;
        }
        return new Plan(width, height, 0, state, false,
                Collections.emptyList(), Collections.emptyList(), Collections.emptyList(), null);
    }

    private static Bounds centered(int width, int height, int cardWidth, int cardHeight) {
        int x = (width - cardWidth) / 2, y = (height - cardHeight) / 2;
        return new Bounds(x, y, x + cardWidth, y + cardHeight);
    }

    private static int headerWidth(float density, boolean mark, boolean stale, Glyphs badge) {
        return dp(density, 32) + (stale ? badge.width() : 0)
                + (mark ? dp(density, 36) : 0) + (mark && stale ? dp(density, 6) : 0);
    }

    private static void addBadge(List<TextRun> text, Glyphs badge, Bounds card,
            float density, int header) {
        int lineHeight = badge.lineBottom - badge.lineTop;
        int lineY = card.top + Math.max(0, (header - lineHeight - dp(density, 2)) / 2);
        text.add(new TextRun("STALE", Style.STALE, badge, card.left + dp(density, 16),
                lineY + badge.top - badge.lineTop));
    }

    private static boolean fitsBytes(Plan plan, long budget, int markBytes) {
        long bytes = plan.bitmapBytes();
        return bytes != Long.MAX_VALUE && bytes + (plan.mark ? markBytes : 0L) <= budget;
    }

    private static Plan rows(int width, int height, float density, List<Measured> measured,
            int columns, boolean small, boolean stale, Glyphs badge) {
        int margin = dp(density, 16), gap = dp(density, 6), accent = dp(density, 12);
        boolean details = columns == 3;
        boolean labels = columns >= 2;
        int primaryWidth = 0, labelWidth = 0, detailWidth = 0;
        for (Measured item : measured) {
            Glyphs primary = item.primary(details, small);
            if (item.row.primary(details).isEmpty() || !primary.supported) return null;
            primaryWidth = Math.max(primaryWidth, primary.width());
            if (labels) {
                if (!item.family.supported || !item.pool.supported) return null;
                labelWidth = Math.max(labelWidth, Math.max(item.family.width(), item.pool.width()));
            }
        }
        int availableDetail = width - 2 * margin - accent - primaryWidth - 2 * gap - labelWidth;
        for (Measured item : measured) if (details) {
            if (!item.row.detail.isEmpty()) {
                if (!item.detail.supported || item.detail.width() > availableDetail) return null;
                detailWidth = Math.max(detailWidth, item.detail.width());
            }
            // A real reset may be omitted before its balance; budget state is not a reset.
            if (!item.row.lower.isEmpty() && item.lower.supported
                    && item.lower.width() <= availableDetail)
                detailWidth = Math.max(detailWidth, item.lower.width());
            else if (item.row.budget && !item.row.lower.isEmpty()) return null;
        }
        if (details && detailWidth == 0) return null;
        int blockWidth = accent + primaryWidth + (labels ? gap + labelWidth : 0)
                + (details ? gap + detailWidth : 0);
        boolean showBadge = stale && badge.supported;
        int header = dp(density, 19);
        if (showBadge) header = Math.max(header,
                badge.lineBottom - badge.lineTop + dp(density, 2));
        int cardWidth = Math.max(blockWidth + 2 * margin,
                headerWidth(density, true, showBadge, badge));
        if (cardWidth > width) return null;
        int rowHeight = dp(density, 44), lowerTop = dp(density, 29);
        for (Measured item : measured) if (details && !item.row.detail.isEmpty())
            lowerTop = Math.max(lowerTop, item.detail.height() + dp(density, 3));
        for (Measured item : measured) {
            rowHeight = Math.max(rowHeight, item.primary(details, small).height());
            if (labels) rowHeight = Math.max(rowHeight, item.family.height()
                    + (item.row.family.isEmpty() ? 0 : dp(density, 3)) + item.pool.height());
            if (details) {
                rowHeight = Math.max(rowHeight, item.detail.height());
                if (!item.row.lower.isEmpty() && item.lower.supported
                        && item.lower.width() <= availableDetail) {
                    // Include the lower line's native descent, not only its visible ink.
                    rowHeight = Math.max(rowHeight, lowerTop - item.lower.top
                            + Math.max(item.lower.bottom, item.lower.lineBottom));
                }
            }
        }
        int blockHeight = rowHeight * measured.size() + dp(density, 8) * (measured.size() - 1);
        int cardHeight = header + blockHeight + margin;
        if (cardHeight > height) return null;
        Bounds card = centered(width, height, cardWidth, cardHeight);
        int x = card.left + (cardWidth - blockWidth) / 2, y = card.top + header;
        int labelX = x + accent + primaryWidth + gap, end = x + blockWidth;
        List<TextRun> text = new ArrayList<>();
        List<Bar> bars = new ArrayList<>();
        List<VisibleRow> visible = new ArrayList<>();
        if (showBadge) addBadge(text, badge, card, density, header);
        for (Measured item : measured) {
            Row row = item.row;
            boolean detail = details && !row.detail.isEmpty();
            boolean lower = details && !row.lower.isEmpty() && item.lower.supported
                    && item.lower.width() <= availableDetail;
            Glyphs primary = item.primary(details, small);
            String value = row.primary(details);
            Style style = small && row.budget && !value.equals(row.percent)
                    ? Style.CREDIT : Style.PERCENT;
            text.add(new TextRun(value, style, primary,
                    x + accent, y + (rowHeight - primary.height()) / 2));
            bars.add(new Bar(x, y + dp(density, 2), dp(density, 3),
                    rowHeight - dp(density, 4), row.color));
            if (labels) {
                int lineGap = row.family.isEmpty() ? 0 : dp(density, 3);
                int labelY = y + (rowHeight - item.family.height() - lineGap - item.pool.height()) / 2;
                if (!row.family.isEmpty()) text.add(new TextRun(row.family, Style.FAMILY,
                        item.family, labelX + (labelWidth - item.family.width()) / 2, labelY));
                if (!row.pool.isEmpty()) text.add(new TextRun(row.pool, Style.POOL, item.pool,
                        labelX + (labelWidth - item.pool.width()) / 2,
                        labelY + item.family.height() + lineGap));
            }
            if (detail) text.add(new TextRun(row.detail, row.detailStyle, item.detail,
                    end - item.detail.width(), y + (lower
                            ? lowerTop - dp(density, 3) - item.detail.height()
                            : (rowHeight - item.detail.height()) / 2)));
            if (lower) text.add(new TextRun(row.lower, Style.RESET, item.lower,
                    end - item.lower.width(), y + lowerTop));
            visible.add(new VisibleRow(row, labels, detail, lower, value, y, rowHeight));
            y += rowHeight + dp(density, 8);
        }
        return new Plan(width, height, 0, EmptyState.NONE, true, text, bars, visible, card);
    }
}
