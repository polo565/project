package com.polo.adblock

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.VpnService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    companion object {
        private const val REQUEST_VPN = 1
    }

    private var pendingStart: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "adblock").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val consent = VpnService.prepare(this)
                    if (consent == null) {
                        startVpn()
                        result.success(true)
                    } else {
                        pendingStart = result
                        startActivityForResult(consent, REQUEST_VPN)
                    }
                }
                "stop" -> {
                    startService(Intent(this, AdBlockVpnService::class.java).setAction(AdBlockVpnService.ACTION_STOP))
                    result.success(null)
                }
                "status" -> {
                    if (Blocklist.size == 0) thread { Blocklist.ensureLoaded(this) }
                    result.success(
                        mapOf(
                            "running" to AdBlockState.running,
                            "blocked" to AdBlockState.blocked.get(),
                            "total" to AdBlockState.total.get(),
                            "listSize" to Blocklist.size,
                            "listDate" to Blocklist.lastUpdate(this),
                            "recent" to AdBlockState.recentList(),
                        )
                    )
                }
                "updateList" -> thread {
                    try {
                        val count = Blocklist.download(this)
                        runOnUiThread { result.success(count) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("DOWNLOAD", e.message, null) }
                    }
                }
                "getApps" -> thread {
                    val apps = installedApps()
                    runOnUiThread { result.success(apps) }
                }
                "getAllowed" -> result.success(AllowedApps.get(this).toList())
                "setAllowed" -> {
                    AllowedApps.set(this, (call.arguments as List<*>).map { it as String })
                    if (AdBlockState.running) startVpn() // applique la nouvelle liste
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQUEST_VPN) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pendingStart
        pendingStart = null
        if (resultCode == RESULT_OK) {
            startVpn()
            result?.success(true)
        } else {
            result?.success(false)
        }
    }

    private fun startVpn() {
        startService(Intent(this, AdBlockVpnService::class.java))
    }

    private fun installedApps(): List<Map<String, Any>> {
        val pm = packageManager
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        @Suppress("DEPRECATION")
        return pm.queryIntentActivities(launcher, 0)
            .map { it.activityInfo.applicationInfo }
            .distinctBy { it.packageName }
            .filter { it.packageName != packageName }
            .map { info ->
                mapOf(
                    "package" to info.packageName,
                    "name" to info.loadLabel(pm).toString(),
                    "icon" to iconPng(info.loadIcon(pm)),
                )
            }
            .sortedBy { (it["name"] as String).lowercase() }
    }

    private fun iconPng(drawable: Drawable): ByteArray {
        val size = 96
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        drawable.setBounds(0, 0, size, size)
        drawable.draw(Canvas(bitmap))
        return ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
    }
}
