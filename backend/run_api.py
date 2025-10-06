"""Helper launcher to avoid module import issues.
Usage:
  python run_api.py --reload --port 8000
"""
import uvicorn
import argparse
from pathlib import Path


def main():
  parser = argparse.ArgumentParser()
  parser.add_argument('--host', default='127.0.0.1')
  parser.add_argument('--port', type=int, default=8000)
  parser.add_argument('--reload', action='store_true')
  parser.add_argument('--no-reload', dest='reload', action='store_false')
  parser.set_defaults(reload=True)
  args = parser.parse_args()

  reload_dirs = [str(Path(__file__).parent / 'app')] if args.reload else None
  uvicorn.run(
    "app.main:app",
    host=args.host,
    port=args.port,
    reload=args.reload,
    reload_dirs=reload_dirs,
    log_level="info",
  )


if __name__ == '__main__':
  main()
