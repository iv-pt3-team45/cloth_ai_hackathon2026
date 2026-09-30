# 設計: 会場情報取得(F14)

- 対応する要件: `./requirements.md`
- ステータス: draft
- 更新日: 2026-09-29(位置情報の取得を追加)

## 1. 設計方針

| 案 | 概要 | 採否 | 理由 |
| --- | --- | --- | --- |
| A | Gemini APIのGoogle検索グラウンディング(Grounding with Google Search)ツールを使い、会場名から会場情報をWeb検索させる | 採用 | 入力が「会場名(テキスト)」のみでURLを持たないため、URL Contextより適合する。既存コードもすべてGemini経由の統一アーキテクチャなので踏襲しやすい |
| B | Gemini APIのURL Contextツールを使う | 却下 | 入力に会場の公式ページURLが無い(F08/F09未実装のため会場名しか渡せない)。将来F08と結合すればURL Contextを追加検討する余地はある |
| C | 会場情報専用の外部データベース/APIを別途契約する | 却下 | ハッカソンの残り期間に対して調査・契約コストが見合わない。MVP優先度もShouldであり、フォールバック(形態不明)が許容されている |

**技術リスク(要検証)**: Gemini APIで「Google検索グラウンディング(tools)」と「構造化出力(response_schema)」を同一リクエストで併用できるかは未検証。もし併用不可であれば、(1)グラウンディング付きで自由文の説明を取得する呼び出しと、(2)その説明文から会場形態を分類する処理、の2段階に分ける設計とする(下記フローは2段階構成で記載)。

## 2. 全体フロー

```
(呼び出し元: チャットエージェントのFunction Calling、または他サービスからの直接呼び出し)
        │
        ▼
get_venue_info(venue_name)              [backend/app/services/venue.py]
        │
        ├─ 1. _search_venue(venue_name)
        │      genai.Client.models.generate_content(
        │        tools=[Tool(google_search=GoogleSearch())]
        │      ) --> 会場に関する説明文(座席形態・住所を含む、グラウンディングされたテキスト)
        │
        ├─ 2. _classify_format(raw_text)
        │      キーワードマッチングで "standing" / "seated" / "unknown" に分類
        │      (外部呼び出し無し。ユニットテストしやすくするため)
        │
        ├─ 3. _extract_address(raw_text)
        │      genai.Client.models.generate_content(構造化出力、toolsは使わない)
        │      --> raw_textから住所だけを抽出(不明なら空文字)
        │
        └─ 4. 例外発生時は catch し、format="unknown" / status="error" として返す
                (address抽出の失敗は致命的にしない。取得できなければ空文字のままにする)
                │
                ▼
        VenueInfo(venue_name, format, address, summary, status, message)
```

## 3. API 設計

該当なし。F14はHTTPエンドポイントを持たない。チャットエージェントのツール(Function Calling)として、または他のサービス層コードから直接呼び出される内部関数として提供する(F20側からの利用方法は本spec範囲外、requirements.md 6章の未決事項2を参照)。

## 4. データモデル

```python
class VenueFormat(str, Enum):
    STANDING = "standing"
    SEATED = "seated"
    UNKNOWN = "unknown"

class VenueInfo(BaseModel):
    venue_name: str
    format: VenueFormat = VenueFormat.UNKNOWN
    address: str = ""       # 会場の住所(取得できない場合は空文字。F15が利用する)
    summary: str = ""       # グラウンディングで得られた説明文(短縮)
    status: Literal["ok", "error"] = "ok"
    message: str = ""       # status="error" のときの理由
```

**位置情報について**: 緯度経度までは求めず、住所(文字列)のみをF14の責務とする。理由は、Geminiに緯度経度を直接答えさせると数値のハルシネーションのリスクがあり、正確性が要求される割に検証が難しいため。住所から緯度経度への変換が必要になった場合は、F15側の実装時にジオコーディングの要否とあわせて検討する(未決事項3)。

要件定義の未決事項1(会場形態の粒度)は、MVPでは `standing` / `seated` / `unknown` の3値とする。スタンディング席と着席指定席が混在する会場は、暫定的に `unknown` に含める(将来細分化する余地は残す)。

## 5. フロントエンド設計

該当なし。本specにフロントエンド変更は含まない。

## 6. バックエンド設計

