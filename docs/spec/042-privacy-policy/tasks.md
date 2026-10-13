# 実装タスク: プライバシーポリシーの画面

- 対応する設計: `./design.md`
- 進捗: 4 / 4

## 凡例

- 1 タスク = 30〜90 分。テストまで含めて「動く状態」で終えられる粒度にする。
- 完了したら `- [ ]` を `- [x]` にする。

## タスク一覧

### フロントエンド

- [x] **T-01: ポリシーの文(`privacy_policy.dart`)**
  - 変更対象: `frontend/lib/features/privacy/privacy_policy.dart`
  - 完了条件: 11 の節が設計 4.2 の内容で入っている。運営者・制定日が定数になっている
  - 関連 AC: AC-4
- [x] **T-02: ポリシーの画面とリンク(`privacy_policy_screen.dart`)**
  - 変更対象: `frontend/lib/features/privacy/privacy_policy_screen.dart`
  - 完了条件: 画面が今のデザインで表示され、← で戻れる。リンクは 12px・灰色・下線
  - 関連 AC: AC-2, AC-3
- [x] **T-03: 初期ページにリンクを置く・テスト**
  - 変更対象: `frontend/lib/app/home_page.dart`, `frontend/test/privacy_policy_test.dart`, `frontend/test/home_page_test.dart`
  - 完了条件: 設計 6. のテストが通る。`dart format` / `flutter analyze` / `flutter test` が通る
  - 関連 AC: AC-1, AC-2, AC-3, AC-4, AC-5, AC-6

### 仕上げ

- [x] **T-04: ドキュメント更新・画面での確認**
  - 変更対象: `README.md`
  - 完了条件: README の §2.4・§4.12・§4.15・§6 が実装と一致している。ブラウザ(スマホの幅)でリンクと画面を確かめる
  - 関連 AC: AC-7
