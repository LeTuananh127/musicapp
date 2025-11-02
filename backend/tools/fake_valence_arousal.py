"""Fake valence and arousal for tracks missing them.

Usage:
  python tools/fake_valence_arousal.py [--execute] [--limit N] [--seed S] [--min V] [--max V] [--const]

Options:
  --execute    Actually write updates. Without this the script does a dry-run.
  --limit N    Max number of rows to process (0 = all). Default 0.
  --seed S     Random seed for reproducibility. Default 42.
  --min V      Minimum generated value (inclusive). Default 0.0.
  --max V      Maximum generated value (inclusive). Default 1.0.
  --const      Use a constant value (midpoint) instead of random.

This script will look for tracks where both valence and arousal are NULL and set them
to synthetic values in the range [min, max]. It uses the project's SQLAlchemy models
and session handling. It is conservative by default (dry-run).
"""
from __future__ import annotations

import argparse
import random
from decimal import Decimal
from typing import Tuple

from sqlalchemy import select

import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from app.core.db import SessionLocal
from app.models.music import Track


def parse_args():
    p = argparse.ArgumentParser(description="Fake valence/arousal for missing tracks")
    p.add_argument("--execute", action="store_true", help="Write changes to DB")
    p.add_argument("--limit", type=int, default=0, help="Max rows to process (0=all)")
    p.add_argument("--seed", type=int, default=42, help="Random seed")
    p.add_argument("--min", dest="minv", type=float, default=0.0, help="Min value")
    p.add_argument("--max", dest="maxv", type=float, default=1.0, help="Max value")
    p.add_argument("--const", action="store_true", help="Use constant midpoint value instead of random")
    return p.parse_args()


def gen_value(minv: float, maxv: float, const: bool) -> float:
    if const:
        return (minv + maxv) / 2.0
    return random.uniform(minv, maxv)


def main():
    args = parse_args()
    random.seed(args.seed)

    session = SessionLocal()
    try:
        q = session.query(Track).filter(Track.valence == None, Track.arousal == None)
        if args.limit and args.limit > 0:
            rows = q.limit(args.limit).all()
        else:
            rows = q.all()

        total = len(rows)
        if total == 0:
            print("No tracks found with both valence and arousal missing.")
            return

        print(f"Found {total} tracks with missing valence/arousal. (limit={args.limit})")

        updates = []
        for t in rows:
            v = gen_value(args.minv, args.maxv, args.const)
            a = gen_value(args.minv, args.maxv, args.const)
            # round to 4 decimals to keep DB tidy
            v = round(float(v), 4)
            a = round(float(a), 4)
            updates.append((t.id, v, a, t.title, getattr(t.artist, 'name', None) if hasattr(t, 'artist') else None))

        # show a small sample
        sample = updates[:10]
        print("Sample updates (id, valence, arousal, title, artist):")
        for u in sample:
            print(u)

        print(f"Total to update: {total}")
        if not args.execute:
            print("Dry-run mode. No changes written. Rerun with --execute to persist updates.")
            return

        # perform updates
        count = 0
        if args.execute:
            for track_id, valence, arousal, title, artist_name in updates:
                session.query(Track).filter(Track.id == track_id).update({"valence": valence, "arousal": arousal})
                count += 1
            session.commit()
            print(f"Wrote {count} rows to DB (valence/arousal set).")
        else:
            print("Dry-run completed. No DB changes were made.")
    finally:
        session.close()


if __name__ == "__main__":
    main()
