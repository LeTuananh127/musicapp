import requests

print("Testing ML recommendations for User 4...")
response = requests.get('http://localhost:8000/recommend/user/4/ml?limit=10')

print(f"Status: {response.status_code}")

if response.status_code == 200:
    data = response.json()
    print(f"Received {len(data)} recommendations\n")
    
    if data:
        print("Top 5 recommendations:")
        for i, rec in enumerate(data[:5], 1):
            print(f"{i}. [{rec['track_id']}] {rec['title']} - {rec['artist_name']} (score: {rec['score']:.3f})")
    else:
        print("No recommendations (user may be cold-start)")
else:
    print(f"Error: {response.text}")

print("\n" + "="*60)
print("Testing ML recommendations for User 30...")
response = requests.get('http://localhost:8000/recommend/user/30/ml?limit=10')

print(f"Status: {response.status_code}")

if response.status_code == 200:
    data = response.json()
    print(f"Received {len(data)} recommendations\n")
    
    if data:
        print("Top 5 recommendations:")
        for i, rec in enumerate(data[:5], 1):
            print(f"{i}. [{rec['track_id']}] {rec['title']} - {rec['artist_name']} (score: {rec['score']:.3f})")
    else:
        print("No recommendations")
else:
    print(f"Error: {response.text}")
