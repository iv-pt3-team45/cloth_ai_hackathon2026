# 実装タスク: 画面の作り直し(tadasii のデザインに合わせる)

- 対応する設計: `./design.md`
- 進捗: 9 / 10

## 凡例

- 1 タスク = 30〜90 分。テストまで含めて「動く状態」で終えられる粒度にする。
- 各タスクに「完了条件」と「関連する受け入れ基準(AC-x)」を書く。
- 完了したら `- [ ]` を `- [x]` にする。
- バックエンドは変えない(AC-20)。各タスクの終わりに `dart format .` / `flutter analyze` / `flutter test` を通す。

## タスク一覧

### 土台

- [x] **T-01: テーマ・共通部品・Web のアセット**
  - 変更対象: `frontend/lib/core/theme.dart`, `frontend/lib/core/widgets.dart`, `frontend/lib/main.dart`, `frontend/web/`(index.html・manifest.json・favicon・icons)
  - 完了条件: tadasii の配色・`SectionCard`・`Hint`・`Pill`・`Bullets`・`MessageBox` が使え、タイトルとアイコンが「はじめてのライブ服」のものになる
  - 関連 AC: AC-15, AC-16
- [x] **T-02: 出典のリンク(`url_launcher`)と検索候補の表示**
  - 変更対象: `frontend/pubspec.yaml`, `frontend/lib/core/link.dart`, `features/mv_lookup/grounding_footer.dart`, `search_suggestions_view_web.dart`
  - 完了条件: 「参照した情報源:」のリンクをタップで開ける。検索候補の HTML が空でも空の枠が出ない
  - 関連 AC: AC-18

### 入力のカード

- [x] **T-03: ① MV を選ぶ / ② 行くライブを検索(`MvLookupPanel`)**
  - 変更対象: `features/mv_lookup/mv_lookup_panel.dart`(`mv_lookup_screen.dart` を置き換え), `live_section.dart`, `culture_section.dart`, 関係するテスト
  - 完了条件: 今の MV・カルチャー・ライブのテストを新しい表示に移して通る。ライブの「詳細検索(任意)」の公演日、選んだ候補だけの表示と「変更」のテストが通る
  - 関連 AC: AC-3, AC-4
- [x] **T-04: ③ 手持ちの服(`WardrobeSection`)と確認画面の見た目**
  - 変更対象: `features/wardrobe/wardrobe_section.dart`(`wardrobe_screen.dart` を置き換え), `wardrobe_review_screen.dart`, 関係するテスト
  - 完了条件: 格子・属性のシート・削除(確認あり)・0 件・読み込み失敗・保存後の読み直しのテストが通る
  - 関連 AC: AC-5

### コーデ提案

- [x] **T-05: `OutfitController`**
  - 変更対象: `features/outfit/outfit_controller.dart`, `test/outfit_controller_test.dart`
  - 完了条件: 提案 → 画像の順、画像だけの失敗、提案の失敗、キャンセル後の結果を捨てる、作り直しのテストが通る
  - 関連 AC: AC-9, AC-12, AC-13
- [x] **T-06: 進捗の画面と結果の画面**
  - 変更対象: `features/outfit/outfit_progress_view.dart`, `outfit_result_view.dart`, `save_image*.dart`, テスト
  - 完了条件: 段階と経過時間の表示、結果の各項目、画像の拡大、Web 以外で保存ボタンを出さないことのテストが通る
  - 関連 AC: AC-8, AC-10, AC-11, AC-12

### 画面の組み立て

- [x] **T-07: `HomePage`(ヘッダー・段階・送信バー・メッセージ)と旧画面の削除**
  - 変更対象: `frontend/lib/app/home_page.dart`, `frontend/lib/main.dart`, `features/outfit/confirm_screen.dart`・`wardrobe_strip.dart`(削除), テスト
  - 完了条件: 段階の切り替え・チェックリスト・足りないときのエラー 4 種・キャンセル・提案の失敗・「条件を変えてもう一度」で入力が残ることのテストが通る。下部のタブが無い。`flutter build web --release` が通る
  - 関連 AC: AC-1, AC-2, AC-6, AC-7, AC-9, AC-13, AC-14, AC-17, AC-19

### 仕上げ

- [x] **T-08: ドキュメント更新**
  - 変更対象: `README.md`, `docs/spec/011-outfit-suggestion/requirements.md`
  - 完了条件: README の画面の説明・構成・依存が実装と一致している。spec 011 に置き換えの旨を書く
- [x] **T-09: ブラウザでの目視確認(縦画面)**
  - 完了条件: 幅 390px の縦画面で、tadasii の画面イメージと見比べて各段階を確認し、スクリーンショットを `docs/screenshot/`(Git 管理外)に保存する。実際の API(MV・カルチャー・ライブ・服の解析・提案・画像)で 1 回通す
  - 関連 AC: AC-15, AC-17
  - 結果(2026-10-05): 幅 390px の Edge(ヘッドレス)で、MV「YOASOBI アイドル」→ カルチャー情報 → ライブ「電光石火」(名古屋公演を選択)→
    手持ちの服(サンプル 12 点の複製)→ 写真の解析(保存せずに閉じる)→ 提案 → 結果 を実 API で通した。スクリーンショットは
    `docs/screenshot/015-*.png`(21 枚)。tadasii の画面イメージ(入力・エラー・検索結果・選択・服の写真・進捗)と見た目が一致した。
    - 1 回目の提案は画像の生成だけが失敗し(このブランチのバックエンドは `fix/image-create-bug` を含まない)、結果の画面の「画像を作り直す」が
      期待どおりに出た。修正版のバックエンドでも同じ組み合わせ(服 5 点)は `NO_IMAGE` だったが、「条件を変えてもう一度」で
      作り直した提案(服 3 点)は画像ができ、拡大・保存のボタンも確認した。
    - 見つけた問題: 画像だけ失敗しても進捗の画面が「できました」と出ていた → 失敗の表示に直した(design.md 5.6)。

- [ ] **T-10: ユーザーによる確認**
  - 完了条件: ユーザーが画面を確認する。確認後に `requirements.md` のステータスを `done` にする
