import 'dart:convert';
import 'dart:typed_data';

/// Device-local preferences. Account email and credentials remain server-owned.
class ProfilePreferences {
  const ProfilePreferences({
    this.fullName = '',
    this.avatarAsset = defaultAvatar,
    this.avatarBase64,
    this.deviceNotifications = true,
    this.expiryReminders = true,
    this.daysBeforeExpiry = 3,
    this.dailyCheckIn = true,
    this.notificationHour = 9,
    this.notificationMinute = 0,
  });

  static const defaultAvatar = 'assets/images/avatars/default_avatar.png';
  final String fullName;
  final String avatarAsset;
  final String? avatarBase64;
  final bool deviceNotifications;
  final bool expiryReminders;
  final int daysBeforeExpiry;
  final bool dailyCheckIn;
  final int notificationHour;
  final int notificationMinute;

  Uint8List? get avatarBytes =>
      avatarBase64 == null ? null : base64Decode(avatarBase64!);

  ProfilePreferences withIdentity({
    required String fullName,
    required String avatarAsset,
    Uint8List? avatarBytes,
  }) => ProfilePreferences(
    fullName: fullName,
    avatarAsset: avatarAsset,
    avatarBase64: avatarBytes == null ? null : base64Encode(avatarBytes),
    deviceNotifications: deviceNotifications,
    expiryReminders: expiryReminders,
    daysBeforeExpiry: daysBeforeExpiry,
    dailyCheckIn: dailyCheckIn,
    notificationHour: notificationHour,
    notificationMinute: notificationMinute,
  );

  ProfilePreferences withReminders({
    bool? deviceNotifications,
    bool? expiryReminders,
    int? daysBeforeExpiry,
    bool? dailyCheckIn,
    int? notificationHour,
    int? notificationMinute,
  }) => ProfilePreferences(
    fullName: fullName,
    avatarAsset: avatarAsset,
    avatarBase64: avatarBase64,
    deviceNotifications: deviceNotifications ?? this.deviceNotifications,
    expiryReminders: expiryReminders ?? this.expiryReminders,
    daysBeforeExpiry: daysBeforeExpiry ?? this.daysBeforeExpiry,
    dailyCheckIn: dailyCheckIn ?? this.dailyCheckIn,
    notificationHour: notificationHour ?? this.notificationHour,
    notificationMinute: notificationMinute ?? this.notificationMinute,
  );

  factory ProfilePreferences.fromJson(Map<String, dynamic> json) {
    final avatar = json['avatar_base64'] as String?;
    if (avatar != null) base64Decode(avatar);
    return ProfilePreferences(
      fullName: json['full_name'] as String? ?? '',
      avatarAsset: json['avatar_asset'] as String? ?? defaultAvatar,
      avatarBase64: avatar,
      deviceNotifications: json['device_notifications'] as bool? ?? true,
      expiryReminders: json['expiry_reminders'] as bool? ?? true,
      daysBeforeExpiry: (json['days_before_expiry'] as int? ?? 3).clamp(1, 7),
      dailyCheckIn: json['daily_check_in'] as bool? ?? true,
      notificationHour: (json['notification_hour'] as int? ?? 9).clamp(0, 23),
      notificationMinute: (json['notification_minute'] as int? ?? 0).clamp(
        0,
        59,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'full_name': fullName,
    'avatar_asset': avatarAsset,
    'avatar_base64': avatarBase64,
    'device_notifications': deviceNotifications,
    'expiry_reminders': expiryReminders,
    'days_before_expiry': daysBeforeExpiry,
    'daily_check_in': dailyCheckIn,
    'notification_hour': notificationHour,
    'notification_minute': notificationMinute,
  };
}

/// The design uses requests; backend voice seconds must not be cast to requests.
class VoiceUsage {
  const VoiceUsage({
    required this.used,
    required this.limit,
    required this.period,
    required this.resetsAt,
  }) : assert(used >= 0),
       assert(limit >= 0);

  final int used;
  final int limit;
  final DateTime period;
  final DateTime resetsAt;
  int get remaining => (limit - used).clamp(0, limit);
  double get fraction => limit == 0 ? 0 : (used / limit).clamp(0, 1);
}
