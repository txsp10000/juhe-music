import requests
import json

BASE_URL = "https://music-api.gdstudio.xyz/api.php"
HEADERS = {"User-Agent": "Mozilla/5.0"}

r = requests.get(f"{BASE_URL}?types=url&source=netease&id=1913206466&br=320", headers=HEADERS)
url = json.loads(r.text)["url"]
print(f"URL: {url}")

resp = requests.head(url, headers=HEADERS)
cl = resp.headers.get("Content-Length", "unknown")
ct = resp.headers.get("Content-Type", "unknown")
print(f"Content-Length: {cl}")
print(f"Content-Type: {ct}")

resp2 = requests.get(url, headers={**HEADERS, "Range": "bytes=0-4095"})
data = resp2.content
print(f"First 3 bytes: {data[:3]}")

if data[:3] == b"ID3":
    sz = ((data[6] & 0x7f) << 21) | ((data[7] & 0x7f) << 14) | ((data[8] & 0x7f) << 7) | (data[9] & 0x7f)
    print(f"ID3 tag size: {sz + 10} bytes")

file_size = int(cl) if cl != "unknown" else 0
if file_size > 0:
    audio_bytes = file_size - (sz + 10 if data[:3] == b"ID3" else 0)
    bitrate = 320000
    estimated_duration = audio_bytes * 8 / bitrate
    print(f"Estimated duration (CBR 320kbps): {estimated_duration:.1f}s = {int(estimated_duration)//60}:{int(estimated_duration)%60:02d}")
