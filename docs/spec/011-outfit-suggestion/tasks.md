# 実装タスク: 情報の確認タブと、手持ちの服からのコーデ提案

- 対応する設計: `./design.md`
- 進捗: 8 / 9

## 凡例

- 1 タスク = 30〜90 分。テストまで含めて「動く状態」で終えられる粒度にする。
- 各タスクに「完了条件」と「関連する受け入れ基準(AC-x)」を書く。
- 完了したら `- [ ]` を `- [x]` にする。

## タスク一覧

### バックエンド

- [x] **T-01: マネキン画像の移動・設定・スキーマ**
  - 変更対象: `backend/app/assets/white_manekin.jpeg`(移動), `backend/app/core/config.py`, `backend/.env.example`, `backend/app/schemas/outfit.py`
  - 完了条件: マネキン画像が Git の管理下にあり、`OUTFIT_MODEL` / `OUTFIT_TIMEOUT` / `OUTFIT_MANNEQUIN_PATH` を読める
  - 関連 AC: —
- [x] **T-02: 提案(プロンプト・構造化出力・手持ち以外の除外)**
  - 変更対象: `backend/app/services/outfit.py`, `backend/tests/test_outfit_service.py`
  - 完了条件: プロンプトの組み立てと、除外・エラーのテストが通る
  - 関連 AC: AC-9, AC-10, AC-13, AC-15
- [x] **T-03: 画像の生成とエンドポイント**
  - 変更対象: `backend/app/services/outfit.py`, `backend/app/api/routes/outfit.py`, `backend/app/api/router.py`, `backend/tests/test_outfit_service.py`, `backend/tests/test_outfit_api.py`
  - 完了条件: 画像の入力の組み立て・取り出し・保存とエラー、ルータのテストが通る。ruff / mypy が通る
  - 関連 AC: AC-10, AC-11, AC-13, AC-15

### フロントエンド

- [x] **T-04: MV 検索タブの状態の要約とタブの追加**
  - 変更対象: `frontend/lib/features/mv_lookup/mv_lookup_snapshot.dart`, `mv_lookup_screen.dart`, `frontend/lib/main.dart`, `frontend/test/mv_lookup_snapshot_test.dart`
  - 完了条件: 動画の表示・ライブの選択で要約が出るテストが通る
  - 関連 AC: AC-1, AC-7
- [x] **T-05: モデル / Repository / 手持ちの服の横並び**
  - 変更対象: `frontend/lib/features/outfit/outfit_models.dart`, `outfit_repository.dart`, `wardrobe_strip.dart`, `frontend/test/outfit_models_test.dart`
  - 完了条件: `fromJson` のテストが通る
  - 関連 AC: AC-5
- [x] **T-06: 確認タブ(表示とコーデ提案)**
  - 変更対象: `frontend/lib/features/outfit/confirm_screen.dart`, `frontend/test/confirm_screen_test.dart`
  - 完了条件: `dart format .` / `flutter analyze`(警告 0)/ `flutter test` が通る。Web 向けビルドが通る
  - 関連 AC: AC-2〜AC-14

### 結合 / 仕上げ

- [x] **T-07: ドキュメント更新**
  - 変更対象: `README.md`
  - 完了条件: README の記述と実装が一致している
- [x] **T-08: 実 API での確認**
  - 完了条件: 実際の手持ちの服・MV・ライブで提案と画像の生成を 1 回行い、手持ちの服だけで提案され、マネキンに着せた画像ができることを確かめる
  - 結果(2026-10-02): サンプルの服 5 点(`tests/sample_cloth_indexs` の複製)と、YOASOBI の MV・12 月のアリーナ公演(曇り 7℃ / 1℃)で実施。
    提案は 2 回とも、白または黒の T シャツ + チェックシャツ + ブラックジーンズ(すべて手持ち。除外 0)。
    画像は写真 3 枚の柄・色を再現してマネキンに着せ、姿勢・台・背景も保たれた。
    1 回目だけ画像が返らず 502 になった(同じ入力の再試行 3 回はすべて成功)。原因を追えるよう終了理由をログに残すようにした(design.md 7.)
- [ ] **T-09: ブラウザでの目視確認**
  - 完了条件: Web アプリで確認タブの表示とコーデ提案を目視で確認する(ユーザーが実施)。確認後に `requirements.md` のステータスを `done` にする
