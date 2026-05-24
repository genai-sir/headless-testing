package com.headless.mockloc.hooks

import de.robv.android.xposed.XC_MethodReplacement
import de.robv.android.xposed.XposedBridge
import de.robv.android.xposed.XposedHelpers

/**
 * Defeat the common SSL-pinning patterns so the local mitmproxy can decrypt
 * HTTPS traffic from scoped apps.
 *
 * What we touch:
 *
 *   - OkHttp 3/4 (most apps, including React Native fetch):
 *     CertificatePinner.check(String, List<Certificate>) -> no-op return
 *
 *   - AndroidX/Conscrypt platform trust manager:
 *     TrustManagerImpl.checkServerTrusted(X509Certificate[], String, String|SSLSession)
 *     return the input chain instead of validating
 *
 *   - Network security config "Trust user CAs":
 *     RootTrustManager.checkServerTrusted(...) -> return input
 *
 *   - WebView client SSL errors:
 *     WebViewClient.onReceivedSslError -> handler.proceed()
 *
 * Each hook is wrapped in runCatching so a missing class in some build
 * doesn't take the whole module down — different apps ship different
 * versions of OkHttp/Conscrypt under different package names (some apps
 * shade-rename OkHttp, e.g. `com.acme.okhttp3.CertificatePinner`).
 *
 * NOTE: pinning bypass only applies inside processes where this LSPosed
 * module is scoped. Apps not in scope continue to pin and fail TLS through
 * mitmproxy. Use the dashboard's "scope all internet apps" toggle to apply
 * broadly.
 */
object NetworkHooks {

    fun install(cl: ClassLoader) {
        installOkHttp(cl)
        installConscryptTrustManager(cl)
        installRootTrustManager(cl)
        installWebViewSslHandler(cl)
    }

    // ----- OkHttp CertificatePinner -----
    private fun installOkHttp(cl: ClassLoader) {
        for (cn in OKHTTP_PINNER_CLASSES) {
            runCatching {
                val cls = XposedHelpers.findClassIfExists(cn, cl) ?: return@runCatching
                // Both okhttp3 4.x and 3.x have a check(String, List) overload.
                XposedHelpers.findAndHookMethod(
                    cls, "check", String::class.java, List::class.java,
                    XC_MethodReplacement.returnConstant(null),
                )
                // OkHttp 4 also has check(String, vararg Certificate). The
                // varargs form is reflected as Certificate[]. Skip-able.
                runCatching {
                    XposedHelpers.findAndHookMethod(
                        cls, "check", String::class.java,
                        Array<java.security.cert.Certificate>::class.java,
                        XC_MethodReplacement.returnConstant(null),
                    )
                }
                XposedBridge.log("[$TAG] OkHttp pinner neutralized: $cn")
            }
        }
    }

    // ----- Platform Conscrypt TrustManagerImpl -----
    private fun installConscryptTrustManager(cl: ClassLoader) {
        val cls = XposedHelpers.findClassIfExists(
            "com.android.org.conscrypt.TrustManagerImpl", cl,
        ) ?: return

        // checkServerTrusted(X509Certificate[], String, String) returns the chain.
        runCatching {
            XposedHelpers.findAndHookMethod(
                cls, "checkServerTrusted",
                Array<java.security.cert.X509Certificate>::class.java,
                String::class.java, String::class.java,
                object : XC_MethodReplacement() {
                    override fun replaceHookedMethod(p: MethodHookParam): Any? {
                        @Suppress("UNCHECKED_CAST")
                        val chain = p.args[0] as Array<java.security.cert.X509Certificate>
                        // Returning the chain matches the pre-hook contract:
                        // a successful validation returns the chain.
                        return java.util.Arrays.asList(*chain)
                    }
                },
            )
            XposedBridge.log("[$TAG] Conscrypt TrustManagerImpl.checkServerTrusted(3-arg) bypassed")
        }

        // Older 2-arg overload used by some pre-O paths.
        runCatching {
            XposedHelpers.findAndHookMethod(
                cls, "checkServerTrusted",
                Array<java.security.cert.X509Certificate>::class.java,
                String::class.java,
                XC_MethodReplacement.returnConstant(null),
            )
        }
    }

    // ----- Network Security Config RootTrustManager -----
    private fun installRootTrustManager(cl: ClassLoader) {
        val cls = XposedHelpers.findClassIfExists(
            "android.security.net.config.RootTrustManager", cl,
        ) ?: return
        runCatching {
            XposedHelpers.findAndHookMethod(
                cls, "checkServerTrusted",
                Array<java.security.cert.X509Certificate>::class.java,
                String::class.java, String::class.java,
                object : XC_MethodReplacement() {
                    override fun replaceHookedMethod(p: MethodHookParam): Any? {
                        @Suppress("UNCHECKED_CAST")
                        val chain = p.args[0] as Array<java.security.cert.X509Certificate>
                        return java.util.Arrays.asList(*chain)
                    }
                },
            )
            XposedBridge.log("[$TAG] RootTrustManager.checkServerTrusted bypassed")
        }
    }

    // ----- WebView SSL errors -----
    private fun installWebViewSslHandler(cl: ClassLoader) {
        val cls = XposedHelpers.findClassIfExists(
            "android.webkit.WebViewClient", cl,
        ) ?: return
        runCatching {
            XposedHelpers.findAndHookMethod(
                cls, "onReceivedSslError",
                XposedHelpers.findClass("android.webkit.WebView", cl),
                XposedHelpers.findClass("android.webkit.SslErrorHandler", cl),
                XposedHelpers.findClass("android.net.http.SslError", cl),
                object : XC_MethodReplacement() {
                    override fun replaceHookedMethod(p: MethodHookParam): Any? {
                        val handler = p.args[1]
                        XposedHelpers.callMethod(handler, "proceed")
                        return null
                    }
                },
            )
            XposedBridge.log("[$TAG] WebViewClient.onReceivedSslError -> proceed()")
        }
    }

    private const val TAG = "headless-stealth/net"

    // Apps frequently shade-rename OkHttp into their own namespace. Cover the
    // common ones; extend as needed when a target ships its own rename.
    private val OKHTTP_PINNER_CLASSES = listOf(
        "okhttp3.CertificatePinner",
        "com.squareup.okhttp.CertificatePinner",
    )
}