- サービス: `backend/app/services/venue.py`(新規)
  - `_search_venue(venue_name: str, client: genai.Client | None = None) -> str`: コア処理その1。Google検索グラウンディング付きでGeminiを呼び出し、説明文を返す。
  - `_classify_format(raw_text: str) -> VenueFormat`: コア処理その2。外部呼び出し無しの純粋関数。
  - `_extract_address(raw_text: str, client: genai.Client | None = None) -> str`: コア処理その3。`_search_venue`の結果から住所だけを抽出する(構造化出力を使用、toolsは付けない)。失敗・不明時は空文字を返す(例外は投げない)。
  - `get_venue_info(venue_name: str, client: genai.Client | None = None) -> dict`: 上記を組み合わせ、例外を握りつぶして辞書を返す(`wardrobe.py`の`list_wardrobe`等と同じ、失敗してもエージェントを止めない方針)。
  - `build_venue_tools(settings: Settings | None = None) -> list[Callable[..., Any]]`: ADKツール登録用の薄いラッパー(`build_wardrobe_tools`と同じパターン)。
- ルータ追加: 無し(F14専用エンドポイントは作らない)。
- 設定追加(`backend/app/core/config.py`): `VENUE_INFO_MODEL`(既定値は`GEMINI_MODEL`と同じでよい。将来モデルを分けたくなった場合に備えて独立させる。`CLOTH_INDEX_MODEL`と同じ考え方)。

## 7. Gemini プロンプト設計

- モデル: `settings.venue_info_model`(既定 `gemini-2.5-flash`)
- 呼び出し例:

```python
# 1回目: Google検索グラウンディングで自由文の説明を得る
response = client.models.generate_content(
    model=settings.venue_info_model,
    contents=f"「{venue_name}」という会場について、座席形態(スタンディング/着席/混在)と"
             f"住所(所在地)が分かる範囲で日本語で簡潔に説明してください。",
    config=types.GenerateContentConfig(
        tools=[types.Tool(google_search=types.GoogleSearch())],
    ),
)

# 2回目: 1回目の説明文から住所だけを構造化出力で抽出する(toolsは付けない)
class _AddressExtraction(BaseModel):
    address: str = Field(default="", description="住所。説明文から読み取れない場合は空文字")

response2 = client.models.generate_content(
    model=settings.venue_info_model,
    contents=f"次の説明文から、住所だけを抽出してください。読み取れない場合は空文字にしてください。\n\n{raw_text}",
    config=types.GenerateContentConfig(
        response_mime_type="application/json",
        response_schema=_AddressExtraction,
    ),
)
```

- 出力フォーマット: 1回目の呼び出しは構造化出力を使わない(上記「技術リスク」参照)。自由文のテキストを`_classify_format`でキーワード判定する。2回目の呼び出しは検索ツールを使わないため、構造化出力(`response_schema`)を安全に併用できる。
- 失敗時のフォールバック: 1回目呼び出しの例外(タイムアウト・API エラー等)は`get_venue_info`側でcatchし、`VenueFormat.UNKNOWN` / `status="error"`として返す。2回目(住所抽出)の失敗は致命的にせず、`address=""`のまま処理を継続する。呼び出し元(エージェント/Orchestrator)を止めない。

## 8. エラーハンドリング / 非機能

- 異常系: Gemini呼び出し失敗、グラウンディング結果が空、キーワードにマッチしない、のいずれも例外にせず`unknown`として返す(requirements.md AC-2)。
- タイムアウト・リトライ: 既存の`media.py`等と同様、明示的なリトライは行わない(MVP優先度Shouldのため簡易実装で十分と判断)。
- ログ: 検索クエリ(会場名)と分類結果をログに残す(個人情報は含まないため機微情報の懸念は無し)。

## 9. テスト方針

| 層 | 対象 | 手段 |
| --- | --- | --- |
| backend unit | `_classify_format` | pytest(様々な説明文パターンを与えて分類結果を検証。外部API呼び出し無し) |
| backend unit | `_extract_address` | pytest(genai.Clientをモック/スタブ化し、住所が取れる場合・取れない場合を検証) |
| backend unit | `get_venue_info` | pytest(genai.Clientをモック/スタブ化し、正常系・例外系の両方を検証。address抽出の失敗が致命的にならないことも検証) |
