"""
Test script for ML recommendation endpoints.
Run after training model and starting backend server.
"""
import requests
import json

BASE_URL = "http://localhost:8000"

def test_ml_recommendations(user_id: int = 1, limit: int = 10):
    """Test personalized ML recommendations."""
    print(f"\n=== Testing ML Recommendations for User {user_id} ===")
    
    url = f"{BASE_URL}/recommend/user/{user_id}/ml?limit={limit}"
    response = requests.get(url)
    
    print(f"Status: {response.status_code}")
    
    if response.status_code == 200:
        data = response.json()
        print(f"Received {len(data)} recommendations")
        
        if data:
            print("\nTop 5 recommendations:")
            for i, rec in enumerate(data[:5], 1):
                print(f"{i}. [{rec['track_id']}] {rec['title']} - {rec['artist_name']} (score: {rec['score']:.3f})")
        else:
            print("No recommendations returned (user may be new)")
    else:
        print(f"Error: {response.text}")

def test_similar_tracks(track_id: int = 1, limit: int = 10):
    """Test similar tracks endpoint."""
    print(f"\n=== Testing Similar Tracks for Track {track_id} ===")
    
    url = f"{BASE_URL}/recommend/similar/{track_id}?limit={limit}"
    response = requests.get(url)
    
    print(f"Status: {response.status_code}")
    
    if response.status_code == 200:
        data = response.json()
        print(f"Received {len(data)} similar tracks")
        
        if data:
            print("\nTop 5 similar tracks:")
            for i, rec in enumerate(data[:5], 1):
                print(f"{i}. [{rec['track_id']}] {rec['title']} - {rec['artist_name']} (similarity: {rec['score']:.3f})")
        else:
            print("No similar tracks found (track may not be in model)")
    else:
        print(f"Error: {response.text}")

def test_legacy_recommendations(user_id: int = 1, limit: int = 10):
    """Test legacy fallback recommendations."""
    print(f"\n=== Testing Legacy Recommendations for User {user_id} ===")
    
    url = f"{BASE_URL}/recommend/user/{user_id}?limit={limit}"
    response = requests.get(url)
    
    print(f"Status: {response.status_code}")
    
    if response.status_code == 200:
        data = response.json()
        print(f"Received {len(data)} recommendations")
        print(f"Sample: {data[:3]}")
    else:
        print(f"Error: {response.text}")

def compare_recommendations(user_id: int = 1):
    """Compare ML vs legacy recommendations."""
    print(f"\n=== Comparing ML vs Legacy for User {user_id} ===")
    
    # Get ML recommendations
    ml_response = requests.get(f"{BASE_URL}/recommend/user/{user_id}/ml?limit=10")
    ml_tracks = [r['track_id'] for r in ml_response.json()] if ml_response.status_code == 200 else []
    
    # Get legacy recommendations
    legacy_response = requests.get(f"{BASE_URL}/recommend/user/{user_id}?limit=10")
    legacy_tracks = [r['track_id'] for r in legacy_response.json()] if legacy_response.status_code == 200 else []
    
    print(f"ML recommendations: {ml_tracks}")
    print(f"Legacy recommendations: {legacy_tracks}")
    
    # Calculate overlap
    if ml_tracks and legacy_tracks:
        overlap = set(ml_tracks) & set(legacy_tracks)
        print(f"Overlap: {len(overlap)} tracks ({len(overlap)/len(ml_tracks)*100:.1f}%)")
    else:
        print("Cannot compare (one or both lists empty)")

def main():
    """Run all tests."""
    print("=" * 60)
    print("ML Recommendation System - Test Suite")
    print("=" * 60)
    
    # Test with different users
    test_ml_recommendations(user_id=1, limit=10)
    test_ml_recommendations(user_id=2, limit=10)
    
    # Test similar tracks
    test_similar_tracks(track_id=1, limit=10)
    test_similar_tracks(track_id=100, limit=10)
    
    # Test legacy endpoint
    test_legacy_recommendations(user_id=1)
    
    # Compare approaches
    compare_recommendations(user_id=1)
    
    print("\n" + "=" * 60)
    print("Tests completed!")
    print("=" * 60)

if __name__ == "__main__":
    try:
        main()
    except requests.exceptions.ConnectionError:
        print("ERROR: Cannot connect to backend server.")
        print("Make sure server is running: uvicorn app.main:app --reload")
    except Exception as e:
        print(f"ERROR: {str(e)}")
