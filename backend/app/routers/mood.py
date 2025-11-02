from typing import List, Optional, Dict, Any
from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
import os
import json
import numpy as np
from sqlalchemy.orm import Session
from ..core.db import get_db
from ..models.music import Track

router = APIRouter(prefix="/mood", tags=["mood"])

# Lazy load model and encoder
_model = None
_encoder = None
# Prefer explicit mood storage, but also accept models placed under storage/recommender
BASE_STORAGE = os.path.join(os.path.dirname(__file__), '..', '..', 'storage')
# By default try multiple candidate locations. Optionally force using only the
# deezer mood model by setting the environment variable `MOOD_ONLY_DEEZER=true`.
_deezer_candidate = os.path.join(BASE_STORAGE, 'recommender', 'deezer_mood_model.pkl')
_model_path_candidates = [
    os.path.join(BASE_STORAGE, 'mood', 'mood_model.pkl'),
    _deezer_candidate,
    os.path.join(BASE_STORAGE, 'recommender', 'mood_model.pkl'),
    os.path.join(BASE_STORAGE, 'recommender', 'model.pkl'),
]

# Honor env flag to only use deezer model when set (useful for production/testing).
try:
    if os.environ.get('MOOD_ONLY_DEEZER', 'false').lower() in ('1', 'true', 'yes'):
        _model_path_candidates = [_deezer_candidate]
except Exception:
    pass

def _load_model():
    global _model, _encoder
    if _model is not None:
        return _model
    # Diagnostic info: print storage paths and cwd so runtime server logs reveal why a model
    # wasn't loaded (helpful when the running process has a different working dir).
    try:
        print(f"[mood] _load_model: BASE_STORAGE={BASE_STORAGE}")
        print(f"[mood] _load_model: cwd={os.getcwd()}")
        print(f"[mood] _load_model: candidate_paths={_model_path_candidates}")
    except Exception:
        pass

    try:
        import joblib
        # Try to load the first candidate that both exists and can be loaded.
        _model = None
        for p in _model_path_candidates:
            try:
                if not os.path.exists(p):
                    continue
            except Exception:
                continue
            try:
                _model = joblib.load(p)
                try:
                    print(f"[mood] Loaded model from {p}; classes={getattr(_model, 'classes_', None)}")
                except Exception:
                    print(f"[mood] Loaded model from {p}")
                
                # Try to load encoder from same directory (for class name mapping)
                if _encoder is None:
                    encoder_path = os.path.join(os.path.dirname(p), 'encoder.pkl')
                    try:
                        if os.path.exists(encoder_path):
                            _encoder = joblib.load(encoder_path)
                            print(f"[mood] Loaded encoder from {encoder_path}; classes={getattr(_encoder, 'classes_', None)}")
                    except Exception as e:
                        print(f"[mood] Could not load encoder: {e}")
                        _encoder = None
                
                break
            except Exception as e:
                # Log and continue to next candidate instead of stopping on first existing file.
                try:
                    print(f"[mood] Failed to load model from {p}: {e}")
                except Exception:
                    pass
                _model = None
                continue
        if _model is None:
            print("[mood] No loadable model file found in candidate paths")
    except Exception as e:
        print(f"[mood] joblib import/load error: {e}")
        _model = None
    return _model


class TrackCandidate(BaseModel):
    id: int
    title: Optional[str]
    valence: float
    arousal: float
    preview_url: Optional[str] = None
    cover_url: Optional[str] = None


class MoodRequest(BaseModel):
    user_text: str
    candidate_tracks: List[TrackCandidate]
    top_k: Optional[int] = 10


class MoodResponse(BaseModel):
    # Allow returning a field named `model_classes` (starts with protected prefix
    # `model_`) without Pydantic emitting a protected-namespaces warning.
    # Use Pydantic v2 style `model_config`. Do not declare a `Config` inner
    # class because mixing `model_config` and `Config` causes an import-time
    # error on Pydantic v2.
    model_config = {'protected_namespaces': ()}

    mood: str
    candidates: List[Dict[str, Any]]
    used_model: Optional[bool] = False
    model_classes: Optional[List[str]] = None


class MoodDBRequest(BaseModel):
    user_text: str
    top_k: Optional[int] = 10
    # optional maximum number of candidates to scan from DB (None => all)
    limit: Optional[int] = 10000


