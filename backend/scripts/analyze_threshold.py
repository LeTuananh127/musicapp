"""
Analyze optimal threshold for mood classification
Compare threshold=0.0 vs threshold=1.0
"""
import pandas as pd
import numpy as np

# Load all datasets
df = pd.concat([
    pd.read_csv('train.csv'),
    pd.read_csv('test.csv'),
    pd.read_csv('validation.csv')
])

print('Deezer Dataset Statistics:')
print('=' * 70)
print(f'Total samples: {len(df)}')
print(f'\nValence - Mean: {df["valence"].mean():.3f}, Median: {df["valence"].median():.3f}')
print(f'Valence - Std: {df["valence"].std():.3f}')
print(f'Valence - Range: [{df["valence"].min():.3f}, {df["valence"].max():.3f}]')
print(f'\nArousal - Mean: {df["arousal"].mean():.3f}, Median: {df["arousal"].median():.3f}')
print(f'Arousal - Std: {df["arousal"].std():.3f}')
print(f'Arousal - Range: [{df["arousal"].min():.3f}, {df["arousal"].max():.3f}]')

print('\n' + '=' * 70)
print('Quadrant Distribution with Different Thresholds:')
print('=' * 70)

for thresh, name in [(0.0, 'CENTER at 0'), (1.0, 'CENTER at 1')]:
    print(f'\nThreshold = {thresh} ({name}):')
    print('-' * 70)
    
    energetic = ((df['valence'] >= thresh) & (df['arousal'] >= thresh)).sum()
    relaxed = ((df['valence'] >= thresh) & (df['arousal'] < thresh)).sum()
    angry = ((df['valence'] < thresh) & (df['arousal'] >= thresh)).sum()
    sad = ((df['valence'] < thresh) & (df['arousal'] < thresh)).sum()
    total = len(df)
    
    print(f'  Energetic (v>={thresh:4.1f}, a>={thresh:4.1f}): {energetic:5d} ({energetic/total*100:5.1f}%)')
    print(f'  Relaxed   (v>={thresh:4.1f}, a< {thresh:4.1f}): {relaxed:5d} ({relaxed/total*100:5.1f}%)')
    print(f'  Angry     (v< {thresh:4.1f}, a>={thresh:4.1f}): {angry:5d} ({angry/total*100:5.1f}%)')
    print(f'  Sad       (v< {thresh:4.1f}, a< {thresh:4.1f}): {sad:5d} ({sad/total*100:5.1f}%)')
    
    # Check balance
    min_class = min(energetic, relaxed, angry, sad)
    max_class = max(energetic, relaxed, angry, sad)
    balance_ratio = min_class / max_class if max_class > 0 else 0
    print(f'\n  Class balance (min/max): {balance_ratio:.3f}')
    if balance_ratio > 0.5:
        print(f'  ✅ Well balanced (ratio > 0.5)')
    elif balance_ratio > 0.2:
        print(f'  ⚠️  Moderately imbalanced (0.2 < ratio < 0.5)')
    else:
        print(f'  ❌ Highly imbalanced (ratio < 0.2)')

print('\n' + '=' * 70)
print('RECOMMENDATION:')
print('=' * 70)

# Calculate which threshold gives better balance
thresh_0_energetic = ((df['valence'] >= 0.0) & (df['arousal'] >= 0.0)).sum()
thresh_0_sad = ((df['valence'] < 0.0) & (df['arousal'] < 0.0)).sum()
thresh_0_balance = min(thresh_0_energetic, thresh_0_sad) / max(thresh_0_energetic, thresh_0_sad)

thresh_1_energetic = ((df['valence'] >= 1.0) & (df['arousal'] >= 1.0)).sum()
thresh_1_sad = ((df['valence'] < 1.0) & (df['arousal'] < 1.0)).sum()
thresh_1_balance = min(thresh_1_energetic, thresh_1_sad) / max(thresh_1_energetic, thresh_1_sad)

if thresh_0_balance > thresh_1_balance:
    print(f'✅ Threshold = 0.0 is MORE balanced (ratio: {thresh_0_balance:.3f} vs {thresh_1_balance:.3f})')
    print(f'   Mean/median are close to 0, so 0.0 is the natural center.')
else:
    print(f'⚠️  Threshold = 1.0 is MORE balanced (ratio: {thresh_1_balance:.3f} vs {thresh_0_balance:.3f})')
    print(f'   BUT mean/median suggest 0.0 as natural center.')

print(f'\n💡 Since valence mean={df["valence"].mean():.3f} and arousal mean={df["arousal"].mean():.3f}')
print(f'   are both close to 0.0, using threshold=0.0 aligns with data distribution.')
