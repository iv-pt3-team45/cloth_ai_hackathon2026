# 設計: エージェントループ(生成 → 検証 → 再生成)

- 対応する要件: `./requirements.md`
- ステータス: approved
- 更新日: 2026-09-17

## 1. 設計方針

| 案 | 概要 | 採否 | 理由 |
| --- | --- | --- | --- |
| A | ループ制御はアプリ側(Python)で行い、生成は既存エージェント、検証は構造化出力の LLM 判定 | 採用 | 反復回数を確実に制御でき、各周回のログが取れる。検証が必ず実行される |
| B | ADK の `LoopAgent` + `exit_loop` ツールに任せる | 却下 | 停止判断がモデル任せになり、`exit_loop` を呼ばない / 早期に呼ぶ事故が起きうる。経過ログも取りにくい |
| C | 生成のみ繰り返し、検証は人間 | 却下 | 自動化の要件を満たさない |

> B の `LoopAgent` はサブエージェント構成が固まった段階で再検討する余地がある(未決事項 #1)。

## 2. 全体フロー

```
要望 ──┐
       ▼
  ┌─ 生成: AgentService.generate_reply(prompt, history)
  │     └─ 必要なら generate_image / generate_video ツールを呼ぶ(spec 003)
  │  生成物の検出: 保存ディレクトリのスナップショット差分
  │     ▼
  │  検証: verify_result(要望, 応答テキスト, 生成物)
  │     └─ 画像/動画は中身を Part として渡し、構造化 JSON で判定
  │     ▼
  │  satisfied?
  │     ├─ yes → 終了(成功)
  │     └─ no  → 指摘と改善点を次の指示に含めて ──┐
  └────────────────────────────────────────────────┘
        上限回数に達したら終了(未達)
```

## 3. データモデル

| 型 | 内容 |
| --- | --- |
| `Verdict` | `satisfied: bool` / `reason: str` / `improvements: str`(LLM の構造化出力) |
| `LoopStep` | `iteration` / `prompt` / `reply` / `artifact: Path \| None` / `verdict` |
| `LoopResult` | `steps: list[LoopStep]` / `satisfied: bool` / `final_artifact` |

## 4. バックエンド設計

### `app/services/verification.py`(新規)

| 要素 | 役割 |
| --- | --- |
| `Verdict` | 判定結果(pydantic。`response_schema` としてそのまま渡す) |
| `build_verification_parts()` | 要望・応答・生成物を Part 列に組み立てる(生成物は inline bytes) |
| `verify_result()` | 検証モデルを呼び、`Verdict` を返す。失敗時は `satisfied=False` で理由を入れる |

### `app/services/agent_loop.py`(新規)

| 要素 | 役割 |
| --- | --- |
| `snapshot_media_files()` | 生成物ディレクトリのファイル集合を取得 |
| `detect_new_artifact()` | 前後の差分から今回の生成物を特定(複数なら最新) |
| `build_retry_prompt()` | 指摘・改善点を含む再生成の指示文を作る |
| `run_agent_loop()` | ループ本体。`on_step` コールバックで経過を通知する |

**表示はサービス層で行わない。** CLI が `on_step` を受け取って出力する。

### `scripts/run_agent_loop.py`(新規)

```
uv run python scripts/run_agent_loop.py -m "<要望>" [-n 3] [-f 参考画像] [--model ...] [-v]
```

- 各周回で「生成内容 / 生成物 / 判定 / 理由」を出力する。
- 終了コード: 要望を満たしたら 0、上限まで未達なら 1(AC-4)。

### 設定(`app/core/config.py`)

| 設定 | 既定値 | 用途 |
| --- | --- | --- |
| `verifier_model` | `gemini-2.5-flash` | 検証用モデル。生成モデルとクォータを分けるため既定を別にする |
| `loop_max_iterations` | `3` | 既定の上限回数(CLI の `-n` で上書き) |

## 5. エラーハンドリング / 非機能

- 生成の失敗(`AgentError`)はその周回を失敗として記録し、ループを中断する(繰り返しても同じ失敗が続くため)。
- 検証の失敗は `satisfied=False` として扱い、理由に例外内容を入れる。ループは続行する。
- 1 周につきモデル呼び出しは 2 回。既定の上限 3 周で最大 6 回。

## 6. テスト方針

| 層 | 対象 | 手段 |
| --- | --- | --- |
| unit | 停止条件(満たしたら終了 / 上限で終了) | フェイクのサービスと検証関数を注入 |
| unit | `build_retry_prompt` | 指摘が含まれることを確認 |
| unit | `detect_new_artifact` | 一時ディレクトリでファイル差分を検証 |
| 手動 | 実ループ | CLI で画像生成の要望を与えて周回を確認 |
