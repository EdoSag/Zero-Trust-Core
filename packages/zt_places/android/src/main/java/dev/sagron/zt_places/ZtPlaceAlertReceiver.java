package dev.sagron.zt_places;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.location.LocationManager;

/** Proximity alerts from the OS, and the notification's "Done" button. */
public class ZtPlaceAlertReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        String id = intent.getStringExtra(ZtPlaceAlerts.EXTRA_ID);
        if (id == null) return;
        if (ZtPlaceAlerts.ACTION_ALERT.equals(intent.getAction())) {
            if (!intent.hasExtra(LocationManager.KEY_PROXIMITY_ENTERING)) return;
            boolean entering = intent.getBooleanExtra(LocationManager.KEY_PROXIMITY_ENTERING, false);
            ZtPlaceAlerts.onTransition(context, id, entering);
        } else if (ZtPlaceAlerts.ACTION_DONE.equals(intent.getAction())) {
            ZtPlaceAlerts.onDone(context, id, intent.getStringExtra(ZtPlaceAlerts.EXTRA_PAYLOAD));
        }
    }
}
