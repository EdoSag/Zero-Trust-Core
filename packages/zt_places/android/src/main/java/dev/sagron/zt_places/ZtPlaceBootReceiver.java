package dev.sagron.zt_places;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** The OS forgets proximity alerts on reboot and app update; set them again. */
public class ZtPlaceBootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        String a = intent.getAction();
        if (Intent.ACTION_BOOT_COMPLETED.equals(a)
                || Intent.ACTION_MY_PACKAGE_REPLACED.equals(a)
                || "android.intent.action.QUICKBOOT_POWERON".equals(a)) {
            ZtPlaceAlerts.reRegisterAll(context);
        }
    }
}
