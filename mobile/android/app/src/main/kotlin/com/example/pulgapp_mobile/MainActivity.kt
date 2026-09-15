package com.example.pulgapp_mobile

import android.os.Bundle
import android.net.wifi.WifiManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val preferences = getSharedPreferences("pulgapp", MODE_PRIVATE)
        MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, "pulgapp/preferences")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAll" -> result.success(preferences.all.mapValues { it.value as String })
                    "setString" -> {
                        val key = call.argument<String>("key")
                        val value = call.argument<String>("value")
                        if (key == null || value == null) result.error("invalid_arguments", "Expected key and value.", null)
                        else {
                            preferences.edit().putString(key, value).apply()
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, "pulgapp/wakelock")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enable" -> { window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON); result.success(null) }
                    "disable" -> { window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON); result.success(null) }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, "pulgapp/multicast")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> { val wifi = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager; multicastLock = wifi.createMulticastLock("pulgapp-discovery").apply { setReferenceCounted(false); acquire() }; result.success(null) }
                    "release" -> { multicastLock?.takeIf { it.isHeld }?.release(); multicastLock = null; result.success(null) }
                    else -> result.notImplemented()
                }
            }
        val vibrator = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            val vibratorManager = getSystemService(android.content.Context.VIBRATOR_MANAGER_SERVICE) as android.os.VibratorManager
            vibratorManager.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(android.content.Context.VIBRATOR_SERVICE) as android.os.Vibrator
        }
        MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, "pulgapp/vibrate")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "click", "heavyClick", "tick" -> {
                        var played = false
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                            try {
                                val effectId = when (call.method) {
                                    "heavyClick" -> android.os.VibrationEffect.EFFECT_HEAVY_CLICK
                                    "tick" -> android.os.VibrationEffect.EFFECT_TICK
                                    else -> android.os.VibrationEffect.EFFECT_CLICK
                                }
                                vibrator.vibrate(android.os.VibrationEffect.createPredefined(effectId))
                                played = true
                            } catch (_: Exception) {
                                played = false
                            }
                        }
                        if (!played) {
                            val durationMs = when (call.method) {
                                "heavyClick" -> 16L
                                "tick" -> 8L
                                else -> 10L
                            }
                            val amplitude = when (call.method) {
                                "heavyClick" -> 140
                                "tick" -> 80
                                else -> 110
                            }
                            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                                val amp = if (vibrator.hasAmplitudeControl()) amplitude else android.os.VibrationEffect.DEFAULT_AMPLITUDE
                                vibrator.vibrate(android.os.VibrationEffect.createOneShot(durationMs, amp))
                            } else {
                                @Suppress("DEPRECATION")
                                vibrator.vibrate(durationMs)
                            }
                        }
                        result.success(null)
                    }
                    "cancel" -> {
                        vibrator.cancel()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
