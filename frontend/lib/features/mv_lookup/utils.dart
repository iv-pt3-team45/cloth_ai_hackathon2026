// MV 検索機能の中で共通に使う、JSON の読み取りと日付の表示。

Map<String, dynamic> jsonMap(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

List<dynamic> jsonList(Object? value) => value is List ? value : const [];

List<String> jsonStrings(Object? value) =>
    jsonList(value).whereType<String>().toList();

List<int> jsonInts(Object? value) => jsonList(value).whereType<int>().toList();

/// 例: 2023/06/04
String formatDate(DateTime date) {
  final local = date.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)}';
}

/// バックエンドに送る日付(YYYY-MM-DD)。
String isoDate(DateTime date) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${date.year.toString().padLeft(4, '0')}-${two(date.month)}-${two(date.day)}';
}
