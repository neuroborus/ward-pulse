#!/usr/bin/env python3
"""HOST-only JVM regression for the production Cursor WebViewClient boundary.

API doubles model callback dispatch, not an Android renderer or live provider.
The ordinary Android APK build and artifact-bound WebView checks remain required.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]

# Only framework signatures used by the production wrapper are doubled. Policy,
# callback routing and failure classification come from the production source.
CLIENT = """package android.webkit;
import android.graphics.Bitmap;
import android.net.http.SslError;
import android.os.Message;
import android.view.KeyEvent;
public class WebViewClient {
 public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest r) { return false; }
 public boolean shouldOverrideUrlLoading(WebView v, String u) { return false; }
 public WebResourceResponse shouldInterceptRequest(WebView v, WebResourceRequest r) { return null; }
 public WebResourceResponse shouldInterceptRequest(WebView v, String u) { return null; }
 public void onReceivedHttpError(WebView v, WebResourceRequest r, WebResourceResponse s) {}
 public void onPageStarted(WebView v, String u, Bitmap b) {}
 public void onPageFinished(WebView v, String u) {}
 public void onPageCommitVisible(WebView v, String u) {}
 public void onLoadResource(WebView v, String u) {}
 public void doUpdateVisitedHistory(WebView v, String u, boolean r) {}
 public void onReceivedError(WebView v, WebResourceRequest r, WebResourceError e) {}
 public void onReceivedError(WebView v, int c, String d, String u) {}
 public void onReceivedSslError(WebView v, SslErrorHandler h, SslError e) {}
 public void onReceivedHttpAuthRequest(WebView v, HttpAuthHandler h, String s, String r) {}
 public void onReceivedClientCertRequest(WebView v, ClientCertRequest r) {}
 public void onFormResubmission(WebView v, Message d, Message r) {}
 public void onScaleChanged(WebView v, float o, float n) {}
 public void onReceivedLoginRequest(WebView v, String r, String a, String s) {}
 public void onUnhandledKeyEvent(WebView v, KeyEvent e) {}
}
"""


def main():
    with tempfile.TemporaryDirectory(prefix="wardpulse-cursor-test-") as directory:
        temp = Path(directory)
        sources = []

        def source(name, body):
            path = temp / (name.replace(".", "/") + ".java")
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(body, encoding="utf-8")
            sources.append(str(path))

        for name in [
            "android.graphics.Bitmap", "android.net.http.SslError", "android.os.Message",
            "android.view.KeyEvent", "android.webkit.ClientCertRequest",
            "android.webkit.HttpAuthHandler", "android.webkit.SslErrorHandler",
            "android.webkit.WebResourceError", "android.webkit.WebView",
        ]:
            package, cls = name.rsplit(".", 1)
            source(name, f"package {package}; public class {cls} {{}}")
        source("android.net.Uri", """package android.net;
public final class Uri {
 private final String value;
 private Uri(String value) { this.value = value; }
 public static Uri parse(String value) { return new Uri(value); }
 public String toString() { return value; }
}""")
        source("android.webkit.WebResourceRequest", """package android.webkit;
import android.net.Uri;
import java.util.Map;
public interface WebResourceRequest {
 Uri getUrl(); boolean isForMainFrame(); boolean isRedirect(); boolean hasGesture();
 String getMethod(); Map<String, String> getRequestHeaders();
}""")
        source("android.webkit.WebResourceResponse", """package android.webkit;
import java.io.InputStream;
import java.util.Map;
public class WebResourceResponse {
 public WebResourceResponse(String mime, String encoding, int status, String reason,
     Map<String, String> headers, InputStream data) {}
}""")
        source("android.webkit.WebViewClient", CLIENT)
        production = ROOT / "apps/phone_flutter/android/app/src/main/java/app/wardpulse/CursorSignInWebViewClient.java"
        test = Path(__file__).with_name("CursorSignInClientTest.java")
        classes = temp / "classes"
        classes.mkdir()
        subprocess.run(["javac", "-d", str(classes), *sources, str(production), str(test)], check=True)
        subprocess.run(["java", "-cp", str(classes), "app.wardpulse.CursorSignInClientTest"], check=True)


if __name__ == "__main__":
    main()
