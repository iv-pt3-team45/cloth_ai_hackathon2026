# 設計: ユーザーのログインと、手持ちの服のユーザーごとの紐づけ

- 対応する要件: `./requirements.md`
- ステータス: approved
- 更新日: 2026-10-09(実装時の変更を 4.4・5.1 に追記)

## 1. 設計方針

- **持ち主(Owner)** という考え方を入れる。持ち主は「ログインしたユーザー」か「ゲスト」のどちらかで、手持ちの服の保存先は持ち主ごとに分ける。
- ログインもゲストも、サーバーが署名した**トークン**(通行証)をブラウザに渡し、画面は手持ちの服・コーデ提案の API に `Authorization: Bearer <トークン>` を付けて呼ぶ。サーバーはユーザーのセッションを覚えない(ステートレス)。
- 手持ちの服(spec 010)とコーデ提案(spec 011)の処理そのものは変えない。spec 036 の `create_wardrobe_store` に持ち主を渡し、置き場所だけを持ち主ごとに変える。

| 論点 | 案 | 採否 | 理由 |
| --- | --- | --- | --- |
| トークンの形式 | JWT(HS256)を `PyJWT` で作る・確かめる | 採用 | 広く使われている形式とライブラリ。署名・期限の確認を自前で書かずに済む |
| | HMAC で自作の形式 | 却下 | 実質 JWT の再発明になり、確認漏れの危険がある |
| パスワードの保存 | 標準ライブラリの `hashlib.scrypt`(ソルト 16 バイト)。比較は `hmac.compare_digest` | 採用 | 追加の依存なしで、パスワード用の安全なハッシュが使える |
| ユーザーの保存先 | 手持ちの服と同じ保存先(local: `data/auth/users.json` / gcs: バケットの `auth/users.json`) | 採用 | 新しいサービスが要らない。ログインのたびに読むため、追加・削除がすぐ反映される(AC-15) |
| | 環境変数・Secret Manager に一覧を置く | 却下 | 変更のたびにデプロイが要る |
| ログイン状態の受け渡し | トークンを画面が保存し、ヘッダで送る | 採用 | 画面と API のドメインが違っても動く |
| | Cookie | 却下 | ドメインが違うため、ブラウザが送らない |
| ゲストの服を消す | Cloud Storage のライフサイクルルール(`guests/` の下を作成から 1 日で削除)+ 読むときに 1 日より古い服を除く | 採用 | 消す処理を書かずに済む。ルールの削除は遅れることがあり、`index.json` は更新のたびに作り直されて写真より長く残るため、読む側でも期限で除く |
| 写真の読み込み | 画面が API から(トークン付きで)写真のバイト列を取り、画面に表示する | 採用 | requirements の決定事項 3 |

## 2. 全体フロー

### 2.1 起動時(画面)

```
保存してあるトークンを読む(shared_preferences)
 ├─ ユーザーのトークンがあり、期限内 → ログイン中として使う
 ├─ ゲストのトークンがあり、期限内 → ゲストとして使う
 └─ どちらも無い・期限切れ → POST /auth/guest でゲストのトークンをもらい、保存する
```

### 2.2 手持ちの服の API を呼ぶとき

```
画面 ─(Authorization: Bearer <トークン>)→ routes/wardrobe.py
        → api/deps.py current_owner : トークンを確かめ、持ち主(Owner)にする。無効なら 401
        → WardrobeService(owner) → create_wardrobe_store(settings, owner)
             ├─ ユーザー: users/<ユーザーID>/wardrobe/
             └─ ゲスト  : guests/<ゲスト番号>/wardrobe/(1 日より古い服は読まない)
```

401 が返ったとき(画面):

- ユーザーのトークンなら、ログアウトしてゲストに戻し、「ログインの期限が切れました」と出す。
- ゲストのトークンなら、新しいゲストのトークンをもらって 1 回だけやり直す。

### 2.3 置き場所

```
gs://ai-agent-hackathon-508804-wardrobe/
├── auth/users.json                 # ログインできるユーザー(パスワードはハッシュ)
├── users/<ユーザーID>/wardrobe/     # ログインしたユーザーの服(ずっと残る)
│   ├── index.json
│   └── images/...
├── guests/<ゲスト番号>/wardrobe/    # ゲストの服(作成から 1 日で自動削除)
└── wardrobe/                       # spec 036 の共有の置き場所(今後は CLI の既定だけが使う)
```

ローカル(`WARDROBE_STORAGE=local`)では、同じ構成を `backend/data/` の下に作る(`data/auth/users.json`、`data/users/<ID>/wardrobe/index.json` など)。ローカルではゲストの服は自動では消えない(読むときに 1 日より古い服を除くだけ)。

