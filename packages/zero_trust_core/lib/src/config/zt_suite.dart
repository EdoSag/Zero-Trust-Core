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

  String get fullName => 'Zero-Trust $name';

  Uri get playStoreUrl => Uri.https(
      'play.google.com', '/store/apps/details', {'id': androidPackage});

  /// Opens the app when installed (Android `market://` falls back to the
  /// store app otherwise).
  Uri get marketUrl => Uri.parse('market://details?id=$androidPackage');
}

abstract final class ZtSuite {
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
    icon: Icons.task_alt,
    accent: Color(0xFF3B82F6), // blue
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

  static const List<ZtSuiteApp> apps = [notes, tasks, fitness, contacts];

  static ZtSuiteApp? byId(String appId) {
    for (final app in apps) {
      if (app.appId == appId) return app;
    }
    return null;
  }
}
