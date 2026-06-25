package com.wifi.voiceroom

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class DummyNotificationListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        super.onNotificationRemoved(sbn)
    }
}
