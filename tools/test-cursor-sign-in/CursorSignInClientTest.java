package app.wardpulse;

import android.graphics.Bitmap;
import android.net.Uri;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/** Exercises production WebViewClient overrides against deterministic Android API doubles. */
public final class CursorSignInClientTest {
    private static final class Request implements WebResourceRequest {
        private final Uri uri;
        private final boolean main;
        private final String method;
        Request(String uri, boolean main) { this(uri, main, "GET"); }
        Request(String uri, boolean main, String method) {
            this.uri = Uri.parse(uri);
            this.main = main;
            this.method = method;
        }
        public Uri getUrl() { return uri; }
        public boolean isForMainFrame() { return main; }
        public boolean isRedirect() { return false; }
        public boolean hasGesture() { return false; }
        public String getMethod() { return method; }
        public Map<String, String> getRequestHeaders() { return Map.of(); }
    }

    private static final class Delegate extends WebViewClient {
        int navigations;
        int interceptions;
        int httpErrors;
        int starts;
        int finishes;
        boolean decision;
        String method;
        @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
            navigations++;
            return decision;
        }
        @Override public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
            interceptions++;
            method = request.getMethod();
            return null;
        }
        @Override public void onReceivedHttpError(WebView view, WebResourceRequest request, WebResourceResponse response) {
            httpErrors++;
        }
        @Override public void onPageStarted(WebView view, String url, Bitmap icon) { starts++; }
        @Override public void onPageFinished(WebView view, String url) { finishes++; }
    }

    public static void main(String[] args) {
        WebView view = new WebView();
        for (boolean main : new boolean[] { false, true }) {
            for (String uri : List.of(
                    "https://accounts.google.com/o/oauth2/auth?state=synthetic",
                    "https://accounts.youtube.com/accounts/SetSID",
                    "https://accounts.google.com/gsi/iframe/select",
                    "https://www.google.com/accounts/ServiceLogin",
                    "https://www.google.com/o/oauth2/auth")) {
                Delegate delegate = new Delegate();
                List<CursorSignInWebViewClient.Failure> events = new ArrayList<>();
                CursorSignInWebViewClient client = new CursorSignInWebViewClient(delegate, events::add);
                Request request = new Request(uri, main);
                check(client.shouldOverrideUrlLoading(view, request), "authorization navigation blocked");
                check(client.shouldInterceptRequest(view, request) != null, "authorization resource blocked");
                check(delegate.navigations == 0 && delegate.interceptions == 0, "blocked requests never delegated");
                check(events.equals(List.of(CursorSignInWebViewClient.Failure.GOOGLE_AUTHORIZATION)),
                        "one fixed authorization category, without URL or headers");
            }
        }

        Delegate delegate = new Delegate();
        List<CursorSignInWebViewClient.Failure> events = new ArrayList<>();
        CursorSignInWebViewClient client = new CursorSignInWebViewClient(delegate, events::add);
        for (String uri : List.of(
                "https://www.google.com/recaptcha/api2/anchor",
                "https://www.gstatic.com/recaptcha/resource",
                "https://accounts.google.com/gsi/client",
                "https://accounts.google.com/gsi/style",
                "https://accounts.google.com/gsi/button",
                "https://accounts.google.com.example/resource",
                "https://auth.x.ai/login", "https://github.com/login")) {
            check(client.shouldInterceptRequest(view, new Request(uri, false)) == null, "harmless resource delegated");
            delegate.decision = true;
            check(client.shouldOverrideUrlLoading(view, new Request(uri, false)), "delegate prevent preserved");
            delegate.decision = false;
            check(!client.shouldOverrideUrlLoading(view, new Request(uri, false)), "delegate admission preserved");
        }
        check(events.isEmpty(), "harmless requests do not fail sign-in");
        check(delegate.interceptions == 8 && delegate.navigations == 16, "native callbacks actually forwarded");
        client.onPageStarted(view, "https://cursor.com/login", null);
        client.onPageFinished(view, "https://cursor.com/login");
        check(delegate.starts == 1 && delegate.finishes == 1, "page lifecycle forwarded");
        check(client.shouldInterceptRequest(view, "https://accounts.google.com/signin") != null,
                "legacy interception blocks authorization");
        check(client.shouldOverrideUrlLoading(view, "https://accounts.google.com/signin"),
                "legacy navigation blocks authorization");

        Delegate mainDelegate = new Delegate();
        List<CursorSignInWebViewClient.Failure> mainEvents = new ArrayList<>();
        CursorSignInWebViewClient mainClient = new CursorSignInWebViewClient(mainDelegate, mainEvents::add);
        Request mainRequest = new Request("https://cursor.com/dashboard", true);
        mainDelegate.decision = true;
        check(mainClient.shouldOverrideUrlLoading(view, mainRequest), "approved main-frame delegate prevention preserved");
        mainDelegate.decision = false;
        check(!mainClient.shouldOverrideUrlLoading(view, mainRequest), "approved main-frame delegate admission preserved");
        check(mainDelegate.navigations == 2 && mainEvents.isEmpty(), "approved main-frame callbacks forwarded");

        for (String host : List.of("accounts.x.ai", "accounts.spacex.ai", "auth.x.ai",
                "auth.grok.com", "auth.grokusercontent.com", "auth.grokipedia.com")) {
            checkPost(view, "https://" + host + "/login", true);
            for (String rejected : List.of("http://" + host + "/login",
                    "ftp://" + host + "/login", "https://child." + host + "/login",
                    "https://" + host + ".example/login", "https://prefix" + host + "/login",
                    "https://" + host + "@unrelated.example/login")) {
                checkPost(view, rejected, false);
            }
        }
        for (String permitted : List.of("https://cursor.com/dashboard",
                "https://www.cursor.com/login", "https://authenticator.cursor.sh/login",
                "https://github.com/login", "https://www.github.com/login",
                "https://challenges.cloudflare.com/", "https://www.recaptcha.net/",
                "https://login.microsoftonline.com/login", "https://auth.workos.com/login",
                "HTTPS://AUTH.X.AI/login")) {
            checkPost(view, permitted, true);
        }
        for (String rejected : List.of("https://unrelated.example/login", "http://cursor.com/login",
                "https://notcursor.com/login", "https://cursor.com.example/login",
                "https://grok.com/login", "https://accounts.google.com/gsi/client",
                "https://www.gstatic.com/recaptcha/resource",
                "https://www.google.com/recaptcha/api2/anchor", "about:blank", "about:blank#fragment")) {
            checkPost(view, rejected, false);
        }

        Delegate retiringDelegate = new Delegate();
        List<CursorSignInWebViewClient.Failure> retirementEvents = new ArrayList<>();
        CursorSignInWebViewClient retiring = new CursorSignInWebViewClient(retiringDelegate, retirementEvents::add);
        retiring.beginRetirement();
        check(retiring.shouldInterceptRequest(view, new Request("about:blank", true)) == null,
                "internal blank retirement remains admitted");
        check(retiring.shouldInterceptRequest(view, new Request("https://cursor.com/login", true, "POST")) != null,
                "retiring document cannot restart a permitted login");
        check(retiringDelegate.interceptions == 1, "only the internal blank reaches the retiring client");
        check(retirementEvents.isEmpty(), "internal retirement is not a navigation failure");

        for (boolean main : new boolean[] { false, true }) {
            for (int status : new int[] { 401, 503 }) {
                Delegate target = new Delegate();
                List<CursorSignInWebViewClient.Failure> failures = new ArrayList<>();
                CursorSignInWebViewClient guarded = new CursorSignInWebViewClient(target, failures::add);
                WebResourceResponse response = new WebResourceResponse("text/plain", "UTF-8",
                        status, "Synthetic error", Map.of(), null);
                guarded.onReceivedHttpError(view, new Request("https://cursor.com/login", main), response);
                check(target.httpErrors == 1, "HTTP callback retained");
                check(failures.size() == (main ? 1 : 0), "native main-frame flag classifies HTTP failure");
                if (main) check(guarded.failure() == CursorSignInWebViewClient.Failure.MAIN_FRAME_HTTP_ERROR,
                        "HTTP failure retained for synchronous status check");
            }
        }
        System.out.println("Cursor sign-in native callback contracts passed");
    }

    private static void checkPost(WebView view, String url, boolean allowed) {
        Delegate delegate = new Delegate();
        List<CursorSignInWebViewClient.Failure> events = new ArrayList<>();
        CursorSignInWebViewClient client = new CursorSignInWebViewClient(delegate, events::add);
        // Exercise interception directly: Android skips navigation callbacks for POST.
        WebResourceResponse response = client.shouldInterceptRequest(view, new Request(url, true, "POST"));
        if (allowed) {
            check(response == null && delegate.interceptions == 1, "approved POST is delegated");
            check("POST".equals(delegate.method), "approved POST method is preserved");
            check(events.isEmpty(), "approved POST has no recovery event");
        } else {
            check(response != null && delegate.interceptions == 0, "unapproved POST is prevented before delegation");
            check(events.equals(List.of(CursorSignInWebViewClient.Failure.NAVIGATION_REJECTED)),
                    "rejected POST reports only a fixed navigation category");
            check(client.failure() == CursorSignInWebViewClient.Failure.NAVIGATION_REJECTED,
                    "rejected POST remains failed for completion checks");
        }
    }

    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
}
