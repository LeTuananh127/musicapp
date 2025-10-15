#!/usr/bin/env python3
"""Upload cached preview mp3s to AWS S3.

Usage:
  # dry-run (lists files that would be uploaded)
  python tools/upload_cache_to_s3.py --bucket my-bucket --prefix previews/ --dry-run

  # upload and keep local files
  python tools/upload_cache_to_s3.py --bucket my-bucket --prefix previews/

  # upload and delete local files after success
  python tools/upload_cache_to_s3.py --bucket my-bucket --prefix previews/ --delete-after

Authentication:
  The script uses standard boto3 auth methods:
   - Export AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY (and optionally AWS_SESSION_TOKEN), OR
   - Configure a profile in ~/.aws/credentials and pass --profile PROFILE

Notes:
  - This script does NOT attempt to upload files already present in S3 with the same key (it checks ETag/size)
  - It sets ContentType to audio/mpeg
"""
from pathlib import Path
import argparse
import boto3
from botocore.exceptions import ClientError
import os


def list_cache(cache_dir: Path):
    return sorted([p for p in cache_dir.glob('*.mp3') if p.is_file()])


def s3_key_for(path: Path, prefix: str):
    return (prefix.rstrip('/') + '/' + path.name) if prefix else path.name


def upload_file(s3, bucket, key, path):
    extra = {'ContentType': 'audio/mpeg'}
    try:
        s3.upload_file(str(path), bucket, key, ExtraArgs=extra)
        return True
    except ClientError as e:
        print('Upload failed for', path.name, e)
        return False


def exists_with_same_size(s3, bucket, key, size):
    try:
        head = s3.head_object(Bucket=bucket, Key=key)
        return int(head.get('ContentLength', -1)) == size
    except ClientError as e:
        if e.response.get('Error', {}).get('Code') in ('404', 'NoSuchKey'):
            return False
        # other errors => assume not present
        return False


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--bucket', required=True)
    p.add_argument('--prefix', default='')
    p.add_argument('--profile', default=None, help='AWS profile to use from ~/.aws/credentials')
    p.add_argument('--cache-dir', default=str(Path(__file__).resolve().parents[2] / 'app' / 'static' / 'audio' / 'deezer'))
    p.add_argument('--dry-run', action='store_true')
    p.add_argument('--delete-after', action='store_true', help='Delete local file after successful upload')
    args = p.parse_args()

    cache_dir = Path(args.cache_dir)
    if not cache_dir.exists():
        print('Cache dir not found:', cache_dir)
        return

    session_kwargs = {}
    if args.profile:
        session_kwargs['profile_name'] = args.profile
    session = boto3.Session(**session_kwargs) if session_kwargs else boto3.Session()
    s3 = session.client('s3')

    files = list_cache(cache_dir)
    if not files:
        print('No files to upload in', cache_dir)
        return

    print(f'Found {len(files)} files in cache. Bucket={args.bucket} prefix="{args.prefix}"')
    uploaded = 0
    skipped = 0
    failed = 0
    for pth in files:
        key = s3_key_for(pth, args.prefix)
        size = pth.stat().st_size
        if exists_with_same_size(s3, args.bucket, key, size):
            print('SKIP (exists) ', pth.name)
            skipped += 1
            continue

        if args.dry_run:
            print('DRY  ', pth.name, '->', key)
            uploaded += 1
            continue

        ok = upload_file(s3, args.bucket, key, pth)
        if ok:
            uploaded += 1
            if args.delete_after:
                try:
                    pth.unlink()
                except Exception as e:
                    print('Warning: failed to delete', pth, e)
        else:
            failed += 1

    print(f'Done. uploaded={uploaded} skipped={skipped} failed={failed}')


if __name__ == '__main__':
    main()
