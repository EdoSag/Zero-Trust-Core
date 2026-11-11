package dev.sagron.zt_places;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * The place reminders the OS is watching, kept in the app's private
 * preferences so they can be shown while the app is closed or locked and
 * registered again after a reboot. Only what the notification needs is here:
 * the place, the reminder's title and text, and an opaque app payload.
 */
final class ZtPlaceStore {
    private static final String PREFS = "dev.sagron.zt_places";
    private static final String KEY_REMINDERS = "reminders";
    private static final String KEY_CONFIG = "config";
    private static final String KEY_FIRED = "fired";
    private static final String KEY_EVENTS = "events";

    static final class Reminder {
        String id;
        double latitude;
        double longitude;
        float radius;
        boolean arrive;
        String title;
        String body;
        String payload;
        /** For "arrive": false until the phone has been seen outside the place. */
        boolean armed;
        /**
         * For "arrive": the phone's state at the place is known (it was seen
         * outside when the reminder was set, or has left since), so an
         * arrival is real rather than the OS reporting where it already was.
         */
        boolean settled;
        long registeredAt;

        boolean samePlace(Reminder other) {
            return other != null
                    && latitude == other.latitude
                    && longitude == other.longitude
                    && radius == other.radius
                    && arrive == other.arrive;
        }

        JSONObject toJson() throws JSONException {
            JSONObject o = new JSONObject();
            o.put("id", id);
            o.put("latitude", latitude);
            o.put("longitude", longitude);
            o.put("radius", (double) radius);
            o.put("trigger", arrive ? "arrive" : "leave");
            o.put("title", title);
            o.put("body", body == null ? "" : body);
            o.put("payload", payload == null ? "" : payload);
            o.put("armed", armed);
            o.put("settled", settled);
            o.put("registeredAt", registeredAt);
            return o;
        }

        static Reminder fromJson(JSONObject o) {
            Reminder r = new Reminder();
            r.id = o.optString("id");
            r.latitude = o.optDouble("latitude");
            r.longitude = o.optDouble("longitude");
            r.radius = (float) o.optDouble("radius", 150);
            r.arrive = !"leave".equals(o.optString("trigger", "arrive"));
            r.title = o.optString("title");
            r.body = o.optString("body");
            r.payload = o.optString("payload");
            r.armed = o.optBoolean("armed", true);
            r.settled = o.optBoolean("settled", true);
            r.registeredAt = o.optLong("registeredAt", 0);
            return r;
        }
    }

    private final SharedPreferences prefs;

    ZtPlaceStore(Context context) {
        prefs = context.getApplicationContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    synchronized Map<String, Reminder> reminders() {
        Map<String, Reminder> out = new LinkedHashMap<>();
        try {
            JSONArray a = new JSONArray(prefs.getString(KEY_REMINDERS, "[]"));
            for (int i = 0; i < a.length(); i++) {
                Reminder r = Reminder.fromJson(a.getJSONObject(i));
                out.put(r.id, r);
            }
        } catch (JSONException ignored) {
            // Unreadable: start over; the app re-sends its reminders.
        }
        return out;
    }

    synchronized void saveReminders(Map<String, Reminder> reminders) {
        JSONArray a = new JSONArray();
        try {
            for (Reminder r : reminders.values()) a.put(r.toJson());
        } catch (JSONException ignored) {
        }
        prefs.edit().putString(KEY_REMINDERS, a.toString()).apply();
    }

    synchronized JSONObject config() {
        try {
            return new JSONObject(prefs.getString(KEY_CONFIG, "{}"));
        } catch (JSONException e) {
            return new JSONObject();
        }
    }

    synchronized void saveConfig(JSONObject config) {
        prefs.edit().putString(KEY_CONFIG, config.toString()).apply();
    }

    /** Ids that already fired; a reminder fires once. */
    synchronized List<String> fired() {
        return readStrings(KEY_FIRED);
    }

    synchronized void saveFired(List<String> ids) {
        prefs.edit().putString(KEY_FIRED, new JSONArray(ids).toString()).apply();
    }

    /** Events (fired, done) the app hasn't collected yet. */
    synchronized void addEvent(String type, String id, String payload) {
        try {
            JSONArray a = new JSONArray(prefs.getString(KEY_EVENTS, "[]"));
            JSONObject o = new JSONObject();
            o.put("type", type);
            o.put("id", id);
            o.put("payload", payload == null ? "" : payload);
            a.put(o);
            // Bounded: an app that never collects shouldn't grow this forever.
            while (a.length() > 200) a.remove(0);
            prefs.edit().putString(KEY_EVENTS, a.toString()).apply();
        } catch (JSONException ignored) {
        }
    }

    synchronized List<Map<String, Object>> takeEvents() {
        List<Map<String, Object>> out = new ArrayList<>();
        try {
            JSONArray a = new JSONArray(prefs.getString(KEY_EVENTS, "[]"));
            for (int i = 0; i < a.length(); i++) {
                JSONObject o = a.getJSONObject(i);
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("type", o.optString("type"));
                m.put("id", o.optString("id"));
                m.put("payload", o.optString("payload"));
                out.add(m);
            }
        } catch (JSONException ignored) {
        }
        prefs.edit().remove(KEY_EVENTS).apply();
        return out;
    }

    synchronized void clearAll() {
        prefs.edit().clear().apply();
    }

    private List<String> readStrings(String key) {
        List<String> out = new ArrayList<>();
        try {
            JSONArray a = new JSONArray(prefs.getString(key, "[]"));
            for (int i = 0; i < a.length(); i++) out.add(a.getString(i));
        } catch (JSONException ignored) {
        }
        return out;
    }
}
