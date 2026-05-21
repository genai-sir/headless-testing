package com.headless.mockloc.hooks

import android.location.Location
import android.os.Bundle
import de.robv.android.xposed.XC_MethodHook
import de.robv.android.xposed.XC_MethodReplacement
import de.robv.android.xposed.XposedHelpers

/**
 * Make every Location object look like it came from real hardware.
 *
 *   isFromMockProvider() -> false   (API 18+; the canonical check)
 *   isMock()             -> false   (API 31+; new name)
 *   getExtras()          -> bundle without "mockLocation" key
 *
 * Anything inside the target app that calls these methods on a Location
 * (including reflection going through android.location.Location.class) will
 * see "not mocked".
 */
object LocationHooks {

    fun install(cl: ClassLoader) {
        val locationCls = XposedHelpers.findClass("android.location.Location", cl)

        // isFromMockProvider() — present since API 18, always returns the mock bit.
        runCatching {
            XposedHelpers.findAndHookMethod(
                locationCls, "isFromMockProvider",
                object : XC_MethodReplacement() {
                    override fun replaceHookedMethod(p: MethodHookParam): Any = false
                },
            )
        }

        // isMock() — API 31+, equivalent.
        runCatching {
            XposedHelpers.findAndHookMethod(
                locationCls, "isMock",
                object : XC_MethodReplacement() {
                    override fun replaceHookedMethod(p: MethodHookParam): Any = false
                },
            )
        }

        // getExtras() returns a Bundle that has historically contained a
        // "mockLocation" key. Strip it on the way out.
        runCatching {
            XposedHelpers.findAndHookMethod(
                locationCls, "getExtras",
                object : XC_MethodHook() {
                    override fun afterHookedMethod(p: MethodHookParam) {
                        val extras = p.result as? Bundle ?: return
                        if (extras.containsKey("mockLocation")) {
                            extras.remove("mockLocation")
                            p.result = extras
                        }
                    }
                },
            )
        }
    }
}
