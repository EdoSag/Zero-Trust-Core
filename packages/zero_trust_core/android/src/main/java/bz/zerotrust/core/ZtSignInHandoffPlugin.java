package bz.zerotrust.core;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;

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

/**
 * "Sign in once per phone" (S-2): carries a request from one Zero-Trust app
 * to another, and the sealed answer back, over the apps' launch intents.
 *
 * Only apps signed with the same key as this one take part: a message goes
 * out only to such an app, and one that names any other sender is dropped.
 * Who really sent a message isn't trusted beyond that: the answer is sealed
 * with a secret only the asking app's request carried, and always goes to
 * the app named as the asker, so a fake request can at most make this app
 * ask its user, and a fake answer doesn't open.
 *
 * The launch intent is used as is (action MAIN, category LAUNCHER), so it
 * matches the receiving activity's filter on every Android version, and it
 * reaches a running app through onNewIntent (CLEAR_TOP | SINGLE_TOP) whether
 * its activity is singleTop or singleTask.
 */
public final class ZtSignInHandoffPlugin
        implements FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
        PluginRegistry.NewIntentListener {
    static final String CHANNEL = "bz.zerotrust.core/sign_in_handoff";
    static final String EXTRA_KIND = "bz.zerotrust.extra.HANDOFF";
    static final String EXTRA_FROM = "bz.zerotrust.extra.HANDOFF_FROM";
    static final String EXTRA_MODE = "bz.zerotrust.extra.HANDOFF_MODE";
    static final String EXTRA_PAYLOAD = "bz.zerotrust.extra.HANDOFF_PAYLOAD";
    static final String EXTRA_AT = "bz.zerotrust.extra.HANDOFF_AT";
    private static final int MAX_PAYLOAD = 16 * 1024;
    private static final int MAX_WAITING = 4;

    private MethodChannel channel;
    private Context context;
    private ActivityPluginBinding activityBinding;
    /** Messages Dart hasn't taken yet (it may not be running yet). */
    private final List<Map<String, Object>> waiting = new ArrayList<>();

    @Override
    public void onAttachedToEngine(FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(FlutterPluginBinding binding) {
        if (channel != null) channel.setMethodCallHandler(null);
        channel = null;
    }

    @Override
    public void onAttachedToActivity(ActivityPluginBinding binding) {
        activityBinding = binding;
        binding.addOnNewIntentListener(this);
        take(binding.getActivity().getIntent());
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity();
    }

    @Override
    public void onReattachedToActivityForConfigChanges(ActivityPluginBinding binding) {
        onAttachedToActivity(binding);
    }

    @Override
    public void onDetachedFromActivity() {
        if (activityBinding != null) activityBinding.removeOnNewIntentListener(this);
        activityBinding = null;
    }

    @Override
    public boolean onNewIntent(Intent intent) {
        return take(intent);
    }

    /** Keeps a handoff message from [intent] for Dart. True when it was one. */
    private boolean take(Intent intent) {
        if (intent == null) return false;
        final String kind;
        final String from;
        final String mode;
        final byte[] payload;
        final long at;
        try {
            kind = intent.getStringExtra(EXTRA_KIND);
            if (kind == null) return false;
            from = intent.getStringExtra(EXTRA_FROM);
            mode = intent.getStringExtra(EXTRA_MODE);
            payload = intent.getByteArrayExtra(EXTRA_PAYLOAD);
            at = intent.getLongExtra(EXTRA_AT, 0L);
        } catch (RuntimeException e) {
            // Extras another app made unreadable: not a message.
            return false;
        }
        // Taken once: a rotation or a return to the activity must not ask again.
        intent.removeExtra(EXTRA_KIND);
        intent.removeExtra(EXTRA_FROM);
        intent.removeExtra(EXTRA_MODE);
        intent.removeExtra(EXTRA_PAYLOAD);
        intent.removeExtra(EXTRA_AT);
        // Reopened from Recents after the process died: an old message.
        if ((intent.getFlags() & Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) return true;
        if (from == null || mode == null || payload == null || payload.length > MAX_PAYLOAD) {
            return true;
        }
        if (!isSibling(from)) return true;
        final Map<String, Object> message = new HashMap<>();
        message.put("kind", kind);
        message.put("from", from);
        message.put("mode", mode);
        message.put("payload", payload);
        message.put("at", at);
        waiting.add(message);
        while (waiting.size() > MAX_WAITING) waiting.remove(0);
        if (channel != null) channel.invokeMethod("changed", null);
        return true;
    }

    /** Another installed app signed with this app's key, that can be opened. */
    private boolean isSibling(String packageName) {
        if (context == null || packageName.equals(context.getPackageName())) return false;
        final PackageManager pm = context.getPackageManager();
        try {
            return pm.checkSignatures(context.getPackageName(), packageName)
                    == PackageManager.SIGNATURE_MATCH
                    && pm.getLaunchIntentForPackage(packageName) != null;
        } catch (RuntimeException e) {
            return false;
        }
    }

    @Override
    public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        switch (call.method) {
            case "siblings": {
                final List<String> packages = call.argument("packages");
                final List<String> found = new ArrayList<>();
                if (packages != null) {
                    for (String p : packages) {
                        if (p != null && isSibling(p)) found.add(p);
                    }
                }
                result.success(found);
                return;
            }
            case "send": {
                final String to = call.argument("to");
                final String kind = call.argument("kind");
                final String mode = call.argument("mode");
                final byte[] payload = call.argument("payload");
                result.success(send(to, kind, mode, payload));
                return;
            }
            case "take": {
                result.success(new ArrayList<>(waiting));
                waiting.clear();
                return;
            }
            default:
                result.notImplemented();
        }
    }

    private boolean send(String to, String kind, String mode, byte[] payload) {
        if (to == null || kind == null || mode == null || payload == null) return false;
        if (!isSibling(to)) return false;
        final Intent launch = context.getPackageManager().getLaunchIntentForPackage(to);
        if (launch == null) return false;
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK
                | Intent.FLAG_ACTIVITY_CLEAR_TOP
                | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        launch.putExtra(EXTRA_KIND, kind);
        launch.putExtra(EXTRA_FROM, context.getPackageName());
        launch.putExtra(EXTRA_MODE, mode);
        launch.putExtra(EXTRA_PAYLOAD, payload);
        launch.putExtra(EXTRA_AT, System.currentTimeMillis());
        try {
            final Activity activity = activityBinding == null ? null : activityBinding.getActivity();
            if (activity != null) {
                activity.startActivity(launch);
            } else {
                context.startActivity(launch);
            }
            return true;
        } catch (RuntimeException e) {
            return false;
        }
    }
}