## 3. API 設計

### 3.1 新規: `POST /api/v1/auth/login`

リクエスト:

```json
{ "user_id": "demo01", "password": "..." }
```

レスポンス (200):

```json
{ "token": "<JWT>", "kind": "user", "user_id": "demo01", "expires_at": "2026-10-16T12:00:00+09:00" }
```

| ステータス | 条件 | ボディ |
| --- | --- | --- |
| 401 | ID が無い・パスワードが違う(区別しない) | `{"detail": "ユーザー ID またはパスワードが違います。"}` |
| 422 | 入力の形式が不正(空など) | FastAPI の既定 |
| 502 | ユーザーの保存先を読めない | `{"detail": "..."}` |
| 503 | `AUTH_SECRET_KEY` が未設定(本番) | `{"detail": "..."}` |

### 3.2 新規: `POST /api/v1/auth/guest`

リクエストボディなし。レスポンス (200):

```json
{ "token": "<JWT>", "kind": "guest", "user_id": null, "expires_at": "..." }
```

### 3.3 新規: `GET /api/v1/auth/me`

`Authorization` ヘッダのトークンの持ち主を返す(画面の起動時の確認用)。200 は 3.1 / 3.2 と同じ形から `token` を除いたもの。無効なら 401。

### 3.4 既存の変更(パス・リクエスト・レスポンスの形は変えない)

| エンドポイント | 変更 |
| --- | --- |
| `/api/v1/wardrobe/*`(analyze 以外)、`/api/v1/outfit/*` | `Authorization: Bearer <トークン>` が必須。無い・無効・期限切れは **401**。保存先はトークンの持ち主ごと |
| `POST /api/v1/wardrobe/analyze` | 写真を解析するだけで保存しないため、トークンは不要のまま(変更なし) |
| MV・カルチャー・ライブ・会場 | 変更なし |

ログアウトの API は作らない(画面がトークンを捨てるだけ。サーバーは覚えていないため)。捨てたトークンは期限まで有効なままになるが、requirements の非ゴール(強制ログアウト)の範囲とする。

## 4. データモデル

### 4.1 トークン(JWT、HS256)

| 項目 | 値 |
| --- | --- |
| `sub` | ユーザー ID、またはゲスト番号(`secrets.token_hex(16)`) |
| `kind` | `user` / `guest` |
| `iat` / `exp` | 発行日時 / 期限(ユーザーもゲストも発行から 7 日) |

ゲストのトークンを 7 日にするのは、トークンが切れて番号が変わると、1 日以内に登録した服まで見えなくなるため。服そのものは 1 日で消える。

### 4.2 ユーザーの保存先 `users.json`

```json
{
  "users": {
    "demo01": {
      "password": "scrypt$16384$8$1$<ソルト base64>$<ハッシュ base64>",
      "created_at": "2026-10-09T12:00:00+09:00",
      "updated_at": "2026-10-09T12:00:00+09:00"
    }
  }
}
```

- ユーザー ID は英小文字・数字・`_`・`-` の 3〜32 文字(置き場所のフォルダ名に使うため)。
- Cloud Storage では、spec 036 と同じく世代番号を条件にして書き込む(運営のコマンドが同時に動いても壊さない)。

### 4.3 持ち主(`app/services/auth.py`)

```python
class Owner(BaseModel):
    kind: Literal["user", "guest"]
    id: str
```

### 4.4 設定(`config.py` と `.env.example` に追加)

| 変数 | 既定値 | 説明 |
| --- | --- | --- |
| `AUTH_SECRET_KEY` | 空 | トークンの署名の鍵(**秘匿情報**)。本番は Secret Manager の `auth-secret-key` から渡す。ローカルで空なら、起動のたびにランダムな鍵を使う(再起動でログアウトされる)。`local` 以外で空ならログイン・ゲストの API は 503 |
| `AUTH_TOKEN_DAYS` | `7` | トークンの有効期間(日) |
| `GUEST_WARDROBE_HOURS` | `24` | ゲストの服を読む期限(時間)。Cloud Storage のライフサイクルルール(1 日)と揃える |
| `WARDROBE_LOCAL_ROOT` | `data` | `WARDROBE_STORAGE=local` のとき、`users/`・`guests/`・`auth/users.json` を置くフォルダ(backend/ からの相対)。実装時に追加(`CLOTH_INDEX_PATH` から決めると、サンプルを指定したときに `tests/` の下へ書いてしまうため) |

### 4.5 画面に保存する値(`shared_preferences`)

`auth.token` / `auth.kind` / `auth.user_id` / `auth.expires_at` の 4 つ。パスワードは保存しない。

## 5. フロントエンド設計

