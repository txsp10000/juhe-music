import requests
import json
import struct

BASE_URL = "https://music-api.gdstudio.xyz/api.php"
HEADERS = {"User-Agent": "Mozilla/5.0"}

r = requests.get(f"{BASE_URL}?types=url&source=netease&id=1913206466&br=999", headers=HEADERS)
url = json.loads(r.text)["url"]
print(f"Downloading full FLAC file...")

resp = requests.get(url, headers=HEADERS, timeout=120)
data = resp.content
print(f"File size: {len(data)} bytes ({len(data)/1024/1024:.1f} MB)")

# Parse FLAC header
assert data[:4] == b"fLaC"
si = data[8:8+34]
sample_rate = (si[10] << 12) | (si[11] << 4) | ((si[12] >> 4) & 0x0F)
total_samples_header = ((si[13] & 0x0F) << 32) | (si[14] << 24) | (si[15] << 16) | (si[16] << 8) | si[17]
print(f"Sample rate: {sample_rate}")
print(f"Total samples (header): {total_samples_header}")
print(f"Duration (header): {total_samples_header/sample_rate:.3f}s")

# Count actual FLAC frames to find real total samples
# Skip metadata blocks
offset = 4
while offset < len(data):
    header_byte = data[offset]
    is_last = (header_byte & 0x80) != 0
    block_size = int.from_bytes(data[offset+1:offset+4], "big")
    offset += 4 + block_size
    if is_last:
        break

audio_start = offset
print(f"\nAudio frames start at byte: {audio_start}")
print(f"Audio data size: {len(data) - audio_start} bytes")

# For CBR FLAC estimate: audio_bytes / (sample_rate * channels * bits/8) * compression
# Better: count frames
frame_count = 0
pos = audio_start
last_frame_sample = 0
while pos < len(data) - 2:
    # FLAC frame sync: 11111111 111110xx
    if data[pos] == 0xFF and (data[pos+1] & 0xFC) == 0xF8:
        frame_count += 1
        if frame_count <= 3 or frame_count % 10000 == 0:
            print(f"  Frame {frame_count} at byte {pos}")
        pos += 16  # skip at least frame header
    else:
        pos += 1

print(f"\nTotal FLAC frames found: {frame_count}")
# Each frame typically contains 1024 samples (matching our min/max block size)
actual_samples = frame_count * 1024
actual_duration = actual_samples / sample_rate
print(f"Estimated actual samples: {actual_samples}")
print(f"Estimated actual duration: {actual_duration:.3f}s = {int(actual_duration)//60}:{int(actual_duration)%60:02d}")
print(f"\nRatio (actual/header): {actual_duration / (total_samples_header/sample_rate):.4f}")
