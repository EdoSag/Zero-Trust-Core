# zt_places

On-device place reminders ("remind me when I arrive at / leave a place") and
the shared place picker for Zero-Trust apps. Android's own `LocationManager`
watches the places (no Google Play services), so the location never leaves
the phone. See the "Place reminders" section of the repository README.

Apps need no manifest changes: the plugin's manifest
brings the location, notification and boot permissions and its receivers.
