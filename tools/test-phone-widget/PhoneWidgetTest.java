package app.wardpulse;

/** Exercises the production fit and navigation state without an Android dependency. */
public final class PhoneWidgetTest {
    private static int assertions;

    private static void check(boolean value, String message) {
        assertions++;
        if (!value) throw new AssertionError(message);
    }

    public static void main(String[] ignored) {
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
