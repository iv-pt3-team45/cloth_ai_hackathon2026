import 'package:flutter_test/flutter_test.dart';
import 'package:tx_hackathon_gc/features/mv_lookup/venue_models.dart';

void main() {
  test('API の値から会場の形態を作る(spec 014)', () {
    expect(VenueFormat.fromValue('standing'), VenueFormat.standing);
    expect(VenueFormat.fromValue('seated'), VenueFormat.seated);
    expect(VenueFormat.fromValue('mixed'), VenueFormat.mixed);
    expect(VenueFormat.fromValue('unknown'), VenueFormat.unknown);
  });

  test('知らない値や null は不明として扱う', () {
    expect(VenueFormat.fromValue('sitting'), VenueFormat.unknown);
    expect(VenueFormat.fromValue(null), VenueFormat.unknown);
  });

  test('表示名', () {
    expect(VenueFormat.standing.label, 'スタンディング(立ち見)');
    expect(VenueFormat.seated.label, '着席(座席あり)');
    expect(VenueFormat.mixed.label, 'スタンディングと着席の両方あり(チケットによって異なる)');
    expect(VenueFormat.unknown.label, '不明');
  });
}
