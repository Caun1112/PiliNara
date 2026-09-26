class RoomInfo {
  int? uid;
  int? roomId;
  int? liveStatus;
  String? title;
  String? cover;
  String? appBackground;

  RoomInfo({
    this.uid,
    this.roomId,
    this.liveStatus,
    this.title,
    this.cover,
    this.appBackground,
  });

  factory RoomInfo.fromJson(Map<String, dynamic> json) => RoomInfo(
    uid: json['uid'] as int?,
    roomId: json['room_id'] as int?,
    liveStatus: json['live_status'] as int?,
    title: json['title'] as String?,
    cover: json['cover'] as String?,
    appBackground: json['app_background'] as String?,
  );
}
