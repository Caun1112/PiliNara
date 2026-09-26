import 'package:PiliPlus/models_new/live/live_room_info_h5/data.dart';

class BiliFollowRoom {
  const BiliFollowRoom({
    required this.roomId,
    required this.userName,
    required this.face,
    required this.title,
    required this.addTime,
  });

  final int roomId;
  final String userName;
  final String face;
  final String title;
  final DateTime addTime;

  factory BiliFollowRoom.fromDetail(
    int roomId,
    RoomInfoH5Data detail, {
    DateTime? addTime,
  }) => BiliFollowRoom(
    roomId: detail.roomInfo?.roomId ?? roomId,
    userName: detail.anchorInfo?.baseInfo?.uname ?? '直播间 $roomId',
    face: detail.anchorInfo?.baseInfo?.face ?? '',
    title: detail.roomInfo?.title ?? '',
    addTime: addTime ?? DateTime.now(),
  );

  factory BiliFollowRoom.fromJson(Map<dynamic, dynamic> json) => BiliFollowRoom(
    roomId: int.tryParse('${json['roomId']}') ?? 0,
    userName: json['userName']?.toString() ?? '',
    face: json['face']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    addTime: DateTime.tryParse('${json['addTime']}') ?? DateTime(1970),
  );

  Map<String, dynamic> toJson() => {
    'roomId': roomId,
    'userName': userName,
    'face': face,
    'title': title,
    'addTime': addTime.toIso8601String(),
  };
}
