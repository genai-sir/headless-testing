package com.headless.mockloc

import com.headless.mockloc.hooks.LocationHooks
import com.headless.mockloc.hooks.PackageManagerHooks
import com.headless.mockloc.hooks.SettingsHooks
import de.robv.android.xposed.IXposedHookLoadPackage
import de.robv.android.xposed.XposedBridge
import de.robv.android.xposed.callbacks.XC_LoadPackage.LoadPackageParam

/**
 * LSPosed entry point. Loaded into every process matching the module's scope.
 *
 * Layers installed:
 *   - LocationHooks   : force Location.isFromMockProvider/isMock to false,
 *                       strip the "mockLocation" bundle key.
 *   - SettingsHooks   : pretend Settings.Secure.mock_location == "0" (legacy).
 *   - PackageManagerHooks: hide com.headless.mockloc from
 *                       getInstalledPackages / queryIntent* calls.
 */
class XposedEntry : IXposedHookLoadPackage {

    override fun handleLoadPackage(lpparam: LoadPackageParam) {
        // Never hook ourselves — saves CPU and avoids feedback loops.
        if (lpparam.packageName == OUR_PKG) return

        // Never hook system_server. The LSPosed daemon lives there; if our
        // PackageManagerHooks fire inside system_server they hide us from
        // the daemon's own queries and the Manager's Modules list goes blank.
        if (lpparam.packageName == "android") return

        try {
            LocationHooks.install(lpparam.classLoader)
        } catch (t: Throwable) {
            XposedBridge.log("[$TAG] LocationHooks failed in ${lpparam.packageName}: $t")
        }

        try {
            SettingsHooks.install(lpparam.classLoader)
        } catch (t: Throwable) {
            XposedBridge.log("[$TAG] SettingsHooks failed in ${lpparam.packageName}: $t")
        }

        // Each target app uses its own ApplicationPackageManager instance.
        // Hooking it in every loaded process catches queries before they
        // reach app code — no need to also hook system_server for the
        // common case.
        try {
            PackageManagerHooks.install(lpparam.classLoader, OUR_PKG)
        } catch (t: Throwable) {
            XposedBridge.log("[$TAG] PackageManagerHooks failed in ${lpparam.packageName}: $t")
        }
    }

    companion object {
        const val OUR_PKG = "com.headless.mockloc"
        const val TAG = "headless-stealth"
    }
}
