package dev.sagron.zt_places;

import android.Manifest;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.location.Location;
import android.location.LocationManager;
import android.net.Uri;
import android.os.Build;

import org.json.JSONObject;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Registers place reminders with the phone's own {@link LocationManager}
 * (proximity alerts: part of Android itself, no Google Play services) and
 * shows them when the phone arrives at or leaves a place.
 */
final class ZtPlaceAlerts {
    static final String ACTION_ALERT = "dev.sagron.zt_places.ALERT";
    static final String ACTION_DONE = "dev.sagron.zt_places.DONE";
    static final String EXTRA_ID = "dev.sagron.zt_places.ID";
    static final String EXTRA_PAYLOAD = "zt_places_payload";
    static final String EXTRA_TAP_ID = "zt_places_id";

    /** Enter events this soon after registering mean "already there". */
    private static final long SETTLE_MS = 2 * 60 * 1000;

    /** Set while the app's Flutter side is running, to hear events at once. */
    interface Listener {
        void onEvent(String type, String id, String payload);
    }

    static volatile Listener listener;

    private ZtPlaceAlerts() {}

    static boolean hasFineLocation(Context c) {
        return c.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)
                == PackageManager.PERMISSION_GRANTED;
    }

    static boolean hasBackgroundLocation(Context c) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return hasFineLocation(c);
        return c.checkSelfPermission(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
                == PackageManager.PERMISSION_GRANTED;
    }

    private static PendingIntent alertIntent(Context c, String id) {
        Intent i = new Intent(c, ZtPlaceAlertReceiver.class)
                .setAction(ACTION_ALERT)
                .setData(Uri.parse("ztplace://alert/" + Uri.encode(id)))
                .putExtra(EXTRA_ID, id);
        int flags = PendingIntent.FLAG_UPDATE_CURRENT;
        // LocationManager adds KEY_PROXIMITY_ENTERING, so it must be mutable;
        // the intent is explicit, which Android 14 requires for that.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) flags |= PendingIntent.FLAG_MUTABLE;
        return PendingIntent.getBroadcast(c, requestCode(id), i, flags);
    }

    static int requestCode(String id) {
        // FNV-1a: stable across runs, unlike String.hashCode on some VMs.
        int hash = 0x811c9dc5;
        for (int k = 0; k < id.length(); k++) {
            hash ^= id.charAt(k);
            hash *= 0x01000193;
        }
        return hash & 0x7fffffff;
    }

    private static LocationManager lm(Context c) {
        return (LocationManager) c.getSystemService(Context.LOCATION_SERVICE);
    }

    private static void register(Context c, ZtPlaceStore.Reminder r) {
        if (!hasFineLocation(c)) return;
        try {
            lm(c).addProximityAlert(r.latitude, r.longitude, r.radius, -1, alertIntent(c, r.id));
        } catch (SecurityException | IllegalArgumentException ignored) {
            // Permission revoked meanwhile, or no location provider; the app
            // shows the permission state and re-syncs.
        }
    }

    private static void unregister(Context c, String id) {
        try {
            lm(c).removeProximityAlert(alertIntent(c, id));
        } catch (SecurityException ignored) {
        }
    }

    /** Is the phone's last known position inside [r]? Null when unknown. */
    private static Boolean lastKnownInside(Context c, ZtPlaceStore.Reminder r) {
        if (!hasFineLocation(c)) return null;
        Location best = null;
        try {
            for (String p : lm(c).getProviders(true)) {
                Location l = lm(c).getLastKnownLocation(p);
                if (l != null && (best == null || l.getTime() > best.getTime())) best = l;
            }
        } catch (SecurityException e) {
            return null;
        }
        if (best == null || System.currentTimeMillis() - best.getTime() > 10 * 60 * 1000) {
            return null;
        }
        float[] d = new float[1];
        Location.distanceBetween(best.getLatitude(), best.getLongitude(), r.latitude, r.longitude, d);
        return d[0] <= r.radius;
    }

    /** Makes the watched reminders exactly [wanted]. Returns how many are active. */
    static int sync(Context c, List<ZtPlaceStore.Reminder> wanted, JSONObject config) {
        ZtPlaceStore store = new ZtPlaceStore(c);
        if (config != null) store.saveConfig(config);
        Map<String, ZtPlaceStore.Reminder> old = store.reminders();
        Set<String> wantedIds = new HashSet<>();
        for (ZtPlaceStore.Reminder r : wanted) wantedIds.add(r.id);

        List<String> fired = new ArrayList<>();
        for (String id : store.fired()) if (wantedIds.contains(id)) fired.add(id);
        store.saveFired(fired);

        for (String id : old.keySet()) {
            if (!wantedIds.contains(id)) unregister(c, id);
        }
        Map<String, ZtPlaceStore.Reminder> next = new java.util.LinkedHashMap<>();
        int active = 0;
        long now = System.currentTimeMillis();
        for (ZtPlaceStore.Reminder r : wanted) {
            if (fired.contains(r.id)) continue;
            ZtPlaceStore.Reminder prev = old.get(r.id);
            if (r.samePlace(prev)) {
                r.armed = prev.armed;
                r.settled = prev.settled;
                r.registeredAt = prev.registeredAt;
            } else {
                if (prev != null) unregister(c, r.id);
                Boolean inside = lastKnownInside(c, r);
                r.armed = !r.arrive || !Boolean.TRUE.equals(inside);
                // Known to be outside: the first arrival counts, even right away.
                r.settled = !r.arrive || Boolean.FALSE.equals(inside);
                r.registeredAt = now;
            }
            next.put(r.id, r);
            register(c, r);
            active++;
        }
        store.saveReminders(next);
        return active;
    }

    /** After a reboot or an app update the OS has forgotten every alert. */
    static void reRegisterAll(Context c) {
        for (ZtPlaceStore.Reminder r : new ZtPlaceStore(c).reminders().values()) register(c, r);
    }

    static void clear(Context c) {
        ZtPlaceStore store = new ZtPlaceStore(c);
        for (String id : store.reminders().keySet()) unregister(c, id);
        store.clearAll();
    }

    /** The OS saw the phone cross a place's edge. */
    static void onTransition(Context c, String id, boolean entering) {
        ZtPlaceStore store = new ZtPlaceStore(c);
        Map<String, ZtPlaceStore.Reminder> all = store.reminders();
        ZtPlaceStore.Reminder r = all.get(id);
        if (r == null) {
            unregister(c, id);
            return;
        }
        boolean fire;
        if (r.arrive) {
            if (!entering) {
                // A departure was seen: the next arrival is a real one.
                r.armed = true;
                r.settled = true;
                fire = false;
            } else if (!r.armed) {
                // Already there when the reminder was set: wait until the
                // phone has left once, then remind on the next arrival.
                fire = false;
            } else if (!r.settled && System.currentTimeMillis() - r.registeredAt < SETTLE_MS) {
                // Where the phone was wasn't known when the reminder was set,
                // and the OS reports "inside" right after registering: that
                // is where it already was, not an arrival.
                r.armed = false;
                fire = false;
            } else {
                fire = true;
            }
        } else {
            fire = !entering;
        }
        if (!fire) {
            store.saveReminders(all);
            return;
        }
        all.remove(id);
        store.saveReminders(all);
        List<String> fired = store.fired();
        fired.add(id);
        store.saveFired(fired);
        unregister(c, id);
        show(c, store.config(), r);
        store.addEvent("fired", r.id, r.payload);
        Listener l = listener;
        if (l != null) l.onEvent("fired", r.id, r.payload);
    }

    static void onDone(Context c, String id, String payload) {
        NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
        nm.cancel(id, requestCode(id));
        new ZtPlaceStore(c).addEvent("done", id, payload);
        Listener l = listener;
        if (l != null) l.onEvent("done", id, payload);
    }

    private static int iconFor(Context c, String name) {
        if (name != null && !name.isEmpty()) {
            int res = c.getResources().getIdentifier(name, "drawable", c.getPackageName());
            if (res == 0) res = c.getResources().getIdentifier(name, "mipmap", c.getPackageName());
            if (res != 0) return res;
        }
        return c.getApplicationInfo().icon;
    }

    private static void show(Context c, JSONObject config, ZtPlaceStore.Reminder r) {
        NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
        String channelId = config.optString("channelId", "zt_place_reminders");
        Notification.Builder b;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel ch = new NotificationChannel(channelId,
                    config.optString("channelName", "Place reminders"),
                    NotificationManager.IMPORTANCE_HIGH);
            ch.setDescription(config.optString("channelDescription", ""));
            ch.setLockscreenVisibility(Notification.VISIBILITY_PRIVATE);
            nm.createNotificationChannel(ch);
            b = new Notification.Builder(c, channelId);
        } else {
            b = new Notification.Builder(c).setPriority(Notification.PRIORITY_HIGH);
        }
        int code = requestCode(r.id);
        Intent open = c.getPackageManager().getLaunchIntentForPackage(c.getPackageName());
        if (open == null) open = new Intent();
        open.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .putExtra(EXTRA_PAYLOAD, r.payload)
                .putExtra(EXTRA_TAP_ID, r.id);
        b.setSmallIcon(iconFor(c, config.optString("smallIcon")))
                .setContentTitle(r.title)
                .setContentText(r.body)
                .setCategory(Notification.CATEGORY_REMINDER)
                .setVisibility(Notification.VISIBILITY_PRIVATE)
                .setAutoCancel(true)
                .setContentIntent(PendingIntent.getActivity(c, code, open,
                        PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE));
        String publicTitle = config.optString("publicTitle", "");
        if (!publicTitle.isEmpty()) {
            Notification.Builder pub = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                    ? new Notification.Builder(c, channelId) : new Notification.Builder(c);
            b.setPublicVersion(pub.setSmallIcon(iconFor(c, config.optString("smallIcon")))
                    .setContentTitle(publicTitle).build());
        }
        String doneLabel = config.optString("doneLabel", "");
        if (!doneLabel.isEmpty()) {
            Intent done = new Intent(c, ZtPlaceAlertReceiver.class)
                    .setAction(ACTION_DONE)
                    .setData(Uri.parse("ztplace://done/" + Uri.encode(r.id)))
                    .putExtra(EXTRA_ID, r.id)
                    .putExtra(EXTRA_PAYLOAD, r.payload);
            PendingIntent pi = PendingIntent.getBroadcast(c, code, done,
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
            b.addAction(new Notification.Action.Builder(null, doneLabel, pi).build());
        }
        try {
            nm.notify(r.id, code, b.build());
        } catch (SecurityException ignored) {
            // Notifications not allowed; the app shows that in its settings.
        }
    }
}