def _heuristic_mood_from_text(text: str) -> str:
    t = text.lower()
    if any(w in t for w in ["energetic", "energy", "năng lượng", "sung", "excited", "hăng"]) or any(w in t for w in ["điên", "đạp", "dance", "edm"]):
        return "energetic"
    if any(w in t for w in ["relaxed", "calm", "chill", "nhẹ", "thư giãn", "yên"]) or any(w in t for w in ["acoustic", "chill"]):
        return "relaxed"
    if any(w in t for w in ["angry", "giận", "bực", "nặng", "hard", "rock"]):
        return "angry"
    if any(w in t for w in ["sad", "buồn", "melanch", "ballad"]):
        return "sad"
    # fallback: simple polarity mapping
    if "happy" in t or "vui" in t:
        return "energetic"
    return "relaxed"


def _extract_mood_with_openai(text: str) -> Optional[str]:
    try:
        api_key = os.environ.get('OPENAI_API_KEY')
        if not api_key:
            return None
        import openai
        openai.api_key = api_key
        prompt = (
            "You are a tiny assistant that maps a user's free-text description of how they feel into one of four moods: energetic, relaxed, angry, sad. "
            "Return only a JSON object like {\"mood\": \"energetic\"}. Do not include extra commentary."
            f"\nUser: {text}\n"
        )
        resp = openai.ChatCompletion.create(model='gpt-3.5-turbo', messages=[{"role": "user", "content": prompt}], max_tokens=30)
        content = resp['choices'][0]['message']['content']
        # Try to parse JSON
        try:
            obj = json.loads(content)
            mood = obj.get('mood')
            if mood in ('energetic', 'relaxed', 'angry', 'sad'):
                return mood
        except Exception:
            # try to extract keyword
            for m in ('energetic', 'relaxed', 'angry', 'sad'):
                if m in content.lower():
                    return m
    except Exception:
        return None
    return None


def _map_numeric_to_mood(valence: float, arousal: float) -> str:
    # thresholds at 0.5 (backend fallback when model unavailable)
    # NOTE: If model was trained with different thresholds (e.g., 1.0),
    # this mapping may differ from training logic.
    v = valence
    a = arousal
    if v >= 0.5 and a >= 0.5:
        return 'energetic'
    if v >= 0.5 and a < 0.5:
        return 'relaxed'
    if v < 0.5 and a >= 0.5:
        return 'angry'
    return 'sad'


def _predict_mood_with_model(model, valence: float, arousal: float):
    """Predict mood using loaded model.
    
    Returns: (predicted_class_name: str, confidence_score: float)
    
    NOTE: Model trained on Deezer dataset expects SCALED features (range ~ -2 to +2).
    Database tracks have raw values (0-1 range), so we convert:
      raw 0.0-1.0 → scaled using linear mapping to Deezer distribution
      
    Deezer stats: valence mean=-0.067, arousal mean=0.196 (both near 0)
    We center at 0.5 and map to range [-2, +2]:
      scaled = (raw - 0.5) * 4.0
      
    This way:
      raw=0.0 → scaled=-2.0 (very negative)
      raw=0.5 → scaled=0.0  (neutral, threshold)
      raw=1.0 → scaled=+2.0 (very positive)
    
    Uses encoder (global _encoder) to map class index to mood name.
    """
    global _encoder
    try:
        import warnings
        
        # Convert raw 0-1 range to Deezer scaled range (-2 to +2)
        # Center at 0.5 → 0.0, which matches Deezer mean≈0
        scaled_valence = (valence - 0.5) * 4.0
        scaled_arousal = (arousal - 0.5) * 4.0
        features = [[scaled_valence, scaled_arousal]]
        
        # Predict class
        pred_class = model.predict(features)[0]
        
        # Map numeric class to string label
        # Priority: use encoder.classes_ if available, else model.classes_
        predicted_label = str(pred_class)
        if _encoder is not None and hasattr(_encoder, 'classes_'):
            try:
                classes = list(_encoder.classes_)
                # pred_class is numeric index (0,1,2,3), map to actual label
                if isinstance(pred_class, (int, np.integer)) and 0 <= pred_class < len(classes):
                    predicted_label = str(classes[int(pred_class)])
                else:
                    predicted_label = str(pred_class)
            except Exception as e:
                print(f"[mood] Encoder mapping failed: {e}")
                predicted_label = str(pred_class)
        elif hasattr(model, 'classes_'):
            try:
                classes = list(model.classes_)
                if isinstance(pred_class, (int, np.integer)) and 0 <= pred_class < len(classes):
                    predicted_label = str(classes[int(pred_class)])
                else:
                    predicted_label = str(pred_class)
            except Exception:
                predicted_label = str(pred_class)
        
        # Get confidence score
        score = 0.0
        if hasattr(model, 'predict_proba'):
            try:
                with warnings.catch_warnings():
                    warnings.simplefilter("ignore")
                    probs = model.predict_proba(features)[0]
                # Use the probability of the predicted class
                if isinstance(pred_class, (int, np.integer)) and 0 <= pred_class < len(probs):
                    score = float(probs[int(pred_class)])
                else:
                    score = float(max(probs))
            except Exception:
                score = 0.0
        
        return predicted_label, score
    except Exception as e:
        print(f"[mood] Model prediction failed: {e}")
        return None, 0.0


