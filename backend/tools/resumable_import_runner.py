"""
Resumable runner for importing train.csv in chunks.

Usage:
  python tools\resumable_import_runner.py --start 3659 --total 11268 --chunk-size 1000

The runner will call import_train_csv.py for each chunk and write per-chunk CSVs to tools/.
It stops on errors and records progress to .import_train_state.json.
"""
from __future__ import annotations
import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

STATE_PATH = Path(ROOT) / '.import_train_state.json'

def load_state():
    if STATE_PATH.exists():
        try:
            return json.loads(STATE_PATH.read_text())
        except Exception:
            return {}
    return {}

def save_state(state: dict):
    STATE_PATH.write_text(json.dumps(state))

def run_chunk(start: int, chunk: int, batch_size: int, sleep: float, export_csv: str) -> int:
    cmd = [sys.executable, 'tools\import_train_csv.py', '--execute', '--start', str(start), '--limit', str(chunk), '--batch-size', str(batch_size), '--export-csv', export_csv, '--sleep', str(sleep)]
    print('Running:', ' '.join(cmd))
    proc = subprocess.run(cmd)
    return proc.returncode

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--start', type=int, required=True)
    p.add_argument('--total', type=int, required=True)
    p.add_argument('--chunk-size', type=int, default=1000)
    p.add_argument('--batch-size', type=int, default=1000)
    p.add_argument('--sleep', type=float, default=0.08)
    p.add_argument('--delay-between-chunks', type=float, default=2.0)
    args = p.parse_args()

    state = load_state()
    cur = args.start
    if state.get('last_processed') and state.get('last_processed') >= args.start:
        cur = state['last_processed'] + 1

    total = args.total
    chunk = args.chunk_size
    print(f"Resumable import runner starting at {cur} / {total} (chunk_size={chunk})")

    try:
        while cur <= total:
            to_process = min(chunk, total - cur + 1)
            export_csv = f"tools/import_train_chunk_{cur}.csv"
            rc = run_chunk(cur, to_process, args.batch_size, args.sleep, export_csv)
            if rc != 0:
                print(f"Chunk starting at {cur} failed with return code {rc}. Aborting. State written.")
                save_state({'last_processed': cur - 1})
                return
            # mark progress: last processed row = cur + to_process - 1
            last = cur + to_process - 1
            save_state({'last_processed': last})
            print(f"Completed chunk {cur}-{last}. Sleeping {args.delay_between_chunks}s before next chunk.")
            cur = last + 1
            time.sleep(args.delay_between_chucks if False else args.delay_between_chunks)
        print('All chunks completed successfully')
    except KeyboardInterrupt:
        print('Interrupted by user; saving state and exiting')
        save_state({'last_processed': cur - 1})

if __name__ == '__main__':
    main()