### 5.1 ファイル

| ファイル | 内容 |
| --- | --- |
| `lib/core/auth_session.dart`(新規) | ログイン状態(`ChangeNotifier`)。トークンの保存・読み込み・ゲストのトークンの取得・ログイン・ログアウトと、`/auth/login`・`/auth/guest` の呼び出し。アプリで 1 つ(`AuthSession.shared`)、テストでは差し替える。**実装時に変更**: 当初は API の呼び出しを `features/auth/auth_repository.dart` に分ける予定だったが、手持ちの服・コーデ提案の Repository(別の feature)から使うため core にまとめた(README 2.2 の「他 feature の内部への直接依存」を避ける)。`/auth/me` は画面からは使っていない(期限は保存した値で判断し、無効なら API の 401 で気付く) |
| `lib/core/api_client.dart` | `AuthSession` を渡したクライアント(手持ちの服・コーデ提案の Repository)は `Authorization` を付ける。401 のとき 2.2 の扱いをする。写真用に `getBytes` を追加 |
| `lib/features/auth/login_card.dart`(新規) | ③ のカードの中に出す、ゲストの案内とログインの入力欄(`LoginCard`)と、ヘッダの右側の表示(`AccountStatus`) |
| `lib/app/home_page.dart` | `AccountStatus` をヘッダに、`LoginCard` を ③ のカードの上部(`WardrobeSection.header`)に置く。持ち主が変わったら `WardrobeSection` を作り直して一覧を読み直す(key に持ち主を使う) |
| `lib/features/wardrobe/wardrobe_section.dart` | 上部に部品を差し込める `header` を追加。`ClothPhoto` を、URL ではなく写真のバイト列を取得して表示する形に変える |
| `lib/features/wardrobe/wardrobe_repository.dart` | `imageUrl` の代わりに `imageBytes(image)`(トークン付きで取得。持ち主 + 写真名でメモリにキャッシュ) |
| `lib/features/outfit/*_view.dart` | 写真の表示を `ClothPhoto` の新しい形に合わせる |
| `pubspec.yaml` | `shared_preferences` を追加 |

### 5.2 画面のイメージ

ゲストのとき(③ のカードの上部):

```
┌ ③ 手持ちの服 ─────────────────────────────┐
│ ⓘ ゲストとして使っています。登録した服は 1 日で消えます。 │
│    ログインすると、ずっと残せます。   [ログイン]       │
│ ─ (ログインを押すと開く) ─────────────────── │
│   ユーザー ID [__________]                          │
│   パスワード  [__________] 👁                        │
│   [ログインする]  [やめる]                           │
│   ⚠ ユーザー ID またはパスワードが違います。          │
│ ─────────────────────────────────────── │
│ [写真を選ぶ]                                        │
│ (登録した服の格子)                                   │
└─────────────────────────────────┘
```

ヘッダ(右上):

```
♪ はじめてのライブ服                ゲスト | ログイン
♪ はじめてのライブ服          👤 demo01 | ログアウト
```

- 配色・カード・ボタンは `core/theme.dart` / `core/widgets.dart` の既存の部品を使う(AC-14)。
- ログイン・ログアウトしても、① ② の入力と選択は残す(AC-12)。手持ちの服の一覧は読み直す。結果の画面にいる場合は、入力の段階に戻す(前の持ち主の服で作った提案を残さないため)。

### 5.3 写真の表示

- `ClothPhoto` は写真名を受け取り、`WardrobeRepository.imageBytes` で取得して `Image.memory` で表示する。取得中はいまのプレースホルダ、失敗してもプレースホルダ。
- 同じ写真を何度も取りに行かないよう、持ち主 + 写真名でメモリに保存する。持ち主が変わったら捨てる。

## 6. バックエンド設計

### 6.1 ファイル

