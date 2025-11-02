# Threshold Analysis: Why 0.0 is Better Than 1.0

## Data Statistics (Deezer Dataset - 18,644 tracks)

### Feature Distribution
```
Valence: mean = -0.067, median = 0.032, std = 1.058, range = [-2.15, 1.55]
Arousal: mean =  0.196, median = 0.040, std = 0.961, range = [-2.33, 2.76]
```

**Key insight:** Both features are **centered around 0**, NOT around 1!

---

## Class Distribution Comparison

### ❌ Threshold = 1.0 (ORIGINAL - IMBALANCED)
```
Energetic (v≥1.0, a≥1.0):  2,482 (13.3%)  ████████████
Relaxed   (v≥1.0, a<1.0):  1,133 ( 6.1%)  ██████
Angry     (v<1.0, a≥1.0):  1,434 ( 7.7%)  ███████
Sad       (v<1.0, a<1.0): 13,595 (72.9%)  ████████████████████████████████████████████████████████████████████████

Balance ratio: 0.083 ❌ HIGHLY IMBALANCED!
```

**Problems:**
- 73% of samples are "sad" → model overfits to single class
- Minority classes (6-13%) don't have enough training data
- Threshold 1.0 is far from data center (mean≈0)

---

### ✅ Threshold = 0.0 (NEW - BALANCED)
```
Energetic (v≥0.0, a≥0.0):  6,001 (32.2%)  ████████████████████████████████
Sad       (v<0.0, a<0.0):  5,444 (29.2%)  █████████████████████████████
Angry     (v<0.0, a≥0.0):  3,638 (19.5%)  ███████████████████
Relaxed   (v≥0.0, a<0.0):  3,561 (19.1%)  ███████████████████

Balance ratio: 0.593 ✅ WELL BALANCED!
```

**Benefits:**
- All classes between 19-32% → model learns all moods equally well
- Threshold 0.0 aligns with natural data center
- Better generalization to unseen data

---

## Model Performance

| Metric | Threshold = 1.0 | Threshold = 0.0 |
|--------|----------------|----------------|
| CV Accuracy | 99.99% | **100.00%** ✅ |
| Class Balance | 0.083 ❌ | **0.593** ✅ |
| Largest Class | 72.9% (sad) | 32.2% (energetic) |
| Smallest Class | 6.1% (relaxed) | 19.1% (relaxed) |

---

## Raw Value Mapping

Database tracks have raw values [0, 1]. Here's how they map to moods:

### With Threshold = 0.0 (current)
```python
scaled = (raw - 0.5) * 4.0

Raw=0.8, 0.8 → Scaled=+1.2, +1.2 → energetic ✅
Raw=0.8, 0.2 → Scaled=+1.2, -1.2 → relaxed   ✅
Raw=0.2, 0.8 → Scaled=-1.2, +1.2 → angry     ✅
Raw=0.2, 0.2 → Scaled=-1.2, -1.2 → sad       ✅
Raw=0.5, 0.5 → Scaled= 0.0,  0.0 → boundary (neutral)
```

**Interpretation:**
- Raw < 0.5 = negative mood (angry/sad)
- Raw ≥ 0.5 = positive mood (energetic/relaxed)
- **Intuitive and balanced!**

---

## Conclusion

**Threshold = 0.0 is objectively better because:**

1. ✅ **Aligns with data**: Mean/median are near 0, not near 1
2. ✅ **Better balance**: 59% ratio vs 8% ratio
3. ✅ **More training data per class**: Smallest class has 19% vs 6%
4. ✅ **Slightly higher accuracy**: 100% vs 99.99% CV score
5. ✅ **Intuitive mapping**: Raw 0.5 (middle) → Scaled 0 (threshold)

**Using threshold = 1.0 would be like:**
- Setting "cold" threshold at 30°C when average temperature is 10°C
- Most things would be "cold", very few would be "warm"
- Doesn't make sense statistically!
