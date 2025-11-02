"""
Test chat API endpoints
Requires backend server running on http://localhost:8000
"""
import requests
import json
from uuid import uuid4

BASE_URL = "http://localhost:8000"

print("=" * 70)
print("Testing Chat API Endpoints")
print("=" * 70)

# Check if server is running
try:
    response = requests.get(f"{BASE_URL}/")
    print(f"\n✅ Server is running: {response.json()}")
except Exception as e:
    print(f"\n❌ Server not running! Start it with:")
    print("   cd C:\\musicapp\\backend")
    print("   uvicorn app.main:app --reload --host 0.0.0.0 --port 8000")
    exit(1)

# Create unique session
session_id = str(uuid4())
print(f"\n📝 Session ID: {session_id}")

# Test conversation
conversations = [
    ("I'm feeling tired today", "groq"),
    ("Something relaxing please", "groq"),
    ("Actually, I want energetic music to wake me up!", "groq"),
]

print("\n" + "=" * 70)
print("Simulated Conversation:")
print("=" * 70)

for message, provider in conversations:
    print(f"\n👤 User: {message}")
    
    try:
        response = requests.post(
            f"{BASE_URL}/chat/send",
            json={
                "session_id": session_id,
                "message": message,
                "provider": provider,
                "include_music_context": True
            },
            timeout=30
        )
        
        if response.status_code == 200:
            data = response.json()
            bot_message = data.get("message", "")
            mood = data.get("mood")
            action = data.get("suggested_action")
            
            print(f"🤖 Bot: {bot_message}")
            
            if mood:
                print(f"   🎵 Detected Mood: {mood.upper()}")
            
            if action == "search_mood":
                print(f"   ⚡ Action: TRIGGER MUSIC SEARCH")
        else:
            print(f"❌ Error: {response.status_code}")
            print(f"   {response.text}")
    
    except Exception as e:
        print(f"❌ Request failed: {e}")

# Get conversation history
print("\n" + "=" * 70)
print("Conversation History:")
print("=" * 70)

try:
    response = requests.get(f"{BASE_URL}/chat/history/{session_id}")
    if response.status_code == 200:
        data = response.json()
        history = data.get("history", [])
        print(f"\n✅ Found {len(history)} messages in history")
        
        for i, msg in enumerate(history, 1):
            role = msg["role"]
            content = msg["content"]
            icon = "👤" if role == "user" else "🤖"
            print(f"\n{i}. {icon} {role.upper()}: {content[:80]}...")
except Exception as e:
    print(f"❌ Error getting history: {e}")

# Clear conversation
print("\n" + "=" * 70)
print("Cleanup:")
print("=" * 70)

try:
    response = requests.delete(f"{BASE_URL}/chat/clear/{session_id}")
    if response.status_code == 200:
        print(f"✅ Conversation cleared: {response.json()}")
except Exception as e:
    print(f"❌ Error clearing: {e}")

print("\n" + "=" * 70)
print("✅ Chat API test completed!")
print("=" * 70)
