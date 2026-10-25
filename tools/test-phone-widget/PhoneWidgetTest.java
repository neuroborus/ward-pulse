package app.wardpulse;

/** Exercises production presentation, fit and navigation without an Android dependency. */
public final class PhoneWidgetTest {
    private static int assertions;

    private static void check(boolean value, String message) {
        assertions++;
        if (!value) throw new AssertionError(message);
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

        check(PhoneWidgetLayout.completeRows(0, 1, 0) == 0, "No forced clipped row.");
        check(PhoneWidgetLayout.completeRows(48, 1, 0) == 0, "Fresh lower boundary.");
        check(PhoneWidgetLayout.completeRows(49, 1, 0) == 1, "Fresh complete row.");
        check(PhoneWidgetLayout.completeRows(65, 1, 17) == 0, "Stale inset excluded from fit.");
        check(PhoneWidgetLayout.completeRows(66, 1, 17) == 1, "Stale complete row.");
        check(PhoneWidgetLayout.completeRows(101, 1, 17) == 1, "No partial second stale row.");
        check(PhoneWidgetLayout.completeRows(102, 1, 17) == 2, "Second stale row boundary.");
        check(PhoneWidgetLayout.completeRows(56, 2.625f, 44) == 0, "Pixel inset short host.");
        check(PhoneWidgetLayout.completeRows(66, 2.625f, 44) == 1, "Pixel inset fits one row.");
        check(PhoneWidgetLayout.completeRows(1000, 3, 100) == 6, "Six-row cap.");
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
