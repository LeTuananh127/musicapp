# Windows Build Notes for `implicit`

The `implicit` library (ALS recommender) compiles native extensions. On Windows you need:

## 1. Install Build Toolchain
1. Install **Visual Studio Build Tools**:
   - https://visualstudio.microsoft.com/downloads/
   - Select: "Desktop development with C++" (includes MSVC, Windows SDK, CMake, Ninja).
2. Ensure CMake in PATH (`cmake --version`).
3. (Optional) Install latest CMake separately: https://cmake.org/download/

## 2. Upgrade pip & wheel
```powershell
python -m pip install --upgrade pip setuptools wheel
```

## 3. Re-enable dependency
Uncomment in `requirements.txt`:
```
implicit==0.7.2
```
Then reinstall:
```powershell
pip install -r requirements.txt
```

## 4. Common Errors
- `MSVC is required` → Missing Build Tools; re-run installer and add C++ workload.
- Generator not found Visual Studio → Launch "Developer PowerShell for VS" once to finalize components.

## 5. Temporary Fallback
Until `implicit` builds, you can use a simple random or SVD-based recommender (see `services/recommendation_service.py`).

## 6. Future Optimization
After working, persist factor matrices under `app/ml/artifacts` and load lazily on startup instead of regenerating.
