import sys
from pathlib import Path

# Ensure backend directory in path
root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root))

from app.tools.add_external_interaction_column import ensure_column

if __name__ == '__main__':
    ensure_column()
