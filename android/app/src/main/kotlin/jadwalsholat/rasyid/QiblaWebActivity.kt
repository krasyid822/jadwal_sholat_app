package jadwalsholat.rasyid

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.webkit.PermissionRequest
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.appcompat.app.AppCompatActivity

class QiblaWebActivity : AppCompatActivity() {

    companion object {
        // Keep a weak-ish static reference to the active WebView by exposing a nullable holder.
        // We avoid strong leaks by setting it to null on destroy.
        private var activeWebView: WebView? = null

        // Called from MainActivity via MethodChannel to forward injected locations
        @JvmStatic
        fun sendInjectedLocation(lat: Double?, lon: Double?, accuracy: Double?, timestamp: Long?) {
            val webView = activeWebView ?: return

            if (lat == null || lon == null) return

            // Prepare a safe JS call that will call a window-level handler if present
            val safeLat = lat.toString()
            val safeLon = lon.toString()
            val safeAcc = (accuracy ?: 0.0).toString()
            val ts = timestamp ?: System.currentTimeMillis()

            // This JS will either call the handler (if present) or set a fallback window.__last_injected_pos and emit a console marker
            val js = "(function(){ try{ var pos={coords:{latitude:$safeLat,longitude:$safeLon,accuracy:$safeAcc},timestamp:$ts}; if(window.__flutter_injected_gps_handler){ window.__flutter_injected_gps_handler(pos); console.log('FLUTTER_INJECTED_GPS', $safeLat, $safeLon, $safeAcc); } else { try{ window.__last_injected_pos = pos; console.log('FLUTTER_INJECTED_GPS_FALLBACK', $safeLat, $safeLon, $safeAcc); }catch(e){} } }catch(e){console.error(e)} })();"

            // Use post to ensure thread-safety
            webView.post {
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.KITKAT) {
                    webView.evaluateJavascript(js, null)
                } else {
                    webView.loadUrl("javascript:$js")
                }
            }
        }
    }

    private var webView: WebView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

    webView = WebView(this)

        val url = intent.getStringExtra("url") ?: "https://qiblafinder.withgoogle.com/"

        val settings = webView!!.settings
        settings.javaScriptEnabled = true
        settings.mediaPlaybackRequiresUserGesture = false

                webView!!.webViewClient = object : WebViewClient() {
                        override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                                return false
                        }

                        override fun onPageFinished(view: WebView?, url: String?) {
                                try {
                                        val shim = """
                                                (function(){
                                                    try {
                                                        if (!window.__flutter_injected_gps_handler) {
                                                            console.log('FLUTTER_SHIM_INSTALLED');
                                                            window.__flutter_injected_gps_handler = function(pos){
                                                                try {
                                                                    // Save last injected position
                                                                    window.__last_injected_pos = pos;
                                                                    // Emit a console marker so native logs show the injection in page console
                                                                    try { console.log('FLUTTER_INJECTED_GPS_HANDLER', pos && pos.coords && pos.coords.latitude, pos && pos.coords && pos.coords.longitude, pos && pos.coords && pos.coords.accuracy); } catch(e) {}
                                                                    // Call any page handler if present
                                                                    if (window.onInjectedGeolocation) {
                                                                        try{ window.onInjectedGeolocation(pos); }catch(e){}
                                                                    }
                                                                } catch(e){}
                                                            };
                                                            // Override getCurrentPosition to return injected pos when available
                                                            if (navigator.geolocation) {
                                                                constOriginalGetCurrent = navigator.geolocation.getCurrentPosition;
                                                                navigator.geolocation.getCurrentPosition = function(success, error, options) {
                                                                    try {
                                                                        if (window.__last_injected_pos) {
                                                                            success(window.__last_injected_pos);
                                                                            return;
                                                                        }
                                                                    } catch(e){}
                                                                    return constOriginalGetCurrent.apply(navigator.geolocation, arguments);
                                                                };

                                                                constOriginalWatch = navigator.geolocation.watchPosition;
                                                                navigator.geolocation.watchPosition = function(success, error, options) {
                                                                    try {
                                                                        if (window.__last_injected_pos) {
                                                                            success(window.__last_injected_pos);
                                                                            // return a dummy id
                                                                            return 1;
                                                                        }
                                                                    } catch(e){}
                                                                    return constOriginalWatch.apply(navigator.geolocation, arguments);
                                                                };
                                                            }
                                                        }
                                                    } catch(e){}
                                                })();
                                        """.trimIndent()

                                        if (view != null) {
                                                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.KITKAT) {
                                                        view.evaluateJavascript(shim, null)
                                                } else {
                                                        view.loadUrl("javascript:(function(){${shim}})()")
                                                }
                                        }
                                } catch (_: Exception) {}
                        }
                }

        webView!!.webChromeClient = object : WebChromeClient() {
            override fun onPermissionRequest(request: PermissionRequest) {
                try {
                    // If app has camera permission, grant requested resources (camera/microphone)
                    val pm: PackageManager = applicationContext.packageManager
                    val hasCamera = pm.checkPermission(android.Manifest.permission.CAMERA, applicationContext.packageName) == PackageManager.PERMISSION_GRANTED

                    if (hasCamera) {
                        request.grant(request.resources)
                    } else {
                        request.deny()
                    }
                } catch (e: Exception) {
                    request.deny()
                }
            }
        }

        // Install a small JS shim on page load to expose a handler that our injected JS will call.
        webView!!.addJavascriptInterface(object {
            @android.webkit.JavascriptInterface
            fun postMessage(msg: String) {
                // no-op; reserved for future use
            }
        }, "FlutterGPS")

        // Keep a reference for injection
        activeWebView = webView

        // Add a simple overlay with reload and close controls
        // We'll create a FrameLayout as the root and add the webView and a small button.
        val root = android.widget.FrameLayout(this)
        val params = android.widget.FrameLayout.LayoutParams(
            android.widget.FrameLayout.LayoutParams.MATCH_PARENT,
            android.widget.FrameLayout.LayoutParams.MATCH_PARENT
        )

        // Add the webView to the root container (do not call setContentView(webView) earlier)
        root.addView(webView, params)

        // Reload button
        val reloadButton = android.widget.ImageButton(this)
        reloadButton.setImageResource(android.R.drawable.ic_menu_rotate)
        reloadButton.setBackgroundColor(android.graphics.Color.parseColor("#CC000000"))
        val size = resources.displayMetrics.density.times(48).toInt()
        val reloadParams = android.widget.FrameLayout.LayoutParams(size, size)
        reloadParams.marginEnd = resources.displayMetrics.density.times(12).toInt()
        reloadParams.topMargin = resources.displayMetrics.density.times(12).toInt()
        reloadParams.gravity = android.view.Gravity.END or android.view.Gravity.TOP
        reloadButton.setOnClickListener {
            try {
                webView?.reload()
            } catch (_: Exception) {}
        }
        root.addView(reloadButton, reloadParams)

        // Optional close button
        val closeButton = android.widget.ImageButton(this)
        closeButton.setImageResource(android.R.drawable.ic_menu_close_clear_cancel)
        closeButton.setBackgroundColor(android.graphics.Color.parseColor("#CC000000"))
        val closeParams = android.widget.FrameLayout.LayoutParams(size, size)
        closeParams.marginStart = resources.displayMetrics.density.times(12).toInt()
        closeParams.topMargin = resources.displayMetrics.density.times(12).toInt()
        closeParams.gravity = android.view.Gravity.START or android.view.Gravity.TOP
        closeButton.setOnClickListener {
            finish()
        }
    root.addView(closeButton, closeParams)

    // Load the URL after webView has been attached to the root
    webView!!.loadUrl(url)

    // Finally set the composed root as the content view
    setContentView(root)
    }

    override fun onDestroy() {
        super.onDestroy()
        // Clear static reference to avoid leak
        if (activeWebView === webView) {
            activeWebView = null
        }
        webView?.destroy()
        webView = null
    }
}
