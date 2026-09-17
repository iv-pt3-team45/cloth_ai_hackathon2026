"""添付ファイル(画像・動画)を Attachment スキーマに変換するヘルパー。

CLI からローカルファイルを渡すときに使う。
Cloud Storage(`gs://`)や HTTPS の URI は、ダウンロードせずそのまま Gemini に渡す。
"""

import base64
from pathlib import Path

from app.schemas.chat import Attachment

# 拡張子 → MIME。`mimetypes` は環境によって結果が変わるため、対応形式を明示的に持つ。
_MIME_BY_SUFFIX = {
    # 画像
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".gif": "image/gif",
    ".webp": "image/webp",
    ".heic": "image/heic",
    ".heif": "image/heif",
    # 動画
    ".mp4": "video/mp4",
    ".mov": "video/quicktime",
    ".webm": "video/webm",
    ".avi": "video/x-msvideo",
    ".mpeg": "video/mpeg",
    ".mpg": "video/mpeg",
    ".flv": "video/x-flv",
    ".wmv": "video/x-ms-wmv",
    # 音声 / 文書(動作確認対象外だが同じ経路で渡せる)
    ".mp3": "audio/mpeg",
    ".wav": "audio/wav",
    ".pdf": "application/pdf",
}

_URI_PREFIXES = ("gs://", "http://", "https://")


class AttachmentError(ValueError):
    """添付の読み込みに失敗したときの例外。"""


def supported_suffixes() -> list[str]:
    """対応している拡張子の一覧(エラーメッセージ用)。"""
    return sorted(_MIME_BY_SUFFIX)


def guess_mime_type(path_or_uri: str) -> str:
    """拡張子から MIME タイプを判定する。判定できなければ AttachmentError。"""
    suffix = Path(path_or_uri).suffix.lower()
    mime = _MIME_BY_SUFFIX.get(suffix)
    if mime is None:
        raise AttachmentError(
            f"対応していない拡張子です: {suffix or '(拡張子なし)'} / "
            f"対応: {', '.join(supported_suffixes())}"
        )
    return mime


def is_uri(path_or_uri: str) -> bool:
    """gs:// や https:// で始まるかどうか。"""
    return path_or_uri.startswith(_URI_PREFIXES)


def load_attachment(path_or_uri: str, mime_type: str | None = None) -> Attachment:
    """ローカルパスまたは URI から Attachment を作る。

    URI はダウンロードせずそのまま渡す。ローカルファイルは読み込んで base64 化する。
    """
    mime = mime_type or guess_mime_type(path_or_uri)

    if is_uri(path_or_uri):
        return Attachment(mime_type=mime, uri=path_or_uri)

    path = Path(path_or_uri).expanduser()
    if not path.is_file():
        raise AttachmentError(f"ファイルが見つかりません: {path}")

    data = base64.b64encode(path.read_bytes()).decode("ascii")
    return Attachment(mime_type=mime, data=data)
