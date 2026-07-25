import requests
import json

BASE_URL = "https://music-api.gdstudio.xyz/api.php"
HEADERS = {"User-Agent": "Mozilla/5.0"}

url_api = f"{BASE_URL}?types=url&source=netease&id=1913206466&br=999"
r = requests.get(url_api, headers=HEADERS, timeout=10)
data = json.loads(r.text)
play_url = data.get("url", "")
print(f"Play URL: {play_url}")

print("\nDownloading first 64KB to analyze FLAC header...")
resp = requests.get(play_url, headers={**HEADERS, "Range": "bytes=0-65535"}, timeout=30)
audio_data = resp.content
print(f"Downloaded: {len(audio_data)} bytes")
print(f"First 4 bytes: {audio_data[:4]}")

if audio_data[:4] == b"fLaC":
    print("\nFormat: FLAC confirmed\n")
    print("STREAMINFO block (raw hex):")
    si = audio_data[8:8+34]
    print(" ".join(f"{b:02x}" for b in si))
    
    min_block = (si[0] << 8) | si[1]
    max_block = (si[2] << 8) | si[3]
    min_frame = (si[4] << 16) | (si[5] << 8) | si[6]
    max_frame = (si[7] << 16) | (si[8] << 8) | si[9]
    
    sample_rate = (si[10] << 12) | (si[11] << 4) | ((si[12] >> 4) & 0x0F)
    channels = ((si[12] >> 1) & 0x07) + 1
    bits_per_sample = ((si[12] & 0x01) << 4) | ((si[13] >> 4) & 0x0F)
    bits_per_sample += 1
    total_samples = ((si[13] & 0x0F) << 32) | (si[14] << 24) | (si[15] << 16) | (si[16] << 8) | si[17]
    
    print(f"\nMin block size: {min_block}")
    print(f"Max block size: {max_block}")
    print(f"Sample rate: {sample_rate} Hz")
    print(f"Channels: {channels}")
    print(f"Bits per sample: {bits_per_sample}")
    print(f"Total samples: {total_samples}")
    
    if sample_rate > 0:
        duration_sec = total_samples / sample_rate
        minutes = int(duration_sec) // 60
        seconds = int(duration_sec) % 60
        print(f"Duration: {duration_sec:.3f} seconds ({minutes}:{seconds:02d})")
