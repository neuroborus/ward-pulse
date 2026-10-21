package app.wardpulse;

/** A widget navigation intent waits for its own Dart handler, independently from refresh. */
public final class DashboardLaunchRequest {
    public static final String ACTION = "app.wardpulse.action.OPEN_DASHBOARD";
    private boolean ready;
    private boolean pending;

    public boolean record(String action) {
        if (!ACTION.equals(action)) return false;
        pending = true;
        return true;
    }

    public void markReady() {
        ready = true;
    }

    public boolean takeReadyRequest() {
        if (!ready || !pending) return false;
        pending = false;
        return true;
    }

    public void reset() {
        ready = false;
        pending = false;
    }
}