@router.post('/recommend', response_model=MoodResponse)
def recommend_by_mood(req: MoodRequest):
    # 1) get mood from text (try OpenAI if enabled, else heuristic)
    use_openai = os.environ.get('USE_OPENAI', 'true').lower() in ('1', 'true', 'yes')
    mood = None
    if use_openai:
        mood = _extract_mood_with_openai(req.user_text)
    if mood is None:
        mood = _heuristic_mood_from_text(req.user_text)

    # 2) load model
    model = _load_model()
    model_used = model is not None

    scored = []
    for t in req.candidate_tracks:
        predicted = None
        score = 0.0
        if model is not None:
            predicted, score = _predict_mood_with_model(model, t.valence, t.arousal)
            if predicted is None:
                # Fallback if model prediction failed
                predicted = _map_numeric_to_mood(t.valence, t.arousal)
                score = 0.0
        else:
            predicted = _map_numeric_to_mood(t.valence, t.arousal)
            score = 0.0

        scored.append({
            'id': t.id,
            'title': t.title,
            'preview_url': t.preview_url,
            'cover_url': t.cover_url,
            'predicted_mood': predicted,
            'score': score,
        })

    # Filter by requested mood
    filtered = [s for s in scored if s.get('predicted_mood') == mood]
    # If none match, fallback to nearest by distance in valence/arousal
    if not filtered:
        # compute distance to mood centroid
        centroids = {
            'energetic': (0.8, 0.8),
            'relaxed': (0.8, 0.2),
            'angry': (0.2, 0.8),
            'sad': (0.2, 0.2),
        }
        cx, cy = centroids.get(mood, (0.5, 0.5))
        def dist(item):
            # find original candidate
            ct = next((c for c in req.candidate_tracks if c.id == item['id']), None)
            if ct is None: return 1e9
            dx = (ct.valence - cx)
            dy = (ct.arousal - cy)
            return dx*dx + dy*dy
        scored.sort(key=dist)
        filtered = scored[: req.top_k]
    else:
        filtered.sort(key=lambda x: x.get('score', 0.0), reverse=True)
        filtered = filtered[: req.top_k]
    # Optionally include model metadata to help clients determine whether
    # predictions came from the trained model or from the numeric heuristic.
    meta = {'used_model': bool(model_used)}
    try:
        if model_used and hasattr(model, 'classes_'):
            # Ensure classes are plain Python strings to satisfy Pydantic response model
            try:
                raw = list(model.classes_)
                cleaned = []
                for v in raw:
                    try:
                        # numpy scalars have .item()
                        if hasattr(v, 'item'):
                            cleaned.append(str(v.item()))
                        else:
                            cleaned.append(str(v))
                    except Exception:
                        cleaned.append(str(v))
                meta['model_classes'] = cleaned
            except Exception:
                meta['model_classes'] = [str(x) for x in getattr(model, 'classes_', [])]
    except Exception:
        pass

    return {'mood': mood, 'candidates': filtered, **meta}


