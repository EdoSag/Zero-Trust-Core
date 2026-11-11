package dev.sagron.zt_places;

import android.Manifest;
import android.app.Activity;
import android.app.NotificationManager;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.CancellationSignal;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;

import androidx.annotation.NonNull;

import org.json.JSONObject;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;

/** Flutter side of place reminders. See lib/zt_places.dart. */
public class ZtPlacesPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
        PluginRegistry.RequestPermissionsResultListener, PluginRegistry.NewIntentListener {
    private static final int REQ_LOCATION = 0x5a70;
    private static final int REQ_BACKGROUND = 0x5a71;
    private static final int REQ_NOTIFICATIONS = 0x5a72;

    private MethodChannel channel;
    private Context context;
    private ActivityPluginBinding binding;
    private MethodChannel.Result pendingPermission;
    private Map<String, Object> launchTap;
    private final Handler main = new Handler(Looper.getMainLooper());

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding b) {
        context = b.getApplicationContext();
        channel = new MethodChannel(b.getBinaryMessenger(), "dev.sagron.zt_places");
        channel.setMethodCallHandler(this);
        ZtPlaceAlerts.listener = (type, id, payload) -> main.post(() -> {
            if (channel == null) return;
            Map<String, Object> m = new HashMap<>();
            m.put("type", type);
            m.put("id", id);
            m.put("payload", payload);
            channel.invokeMethod("event", m);
        });
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding b) {
        ZtPlaceAlerts.listener = null;
        channel.setMethodCallHandler(null);
        channel = null;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "sync": {
                List<ZtPlaceStore.Reminder> wanted = new ArrayList<>();
                List<Map<String, Object>> raw = call.argument("reminders");
                if (raw != null) {
                    for (Map<String, Object> m : raw) wanted.add(reminderFrom(m));
                }
                Map<String, Object> config = call.argument("config");
                result.success(ZtPlaceAlerts.sync(context, wanted,
                        config == null ? null : new JSONObject(config)));
                break;
            }
            case "clear":
                ZtPlaceAlerts.clear(context);
                result.success(null);
                break;
            case "permissions":
                result.success(permissions());
                break;
            case "requestLocation":
                request(new String[]{Manifest.permission.ACCESS_FINE_LOCATION,
                        Manifest.permission.ACCESS_COARSE_LOCATION}, REQ_LOCATION, result);
                break;
            case "requestBackground":
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                    result.success(permissions());
                } else {
                    request(new String[]{Manifest.permission.ACCESS_BACKGROUND_LOCATION},
                            REQ_BACKGROUND, result);
                }
                break;
            case "requestNotifications":
                if (Build.VERSION.SDK_INT < 33) {
                    result.success(permissions());
                } else {
                    request(new String[]{Manifest.permission.POST_NOTIFICATIONS},
                            REQ_NOTIFICATIONS, result);
                }
                break;
            case "openSettings": {
                Intent i = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.fromParts("package", context.getPackageName(), null))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                context.startActivity(i);
                result.success(null);
                break;
            }
            case "currentLocation": {
                Integer timeout = call.argument("timeoutMs");
                currentLocation(timeout == null ? 20000 : timeout, result);
                break;
            }
            case "takeEvents":
                result.success(new ZtPlaceStore(context).takeEvents());
                break;
            case "takeLaunchTap": {
                Map<String, Object> tap = launchTap;
                launchTap = null;
                result.success(tap);
                break;
            }
            default:
                result.notImplemented();
        }
    }

    private static ZtPlaceStore.Reminder reminderFrom(Map<String, Object> m) {
        ZtPlaceStore.Reminder r = new ZtPlaceStore.Reminder();
        r.id = (String) m.get("id");
        r.latitude = ((Number) m.get("latitude")).doubleValue();
        r.longitude = ((Number) m.get("longitude")).doubleValue();
        r.radius = ((Number) m.get("radius")).floatValue();
        r.arrive = !"leave".equals(m.get("trigger"));
        r.title = (String) m.get("title");
        r.body = (String) m.get("body");
        r.payload = (String) m.get("payload");
        return r;
    }

    private Map<String, Object> permissions() {
        Map<String, Object> m = new HashMap<>();
        m.put("fine", ZtPlaceAlerts.hasFineLocation(context));
        m.put("coarse", context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION)
                == PackageManager.PERMISSION_GRANTED);
        m.put("background", ZtPlaceAlerts.hasBackgroundLocation(context));
        NotificationManager nm = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        m.put("notifications", nm.areNotificationsEnabled());
        LocationManager lm = (LocationManager) context.getSystemService(Context.LOCATION_SERVICE);
        boolean on;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            on = lm.isLocationEnabled();
        } else {
            on = lm.isProviderEnabled(LocationManager.GPS_PROVIDER)
                    || lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER);
        }
        m.put("locationOn", on);
        return m;
    }

    private void request(String[] perms, int code, MethodChannel.Result result) {
        Activity a = binding == null ? null : binding.getActivity();
        if (a == null || pendingPermission != null) {
            result.success(permissions());
            return;
        }
        pendingPermission = result;
        a.requestPermissions(perms, code);
    }

    @Override
    public boolean onRequestPermissionsResult(int code, @NonNull String[] perms, @NonNull int[] grants) {
        if (code != REQ_LOCATION && code != REQ_BACKGROUND && code != REQ_NOTIFICATIONS) return false;
        MethodChannel.Result r = pendingPermission;
        pendingPermission = null;
        if (r != null) r.success(permissions());
        return true;
    }

    private void currentLocation(int timeoutMs, MethodChannel.Result result) {
        if (!ZtPlaceAlerts.hasFineLocation(context)
                && context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION)
                != PackageManager.PERMISSION_GRANTED) {
            result.success(null);
            return;
        }
        LocationManager lm = (LocationManager) context.getSystemService(Context.LOCATION_SERVICE);
        String provider = null;
        // "fused" here is Android's own (AOSP) fused provider, not Play services.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && lm.isProviderEnabled(LocationManager.FUSED_PROVIDER)) {
            provider = LocationManager.FUSED_PROVIDER;
        } else if (lm.isProviderEnabled(LocationManager.GPS_PROVIDER) && ZtPlaceAlerts.hasFineLocation(context)) {
            provider = LocationManager.GPS_PROVIDER;
        } else if (lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
            provider = LocationManager.NETWORK_PROVIDER;
        }
        if (provider == null) {
            result.success(null);
            return;
        }
        final boolean[] done = {false};
        final CancellationSignal cancel = new CancellationSignal();
        final LocationListener[] legacy = {null};
        Runnable finishWithLastKnown = () -> {
            if (done[0]) return;
            done[0] = true;
            cancel.cancel();
            if (legacy[0] != null) lm.removeUpdates(legacy[0]);
            result.success(toMap(lastKnown(lm)));
        };
        main.postDelayed(finishWithLastKnown, timeoutMs);
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                lm.getCurrentLocation(provider, cancel, context.getMainExecutor(), loc -> {
                    if (done[0]) return;
                    if (loc == null) {
                        main.removeCallbacks(finishWithLastKnown);
                        finishWithLastKnown.run();
                        return;
                    }
                    done[0] = true;
                    main.removeCallbacks(finishWithLastKnown);
                    result.success(toMap(loc));
                });
            } else {
                legacy[0] = new LocationListener() {
                    @Override
                    public void onLocationChanged(@NonNull Location loc) {
                        if (done[0]) return;
                        done[0] = true;
                        main.removeCallbacks(finishWithLastKnown);
                        lm.removeUpdates(this);
                        result.success(toMap(loc));
                    }

                    @Override
                    public void onStatusChanged(String p, int s, Bundle e) {}

                    @Override
                    public void onProviderEnabled(@NonNull String p) {}

                    @Override
                    public void onProviderDisabled(@NonNull String p) {}
                };
                lm.requestLocationUpdates(provider, 0, 0, legacy[0], Looper.getMainLooper());
            }
        } catch (SecurityException e) {
            main.removeCallbacks(finishWithLastKnown);
            if (!done[0]) {
                done[0] = true;
                result.success(null);
            }
        }
    }

    private Location lastKnown(LocationManager lm) {
        Location best = null;
        try {
            for (String p : lm.getProviders(true)) {
                Location l = lm.getLastKnownLocation(p);
                if (l != null && (best == null || l.getTime() > best.getTime())) best = l;
            }
        } catch (SecurityException ignored) {
        }
        return best;
    }

    private static Map<String, Object> toMap(Location l) {
        if (l == null) return null;
        Map<String, Object> m = new HashMap<>();
        m.put("latitude", l.getLatitude());
        m.put("longitude", l.getLongitude());
        m.put("accuracy", (double) l.getAccuracy());
        m.put("time", l.getTime());
        return m;
    }

    private boolean readTap(Intent intent, boolean live) {
        if (intent == null || !intent.hasExtra(ZtPlaceAlerts.EXTRA_TAP_ID)) return false;
        Map<String, Object> tap = new HashMap<>();
        tap.put("id", intent.getStringExtra(ZtPlaceAlerts.EXTRA_TAP_ID));
        tap.put("payload", intent.getStringExtra(ZtPlaceAlerts.EXTRA_PAYLOAD));
        // Read once: a rotated or recreated activity must not open it again.
        intent.removeExtra(ZtPlaceAlerts.EXTRA_TAP_ID);
        intent.removeExtra(ZtPlaceAlerts.EXTRA_PAYLOAD);
        if (live && channel != null) {
            channel.invokeMethod("tap", tap);
        } else {
            // The tap that started the app: Dart collects it with takeLaunchTap.
            launchTap = tap;
        }
        return true;
    }

    @Override
    public boolean onNewIntent(@NonNull Intent intent) {
        return readTap(intent, true);
    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding b) {
        binding = b;
        b.addRequestPermissionsResultListener(this);
        b.addOnNewIntentListener(this);
        readTap(b.getActivity().getIntent(), false);
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity();
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding b) {
        onAttachedToActivity(b);
    }

    @Override
    public void onDetachedFromActivity() {
        if (binding != null) {
            binding.removeRequestPermissionsResultListener(this);
            binding.removeOnNewIntentListener(this);
        }
        binding = null;
    }
}
