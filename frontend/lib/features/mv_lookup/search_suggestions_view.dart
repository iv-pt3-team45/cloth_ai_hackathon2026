// Google 検索の検索候補(Search Suggestions)の表示。
// Web では API が返した HTML をそのまま描画し、それ以外(テスト・モバイル)では検索クエリを文字で出す。
export 'search_suggestions_view_stub.dart'
    if (dart.library.js_interop) 'search_suggestions_view_web.dart';
