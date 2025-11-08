"""
Usage:
  python tools/check_duration.py <path-to-audio-file>
Prints duration in milliseconds or a message when unknown.
"""
import sys
from mutagen import File

if len(sys.argv) < 2:
    print("Usage: python tools/check_duration.py <audio_path>")
    sys.exit(1)

path = sys.argv[1]
try:
    m = File(path)
    if not m or not getattr(m, 'info', None) or getattr(m.info, 'length', None) is None:
        print("UNKNOWN")
    else:
        print(int(m.info.length * 1000))
except Exception as e:
    print("ERROR:", e)
    sys.exit(1)
