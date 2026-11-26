package dev.sagron.zt_assist;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.Message;
import android.os.Messenger;
import android.os.RemoteException;

import androidx.annotation.NonNull;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * Carries an app's requests to ZT Assist and its answers back. See
 * lib/zt_assist.dart.
 *
 * <p>ZT Assist answers from a service (AssistService.java in
 * Zero-Trust-Assist). The message numbers and field names below are the
 * contract between the two; change them in both.
 *
 * <p>Before anything is sent, the app that holds the name
 * dev.sagron.zerotrustassist must be signed with the same key as this app.
 * Otherwise another app installed under that name could read the text a
 * user asks to have summarized.
 */
public class ZtAssistPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
    static final String ASSIST_PACKAGE = "dev.sagron.zerotrustassist";
    static final String ASSIST_SERVICE = ASSIST_PACKAGE + ".AssistService";

    // To ZT Assist.
    static final int MSG_STATUS = 1;
    static final int MSG_ASK = 2;
    static final int MSG_CANCEL = 3;

    // From ZT Assist.
    static final int MSG_STATUS_REPLY = 101;
    static final int MSG_CHUNK = 102;
    static final int MSG_DONE = 103;
    static final int MSG_FAILED = 104;

    /**
     * How long the connection is kept after the last answer. While it is
     * kept the model stays in memory, so the next request starts at once;
     * after it ZT Assist gives the memory back.
     */
    static final long KEEP_CONNECTED_MS = 2 * 60 * 1000;

    /** How long a stopped request may take to end before it is forgotten. */
    static final long FORGET_STOPPED_MS = 10 * 1000;

    private final Handler main = new Handler(Looper.getMainLooper());
    private Context context;
    private MethodChannel channel;

    /** ZT Assist, once connected. */
    private Messenger service;
    private boolean bound = false;
    /** Messages written before the connection was up. */
    private final ArrayList<Message> unsent = new ArrayList<>();
    /** Requests and status questions still waiting for their end. */
    private final Set<String> open = new HashSet<>();
    /** The app asked to let go while an answer was still on its way. */
    private boolean releaseWhenIdle = false;

    private final Messenger replies = new Messenger(new Handler(Looper.getMainLooper()) {
        @Override
        public void handleMessage(Message message) {
            onReply(message);
        }
    });

    private final Runnable disconnectWhenIdle = this::disconnect;

    private final ServiceConnection connection = new ServiceConnection() {
        @Override
        public void onServiceConnected(ComponentName name, IBinder binder) {
            service = new Messenger(binder);
            final ArrayList<Message> waiting = new ArrayList<>(unsent);
            unsent.clear();
            for (Message message : waiting) {
                // A failed delivery has already ended every request and
                // closed the connection; the rest has nowhere to go.
                if (!deliver(message)) break;
            }
        }

        @Override
        public void onServiceDisconnected(ComponentName name) {
            // ZT Assist stopped (the phone took its memory, or it crashed).
            failAll("stopped");
            disconnect();
        }

        @Override
        public void onBindingDied(ComponentName name) {
            failAll("stopped");
            disconnect();
        }

        @Override
        public void onNullBinding(ComponentName name) {
            failAll("not_installed");
            disconnect();
        }
    };

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(), "dev.sagron.zt_assist");
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        open.clear();
        disconnect();
        if (channel != null) channel.setMethodCallHandler(null);
        channel = null;
        context = null;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "installed":
                result.success(presence());
                break;
            case "status": {
                final String id = call.argument("id");
                final Bundle data = new Bundle();
                data.putString("id", id);
                result.success(null);
                send(MSG_STATUS, id, data);
                break;
            }
            case "ask": {
                final String id = call.argument("id");
                final Bundle data = new Bundle();
                data.putString("id", id);
                data.putString("task", call.<String>argument("task"));
                data.putString("text", call.<String>argument("text"));
                final String instruction = call.argument("instruction");
                if (instruction != null) data.putString("instruction", instruction);
                final String language = call.argument("language");
                if (language != null) data.putString("language", language);
                final Integer maxTokens = call.argument("maxTokens");
                if (maxTokens != null) data.putInt("maxTokens", maxTokens);
                result.success(null);
                send(MSG_ASK, id, data);
                break;
            }
            case "cancel": {
                final String id = call.argument("id");
                result.success(null);
                if (id == null || !open.contains(id)) break;
                final Bundle data = new Bundle();
                data.putString("id", id);
                // Not counted as a new request: the one it stops ends with
                // a "done" of its own.
                post(MSG_CANCEL, data);
                // Should that end never come, the request is forgotten, so
                // it cannot keep the connection, and with it the model in
                // memory, for as long as this app runs.
                main.postDelayed(() -> {
                    if (open.remove(id)) idle();
                }, FORGET_STOPPED_MS);
                break;
            }
            case "release":
                result.success(null);
                if (open.isEmpty()) {
                    disconnect();
                } else {
                    releaseWhenIdle = true;
                }
                break;
            default:
                result.notImplemented();
        }
    }

    /**
     * "ready" when ZT Assist is installed and signed like this app,
     * "untrusted" when something else holds its name, else "not_installed".
     */
    private String presence() {
        if (context == null) return "not_installed";
        final PackageManager packages = context.getPackageManager();
        try {
            packages.getPackageInfo(ASSIST_PACKAGE, 0);
        } catch (PackageManager.NameNotFoundException missing) {
            return "not_installed";
        }
        return packages.checkSignatures(context.getPackageName(), ASSIST_PACKAGE)
                == PackageManager.SIGNATURE_MATCH ? "ready" : "untrusted";
    }

    /** Sends a request that will get an answer, connecting first if needed. */
    private void send(int what, String id, Bundle data) {
        if (id == null) return;
        final String presence = presence();
        if (!"ready".equals(presence)) {
            fail(id, presence);
            return;
        }
        open.add(id);
        releaseWhenIdle = false;
        main.removeCallbacks(disconnectWhenIdle);
        if (!post(what, data)) {
            open.remove(id);
            fail(id, "not_installed");
            idle();
        }
    }

    /** False when ZT Assist cannot be reached at all. */
    private boolean post(int what, Bundle data) {
        final Message message = Message.obtain(null, what);
        message.setData(data);
        message.replyTo = replies;
        if (service != null) {
            deliver(message);
            return true;
        }
        if (!bound) {
            final Intent intent = new Intent();
            intent.setComponent(new ComponentName(ASSIST_PACKAGE, ASSIST_SERVICE));
            try {
                // Important: ZT Assist is not on screen while it answers,
                // and Android gives a background app only its slow cores.
                // This keeps it as fast as the app the user is looking at.
                bound = context.bindService(intent, connection,
                        Context.BIND_AUTO_CREATE | Context.BIND_IMPORTANT);
            } catch (SecurityException refused) {
                bound = false;
            }
            if (!bound) {
                // Android wants the connection given back even when the
                // bind did not take.
                try {
                    context.unbindService(connection);
                } catch (RuntimeException neverBound) {
                    // Nothing to give back.
                }
                return false;
            }
        }
        unsent.add(message);
        return true;
    }

    /** False when ZT Assist was gone; every open request has then failed. */
    private boolean deliver(Message message) {
        final Messenger to = service;
        if (to == null) return false;
        try {
            to.send(message);
            return true;
        } catch (RemoteException gone) {
            failAll("stopped");
            disconnect();
            return false;
        }
    }

    private void onReply(Message message) {
        final Bundle data = message.getData();
        if (data == null) return;
        final String id = data.getString("id");
        if (id == null || !open.contains(id)) return;
        final Map<String, Object> event = new HashMap<>();
        event.put("id", id);
        switch (message.what) {
            case MSG_CHUNK:
                event.put("type", "chunk");
                event.put("text", data.getString("text", ""));
                emit(event);
                return;
            case MSG_STATUS_REPLY:
                event.put("type", "status");
                event.put("protocol", data.getInt("protocol", 0));
                event.put("ready", data.getBoolean("ready", false));
                event.put("busy", data.getBoolean("busy", false));
                break;
            case MSG_DONE:
                event.put("type", "done");
                event.put("stopped", data.getBoolean("stopped", false));
                event.put("truncated", data.getBoolean("truncated", false));
                event.put("tokens", data.getInt("tokens", 0));
                event.put("milliseconds", data.getInt("milliseconds", 0));
                event.put("firstMilliseconds", data.getInt("firstMilliseconds", 0));
                break;
            case MSG_FAILED:
                event.put("type", "failed");
                event.put("code", data.getString("code", "failed"));
                event.put("detail", data.getString("detail"));
                break;
            default:
                return;
        }
        open.remove(id);
        emit(event);
        idle();
    }

    private void fail(String id, String code) {
        final Map<String, Object> event = new HashMap<>();
        event.put("id", id);
        event.put("type", "failed");
        event.put("code", code);
        event.put("detail", null);
        // After the call that asked has returned, like every other answer.
        main.post(() -> emit(event));
    }

    private void failAll(String code) {
        final ArrayList<String> ids = new ArrayList<>(open);
        open.clear();
        for (String id : ids) fail(id, code);
    }

    private void emit(Map<String, Object> event) {
        if (channel != null) channel.invokeMethod("event", event);
    }

    /** Starts the wait after which an unused connection is closed. */
    private void idle() {
        if (!open.isEmpty()) return;
        if (releaseWhenIdle) {
            disconnect();
            return;
        }
        main.removeCallbacks(disconnectWhenIdle);
        main.postDelayed(disconnectWhenIdle, KEEP_CONNECTED_MS);
    }

    private void disconnect() {
        main.removeCallbacks(disconnectWhenIdle);
        releaseWhenIdle = false;
        unsent.clear();
        service = null;
        if (!bound) return;
        bound = false;
        try {
            context.unbindService(connection);
        } catch (RuntimeException alreadyGone) {
            // Nothing to give back.
        }
    }
}