| ファイル | 内容 |
| --- | --- |
| `app/services/auth.py`(新規) | `Owner`、パスワードのハッシュ・照合、トークンの発行・確認、`AuthService`(ログイン・ゲスト)、業務例外 `AuthError` / `InvalidCredentialsError` / `InvalidTokenError` |
| `app/services/user_store.py`(新規) | `UserStore`(Protocol)とローカル / Cloud Storage の実装。`users.json` の読み書き |
| `app/schemas/auth.py`(新規) | `LoginRequest` / `TokenResponse` / `MeResponse` |
| `app/api/routes/auth.py`(新規) | `/auth/login`・`/auth/guest`・`/auth/me`。`router.py` に登録 |
| `app/api/deps.py`(新規) | `current_owner`(`Authorization` ヘッダを読み、`AuthService` で確かめ、無効なら 401)。HTTP の処理なのでルータ側に置く |
| `app/services/wardrobe_store.py` | `create_wardrobe_store(settings, owner=None)`。owner があれば持ち主ごとの置き場所。無ければ今までどおり(CLI の既定) |
| `app/services/wardrobe_gcs.py` / `LocalWardrobeStore` | ゲスト用に「この時間より古い服は読まない」(`max_age`)を足す |
| `app/services/wardrobe_registry.py` / `outfit.py` | 各メソッドが `owner` を受け取り、保存先をその持ち主で作る(テスト用に `store_factory` を差し込める)。業務の処理は変えない |
| `app/api/routes/wardrobe.py` / `outfit.py` | `current_owner` を受け取り、サービスに渡す |
| `scripts/manage_users.py`(新規) | `add` / `delete` / `passwd` / `list`。パスワードは `getpass` で入力するか、`--generate` でランダムに作って 1 回だけ表示する(AC-15) |
| `scripts/run_agent.py` / `run_agent_loop.py` | `--user <ID>` で、そのユーザーの服を読む(AC-16) |
| `pyproject.toml` | `uv add pyjwt` |

### 6.2 パスワードとトークン

- `hashlib.scrypt(password, salt=os.urandom(16), n=2**14, r=8, p=1, dklen=32)`。
- 存在しない ID のときも、ダミーのハッシュで照合して処理時間をそろえる(ID が存在するかを推測されにくくする)。
- トークンの確認では、署名・期限・`kind` の値・`sub` の形式(ユーザー ID の規則 / 32 桁の 16 進数)を確かめる。どれかが違えば `InvalidTokenError`(→ 401)。
- ユーザーのトークンは、確認のたびに `users.json` にそのユーザーがいるかも確かめる(削除したユーザーはすぐ使えなくなる)。

### 6.3 GCP 側の設定(Claude が gcloud で実行。実行前にコマンドを提示して承認を得る)

```bash
# ゲストの服を作成から 1 日で消すルール(guests/ の下だけ)
gcloud storage buckets update gs://ai-agent-hackathon-508804-wardrobe --lifecycle-file=lifecycle.json
# lifecycle.json: {"rule":[{"action":{"type":"Delete"},"condition":{"age":1,"matchesPrefix":["guests/"]}}]}

# トークンの署名の鍵を Secret Manager に作り、Cloud Run の実行用サービスアカウントに読む権限を付ける
gcloud secrets create auth-secret-key --data-file=<ランダムな鍵を書いた一時ファイル>
gcloud secrets add-iam-policy-binding auth-secret-key \
  --member serviceAccount:872278396120-compute@developer.gserviceaccount.com \
  --role roles/secretmanager.secretAccessor

# デモ用のユーザー(本番のバケットに作る)
WARDROBE_STORAGE=gcs uv run python scripts/manage_users.py add demo01 --generate   # 〜 demo05
```

- `.github/workflows/deploy.yml` の `--set-secrets` に `AUTH_SECRET_KEY=auth-secret-key:latest` を足す。
- Secret Manager の権限付与が編集者の権限でできない場合は、清水に依頼する。

## 7. Gemini プロンプト設計

**変更なし。**

## 8. エラーハンドリング / 非機能

- パスワード・トークン・パスワードのハッシュはログに出さない。ログイン失敗はユーザー ID だけを INFO で出す。
- 401 の文言: トークンが無い「ログインまたはゲストの準備ができていません。」、無効・期限切れ「ログインの期限が切れました。もう一度ログインしてください。」。
- 性能: 手持ちの服の API ごとに、トークンの確認(ユーザーなら `users.json` を 1 回読む)が増える。数十ミリ秒程度。

## 9. テスト方針

| 層 | 対象 | 手段 |
| --- | --- | --- |
| backend unit | パスワードのハッシュ・照合、トークンの発行・確認(期限切れ・改ざん・種類違い)、ユーザーの追加・削除・パスワード変更 | pytest。時刻は引数で渡す |
| backend unit | 持ち主ごとの保存先(local / gcs)、ゲストの期限 | `tmp_path` と spec 036 の偽物のバケット |
| backend api | ログイン・ゲスト・me、401、ユーザー A / B / ゲストの分離(AC-8) | TestClient。既存の API テストは `current_owner` を差し替える |
| backend cli | `manage_users.py` | 一時フォルダの保存先で実行 |
| frontend | ログインの入力欄・ヘッダの表示、ログイン・ログアウトで一覧を読み直す、401 でゲストに戻る、写真の表示 | flutter test。Repository と `shared_preferences` はフェイク(`SharedPreferences.setMockInitialValues`) |
| 手動 | 本番でログイン・ゲスト・再読み込み・別ブラウザ | マージ後 |
