import 'dart:convert';

/// One crash, reduced to what helps fix the bug and nothing about the
/// person: no account, email, device id, IP, locale, device model, error
/// message with user text, or exact time. [toText] is exactly what leaves
/// the phone, and the settings screen shows it before anything is sent.
class ZtCrashReport {
  const ZtCrashReport({
    required this.id,
    required this.appId,
    required this.appVersion,
    required this.platform,
    required this.day,
    required this.errorType,
    required this.frames,
    required this.uncaught,
    required this.fingerprint,
    this.message,
    this.library,
    this.count = 1,
  });

  /// Random, only to tell saved reports apart on this phone. Not sent.
  final String id;

  /// `notes`, `tasks`, ... ([ZtAppConfig.appId]).
  final String appId;

  /// The app's version, for example `0.4.1+12`, or empty.
  final String appVersion;

  /// `android`, `ios`, ... (no OS build, which can narrow down a device).
  final String platform;

  /// UTC date `yyyy-mm-dd`. No time of day.
  final String day;

  /// The error's class, for example `TypeError` or `StateError`.
  final String errorType;

  /// Only for programming errors whose text comes from code, not from the
  /// user, and scrubbed again (see [ZtCrashScrubber.message]).
  final String? message;

  /// Which Flutter library reported it ("widgets library"), if Flutter did.
  final String? library;

  /// Stack frames: `function (package:app/file.dart:line:col)` only.
  final List<String> frames;

  /// True for errors no code caught (usually the app stops working), false
  /// for errors Flutter caught while drawing (a grey box on screen).
  final bool uncaught;

  /// Same bug, same fingerprint: groups reports without identifying anyone.
  final String fingerprint;

  /// How many times this same bug happened before it was sent.
  final int count;

  ZtCrashReport copyWith({int? count}) => ZtCrashReport(
        id: id,
        appId: appId,
        appVersion: appVersion,
        platform: platform,
        day: day,
        errorType: errorType,
        message: message,
        library: library,
        frames: frames,
        uncaught: uncaught,
        fingerprint: fingerprint,
        count: count ?? this.count,
      );

  /// What is sent. [id] stays on the phone.
  Map<String, Object?> toPayload() => {
        'app': appId,
        'version': appVersion,
        'platform': platform,
        'day': day,
        'type': errorType,
        if (message != null) 'message': message,
        if (library != null) 'library': library,
        'uncaught': uncaught,
        'fingerprint': fingerprint,
        'count': count,
        'frames': frames,
      };

  Map<String, Object?> toJson() => {'id': id, ...toPayload()};

  factory ZtCrashReport.fromJson(Map<String, Object?> json) => ZtCrashReport(
        id: json['id'] as String,
        appId: json['app'] as String,
        appVersion: json['version'] as String? ?? '',
        platform: json['platform'] as String? ?? '',
        day: json['day'] as String? ?? '',
        errorType: json['type'] as String? ?? 'Object',
        message: json['message'] as String?,
        library: json['library'] as String?,
        frames: [...(json['frames'] as List? ?? const []).cast<String>()],
        uncaught: json['uncaught'] as bool? ?? true,
        fingerprint: json['fingerprint'] as String? ?? '',
        count: json['count'] as int? ?? 1,
      );

  /// The report as people read it in the preview, and as "Copy" copies it.
  String toText() => const JsonEncoder.withIndent('  ').convert(toPayload());
}

/// Turns an error and its stack trace into a [ZtCrashReport] that can't
/// carry user content. Every rule errs on the side of dropping things.
abstract final class ZtCrashScrubber {
  /// Frames kept per report: enough to find the bug.
  static const maxFrames = 25;

  static const maxMessageLength = 160;

  /// Errors raised by code mistakes, whose message is written by a
  /// programmer (`Null check operator used on a null value`, `RangeError
  /// (index): Invalid value: Not in inclusive range 0..2: 3`). Exceptions
  /// such as [FormatException] or a server error often quote the input,
  /// which can be the user's text, so their message is never kept.
  static const _errorsWithSafeMessage = {
    'TypeError',
    '_TypeError',
    'RangeError',
    'IndexError',
    'StateError',
    'UnsupportedError',
    'UnimplementedError',
    'ConcurrentModificationError',
    'StackOverflowError',
    'OutOfMemoryError',
  };

  static ZtCrashReport build({
    required Object error,
    StackTrace? stack,
    required String appId,
    required String appVersion,
    required String platform,
    required DateTime now,
    required String id,
    bool uncaught = true,
    String? library,
  }) {
    final type = typeName(error);
    final frames = ZtCrashScrubber.frames(stack);
    final text = _errorsWithSafeMessage.contains(type)
        ? ZtCrashScrubber.message(error.toString())
        : null;
    final utc = now.toUtc();
    final day = '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';
    return ZtCrashReport(
      id: id,
      appId: appId,
      appVersion: appVersion,
      platform: platform,
      day: day,
      errorType: type,
      message: text,
      library: library == null ? null : _clean(library, 60),
      frames: frames,
      uncaught: uncaught,
      fingerprint: fingerprintOf(appId, type, frames),
    );
  }

