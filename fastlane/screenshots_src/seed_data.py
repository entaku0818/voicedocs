#!/usr/bin/env python3
"""App Store スクリーンショット用に、シミュレータの Core Data ストアへ
実物らしい日本語のメモを流し込む。

アプリ本体にデバッグ用のシード機構を持たせたくない（本番コードを汚さない）ので、
シミュレータのコンテナにある sqlite を直接書く方式にしている。

前提: 対象シミュレータに voicedocs.app がインストール済みで、
      一度起動して Core Data ストアが作られていること。アプリは終了させておくこと。

使い方:
    python3 seed_data.py <device-udid>
"""

import os
import subprocess
import sqlite3
import sys
import uuid
import wave

BUNDLE_ID = "com.entaku.voicedocs"
# Core Data のタイムスタンプは 2001-01-01 00:00:00 UTC からの秒数
CORE_DATA_EPOCH_OFFSET = 978307200
# スクショの再現性を固定するため、実時刻ではなく固定の基準時刻から相対で作る
# （2026-08-16 10:00:00 UTC = Core Data timestamp）
BASE_TS = 1786953600 - CORE_DATA_EPOCH_OFFSET

MEMOS = [
    {
        "title": "週次定例｜開発チーム",
        "minutes_ago": 35,
        "duration_sec": 1580,
        "text": (
            "それでは週次定例を始めます。まず先週の進捗からお願いします。"
            "認証まわりのリファクタリングは完了しました。テストも通っています。"
            "ありがとうございます。次のリリースはどうしますか。"
            "来月末を目標にしたいです。ただ、検証にどれくらいかかるか読めていません。"
            "では検証の期間を今週中に見積もって、金曜までに共有してください。"
            "承知しました。あと、問い合わせが増えているので、ヘルプページの更新もしたいです。"
            "それは次のスプリントに入れましょう。担当は鈴木さんでお願いします。"
            "はい、対応します。リリースノートの下書きも合わせて用意しておきます。"
        ),
        "ai_note": (
            "# 要約\n"
            "先週は認証まわりのリファクタリングが完了し、テストも通過した。"
            "次回リリースは来月末を目標とするが、検証にかかる期間の見積もりがまだ出ていない。"
            "問い合わせ増加を受けて、ヘルプページの更新を次のスプリントで対応することを決めた。\n"
            "\n"
            "# アクションアイテム\n"
            "- 検証期間の見積もりを今週中に出し、金曜までに共有する\n"
            "- ヘルプページの更新を次のスプリントに入れる（担当: 鈴木）\n"
            "- リリースノートの下書きを用意する"
        ),
    },
    {
        "title": "取材メモ｜個人経営カフェの立ち上げ",
        "minutes_ago": 190,
        "duration_sec": 2260,
        "text": (
            "お店を始めようと思ったきっかけを教えてください。"
            "前職で焙煎の仕事をしていて、自分の選んだ豆をその場で出したいと思ったのが最初です。"
            "開業までにどれくらいかかりましたか。"
            "物件を決めてから半年ほどです。内装は知り合いの大工さんに手伝ってもらいました。"
            "いちばん大変だったことは何ですか。"
            "資金繰りですね。最初の三か月は本当に人が来なくて、貯金を取り崩していました。"
            "そこからどう変わったのでしょうか。"
            "近所の方が口コミで広げてくださって、半年を過ぎたあたりから常連さんが増えました。"
        ),
        "ai_note": "",
    },
    {
        "title": "講義｜マーケティング概論 第5回",
        "minutes_ago": 1500,
        "duration_sec": 4720,
        "text": (
            "今日はセグメンテーションの話をします。市場全体を一度に狙うのは現実的ではありません。"
            "顧客を意味のあるまとまりに分けて、そのうちどこを狙うかを決める必要があります。"
            "分け方には地理的、人口動態的、心理的、行動的の四つの軸があります。"
            "重要なのは、分けること自体が目的ではないという点です。"
            "分けた結果、打ち手が変わらないのであれば、その分け方には意味がありません。"
        ),
        "ai_note": "",
    },
    {
        "title": "打ち合わせメモ｜新機能の方向性",
        "minutes_ago": 2900,
        "duration_sec": 940,
        "text": (
            "今の使われ方を見ると、録音してそのまま置きっぱなしの人が多いようです。"
            "文字起こしまでは進むけれど、そこから先で止まっているということですね。"
            "はい。要約まで自動で出れば、見返す手間が減ると思います。"
            "端末の中だけで処理できると、仕事の会議でも使ってもらいやすいですね。"
        ),
        "ai_note": "",
    },
]


