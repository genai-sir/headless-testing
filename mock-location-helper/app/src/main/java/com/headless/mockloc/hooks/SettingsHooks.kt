package com.headless.mockloc.hooks

import android.content.ContentResolver
import de.robv.android.xposed.XC_MethodHook
import de.robv.android.xposed.XposedBridge
import de.robv.android.xposed.XposedHelpers

/**
 * Make Settings.Secure look clean.
 *
 *   Settings.Secure.getInt(..., "mock_location", ...)         -> 0
 *   Settings.Secure.getString(..., "mock_location")           -> "0"
 *   Settings.Secure.getStringForUser(..., "mock_location", _) -> "0"
 *   Settings.Secure.getIntForUser   (..., "mock_location", _) -> 0
 *
 * This is the legacy "Allow mock locations" developer toggle. Deprecated since
 * API 23 but still polled by detection libraries. The OS already ignores it,
 * so flipping it has no functional impact — only a stealth one.
 */
object SettingsHooks {

    private const val TAG = "headless-stealth"
    private const val ALLOW_MOCK_LOCATION = "mock_location"

    fun install(cl: ClassLoader) {
        val secure = XposedHelpers.findClass("android.provider.Settings\$Secure", cl)

        // ---- int variants ------------------------------------------------
        // getInt(ContentResolver, String)
        tryHook(secure, "getInt",
                ContentResolver::class.java, String::class.java) { p ->
            if ((p.args[1] as? String) == ALLOW_MOCK_LOCATION) p.result = 0
        }
        // getInt(ContentResolver, String, int)
        tryHook(secure, "getInt",
                ContentResolver::class.java, String::class.java, Int::class.javaPrimitiveType!!) { p ->
            if ((p.args[1] as? String) == ALLOW_MOCK_LOCATION) p.result = 0
        }
        // getIntForUser(ContentResolver, String, int, int)
        tryHook(secure, "getIntForUser",
                ContentResolver::class.java, String::class.java,
                Int::class.javaPrimitiveType!!, Int::class.javaPrimitiveType!!) { p ->
            if ((p.args[1] as? String) == ALLOW_MOCK_LOCATION) p.result = 0
        }

        // ---- string variants ---------------------------------------------
        // getString(ContentResolver, String)
        tryHook(secure, "getString",
                ContentResolver::class.java, String::class.java) { p ->
            if ((p.args[1] as? String) == ALLOW_MOCK_LOCATION) p.result = "0"
        }
        // getStringForUser(ContentResolver, String, int)
        tryHook(secure, "getStringForUser",
                ContentResolver::class.java, String::class.java, Int::class.javaPrimitiveType!!) { p ->
            if ((p.args[1] as? String) == ALLOW_MOCK_LOCATION) p.result = "0"
        }
    }

    /**
     * Wrapper around findAndHookMethod that doesn't swallow registration
     * failures silently — they go to the LSPosed log so we can diagnose
     * later if a target Android version changes a signature.
     */
    private fun tryHook(
        cls: Class<*>,
        methodName: String,
        vararg paramTypes: Any,
        body: (XC_MethodHook.MethodHookParam) -> Unit,
    ) {
        try {
            XposedHelpers.findAndHookMethod(
                cls, methodName, *paramTypes,
                object : XC_MethodHook() {
                    override fun afterHookedMethod(p: MethodHookParam) = body(p)
                },
            )
        } catch (e: NoSuchMethodError) {
            // Method not present on this Android version — fine, skip quietly.
        } catch (t: Throwable) {
            XposedBridge.log("[$TAG] failed to hook ${cls.simpleName}.$methodName: $t")
        }
    }
}
