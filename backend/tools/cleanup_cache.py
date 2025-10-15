#!/usr/bin/env python3
"""Cleanup audio cache by age and total size.

Usage examples:
  # dry-run, show files older than 3 days or to trim to 50MB
  python tools/cleanup_cache.py --max-age-days 3 --max-bytes 50MB --dry-run

  # actually delete
  python tools/cleanup_cache.py --max-age-days 7 --max-bytes 200MB --delete
"""
from pathlib import Path
import argparse
import time
def fmt_bytes(n: int) -> str:
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if n < 1024.0:
            return f"{n:.1f}{unit}"
        n /= 1024.0
    return f"{n:.1f}PB"


def parse_size(s: str) -> int:
    s = s.strip().upper()
    multipliers = {'KB': 1024, 'MB': 1024**2, 'GB': 1024**3}
    if s.isdigit():
        return int(s)
    for k, v in multipliers.items():
        if s.endswith(k):
            return int(float(s[:-len(k)]) * v)
    # fallback
    return int(s)


def get_files(cache_dir: Path):
    files = []
    for p in cache_dir.glob('*.mp3'):
        try:
            stat = p.stat()
            files.append({'path': p, 'size': stat.st_size, 'mtime': stat.st_mtime})
        except Exception:
            continue
    return files


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--max-age-days', type=int, default=0, help='Delete files older than N days (0=disabled)')
    p.add_argument('--max-bytes', type=str, default='', help='Ensure total cache <= bytes (e.g. 200MB). Empty=disabled')
    p.add_argument('--cache-dir', default=str(Path(__file__).resolve().parents[2] / 'app' / 'static' / 'audio' / 'deezer'))
    p.add_argument('--dry-run', action='store_true')
    p.add_argument('--delete', action='store_true', help='Perform deletion (default is dry-run)')
    args = p.parse_args()

    cache_dir = Path(args.cache_dir)
    if not cache_dir.exists():
        print('Cache dir not found:', cache_dir)
        return

    files = get_files(cache_dir)
    total = sum(f['size'] for f in files)
    print(f'Cache dir: {cache_dir}')
    print(f'Files: {len(files)}  Total size: {fmt_bytes(total)}')

    now = time.time()
    to_delete = []

    # Age-based deletion
    if args.max_age_days and args.max_age_days > 0:
        cutoff = now - (args.max_age_days * 86400)
        for f in files:
            if f['mtime'] < cutoff:
                to_delete.append((f['mtime'], f))
        print(f'Candidates by age (> {args.max_age_days} days): {len(to_delete)}')

    # Size-based trimming: if max-bytes provided and total > max, delete oldest-first until under limit
    if args.max_bytes:
        max_bytes = parse_size(args.max_bytes)
        if total > max_bytes:
            # sort files by mtime ascending (oldest first)
            need = total - max_bytes
            print(f'Total {fmt_bytes(total)} > limit {fmt_bytes(max_bytes)} -> need to free {fmt_bytes(need)}')
            files_sorted = sorted(files, key=lambda x: x['mtime'])
            freed = 0
            for f in files_sorted:
                if freed >= need:
                    break
                if (f['mtime'], f) not in to_delete:
                    to_delete.append((f['mtime'], f))
                    freed += f['size']
            print(f'Candidates by size trimming: {len([x for x in to_delete])}  (will free ~{fmt_bytes(freed)})')

    # Deduplicate and sort candidates by oldest first
    to_delete_unique = {str(f['path']): f for (_, f) in to_delete}
    to_delete_list = sorted(to_delete_unique.values(), key=lambda x: x['mtime'])

    if not to_delete_list:
        print('No files to delete based on given criteria.')
        return

    print('\nFiles that would be deleted:')
    for f in to_delete_list:
        mtime = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(f['mtime']))
        print(f"{f['path'].name}\t{fmt_bytes(f['size'])}\t{mtime}")

    if args.dry_run and not args.delete:
        print('\nDry-run mode: no files were deleted.')
        return

    # Perform deletion
    deleted = 0
    for f in to_delete_list:
        try:
            f['path'].unlink()
            deleted += f['size']
            print(f'Deleted {f["path"].name}')
        except Exception as e:
            print('Failed to delete', f['path'], e)

    print(f'Deleted total: {fmt_bytes(deleted)}')


if __name__ == '__main__':
    main()