def make_uuid_blob(u: uuid.UUID) -> bytes:
    return u.bytes


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: seed_data.py <device-udid>", file=sys.stderr)
        return 2
    udid = sys.argv[1]

    container = subprocess.run(
        ["xcrun", "simctl", "get_app_container", udid, BUNDLE_ID, "data"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
    db_path = os.path.join(container, "Library", "Application Support", "VoiceMemoModel.sqlite")
    if not os.path.exists(db_path):
        print(f"Core Data ストアが見つかりません: {db_path}\n"
              "アプリを一度起動してから実行してください。", file=sys.stderr)
        return 1

    recordings_dir = os.path.join(container, "Documents", "VoiceRecordings")
    os.makedirs(recordings_dir, exist_ok=True)

    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute("SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME = 'VoiceMemoModel'")
    row = cur.fetchone()
    if row is None:
        print("Z_PRIMARYKEY に VoiceMemoModel がありません", file=sys.stderr)
        return 1
    z_ent = row[0]

    cur.execute("DELETE FROM ZVOICEMEMOMODEL")

    created_ids = []
    for i, memo in enumerate(MEMOS, start=1):
        memo_id = uuid.uuid4()
        created_ids.append((memo_id, memo["duration_sec"]))
        created_at = BASE_TS - memo["minutes_ago"] * 60
        cur.execute(
            """
            INSERT INTO ZVOICEMEMOMODEL
              (Z_PK, Z_ENT, Z_OPT, ZCREATEDAT, ZTRANSCRIBEDAT, ZTRANSCRIPTIONQUALITY,
               ZAITRANSCRIPTIONTEXT, ZTEXT, ZTITLE, ZTRANSCRIPTIONERROR,
               ZTRANSCRIPTIONSTATUS, ZVIDEOFILEPATH, ZID, ZSEGMENTS)
            VALUES (?, ?, 1, ?, ?, ?, ?, ?, ?, NULL, 'completed', NULL, ?, NULL)
            """,
            (
                i, z_ent, created_at, created_at + 30, 0.92,
                memo["ai_note"], memo["text"], memo["title"],
                sqlite3.Binary(make_uuid_blob(memo_id)),
            ),
        )

    cur.execute(
        "UPDATE Z_PRIMARYKEY SET Z_MAX = ? WHERE Z_NAME = 'VoiceMemoModel'",
        (len(MEMOS),),
    )
    conn.commit()
    conn.close()

    # 一覧の再生時間・ファイルサイズ表示のために、実体のある無音 m4a を置く
    for memo_id, duration in created_ids:
        out = os.path.join(recordings_dir, f"recording-{str(memo_id).upper()}.m4a")
        make_silent_m4a(out, duration)

    print(f"{len(MEMOS)} 件を投入しました: {db_path}")
    return 0


def make_silent_m4a(path: str, duration_sec: int) -> None:
    """指定秒数の無音 m4a を作る（一覧に再生時間とファイルサイズを出すため）。

    wave モジュールで無音 WAV を書き、afconvert で m4a に変換する。
    """
    wav = path + ".wav"
    sample_rate = 22050
    with wave.open(wav, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sample_rate)
        silence = b"\x00" * (sample_rate * 2)
        for _ in range(duration_sec):
            w.writeframes(silence)
    subprocess.run(
        ["afconvert", "-f", "m4af", "-d", "aac", "-b", "24000", wav, path],
        check=True, capture_output=True,
    )
    os.remove(wav)


if __name__ == "__main__":
    sys.exit(main())