@router.post('/recommend/from_db', response_model=MoodResponse)
def recommend_from_db(req: MoodDBRequest, db: Session = Depends(get_db)):
    # Determine mood from text
    use_openai = os.environ.get('USE_OPENAI', 'true').lower() in ('1', 'true', 'yes')
    mood = None
    if use_openai:
        mood = _extract_mood_with_openai(req.user_text)
    if mood is None:
        mood = _heuristic_mood_from_text(req.user_text)

    model = _load_model()
    model_used = model is not None

    # Query DB for tracks with valence/arousal
    q = db.query(Track).filter(Track.valence != None, Track.arousal != None)
    if req.limit:
        q = q.limit(req.limit)
    rows = q.all()

    scored = []
    for t in rows:
        v = float(t.valence or 0.0)
        a = float(t.arousal or 0.0)
        predicted = None
        score = 0.0
        if model is not None:
            predicted, score = _predict_mood_with_model(model, v, a)
            if predicted is None:
                # Fallback if model prediction failed
                predicted = _map_numeric_to_mood(v, a)
                score = 0.0
        else:
            predicted = _map_numeric_to_mood(v, a)
            score = 0.0

        scored.append({
            'id': t.id,
            'title': t.title,
            'preview_url': t.preview_url,
            'cover_url': t.cover_url,
            'predicted_mood': predicted,
            'score': score,
        })

    filtered = [s for s in scored if s.get('predicted_mood') == mood]
    if not filtered:
        centroids = {
            'energetic': (0.8, 0.8),
            'relaxed': (0.8, 0.2),
            'angry': (0.2, 0.8),
            'sad': (0.2, 0.2),
        }
        cx, cy = centroids.get(mood, (0.5, 0.5))
        def dist_item(item):
            tr = next((r for r in rows if r.id == item['id']), None)
            if tr is None: return 1e9
            dx = (float(tr.valence or 0.0) - cx)
            dy = (float(tr.arousal or 0.0) - cy)
            return dx*dx + dy*dy
        scored.sort(key=dist_item)
        filtered = scored[: req.top_k]
    else:
        filtered.sort(key=lambda x: x.get('score', 0.0), reverse=True)
        filtered = filtered[: req.top_k]

    meta = {'used_model': bool(model_used)}
    try:
        if model_used and hasattr(model, 'classes_'):
            try:
                raw = list(model.classes_)
                cleaned = []
                for v in raw:
                    try:
                        if hasattr(v, 'item'):
                            cleaned.append(str(v.item()))
                        else:
                            cleaned.append(str(v))
                    except Exception:
                        cleaned.append(str(v))
                meta['model_classes'] = cleaned
            except Exception:
                meta['model_classes'] = [str(x) for x in getattr(model, 'classes_', [])]
    except Exception:
        pass

    return {'mood': mood, 'candidates': filtered, **meta}


@router.get('/status')
def mood_status():
    """Diagnostic endpoint: report whether a model file was found/loaded and candidate paths.

    Use this to quickly inspect the running process' view of storage paths and model status.
    """
    global _encoder
    # Attempt to load model via _load_model (which may have been called earlier)
    model = _load_model()
    status = {
        'base_storage': BASE_STORAGE,
        'cwd': os.getcwd(),
        'candidate_paths': _model_path_candidates,
        'model_loaded': bool(model),
        'model_classes': None,
        'encoder_classes': None,
        'found_path': None,
        'load_error': None,
        'python': None,
        'sklearn': None,
    }

    try:
        import sys, traceback
        status['python'] = sys.version
        try:
            import sklearn
            status['sklearn'] = getattr(sklearn, '__version__', None)
        except Exception:
            status['sklearn'] = None
    except Exception:
        pass

    try:
        if model is not None and hasattr(model, 'classes_'):
            status['model_classes'] = list(model.classes_)
        if _encoder is not None and hasattr(_encoder, 'classes_'):
            status['encoder_classes'] = list(_encoder.classes_)
    except Exception:
        status['model_classes'] = None
    except Exception:
        status['model_classes'] = None

    # For each candidate path, report existence and try a safe joblib.load to capture errors
    for p in _model_path_candidates:
        try:
            exists = os.path.exists(p)
        except Exception:
            exists = False
        if exists and status['found_path'] is None:
            status['found_path'] = p
        if exists:
            # attempt to load to capture any exception details (but do not replace already-loaded model)
            try:
                import joblib
                # load in a try/except and only capture errors
                try:
                    tmp = joblib.load(p)
                    # if load succeeded, note classes if available
                    status['model_loaded'] = True
                    try:
                        status['model_classes'] = list(getattr(tmp, 'classes_', None))
                    except Exception:
                        pass
                    status['found_path'] = p
                    # stop after first successful load
                    break
                except Exception as e:
                    status['load_error'] = repr(e)
                    try:
                        import traceback
                        status['load_error_trace'] = traceback.format_exc()
                    except Exception:
                        pass
            except Exception as e:
                status['load_error'] = repr(e)
                try:
                    import traceback
                    status['load_error_trace'] = traceback.format_exc()
                except Exception:
                    pass

    # Sanitize model_classes to plain Python types (avoid numpy types causing json encoding errors)
    try:
        mc = status.get('model_classes')
        if mc is not None:
            sanitized = []
            for v in mc:
                try:
                    # try convert numpy scalar to native Python
                    if hasattr(v, 'item'):
                        sanitized.append(v.item())
                    else:
                        sanitized.append(v)
                except Exception:
                    try:
                        sanitized.append(int(v))
                    except Exception:
                        try:
                            sanitized.append(str(v))
                        except Exception:
                            sanitized.append(None)
            status['model_classes'] = sanitized
    except Exception:
        # best-effort: drop problematic field
        try:
            status.pop('model_classes', None)
        except Exception:
            pass

    return status
