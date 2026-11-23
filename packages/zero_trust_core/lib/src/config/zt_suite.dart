import 'package:flutter/material.dart';

/// One app of the Zero-Trust suite: its id, name, accent and store ids.
/// The single list every app uses for the brand look and for "Other
/// Zero-Trust apps" in settings.
class ZtSuiteApp {
  const ZtSuiteApp({
    required this.appId,
    required this.name,
    required this.tagline,
    required this.icon,
    required this.accent,
    required this.androidPackage,
    this.available = true,
  });

  /// Same as `ZtAppConfig.appId`.
  final String appId;

  /// Short name, as under the launcher icon: "Notes".
  final String name;

  /// One line on what it's for.
  final String tagline;
  final IconData icon;

  /// The app's accent. The brand seed (indigo) is shared by all of them.
  final Color accent;

  /// Android application id, for the Play Store link.
  final String androidPackage;

  /// False while the app isn't out yet: it is then left out of "Other
  /// Zero-Trust apps", but its data is still backed up and its brand still
  /// shows in the app itself.
  final bool available;

  String get fullName => 'Zero-Trust $name';

  Uri get playStoreUrl => Uri.https(
      'play.google.com', '/store/apps/details', {'id': androidPackage});

  /// Opens the app when installed (Android `market://` falls back to the
  /// store app otherwise).
  Uri get marketUrl => Uri.parse('market://details?id=$androidPackage');
}

abstract final class ZtSuite {
  /// Where people can sponsor development (GitHub Sponsors). Shown only in
  /// builds whose [ZtInstallChannel] allows outside payments.
  static final sponsorUrl = Uri.https('github.com', '/sponsors/EdoSag');

  static const notes = ZtSuiteApp(
    appId: 'notes',
    name: 'Notes',
    tagline: 'Notes, lists and notebooks',
    icon: Icons.sticky_note_2_outlined,
    accent: Color(0xFFF59E0B), // amber
    androidPackage: 'dev.sagron.zerotrustnotes',
  );
  static const tasks = ZtSuiteApp(
    appId: 'tasks',
    name: 'Tasks',
    tagline: 'To-dos, reminders and lists',
    // A checklist rather than a check in a circle, and cyan rather than
    // blue, so it doesn't read as Google Tasks.
    icon: Icons.checklist_rounded,
    accent: Color(0xFF06B6D4), // cyan
    androidPackage: 'dev.sagron.zerotrusttasks',
  );
  static const fitness = ZtSuiteApp(
    appId: 'fitness',
    name: 'Fitness',
    tagline: 'Activity, workouts and health',
    icon: Icons.favorite_outline,
    accent: Color(0xFF10B981), // green
    androidPackage: 'dev.sagron.zerotrustfitness',
  );
  static const contacts = ZtSuiteApp(
    appId: 'contacts',
    name: 'Contacts',
    tagline: 'Your address book',
    icon: Icons.contacts_outlined,
    accent: Color(0xFFEC4899), // pink
    androidPackage: 'dev.sagron.zerotrustcontacts',
  );

  static const clock = ZtSuiteApp(
    appId: 'clock',
    name: 'Clock',
    tagline: 'Alarms, timer, stopwatch and world clock',
    icon: Icons.alarm,
    accent: Color(0xFF6366F1), // indigo
    androidPackage: 'dev.sagron.zerotrustclock',
  );

  static const time = ZtSuiteApp(
    appId: 'time',
    name: 'Time',
    tagline: 'Time tracking for work and projects',
    icon: Icons.timer_outlined,
    accent: Color(0xFF3B82F6), // blue
    androidPackage: 'dev.sagron.zerotrusttime',
  );

  static const quests = ZtSuiteApp(
    appId: 'quests',
    name: 'Quests',
    tagline: 'Daily quests for your goals, with XP and levels',
    icon: Icons.emoji_events_outlined,
    accent: Color(0xFF7C3AED), // violet
    androidPackage: 'dev.sagron.zerotrustquests',
  );

