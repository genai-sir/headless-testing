package com.headless.mockloc

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.location.Criteria
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.SystemClock
import android.util.Log

/**
 * Receives broadcasts of the form:
 *   adb shell am broadcast \
 *     -a com.headless.mockloc.SET_LOCATION \
 *     -n com.headless.mockloc/.LocationReceiver \
 *     --ef lat 12.9716 --ef lng 77.5946 --ef alt 0 --ef accuracy 5
 *
 * Stop mocking:
 *   adb shell am broadcast \
 *     -a com.headless.mockloc.STOP \
 *     -n com.headless.mockloc/.LocationReceiver
 *
 * Prerequisite (granted by the dashboard's location route, but for manual use):
 *   adb shell cmd appops set com.headless.mockloc android:mock_location allow
 */
class LocationReceiver : BroadcastReceiver() {

    override fun onReceive(ctx: Context, intent: Intent) {
        val lm = ctx.getSystemService(Context.LOCATION_SERVICE) as LocationManager

        when (intent.action) {
            ACTION_STOP -> stopAllProviders(lm)
            ACTION_SET -> setLocation(lm, intent)
            else -> Log.w(TAG, "ignoring unknown action ${intent.action}")
        }
    }

    private fun setLocation(lm: LocationManager, intent: Intent) {
        val lat = intent.getFloatExtra("lat", Float.NaN).toDouble()
        val lng = intent.getFloatExtra("lng", Float.NaN).toDouble()
        if (lat.isNaN() || lng.isNaN()) {
            Log.w(TAG, "lat/lng missing or non-numeric")
            return
        }
        val alt = intent.getFloatExtra("alt", 0f).toDouble()
        val acc = intent.getFloatExtra("accuracy", 5f)

        // Mirror coords across GPS, NETWORK and FUSED so any client API sees them.
        for (provider in TARGETS) {
            ensureProvider(lm, provider)
            val loc = Location(provider).apply {
                latitude = lat
                longitude = lng
                altitude = alt
                accuracy = acc
                time = System.currentTimeMillis()
                elapsedRealtimeNanos = SystemClock.elapsedRealtimeNanos()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    verticalAccuracyMeters = acc
                }
            }
            try {
                lm.setTestProviderLocation(provider, loc)
            } catch (e: Exception) {
                Log.w(TAG, "setTestProviderLocation($provider) failed: ${e.message}")
            }
        }
        Log.i(TAG, "mocked lat=$lat lng=$lng acc=$acc")
    }

    private fun ensureProvider(lm: LocationManager, name: String) {
        try {
            lm.addTestProvider(
                name,
                /* requiresNetwork = */ false,
                /* requiresSatellite = */ false,
                /* requiresCell = */ false,
                /* hasMonetaryCost = */ false,
                /* supportsAltitude = */ true,
                /* supportsSpeed = */ true,
                /* supportsBearing = */ true,
                /* powerRequirement = */ Criteria.POWER_LOW,
                /* accuracy = */ Criteria.ACCURACY_FINE,
            )
        } catch (_: IllegalArgumentException) {
            // Already added.
        } catch (e: Exception) {
            Log.w(TAG, "addTestProvider($name) failed: ${e.message}")
        }
        try {
            lm.setTestProviderEnabled(name, true)
        } catch (e: Exception) {
            Log.w(TAG, "setTestProviderEnabled($name) failed: ${e.message}")
        }
    }

    private fun stopAllProviders(lm: LocationManager) {
        for (provider in TARGETS) {
            try {
                lm.setTestProviderEnabled(provider, false)
                lm.removeTestProvider(provider)
            } catch (_: Exception) {
            }
        }
        Log.i(TAG, "stopped all mock providers")
    }

    companion object {
        private const val TAG = "MockLocationHelper"
        private const val ACTION_SET = "com.headless.mockloc.SET_LOCATION"
        private const val ACTION_STOP = "com.headless.mockloc.STOP"
        private val TARGETS = listOf(
            LocationManager.GPS_PROVIDER,
            LocationManager.NETWORK_PROVIDER,
            LocationManager.FUSED_PROVIDER,
        )
    }
}
