"""MV タイトル分解のテスト(外部 API は呼ばない)。"""

import pytest

from app.services.mv_title import ParsedTitle, matches_channel, parse_title, strip_decorations


@pytest.mark.parametrize(
    ("title", "channel", "artist", "song"),
    [
        # AC-5 の例
        (
            "Official髭男dism - Pretender［Official Video］",
            "Official髭男dism",
            "Official髭男dism",
            "Pretender",
        ),
        ("YOASOBI「アイドル」 Official Music Video", "Ayase / YOASOBI", "YOASOBI", "アイドル"),
        # 「」の前にある装飾はアーティスト名から除く
        ("米津玄師 MV「Lemon」", "Kenshi Yonezu 米津玄師", "米津玄師", "Lemon"),
        (
            "Taylor Swift - Anti-Hero (Official Music Video)",
            "Taylor Swift",
            "Taylor Swift",
            "Anti-Hero",
        ),
        # 語中のアポストロフィは引用符とみなさない
        (
            "Queen - Don't Stop Me Now (Official Video)",
            "Queen Official",
            "Queen",
            "Don't Stop Me Now",
        ),
        ("BTS (방탄소년단) 'Dynamite' Official MV", "HYBE LABELS", "BTS (방탄소년단)", "Dynamite"),
    ],
)
def test_parse_title_splits_common_patterns(
    title: str, channel: str, artist: str, song: str
) -> None:
    assert parse_title(title, channel) == ParsedTitle(artist=artist, song_title=song, parsed=True)


def test_parse_title_uses_topic_channel_name() -> None:
    """AC-5: `<アーティスト> - Topic` チャンネルはタイトルが曲名そのもの。"""
    result = parse_title("Pretender", "Official髭男dism - Topic")

    assert result == ParsedTitle(artist="Official髭男dism", song_title="Pretender", parsed=True)


def test_parse_title_swaps_hyphen_when_right_side_is_channel() -> None:
    result = parse_title("Pretender - Official髭男dism", "Official髭男dism")

    assert (result.artist, result.song_title) == ("Official髭男dism", "Pretender")


@pytest.mark.parametrize(
    "title",
    ["【MV】夜に駆ける / YOASOBI", "【MV】YOASOBI / 夜に駆ける", "夜に駆ける／YOASOBI"],
)
def test_parse_title_decides_slash_order_by_channel(title: str) -> None:
    """未決事項 5 の決定: チャンネル名と一致する側をアーティストとみなす。"""
    result = parse_title(title, "Ayase / YOASOBI")

    assert result == ParsedTitle(artist="YOASOBI", song_title="夜に駆ける", parsed=True)


def test_parse_title_ignores_quote_inside_brackets() -> None:
    """「」が別の括弧の中にあるときは「」の前をアーティストとみなさない(実 API で見つかった例)。"""
    result = parse_title("YOASOBI / Idol (「アイドル」English Ver. )", "YOASOBI")

    assert result == ParsedTitle(
        artist="YOASOBI", song_title="Idol (「アイドル」English Ver. )", parsed=True
    )


def test_parse_title_does_not_guess_ambiguous_slash() -> None:
    """どちらの側もチャンネル名と一致しなければ分解しない。"""
    title = "夜に駆ける / YOASOBI"

    result = parse_title(title, "Music Label Japan")

    assert result == ParsedTitle(artist="Music Label Japan", song_title=title, parsed=False)


@pytest.mark.parametrize("title", ["Lemon", "【MV】「アイドル」", "AC/DC Thunderstruck"])
def test_parse_title_falls_back_to_raw_values(title: str) -> None:
    """AC-6: 当てはまらなければチャンネル名・動画タイトルをそのまま使う。"""
    result = parse_title(title, "Some Channel")

    assert result == ParsedTitle(artist="Some Channel", song_title=title, parsed=False)


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("【MV】Song [Official Video]", "Song"),
        ("Song (Official Music Video)", "Song"),
        ("Song（Lyric Video）", "Song"),
        ("Song Official Audio", "Song"),
        ("Song - MV", "Song"),
        ("Song (feat. Someone)", "Song (feat. Someone)"),
        ("Video Killed the Radio Star", "Video Killed the Radio Star"),
    ],
)
def test_strip_decorations(text: str, expected: str) -> None:
    assert strip_decorations(text) == expected


@pytest.mark.parametrize(
    ("text", "channel", "expected"),
    [
        ("YOASOBI", "Ayase / YOASOBI", True),
        ("Taylor Swift", "TaylorSwiftVEVO", True),
        ("ｙｏａｓｏｂｉ", "YOASOBI Official Channel", True),
        ("夜に駆ける", "Ayase / YOASOBI", False),
        ("A", "A", False),
    ],
)
def test_matches_channel(text: str, channel: str, expected: bool) -> None:
    assert matches_channel(text, channel) is expected
