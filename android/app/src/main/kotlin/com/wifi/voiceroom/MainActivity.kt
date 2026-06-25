package com.wifi.voiceroom

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "wifi_connect"
    private var connectedNetwork: Network? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "connect" -> {
                    val ssid = call.argument<String>("ssid") ?: ""
                    val password = call.argument<String>("password") ?: ""
                    val isOpen = call.argument<Boolean>("isOpen") ?: false
                    connectToWifi(ssid, password, isOpen, result)
                }
                "disconnect" -> {
                    disconnectWifi(result)
                }
                "getConnectedSSID" -> {
                    getConnectedSSID(result)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun connectToWifi(ssid: String, password: String, isOpen: Boolean, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Android 10+ uses WifiNetworkSpecifier (shows system dialog)
            val specifierBuilder = WifiNetworkSpecifier.Builder()
                .setSsid(ssid)

            if (!isOpen && password.isNotEmpty()) {
                specifierBuilder.setWpa2Passphrase(password)
            }

            val specifier = specifierBuilder.build()

            val request = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .setNetworkSpecifier(specifier)
                .build()

            val connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

            connectivityManager.requestNetwork(request, object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    super.onAvailable(network)
                    connectedNetwork = network
                    connectivityManager.bindProcessToNetwork(network)
                    runOnUiThread {
                        result.success(true)
                    }
                }

                override fun onUnavailable() {
                    super.onUnavailable()
                    runOnUiThread {
                        result.success(false)
                    }
                }
            })
        } else {
            // Pre-Android 10 — use deprecated WifiManager APIs
            @Suppress("DEPRECATION")
            try {
                val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                val conf = android.net.wifi.WifiConfiguration()
                conf.SSID = "\"${ssid}\""
                if (isOpen) {
                    conf.allowedKeyManagement.set(android.net.wifi.WifiConfiguration.KeyMgmt.NONE)
                } else {
                    conf.preSharedKey = "\"${password}\""
                }
                val netId = wifiManager.addNetwork(conf)
                wifiManager.disconnect()
                wifiManager.enableNetwork(netId, true)
                wifiManager.reconnect()
                result.success(true)
            } catch (e: Exception) {
                result.success(false)
            }
        }
    }

    private fun disconnectWifi(result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                connectedNetwork?.let {
                    connectivityManager.bindProcessToNetwork(null)
                    connectedNetwork = null
                }
            } else {
                @Suppress("DEPRECATION")
                val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                wifiManager.disconnect()
            }
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }

    private fun getConnectedSSID(result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                val network = connectivityManager.activeNetwork
                val capabilities = connectivityManager.getNetworkCapabilities(network)
                if (capabilities != null && capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                    val wifiInfo = capabilities.transportInfo as? WifiInfo
                    val ssid = wifiInfo?.ssid?.replace("\"", "") ?: ""
                    if (ssid.isNotEmpty() && ssid != "<unknown ssid>") {
                        result.success(ssid)
                    } else {
                        result.success(null)
                    }
                } else {
                    result.success(null)
                }
            } else {
                @Suppress("DEPRECATION")
                val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                val info = wifiManager.connectionInfo
                val ssid = info.ssid?.replace("\"", "") ?: ""
                if (ssid.isNotEmpty() && ssid != "<unknown ssid>") {
                    result.success(ssid)
                } else {
                    result.success(null)
                }
            }
        } catch (e: Exception) {
            result.success(null)
        }
    }
}
