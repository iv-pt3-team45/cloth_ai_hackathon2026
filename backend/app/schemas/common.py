"""利用者が文字を打ち込むリクエストの共通チェック(spec 037)。

利用者が文字を打ち込める MV 検索・ライブ検索・服の保存のリクエストの型だけが
`GuardedRequest` を継承し、受け取った文字列を全部たどって制御文字と長さを確かめる(422)。
出力にも使う型(服の属性など)には手を入れないため、Gemini の出力の検証には影響しない。
"""

import re
from typing import Any

from pydantic import BaseModel, model_validator

# 改行・タブ・復帰以外の制御文字(C0 / C1)と、文字の向きを変える制御文字。
# 絵文字の結合(U+200D)などは許す
CONTROL_CHARS = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069]")

# 1 つの文字列の上限。項目ごとの上限を決めていない文字列(服の属性など)への最後の歯止め
MAX_STRING_LENGTH = 50_000

# 服の写真の base64(キー data)は検査しない(大きく、制御文字を含まない)
_SKIP_KEYS = frozenset({"data"})


def check_strings(value: Any, path: str = "") -> None:
    """辞書・リストをたどり、文字列の制御文字と長さを確かめる。問題があれば ValueError。"""
    if isinstance(value, str):
        if CONTROL_CHARS.search(value):
            raise ValueError(f"{path or '入力'} に使えない制御文字が含まれています")
        if len(value) > MAX_STRING_LENGTH:
            raise ValueError(f"{path or '入力'} が長すぎます({MAX_STRING_LENGTH} 文字まで)")
    elif isinstance(value, dict):
        for key, item in value.items():
            if key not in _SKIP_KEYS:
                check_strings(item, f"{path}.{key}" if path else str(key))
    elif isinstance(value, (list, tuple)):
        for index, item in enumerate(value):
            check_strings(item, f"{path}[{index}]")


class GuardedRequest(BaseModel):
    """受け取った文字列すべてに共通チェックを行うリクエストの型の親クラス。"""

    @model_validator(mode="after")
    def _check_strings(self) -> "GuardedRequest":
        check_strings(self.model_dump())
        return self
