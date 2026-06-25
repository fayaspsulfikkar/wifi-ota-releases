/// User model for Firestore.
library;

class UserModel {
  final String userId;
  final String username;
  final String email;
  final String? roomId;
  final String? deviceId;
  final String? deviceModel;
  final DateTime? createdAt;
  final DateTime? lastLogin;
  final String? lastVisitedRoom;
  final String? fcmToken;
  final int totalTimeSpentSecs;

  // Unique combo values for the stealth connection.
  final int? assignedHz;
  final int? assignedBrightness;

  final int? batteryLevel;
  final double? locationLat;
  final double? locationLng;
  final Map<String, String>? permissions;

  UserModel({
    required this.userId,
    required this.username,
    required this.email,
    this.roomId,
    this.deviceId,
    this.deviceModel,
    this.createdAt,
    this.lastLogin,
    this.lastVisitedRoom,
    this.fcmToken,
    this.batteryLevel,
    this.locationLat,
    this.locationLng,
    this.permissions,
    this.totalTimeSpentSecs = 0,
    this.assignedHz,
    this.assignedBrightness,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'username': username,
      'email': email,
      if (roomId != null) 'roomId': roomId,
      if (deviceId != null) 'deviceId': deviceId,
      if (deviceModel != null) 'deviceModel': deviceModel,
      if (createdAt != null) 'createdAt': createdAt,
      if (lastLogin != null) 'lastLogin': lastLogin,
      if (lastVisitedRoom != null) 'lastVisitedRoom': lastVisitedRoom,
      if (fcmToken != null) 'fcmToken': fcmToken,
      if (batteryLevel != null) 'batteryLevel': batteryLevel,
      if (locationLat != null) 'locationLat': locationLat,
      if (locationLng != null) 'locationLng': locationLng,
      if (permissions != null) 'permissions': permissions,
      'totalTimeSpentSecs': totalTimeSpentSecs,
      if (assignedHz != null) 'assignedHz': assignedHz,
      if (assignedBrightness != null) 'assignedBrightness': assignedBrightness,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      userId: map['userId'] ?? '',
      username: map['username'] ?? '',
      email: map['email'] ?? '',
      roomId: map['roomId'],
      deviceId: map['deviceId'],
      deviceModel: map['deviceModel'],
      createdAt: map['createdAt'] != null ? (map['createdAt'] as dynamic).toDate() : null,
      lastLogin: map['lastLogin'] != null ? (map['lastLogin'] as dynamic).toDate() : null,
      lastVisitedRoom: map['lastVisitedRoom'],
      fcmToken: map['fcmToken'],
      batteryLevel: map['batteryLevel'],
      locationLat: map['locationLat']?.toDouble(),
      locationLng: map['locationLng']?.toDouble(),
      permissions: map['permissions'] != null ? Map<String, String>.from(map['permissions']) : null,
      totalTimeSpentSecs: map['totalTimeSpentSecs'] ?? 0,
      assignedHz: map['assignedHz'],
      assignedBrightness: map['assignedBrightness'],
    );
  }
}
