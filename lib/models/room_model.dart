/// Room model for Firestore.
///
/// A room groups two users together for a persistent voice connection.
library;

class RoomModel {
  final String roomId;
  final String roomName;
  final String ownerId;
  final List<String> memberIds;

  RoomModel({
    required this.roomId,
    required this.roomName,
    required this.ownerId,
    required this.memberIds,
  });

  Map<String, dynamic> toMap() {
    return {
      'roomId': roomId,
      'roomName': roomName,
      'ownerId': ownerId,
      'memberIds': memberIds,
    };
  }

  factory RoomModel.fromMap(Map<String, dynamic> map) {
    return RoomModel(
      roomId: map['roomId'] ?? '',
      roomName: map['roomName'] ?? '',
      ownerId: map['ownerId'] ?? '',
      memberIds: List<String>.from(map['memberIds'] ?? []),
    );
  }
}
