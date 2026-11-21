package app.wardpulse;

import android.graphics.Bitmap;
import android.net.http.SslError;
import android.os.Message;
import android.view.KeyEvent;
import android.webkit.ClientCertRequest;
import android.webkit.HttpAuthHandler;
import android.webkit.SslErrorHandler;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import java.io.ByteArrayInputStream;
import java.net.URI;
import java.net.URISyntaxException;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.Locale;
import java.util.Set;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.Consumer;
import java.util.regex.Pattern;

/** Adds request-level policy while retaining the Flutter plugin's existing client. */
public final class CursorSignInWebViewClient extends WebViewClient {
    public enum Failure { GOOGLE_AUTHORIZATION, MAIN_FRAME_HTTP_ERROR, NAVIGATION_REJECTED }

    private static final Pattern GOOGLE_AUTH_PATH =
            Pattern.compile("^/(accounts|signin|o/oauth2)(/|$)");
    // Match isAllowedCursorSignInUrl; identity hosts are exact, not wildcard families.
    private static final Set<String> EXACT_HOSTS = Collections.unmodifiableSet(new HashSet<>(Arrays.asList(
            "accounts.x.ai", "accounts.spacex.ai", "auth.x.ai", "auth.grok.com",
            "auth.grokusercontent.com", "auth.grokipedia.com", "github.com",
            "www.github.com", "challenges.cloudflare.com")));
    private final WebViewClient delegate;
    private final Consumer<Failure> report;
    private final AtomicReference<Failure> failure = new AtomicReference<>();
    private volatile boolean retiring;

    public CursorSignInWebViewClient(WebViewClient delegate, Consumer<Failure> report) {
        this.delegate = delegate;
        this.report = report;
    }

    public Failure failure() {
        return failure.get();
    }

    public void beginRetirement() {
        retiring = true;
    }

    private void fail(Failure category) {
        if (failure.compareAndSet(null, category)) report.accept(category);
    }

    private boolean block(String url, boolean mainFrame) {
        if (isGoogleAuthorization(url)) {
            fail(Failure.GOOGLE_AUTHORIZATION);
            return true;
        }
        if (!mainFrame) return false;
        if (retiring && "about:blank".equals(url)) return false;
        if (!isAllowedMainFrameUrl(url)) {
            fail(Failure.NAVIGATION_REJECTED);
            return true;
        }
        // During retirement, only the internal blank main document may load.
        return retiring;
    }

    private static boolean isAllowedMainFrameUrl(String url) {
        try {
            URI uri = new URI(url);
            if (!"https".equalsIgnoreCase(uri.getScheme()) || uri.getHost() == null) return false;
            String host = uri.getHost().toLowerCase(Locale.ROOT);
            return EXACT_HOSTS.contains(host) || hostMatches(host, "cursor.com")
                    || hostMatches(host, "cursor.sh") || hostMatches(host, "recaptcha.net")
                    || hostMatches(host, "microsoftonline.com") || hostMatches(host, "workos.com");
        } catch (URISyntaxException ignored) {
            return false;
        }
    }

    private static boolean hostMatches(String host, String apex) {
        return host.equals(apex) || host.endsWith("." + apex);
    }

    private static boolean isGoogleAuthorization(String url) {
        try {
            URI uri = new URI(url);
            String host = uri.getHost();
            if (host == null) return false;
            host = host.toLowerCase(Locale.ROOT);
            String path = uri.getPath();
            if (host.equals("accounts.google.com")) {
                // Keep sign-in button scripts/styles distinct from authorization.
                return !("/gsi/client".equals(path) || "/gsi/style".equals(path)
                        || "/gsi/button".equals(path));
            }
            if (host.equals("accounts.youtube.com")) return true;
            return (host.equals("google.com") || host.endsWith(".google.com"))
                    && path != null && GOOGLE_AUTH_PATH.matcher(path).find();
        } catch (URISyntaxException ignored) {
            return false;
        }
    }

    private static WebResourceResponse blockedResponse() {
        return new WebResourceResponse("text/plain", "UTF-8", 403, "Forbidden",
                Collections.emptyMap(), new ByteArrayInputStream(new byte[0]));
    }

    @Override
    public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
        return block(request.getUrl().toString(), request.isForMainFrame())
                || delegate.shouldOverrideUrlLoading(view, request);
    }

    @Override
    public boolean shouldOverrideUrlLoading(WebView view, String url) {
        return block(url, true) || delegate.shouldOverrideUrlLoading(view, url);
    }

    @Override
    public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
        // POST requests do not reach shouldOverrideUrlLoading. Enforce the same
        // main-frame policy here, separately from iframe/fetch authorization checks.
        return block(request.getUrl().toString(), request.isForMainFrame())
                ? blockedResponse() : delegate.shouldInterceptRequest(view, request);
    }

    @Override
    public WebResourceResponse shouldInterceptRequest(WebView view, String url) {
        // This legacy callback has no frame flag; current Android supplies the
        // WebResourceRequest overload above. Keep ordinary subresources harmless.
        return block(url, false) ? blockedResponse() : delegate.shouldInterceptRequest(view, url);
    }

    @Override
    public void onReceivedHttpError(WebView view, WebResourceRequest request,
            WebResourceResponse response) {
        if (request.isForMainFrame()) fail(Failure.MAIN_FRAME_HTTP_ERROR);
        delegate.onReceivedHttpError(view, request, response);
    }

    @Override
    public void onPageStarted(WebView view, String url, Bitmap icon) {
        delegate.onPageStarted(view, url, icon);
    }

    @Override
    public void onPageFinished(WebView view, String url) {
        delegate.onPageFinished(view, url);
    }

    @Override
    public void onPageCommitVisible(WebView view, String url) {
        delegate.onPageCommitVisible(view, url);
    }

    @Override
    public void onLoadResource(WebView view, String url) {
        delegate.onLoadResource(view, url);
    }

    @Override
    public void doUpdateVisitedHistory(WebView view, String url, boolean reload) {
        delegate.doUpdateVisitedHistory(view, url, reload);
    }

    @Override
    public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
        delegate.onReceivedError(view, request, error);
    }

    @Override
    public void onReceivedError(WebView view, int code, String description, String url) {
        delegate.onReceivedError(view, code, description, url);
    }

    @Override
    public void onReceivedSslError(WebView view, SslErrorHandler handler, SslError error) {
        delegate.onReceivedSslError(view, handler, error);
    }

    @Override
    public void onReceivedHttpAuthRequest(WebView view, HttpAuthHandler handler,
            String host, String realm) {
        delegate.onReceivedHttpAuthRequest(view, handler, host, realm);
    }

    @Override
    public void onReceivedClientCertRequest(WebView view, ClientCertRequest request) {
        delegate.onReceivedClientCertRequest(view, request);
    }

    @Override
    public void onFormResubmission(WebView view, Message dontResend, Message resend) {
        delegate.onFormResubmission(view, dontResend, resend);
    }

    @Override
    public void onScaleChanged(WebView view, float oldScale, float newScale) {
        delegate.onScaleChanged(view, oldScale, newScale);
    }

    @Override
    public void onReceivedLoginRequest(WebView view, String realm, String account, String args) {
        delegate.onReceivedLoginRequest(view, realm, account, args);
    }

    @Override
    public void onUnhandledKeyEvent(WebView view, KeyEvent event) {
        delegate.onUnhandledKeyEvent(view, event);
    }

}
