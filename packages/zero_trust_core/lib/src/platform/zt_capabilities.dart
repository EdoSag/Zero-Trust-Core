import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where the app is running.
enum ZtPlatformKind { android, ios, web, windows, macos, linux }

/// What the platform the app runs on can do, so one codebase can hide a
/// feature where it has no meaning (a home screen widget in a browser)
/// instead of crashing or showing a button that does nothing.
///
/// Ask for the feature, never for the platform: `caps.homeScreenWidgets`,
/// not `caps.isWeb`. Read it through [ztCapabilitiesProvider] so tests and
/// previews can pretend to be another platform.
@immutable
class ZtCapabilities {
  const ZtCapabilities(this.platform);

  /// The platform this build is running on.
  factory ZtCapabilities.current() => ZtCapabilities(kIsWeb
      ? ZtPlatformKind.web
      : switch (defaultTargetPlatform) {
          TargetPlatform.android => ZtPlatformKind.android,
          TargetPlatform.iOS => ZtPlatformKind.ios,
          TargetPlatform.windows => ZtPlatformKind.windows,
          TargetPlatform.macOS => ZtPlatformKind.macos,
          TargetPlatform.linux ||
          TargetPlatform.fuchsia =>
            ZtPlatformKind.linux,
        });

  final ZtPlatformKind platform;

  /// Runs in a browser tab (also when installed from the browser).
  bool get isWeb => platform == ZtPlatformKind.web;

  /// A phone or tablet app.
  bool get isMobile =>
      platform == ZtPlatformKind.android || platform == ZtPlatformKind.ios;

  /// A Windows, macOS or Linux app.
  bool get isDesktop => !isWeb && !isMobile;

  /// Home screen widgets.
  bool get homeScreenWidgets => isMobile;

  /// Reminders and alarms that fire while the app is closed.
  bool get scheduledNotifications => isMobile;

  /// Fingerprint or face unlock backed by a hardware key store.
  bool get biometricUnlock => isMobile;

  /// Speech recognition that stays on the device. Browsers send speech to
  /// their maker's servers, so voice input is off there.
  bool get onDeviceSpeech => isMobile;

  /// Text recognition (OCR) on the device.
  bool get onDeviceTextRecognition => isMobile;

  /// Scanning a QR code or a document with the camera.
  bool get cameraScanning => isMobile;

  /// The phone's own data and services: its address book, calls, SMS,
  /// health sensors, GPS tracking in the background.
  bool get phoneIntegration => isMobile;

  /// The system share sheet ("Share to...").
  bool get shareSheet => isMobile;

  /// Files the user exports are handed over as a browser download.
  bool get exportsByDownload => isWeb;

  /// "Remember on this browser" and "Sign out and remove data from this
  /// browser" make sense.
  bool get browserSession => isWeb;

  @override
  bool operator ==(Object other) =>
      other is ZtCapabilities && other.platform == platform;

  @override
  int get hashCode => platform.hashCode;

  @override
  String toString() => 'ZtCapabilities(${platform.name})';
}

/// The running platform's [ZtCapabilities]. Override it in tests to check
/// how a screen looks on the web or on desktop.
final ztCapabilitiesProvider =
    Provider<ZtCapabilities>((ref) => ZtCapabilities.current());
