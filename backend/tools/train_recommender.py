"""Train a simple implicit ALS recommender from interactions.

Usage:
  python train_recommender.py --output backend/storage/recommender/model.npz --factors 64 --iterations 10

This script attempts to use the `implicit` library if available. If not
installed, it will raise an informative error asking you to pip install
`implicit` (and numpy/scipy).

The script writes a .npz containing user_ids, track_ids, user_factors, item_factors.
"""
import argparse
import os
import numpy as np
from collections import defaultdict

from app.core.db import SessionLocal
from app.models.music import Interaction, TrackLike


def gather_interactions(db):
    """
    Gather interaction data with confidence scores:
    - Base play: 1.0
    - Completed or milestone>=75: +3.0
    - Liked (track_likes): +10.0 (strong positive signal)
    """
    # Get play interactions
    q = db.query(Interaction.user_id, Interaction.track_id, Interaction.seconds_listened, Interaction.is_completed, Interaction.milestone)
    rows = q.filter(Interaction.track_id != None).all()
    
    user_map = {}
    item_map = {}
    user_idx = 0
    item_idx = 0
    data = defaultdict(float)
    
    # Process play interactions
    for u, t, secs, completed, milestone in rows:
        if t is None:
            continue
        u = int(u)
        t = int(t)
        if u not in user_map:
            user_map[u] = user_idx; user_idx += 1
        if t not in item_map:
            item_map[t] = item_idx; item_idx += 1
        ui = user_map[u]
        ii = item_map[t]
        # confidence heuristic: base 1.0 for any play, +3.0 for completed or milestone>=75
        conf = 1.0
        if completed or (milestone is not None and milestone >= 75):
            conf += 3.0
        # accumulate (in case of multiple plays)
        data[(ui, ii)] += conf
    
    # Add liked tracks with high confidence boost
    likes = db.query(TrackLike.user_id, TrackLike.track_id).all()
    likes_added = 0
    for u, t in likes:
        if t is None:
            continue
        u = int(u)
        t = int(t)
        # Add user/track to maps if not already present
        if u not in user_map:
            user_map[u] = user_idx; user_idx += 1
        if t not in item_map:
            item_map[t] = item_idx; item_idx += 1
        ui = user_map[u]
        ii = item_map[t]
        # Add strong positive signal for likes
        data[(ui, ii)] += 10.0
        likes_added += 1
    
    print(f"Processed {likes_added} liked tracks with +10.0 confidence boost")
    return user_map, item_map, data


def build_sparse(user_map, item_map, data):
    try:
        from scipy.sparse import coo_matrix
    except Exception:
        raise RuntimeError('scipy is required to build the sparse matrix. pip install scipy')
    rows = []
    cols = []
    vals = []
    for (ui, ii), v in data.items():
        rows.append(ui)
        cols.append(ii)
        vals.append(v)
    mat = coo_matrix((vals, (rows, cols)), shape=(len(user_map), len(item_map)))
    return mat


def train_als(sparse_mat, factors=64, iterations=10, regularization=0.1):
    # Prefer implicit ALS if available (fast C implementation). If it's not
    # available (common on Windows without MSVC), fall back to truncated SVD
    # computed with SciPy which avoids building native extensions.
    try:
        import implicit
        # implicit expects item-user matrix
        item_user = sparse_mat.T.tocsr()
        model = implicit.als.AlternatingLeastSquares(factors=factors, regularization=regularization, iterations=iterations)
        # fit (this will use CPU and can be reasonably fast for moderate sizes)
        model.fit(item_user)
        # item factors correspond to model.item_factors, user_factors to model.user_factors
        return model.user_factors, model.item_factors
    except Exception:
        # Fallback to truncated SVD using scipy (pure Python wiring to LAPACK/ARPACK)
        try:
            from scipy.sparse.linalg import svds
            import numpy as _np
        except Exception:
            raise RuntimeError('Neither implicit nor scipy.sparse.linalg.svds are available. Install scipy or implicit.')

        # Ensure CSR format
        mat = sparse_mat.tocsr()
        n_users, n_items = mat.shape
        # svds requires k < min(n_users, n_items)
        k = int(min(factors, max(1, min(n_users, n_items) - 1)))
        if k < 1:
            raise RuntimeError('Not enough users/items to compute factors with svds (k < 1)')
        # compute largest k singular values/vectors
        print(f'Falling back to truncated SVD (k={k}) via scipy.sparse.linalg.svds')
        u, s, vt = svds(mat, k=k)
        # svds returns singular values in ascending order — flip to descending
        order = _np.argsort(s)[::-1]
        s = s[order]
        u = u[:, order]
        vt = vt[order, :]

        # Convert SVD to factor matrices: U * sqrt(S), V * sqrt(S)
        sqrt_s = _np.sqrt(s)
        user_factors = u * sqrt_s[None, :]
        item_factors = (vt.T) * sqrt_s[None, :]
        return user_factors, item_factors


def save_model(path, user_map, item_map, user_factors, item_factors):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    user_ids = np.array([u for u, _ in sorted(user_map.items(), key=lambda x: x[1])], dtype=np.int32)
    track_ids = np.array([t for t, _ in sorted(item_map.items(), key=lambda x: x[1])], dtype=np.int32)
    np.savez_compressed(path, user_ids=user_ids, track_ids=track_ids, user_factors=user_factors, item_factors=item_factors)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', default='backend/storage/recommender/model.npz')
    parser.add_argument('--factors', type=int, default=64)
    parser.add_argument('--iterations', type=int, default=10)
    parser.add_argument('--regularization', type=float, default=0.1)
    args = parser.parse_args()

    db = SessionLocal()
    try:
        user_map, item_map, data = gather_interactions(db)
        if not data:
            print('No interactions found to train on. Exiting.')
            return
        print(f'Users: {len(user_map)} Items: {len(item_map)} Interactions: {len(data)}')
        mat = build_sparse(user_map, item_map, data)
        print('Starting ALS training (this may take a while)...')
        user_factors, item_factors = train_als(mat, factors=args.factors, iterations=args.iterations, regularization=args.regularization)
        save_model(args.output, user_map, item_map, user_factors, item_factors)
        print('Model saved to', args.output)
    finally:
        db.close()


if __name__ == '__main__':
    main()
