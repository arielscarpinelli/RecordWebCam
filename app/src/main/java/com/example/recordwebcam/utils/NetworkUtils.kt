package com.example.recordwebcam.utils

import java.net.NetworkInterface
import java.util.Collections

fun getIpAddress(): String {
    try {
        val interfaces = Collections.list(NetworkInterface.getNetworkInterfaces())
        var fallbackIp: String? = null
        for (intf in interfaces) {
            val addrs = Collections.list(intf.inetAddresses)
            for (addr in addrs) {
                if (!addr.isLoopbackAddress) {
                    val sAddr = addr.hostAddress
                    val isIPv4 = sAddr.indexOf(':') < 0
                    if (isIPv4) {
                        if (intf.displayName.contains("rndis", ignoreCase = true) ||
                            intf.displayName.contains("usb", ignoreCase = true)
                        ) {
                            return sAddr // Prioritize USB
                        }
                        if (fallbackIp == null) {
                            fallbackIp = sAddr // Store first non-USB IP as fallback
                        }
                    }
                }
            }
        }
        return fallbackIp ?: "Not found"
    } catch (ex: Exception) {
        // Ignore
    }
    return "Not found"
}
