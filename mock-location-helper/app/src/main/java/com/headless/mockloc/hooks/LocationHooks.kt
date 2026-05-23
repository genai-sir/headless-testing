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

    // Real system providers — only Locations from these get sanitized.
    // App-constructed Locations (e.g. `new Location("mock")` for a self-test)
    // pass through untouched so behavioral hook-detection tests don't catch us.
    private val SYSTEM_PROVIDERS = setOf("gps", "network", "fused", "passive")

    private fun isFromSystemProvider(loc: Location): Boolean =
        loc.provider in SYSTEM_PROVIDERS

    fun install(cl: ClassLoader) {
        val locationCls = XposedHelpers.findClass("android.location.Location", cl)

        runCatching {
            XposedHelpers.findAndHookMethod(
                locationCls, "isFromMockProvider",
                object : XC_MethodHook() {
                    override fun afterHookedMethod(p: MethodHookParam) {
                        val loc = p.thisObject as? Location ?: return
                        if (isFromSystemProvider(loc) && p.result == true) {
                            p.result = false
                        }
                    }
                },
            )
        }

        runCatching {
            XposedHelpers.findAndHookMethod(
                locationCls, "isMock",
                object : XC_MethodHook() {
                    override fun afterHookedMethod(p: MethodHookParam) {
                        val loc = p.thisObject as? Location ?: return
                        if (isFromSystemProvider(loc) && p.result == true) {
                            p.result = false
                        }
                    }
                },
            )
        }

        runCatching {
            XposedHelpers.findAndHookMethod(
                locationCls, "getExtras",
                object : XC_MethodHook() {
                    override fun afterHookedMethod(p: MethodHookParam) {
                        val loc = p.thisObject as? Location ?: return
                        if (!isFromSystemProvider(loc)) return
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
