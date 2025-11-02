import requests

BASE_URL = "http://localhost:8000"

print("="*80)
print("Testing ML Recommendations for User 4")
print("="*80)

# Test 1: Default mode (exclude_listened=False) - Recommend what user likes
print("\n1. DEFAULT MODE (exclude_listened=False)")
print("   → Recommend tracks user already likes (for repeat listening)\n")

response = requests.get(f"{BASE_URL}/recommend/user/4/ml?limit=10")
if response.status_code == 200:
    data = response.json()
    print(f"   Status: {response.status_code} ✅")
    print(f"   Received: {len(data)} recommendations\n")
    
    print("   Top 10:")
    for i, rec in enumerate(data, 1):
        print(f"   {i:2d}. [{rec['track_id']:6d}] {rec['title'][:35]:35s} - {rec['artist_name']} (score: {rec['score']:.2f})")
else:
    print(f"   Status: {response.status_code} ❌")
    print(f"   Error: {response.text}")

# Test 2: Discovery mode (exclude_listened=True) - Recommend new tracks
print("\n" + "="*80)
print("2. DISCOVERY MODE (exclude_listened=True)")
print("   → Recommend NEW tracks user hasn't heard yet\n")

response = requests.get(f"{BASE_URL}/recommend/user/4/ml?limit=10&exclude_listened=true")
if response.status_code == 200:
    data = response.json()
    print(f"   Status: {response.status_code} ✅")
    print(f"   Received: {len(data)} recommendations\n")
    
    print("   Top 10:")
    for i, rec in enumerate(data, 1):
        print(f"   {i:2d}. [{rec['track_id']:6d}] {rec['title'][:35]:35s} - {rec['artist_name']} (score: {rec['score']:.2f})")
else:
    print(f"   Status: {response.status_code} ❌")
    print(f"   Error: {response.text}")

print("\n" + "="*80)
