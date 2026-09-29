/// 1 本の動画のメタ情報。バックエンドの VideoInfo と対応する。
class MvVideo {
  const MvVideo({
    required this.videoId,
    required this.url,
    required this.artist,
    required this.songTitle,
    required this.titleParsed,
    required this.title,
    required this.channelTitle,
    this.publishedAt,
    this.thumbnailUrl = '',
    this.description = '',
  });

  final String videoId;

  /// 動画のリンク(https://www.youtube.com/watch?v=...)
  final String url;

  /// アーティスト名(分解できなければチャンネル名)
  final String artist;

  /// 曲名(分解できなければ動画タイトル)
  final String songTitle;

  /// タイトルからアーティスト名・曲名を分解できたか
  final bool titleParsed;

  /// 動画タイトル(YouTube の値そのまま)
  final String title;

  /// チャンネル名(YouTube の値そのまま)
  final String channelTitle;

  final DateTime? publishedAt;
  final String thumbnailUrl;

  /// 概要欄
  final String description;

  factory MvVideo.fromJson(Map<String, dynamic> json) => MvVideo(
    videoId: json['video_id'] as String,
    url: json['url'] as String,
    artist: json['artist'] as String,
    songTitle: json['song_title'] as String,
    titleParsed: json['title_parsed'] as bool,
    title: json['title'] as String,
    channelTitle: json['channel_title'] as String,
    publishedAt: _parseDate(json['published_at']),
    thumbnailUrl: json['thumbnail_url'] as String? ?? '',
    description: json['description'] as String? ?? '',
  );

  /// バックエンドの VideoInfo の形。カルチャー情報の取得で送り返す。
  Map<String, dynamic> toJson() => {
    'video_id': videoId,
    'url': url,
    'artist': artist,
    'song_title': songTitle,
    'title_parsed': titleParsed,
    'title': title,
    'channel_title': channelTitle,
    'published_at': publishedAt?.toUtc().toIso8601String(),
    'thumbnail_url': thumbnailUrl,
    'description': description,
  };
}

/// MV 名で検索したときの候補 1 件。バックエンドの VideoCandidate と対応する。
class MvCandidate {
  const MvCandidate({
    required this.videoId,
    required this.url,
    required this.title,
    required this.channelTitle,
    this.publishedAt,
    this.thumbnailUrl = '',
  });

  final String videoId;
  final String url;
  final String title;
  final String channelTitle;
  final DateTime? publishedAt;
  final String thumbnailUrl;

  factory MvCandidate.fromJson(Map<String, dynamic> json) => MvCandidate(
    videoId: json['video_id'] as String,
    url: json['url'] as String,
    title: json['title'] as String,
    channelTitle: json['channel_title'] as String,
    publishedAt: _parseDate(json['published_at']),
    thumbnailUrl: json['thumbnail_url'] as String? ?? '',
  );
}

/// 検索結果。URL を入力したら [video]、MV 名を入力したら [candidates] が入る。
class MvLookupResult {
  const MvLookupResult({
    required this.inputType,
    this.video,
    this.candidates = const [],
  });

  /// 'url' または 'keyword'
  final String inputType;
  final MvVideo? video;
  final List<MvCandidate> candidates;

  factory MvLookupResult.fromJson(Map<String, dynamic> json) {
    final video = json['video'];
    final candidates = json['candidates'] as List<dynamic>? ?? const [];
    return MvLookupResult(
      inputType: json['input_type'] as String,
      video: video is Map<String, dynamic> ? MvVideo.fromJson(video) : null,
      candidates: candidates
          .map((c) => MvCandidate.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }
}

DateTime? _parseDate(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
