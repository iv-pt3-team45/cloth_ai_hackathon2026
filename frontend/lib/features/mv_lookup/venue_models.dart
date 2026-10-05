/// 会場の形態(spec 014)。バックエンドの VenueFormat と対応する。
enum VenueFormat {
  standing('standing', 'スタンディング(立ち見)'),
  seated('seated', '着席(座席あり)'),
  mixed('mixed', 'スタンディングと着席の両方あり(チケットによって異なる)'),
  unknown('unknown', '不明');

  const VenueFormat(this.value, this.label);

  /// API の値
  final String value;

  /// 確認タブに出す表示名
  final String label;

  /// API の値から作る。知らない値は unknown として扱う
  static VenueFormat fromValue(Object? value) => VenueFormat.values.firstWhere(
    (f) => f.value == value,
    orElse: () => VenueFormat.unknown,
  );
}
