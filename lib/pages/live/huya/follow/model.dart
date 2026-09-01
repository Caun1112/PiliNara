import 'package:simple_live_core/simple_live_core.dart';

class HuyaFollowUser {
  const HuyaFollowUser({
    required this.roomId,
    required this.userName,
    required this.face,
    required this.title,
    required this.cover,
    required this.addTime,
  });

  final String roomId;
  final String userName;
  final String face;
  final String title;
  final String cover;
  final DateTime addTime;

  factory HuyaFollowUser.fromDetail(LiveRoomDetail detail) {
    return HuyaFollowUser(
      roomId: detail.roomId,
      userName: detail.userName,
      face: detail.userAvatar,
      title: detail.title,
      cover: detail.cover,
      addTime: DateTime.now(),
    );
  }

  factory HuyaFollowUser.fromJson(Map<dynamic, dynamic> json) {
    return HuyaFollowUser(
      roomId: json['roomId']?.toString() ?? '',
      userName: json['userName']?.toString() ?? '',
      face: json['face']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      cover: json['cover']?.toString() ?? '',
      addTime:
          DateTime.tryParse(json['addTime']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  HuyaFollowUser updateFromDetail(LiveRoomDetail detail) {
    return HuyaFollowUser(
      roomId: detail.roomId,
      userName: detail.userName,
      face: detail.userAvatar,
      title: detail.title,
      cover: detail.cover,
      addTime: addTime,
    );
  }

  Map<String, dynamic> toJson() => {
    'roomId': roomId,
    'userName': userName,
    'face': face,
    'title': title,
    'cover': cover,
    'addTime': addTime.toIso8601String(),
  };
}