  static const calendar = ZtSuiteApp(
    appId: 'calendar',
    name: 'Calendar',
    tagline: 'Events, reminders and planning',
    icon: Icons.calendar_month_outlined,
    accent: Color(0xFFF97316), // orange
    androidPackage: 'dev.sagron.zerotrustcalendar',
  );

  static const browser = ZtSuiteApp(
    appId: 'browser',
    name: 'Browser',
    tagline: 'Private web browsing',
    icon: Icons.public,
    accent: Color(0xFFF97316), // orange
    androidPackage: 'dev.sagron.zerotrustbrowser',
  );

  static const phone = ZtSuiteApp(
    appId: 'phone',
    name: 'Phone',
    tagline: 'Calls, call log and blocking',
    icon: Icons.phone_outlined,
    accent: Color(0xFF8B5CF6), // violet
    androidPackage: 'dev.sagron.zerotrustphone',
  );

  static const camera = ZtSuiteApp(
    appId: 'camera',
    name: 'Camera',
    tagline: 'Photos and videos, encrypted as you take them',
    icon: Icons.photo_camera_outlined,
    accent: Color(0xFF14B8A6), // teal
    androidPackage: 'dev.sagron.zerotrustcamera',
  );

  static const gallery = ZtSuiteApp(
    appId: 'gallery',
    name: 'Gallery',
    tagline: 'Your photos and albums',
    icon: Icons.photo_library_outlined,
    accent: Color(0xFF8B5CF6), // violet
    androidPackage: 'dev.sagron.zerotrustgallery',
  );

  static const home = ZtSuiteApp(
    appId: 'home',
    name: 'Home',
    tagline: 'Your smart home',
    icon: Icons.home_outlined,
    accent: Color(0xFFF59E0B), // amber
    androidPackage: 'dev.sagron.zerotrusthome',
  );

  static const family = ZtSuiteApp(
    appId: 'family',
    name: 'Family',
    tagline: 'Your family circle and shared locations',
    icon: Icons.family_restroom,
    accent: Color(0xFF14B8A6), // teal
    androidPackage: 'dev.sagron.zerotrustfamily',
  );

  static const meds = ZtSuiteApp(
    appId: 'meds',
    name: 'Meds',
    tagline: 'Medications, doses and reminders',
    icon: Icons.medication_outlined,
    accent: Color(0xFFEF4444), // red
    androidPackage: 'dev.sagron.zerotrustmeds',
  );

  static const keyboard = ZtSuiteApp(
    appId: 'keyboard',
    name: 'Keyboard',
    tagline: 'A private keyboard',
    icon: Icons.keyboard_outlined,
    accent: Color(0xFF22C55E), // green
    androidPackage: 'dev.sagron.zerotrustkeyboard',
  );

  static const authenticator = ZtSuiteApp(
    appId: 'authenticator',
    name: 'Authenticator',
    tagline: 'Two-step sign-in codes',
    icon: Icons.verified_user_outlined,
    accent: Color(0xFF0EA5E9), // sky
    androidPackage: 'dev.sagron.zerotrustauthenticator',
    available: false, // not out yet
  );

  /// Every app, in the website's order.
  static const List<ZtSuiteApp> apps = [
    notes,
    tasks,
    fitness,
    contacts,
    calendar,
    browser,
    phone,
    time,
    quests,
    camera,
    gallery,
    home,
    clock,
    family,
    meds,
    keyboard,
    authenticator,
  ];

  static ZtSuiteApp? byId(String appId) {
    for (final app in apps) {
      if (app.appId == appId) return app;
    }
    return null;
  }

  /// The app with this Android application id, or null.
  static ZtSuiteApp? byPackage(String androidPackage) {
    for (final app in apps) {
      if (app.androidPackage == androidPackage) return app;
    }
    return null;
  }
}
