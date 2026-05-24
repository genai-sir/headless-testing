package com.headless.mitmtest

import android.app.Activity
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.net.HttpURLConnection
import java.net.URL
import javax.net.ssl.HttpsURLConnection
import kotlin.concurrent.thread

/**
 * Bare-minimum HTTPS test client. Tap one of the buttons; the app does a
 * synchronous GET on a background thread using HttpsURLConnection (which
 * goes through the system trust store — including our mitmproxy CA).
 *
 * Why HttpsURLConnection and not OkHttp:
 *  - Smaller APK, zero extra deps.
 *  - HttpsURLConnection on Android delegates to Conscrypt, the same
 *    SSLContext path that ART apps use by default. If our CA is trusted
 *    by Conscrypt, this app trusts it. So a passing test here is
 *    confirmation that any well-behaved AOSP app would also be captured.
 *  - No cert pinning anywhere; pinning is opt-in.
 *
 * Each result line is appended to the scrollable log so you can fire
 * multiple requests in a row and watch flows light up in mitmweb.
 */
class MainActivity : Activity() {

    private lateinit var log: TextView
    private lateinit var urlInput: EditText

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(buildUi())
        append("ready. pick a target or paste a URL, then fire a GET.")
    }

    private fun buildUi(): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(16), dp(16), dp(16))
        }

        urlInput = EditText(this).apply {
            hint = "https://example.com/something"
            setText("https://httpbin.org/get")
            setSingleLine(true)
        }
        root.addView(urlInput)

        val presets = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, dp(8), 0, dp(8))
        }
        listOf(
            "httpbin.org" to "https://httpbin.org/get",
            "ifconfig.me" to "https://ifconfig.me/all.json",
            "api.github" to "https://api.github.com/zen",
        ).forEach { (label, url) ->
            presets.addView(Button(this).apply {
                text = label
                setOnClickListener { urlInput.setText(url) }
            })
        }
        root.addView(presets)

        root.addView(Button(this).apply {
            text = "Fire GET"
            setOnClickListener { fire(urlInput.text.toString().trim()) }
        })

        log = TextView(this).apply {
            setPadding(dp(8), dp(8), dp(8), dp(8))
            textSize = 11f
            setTextIsSelectable(true)
            gravity = Gravity.TOP
            typeface = android.graphics.Typeface.MONOSPACE
        }
        val scroll = ScrollView(this).apply { addView(log) }
        root.addView(scroll, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.MATCH_PARENT,
        ))

        return root
    }

    private fun fire(url: String) {
        if (url.isBlank()) { append("(empty URL)"); return }
        append("--> GET $url")
        thread(name = "http-fire") {
            val started = System.nanoTime()
            try {
                val conn = (URL(url).openConnection() as HttpURLConnection).apply {
                    connectTimeout = 10_000
                    readTimeout = 10_000
                    setRequestProperty("User-Agent", "mitm-test/0.1")
                }
                val code = conn.responseCode
                val cipher = (conn as? HttpsURLConnection)?.cipherSuite
                val body = (conn.errorStream ?: conn.inputStream)
                    .bufferedReader().use { it.readText() }
                val took = (System.nanoTime() - started) / 1_000_000
                val preview = body.take(160).replace("\n", " ")
                runOnUiThread {
                    append("    <- $code  (${took}ms${cipher?.let { "  $it" } ?: ""})")
                    append("       body: $preview${if (body.length > 160) "…" else ""}")
                }
            } catch (t: Throwable) {
                runOnUiThread { append("    <- ERR ${t.javaClass.simpleName}: ${t.message}") }
            }
        }
    }

    private fun append(line: String) {
        log.append(line + "\n")
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()
}
