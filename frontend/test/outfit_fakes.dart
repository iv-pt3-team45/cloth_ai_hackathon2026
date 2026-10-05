import 'package:tx_hackathon_gc/features/mv_lookup/culture_models.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/live_models.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/mv_lookup_snapshot.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/mv_models.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/venue_models.dart';
import 'package:tx_hackathon_gc/features/outfit/outfit_models.dart';
import 'package:tx_hackathon_gc/features/outfit/outfit_repository.dart';
import 'package:tx_hackathon_gc/features/wardrobe/wardrobe_models.dart';

import 'mv_lookup_fakes.dart';
import 'wardrobe_fakes.dart';

const confirmVideo = MvVideo(
  videoId: 'abcDEF12345',
  url: 'https://www.youtube.com/watch?v=abcDEF12345',
  artist: 'YOASOBI',
  songTitle: 'アイドル',
  titleParsed: true,
  title: 'YOASOBI「アイドル」 Official Music Video',
  channelTitle: 'YOASOBI',
);

const ownedShirt = RegisteredCloth(
  id: 'shirt',
  image: 'a.png',
  attributes: shirt,
);
const ownedJeans = RegisteredCloth(
  id: 'jeans',
  image: 'a.png',
  attributes: jeans,
);

/// MV・カルチャー・ライブの選択がそろった状態。
MvLookupSnapshot fullSnapshot({
  LiveCandidate? selectedLive,
  VenueFormat? venueFormat,
  bool venueFormatLoading = false,
}) {
  final lives = liveResult();
  return MvLookupSnapshot(
    mvQuery: 'アイドル',
    video: confirmVideo,
    culture: fullReport,
    liveQuery: '電光石火',
    liveDate: DateTime(2023, 6, 4),
    liveResult: lives,
    selectedLive: selectedLive ?? lives.candidates.first,
    venueFormat: venueFormat,
    venueFormatLoading: venueFormatLoading,
  );
}

OutfitSuggestion suggestionOf(String title, {int excluded = 0}) =>
    OutfitSuggestion(
      title: title,
      summary: '動きやすいカジュアル',
      points: const ['晴れで暑いため薄手'],
      items: const [
        SuggestedCloth(cloth: ownedShirt, role: 'トップス', reason: '白で合わせやすい'),
        SuggestedCloth(cloth: ownedJeans, role: 'ボトムス', reason: '動きやすい'),
      ],
      excludedCount: excluded,
    );

/// 提案の呼び出し 1 回ぶん。
typedef SuggestCall = ({
  MvVideo video,
  LiveCandidate live,
  CultureReport? culture,
  VenueFormat? venueFormat,
});

/// バックエンドを呼ばないコーデ提案のリポジトリ。呼び出しを記録する。
class FakeOutfitRepository implements OutfitRepository {
  FakeOutfitRepository({this.suggestResponder, this.imageResponder});

  Future<OutfitSuggestion> Function()? suggestResponder;
  Future<OutfitImage> Function(List<String> itemIds)? imageResponder;
  final suggestCalls = <SuggestCall>[];
  final imageCalls = <List<String>>[];

  @override
  Future<OutfitSuggestion> suggest({
    required MvVideo video,
    required LiveCandidate live,
    CultureReport? culture,
    VenueFormat? venueFormat,
  }) {
    suggestCalls.add((
      video: video,
      live: live,
      culture: culture,
      venueFormat: venueFormat,
    ));
    return suggestResponder?.call() ??
        Future.value(suggestionOf('晴れの日のライブコーデ', excluded: 1));
  }

  @override
  Future<OutfitImage> generateImage({
    required List<String> itemIds,
    String title = '',
  }) {
    imageCalls.add(itemIds);
    return imageResponder?.call(itemIds) ??
        Future.value(OutfitImage(bytes: pngBytes, mimeType: 'image/png'));
  }
}
