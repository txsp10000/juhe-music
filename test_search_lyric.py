import requests
import json
import time
import urllib.parse

BASE_URL = "https://music-api.gdstudio.xyz/api.php"
HEADERS = {"User-Agent": "Mozilla/5.0"}


def search(keyword, count=20, max_retries=10):
    url = f"{BASE_URL}?types=search&source=netease&name={urllib.parse.quote(keyword)}&count={count}"
    for attempt in range(1, max_retries + 1):
        try:
            resp = requests.get(url, headers=HEADERS, timeout=10)
            resp.raise_for_status()
            data = resp.json()
            if isinstance(data, list) and len(data) > 0:
                return data
        except Exception as e:
            print(f"  重试 {attempt}/{max_retries}: {e}")
        time.sleep(1)
    return []


def get_lyric(song_id, max_retries=10):
    url = f"{BASE_URL}?types=lyric&source=netease&id={urllib.parse.quote(str(song_id))}"
    for attempt in range(1, max_retries + 1):
        try:
            resp = requests.get(url, headers=HEADERS, timeout=10)
            resp.raise_for_status()
            data = resp.json()
            lyric = data.get("lyric", "")
            if lyric.strip():
                return lyric
        except Exception as e:
            print(f"  重试 {attempt}/{max_retries}: {e}")
        time.sleep(1)
    return ""


if __name__ == "__main__":
    print("搜索：古风\n")
    results = search("古风")

    if not results:
        print("未找到结果")
        exit(1)

    print(f"共找到 {len(results)} 首歌曲：\n")
    for i, song in enumerate(results[:5]):
        artist = song.get("artist", "未知")
        if isinstance(artist, list):
            artist = " / ".join(artist)
        print(f"  {i+1}. {song['name']} - {artist}")

    first = results[0]
    song_name = first["name"]
    lyric_id = first.get("lyric_id") or first.get("id")

    print(f"\n--- 获取第一首《{song_name}》的歌词 (id={lyric_id}) ---\n")
    lyric = get_lyric(lyric_id)

    if lyric:
        print(lyric)
    else:
        print("歌词为空")
