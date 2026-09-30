"""MV の動画タイトルをアーティスト名と曲名に分解する(spec 007)。

YouTube API にはアーティスト名・曲名の項目が無いため、よくあるタイトルの書き方から推定する。
どの書き方にも当てはまらない場合はチャンネル名・動画タイトルをそのまま返し、
分解できなかったこと(`parsed=False`)を後続の処理が判断できるようにする。
"""

import re
import unicodedata
from collections.abc import Callable
from dataclasses import dataclass

# 中身にこれらを含む括弧は、曲名ではなく装飾とみなして取り除く
_DECORATION_WORDS = re.compile(
    r"official|music\s*video|(?<![a-z])m/?v(?![a-z])|(?<![a-z])pv(?![a-z])|video|lyrics?"
    r"|audio|visuali[sz]er|公式|ミュージック\s*ビデオ|歌詞",
    re.IGNORECASE,
)
_OPEN_BRACKETS = "(（[［【〔〈《"
_CLOSE_BRACKETS = ")）]］】〕〉》"
_BRACKETED = re.compile(r"[(（\[［【〔〈《]([^)）\]］】〕〉》]*)[)）\]］】〕〉》]")
# 括弧に入っていない末尾の装飾(例: "Official Music Video", "米津玄師 MV" の "MV")
_TRAILING_DECORATION = re.compile(
    r"(?:[\s\-–—|/]*(?<![a-z])(?:official\s*)?"
    r"(?:music\s*video|m/?v|pv|video|lyric\s*video|audio)(?![a-z]))+\s*$",
    re.IGNORECASE,
)
# 分解後の前後から取り除く区切り記号
_EDGE_CHARS = " -–—―−－|｜/／・:："
_QUOTE_CHARS = "「」『』'‘’\"“” "

_TOPIC_SUFFIX = re.compile(r"\s*-\s*topic\s*$", re.IGNORECASE)
_JP_QUOTE = re.compile(r"^(?P<artist>[^「『]*?)\s*[「『](?P<song>[^」』]+)[」』]")
_HYPHEN = re.compile(r"^(?P<left>.+?)\s+[-–—―−－]\s+(?P<right>.+)$")
_QUOTE = re.compile(r"^(?P<artist>.+?)\s+['‘\"“](?P<song>[^'’\"”]+)['’\"”](?:\s|$)")
_SLASH = re.compile(r"^(?P<left>.+?)(?:\s+/\s*|\s*/\s+|\s*／\s*)(?P<right>.+)$")

# チャンネル名との照合で無視する語(公式チャンネルに付きがちな語)
_CHANNEL_NOISE = re.compile(r"official|公式|channel|チャンネル|vevo|topic", re.IGNORECASE)


@dataclass(frozen=True)
class ParsedTitle:
    """タイトルの分解結果。"""

    artist: str
    song_title: str
    # False ならパターンに当てはまらず、チャンネル名・動画タイトルをそのまま入れている
    parsed: bool


def strip_decorations(text: str) -> str:
    """`【MV】`・`(Official Music Video)` などの装飾を取り除く。

    装飾を示す語を含む括弧だけを消すため、`(feat. XX)` のような括弧は残る。
    """
    text = _BRACKETED.sub(
        lambda m: " " if _DECORATION_WORDS.search(m.group(1)) else m.group(0), text
    )
    text = re.sub(r"\s+", " ", text).strip()
    text = _TRAILING_DECORATION.sub("", text)
    return text.strip(_EDGE_CHARS)


def matches_channel(text: str, channel_title: str) -> bool:
    """文字列がチャンネル名と同じアーティストを指しているとみなせるか。

    表記の差(大文字小文字・全角半角・空白・記号・"Official" などの付加語)を無視し、
    一方がもう一方に含まれていれば一致とする。
    """
    a, b = _normalize(text), _normalize(channel_title)
    if len(a) < 2 or len(b) < 2:
        return False
    return a in b or b in a


def parse_title(title: str, channel_title: str) -> ParsedTitle:
    """動画タイトルとチャンネル名から、アーティスト名と曲名を推定する。

    パターンは上から順に試し、最初に当てはまったものを採用する。
    どれにも当てはまらなければ、アーティスト名 = チャンネル名、曲名 = 動画タイトル(そのまま)。
    """
    topic = _TOPIC_SUFFIX.search(channel_title)
    if topic:
        # YouTube が自動生成する「<アーティスト> - Topic」チャンネルはタイトルが曲名そのもの
        artist = channel_title[: topic.start()].strip()
        song = _clean_song(title)
        if artist and song:
            return ParsedTitle(artist=artist, song_title=song, parsed=True)

    cleaned = strip_decorations(title)
    for split in _SPLITTERS:
        pair = split(cleaned, channel_title)
        if pair is None:
            continue
        artist, song = strip_decorations(pair[0]), _clean_song(pair[1])
        if artist and song:
            return ParsedTitle(artist=artist, song_title=song, parsed=True)

    return ParsedTitle(artist=channel_title, song_title=title, parsed=False)


def _normalize(text: str) -> str:
    text = unicodedata.normalize("NFKC", text).lower()
    text = _CHANNEL_NOISE.sub("", text)
    return "".join(ch for ch in text if ch.isalnum())


def _clean_song(text: str) -> str:
    return strip_decorations(text).strip(_QUOTE_CHARS)


def _split_jp_quote(text: str, channel_title: str) -> tuple[str, str] | None:
    """`アーティスト「曲名」` / `アーティスト『曲名』`。

    「」が別の括弧の中にある場合(例: `A / B (「C」English Ver.)`)は、
    「」の前をアーティスト名とみなせないため当てはまらないものとする。
    """
    match = _JP_QUOTE.match(text)
    if not match:
        return None
    artist = match["artist"]
    if sum(map(artist.count, _OPEN_BRACKETS)) > sum(map(artist.count, _CLOSE_BRACKETS)):
        return None
    return artist, match["song"]


def _split_hyphen(text: str, channel_title: str) -> tuple[str, str] | None:
    """`アーティスト - 曲名`。

    右側だけがチャンネル名と一致する場合は `曲名 - アーティスト` とみなして入れ替える。
    """
    match = _HYPHEN.match(text)
    if not match:
        return None
    left, right = match["left"], match["right"]
    if matches_channel(right, channel_title) and not matches_channel(left, channel_title):
        return right, left
    return left, right


def _split_quote(text: str, channel_title: str) -> tuple[str, str] | None:
    """`アーティスト '曲名'`(K-POP に多い)。"""
    match = _QUOTE.match(text)
    return (match["artist"], match["song"]) if match else None


def _split_slash(text: str, channel_title: str) -> tuple[str, str] | None:
    """`A / B`。順序が書き手次第のため、チャンネル名と一致する側をアーティストとみなす。"""
    match = _SLASH.match(text)
    if not match:
        return None
    left, right = match["left"], match["right"]
    left_hit = matches_channel(left, channel_title)
    right_hit = matches_channel(right, channel_title)
    if left_hit and not right_hit:
        return left, right
    if right_hit and not left_hit:
        return right, left
    return None


_SPLITTERS: tuple[Callable[[str, str], tuple[str, str] | None], ...] = (
    _split_jp_quote,
    _split_hyphen,
    _split_quote,
    _split_slash,
)