  /// The class name, without generic arguments (`List<String>` could name
  /// app types, which is fine, but keeps groups stable).
  static String typeName(Object error) {
    final name = error.runtimeType.toString();
    final cut = name.indexOf('<');
    final plain = cut < 0 ? name : name.substring(0, cut);
    return _clean(plain, 80);
  }

  // `#3      Foo.bar (package:app/x.dart:12:5)`
  static final _symbolic = RegExp(r'^#\d+\s+(.+?)\s+\((.+)\)\s*$');

  // `#05 abs 0000007a1b2c3d4e virt 00000000002c3d4e _kDartIsolateSnapshotInstructions+0x1234`
  // (release builds with --split-debug-info). The absolute address is
  // dropped: it changes with address randomisation and says nothing.
  static final _virtual =
      RegExp(r'^#\d+\s+abs\s+[0-9a-f]+\s+virt\s+([0-9a-f]+)\s*(\S*)');

  static final _location =
      RegExp(r'^(package|dart):[A-Za-z0-9_./-]+(:\d+){0,2}$');

  /// Keeps only the function name and `package:` / `dart:` location of
  /// each frame. File paths (`file:///home/<name>/...`) and anything the
  /// parser doesn't recognise are left out.
  static List<String> frames(StackTrace? stack) {
    if (stack == null) return const [];
    final out = <String>[];
    for (final raw in stack.toString().split('\n')) {
      if (out.length >= maxFrames) break;
      final line = raw.trim();
      if (line.isEmpty) continue;
      final symbolic = _symbolic.firstMatch(line);
      if (symbolic != null) {
        final member = _clean(symbolic.group(1)!, 120);
        final where = symbolic.group(2)!;
        out.add(_location.hasMatch(where) ? '$member ($where)' : member);
        continue;
      }
      final virtual = _virtual.firstMatch(line);
      if (virtual != null) {
        final symbol = _clean(virtual.group(2)!, 80);
        out.add('virt ${virtual.group(1)}${symbol.isEmpty ? '' : ' $symbol'}');
      }
    }
    return out;
  }

  static final _email = RegExp(r'[^\s@]+@[^\s@]+');
  static final _url = RegExp(r'[a-zA-Z][a-zA-Z0-9+.-]*://\S+');
  static final _longNumber = RegExp(r'\d{5,}');
  static final _hex = RegExp(r'\b[0-9a-fA-F-]{16,}\b');
  static final _quoted = RegExp(r'"[^"]*"' "|'[^']*'");
  static final _quotedType = RegExp(r"^'[A-Za-z0-9_<>?, .]*'$");

  /// A programming error's message with anything that could be data taken
  /// out: emails, links, long numbers (phone numbers, ids), hex/uuid ids
  /// and quoted text other than type names (`type 'Null' is not a subtype
  /// of type 'String'` keeps its types; `Bad state: "my note"` doesn't).
  static String? message(String text) {
    var s = text
        .replaceAll(_email, '<email>')
        .replaceAll(_url, '<link>')
        .replaceAll(_hex, '<id>')
        .replaceAll(_longNumber, '<number>');
    s = s.replaceAllMapped(_quoted, (m) {
      final q = m.group(0)!;
      return _quotedType.hasMatch(q) && q.length <= 60 ? q : '<text>';
    });
    s = _clean(s, maxMessageLength);
    return s.isEmpty ? null : s;
  }

  /// One line, printable ASCII, at most [max] characters. Non-ASCII is
  /// dropped because code identifiers don't need it and user text does.
  static String _clean(String s, int max) {
    final b = StringBuffer();
    for (final c in s.runes) {
      if (c >= 0x20 && c < 0x7f) {
        b.writeCharCode(c);
      } else if (c == 0x0a || c == 0x09) {
        b.write(' ');
      }
    }
    final one = b.toString().replaceAll(RegExp(r' {2,}'), ' ').trim();
    return one.length <= max ? one : '${one.substring(0, max)}...';
  }

  /// FNV-1a over the error type and the first frames: the same bug in the
  /// same version gets the same value on every phone.
  static String fingerprintOf(String appId, String type, List<String> frames) {
    var h = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    final input = [appId, type, ...frames.take(6)].join('|');
    for (final unit in utf8.encode(input)) {
      h ^= unit;
      h *= prime; // Wraps at 64 bits on the Dart VM.
    }
    return h.toUnsigned(64).toRadixString(16).padLeft(16, '0');
  }
}
