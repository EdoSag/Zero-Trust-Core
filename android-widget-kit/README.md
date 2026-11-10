# Zero-Trust home screen widget kit

One look for every Zero-Trust app's Android home screen widgets (roadmap W1).
The kit is plain Android resources, copied into each app with `apply.sh`, so
an app does not need a newer core version to use it.

```
android-widget-kit/apply.sh ../Zero-Trust-Tasks '#06B6D4'
```

The accent is the app's `ZtAppConfig.accent`. Never edit the copied
`zt_widget_*` files inside an app: change them here and copy again.

## What every widget does

**Shape and colour.** The root view uses `style="@style/ZtWidget.Root"`: the
launcher's own corner radius on Android 12+ (24dp before), Material You
neutral colours on 12+ (fixed neutrals before), light and dark. The app's
accent is used only for the main action button and small markers (dots,
progress), never for large areas.

**Header.** App icon (`@mipmap/ic_launcher`, 20dp) + "ZT App" in
`ZtWidget.AppName`, then an optional title (`ZtWidget.Title`) and one round
accent action at the end (`ZtWidget.Action` with an `ic_zt_widget_*` icon).
Tapping the header opens the app.

**Rows.** `ZtWidget.Body` for the main line, `ZtWidget.Caption` for the second
line, 40dp minimum height so they are easy to tap.

**Locked or private.** When a widget has nothing it may show, it shows
`ic_zt_widget_lock` tinted `zt_widget_on_surface_variant` and one caption
("Open ZT Notes to see this note"), never an emoji or a blank widget.

**Privacy switch (W3).** Every app that puts its own content on a widget has
one switch in Settings, same words everywhere:

- Title: **Show details on the home screen**
- Subtitle: what the widget shows when off, then "On: … are stored
  unencrypted on this phone for the home screen."
- Icon: `Icons.widgets_outlined`, in the app's `appSection`.
- Off by default for new installs. Content written while it is on is removed
  when it is turned off or the account signs out.

**Sizes (W2).** Every widget is resizable (`resizeMode="horizontal|vertical"`,
except a pure 1x1 button) and picks a layout from its current size in
`onAppWidgetOptionsChanged`, showing more as it grows. Set
`targetCellWidth/Height`, `minResizeWidth/Height` and `maxResizeWidth/Height`.

**Widget picker.** Every `appwidget-provider` has `android:description`
and an `android:previewLayout` (Android 12+) with sample content, so the
Widgets menu shows what the widget looks like instead of a blank box.

## Files

| File | What |
|---|---|
| `values*/zt_widget_colors.xml` | surface, tile, on-surface, outline (light/dark, before and after Android 12) |
| `values*/zt_widget_dimens.xml` | corner radii, padding, header icon and action sizes |
| `values/zt_widget_styles.xml` | `ZtWidget.Root`, `.AppName`, `.Title`, `.Display`, `.Body`, `.Caption`, `.Action` |
| `drawable/zt_widget_*.xml` | background, tile, accent circle and pill, tile circle, check ring |
| `drawable/ic_zt_widget_*.xml` | lock, add, search, mic, play, stop, check, call, person, private, qr |
| `values/zt_widget_accent.xml` | written by `apply.sh`: the app's accent |
