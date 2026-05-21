package com.headless.mockloc.hooks

import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager.NameNotFoundException
import android.content.pm.ResolveInfo
import de.robv.android.xposed.XC_MethodHook
import de.robv.android.xposed.XposedHelpers

/**
 * Hide our helper package from any app that enumerates installed packages
 * or resolves intents.
 *
 *   getInstalledPackages       -> filtered list
 *   getInstalledApplications   -> filtered list
 *   queryIntentActivities      -> filtered list
 *   queryIntentServices        -> filtered list
 *   queryIntentReceivers       -> filtered list
 *   getPackageInfo(ourPkg, ..) -> NameNotFoundException
 *   getApplicationInfo(ourPkg) -> NameNotFoundException
 *
 * Hooked on ApplicationPackageManager (the concrete instance every app's
 * Context.getPackageManager() returns).
 */
object PackageManagerHooks {

    fun install(cl: ClassLoader, hide: String) {
        val pmCls = XposedHelpers.findClass(
            "android.app.ApplicationPackageManager", cl,
        )

        // ---- list-style queries: filter result ----
        val filteringNames = listOf(
            "getInstalledPackages",
            "getInstalledApplications",
            "queryIntentActivities",
            "queryIntentServices",
            "queryIntentReceivers",
            "queryBroadcastReceivers",
        )
        for (m in pmCls.declaredMethods) {
            if (m.name !in filteringNames) continue
            runCatching {
                XposedHelpers.findAndHookMethod(
                    pmCls, m.name, *m.parameterTypes,
                    object : XC_MethodHook() {
                        override fun afterHookedMethod(p: MethodHookParam) {
                            p.result = filterOut(p.result, hide)
                        }
                    },
                )
            }
        }

        // ---- direct lookup by package name: throw "not found" ----
        for (m in pmCls.declaredMethods) {
            if (m.name != "getPackageInfo" && m.name != "getApplicationInfo") continue
            runCatching {
                XposedHelpers.findAndHookMethod(
                    pmCls, m.name, *m.parameterTypes,
                    object : XC_MethodHook() {
                        override fun beforeHookedMethod(p: MethodHookParam) {
                            if ((p.args[0] as? String) == hide) {
                                p.throwable = NameNotFoundException(hide)
                            }
                        }
                    },
                )
            }
        }
    }

    private fun filterOut(result: Any?, hide: String): Any? {
        if (result !is MutableList<*>) return result
        @Suppress("UNCHECKED_CAST")
        val mut = result as MutableList<Any?>
        val iter = mut.iterator()
        while (iter.hasNext()) {
            val item = iter.next()
            val pkg = when (item) {
                is PackageInfo -> item.packageName
                is ApplicationInfo -> item.packageName
                is ResolveInfo -> item.activityInfo?.packageName
                    ?: item.serviceInfo?.packageName
                    ?: item.providerInfo?.packageName
                else -> null
            }
            if (pkg == hide) iter.remove()
        }
        return mut
    }
}
