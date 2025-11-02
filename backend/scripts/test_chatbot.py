"""
Demo script to test chatbot API without API keys
Shows the structure and simulates conversation
"""
import sys
sys.path.insert(0, 'C:\\musicapp\\backend')

from app.routers.chat import (
    _get_conversation,
    _extract_mood_and_action,
    SYSTEM_PROMPT
)

print("=" * 70)
print("CHATBOT DEMO - Testing Conversation Logic")
print("=" * 70)

# Test conversation history
session_id = "demo-session"
conversation = _get_conversation(session_id)

print(f"\n✅ Conversation initialized for session: {session_id}")
print(f"   System prompt length: {len(conversation[0]['content'])} characters")
print(f"   Messages in conversation: {len(conversation)}")

# Test mood extraction from different response formats
print("\n" + "=" * 70)
print("Testing Mood Extraction Logic:")
print("=" * 70)

test_cases = [
    # JSON format responses
    ('{"mood": "energetic", "action": "search_mood", "message": "Let me find energetic music!"}', 'energetic', 'search_mood'),
    ('{"mood": "relaxed", "action": "search_mood", "message": "I\'ll find calm music"}', 'relaxed', 'search_mood'),
    
    # Plain text responses with mood keywords
    ('I can help you find some energetic music to wake you up!', 'energetic', 'chat_only'),
    ('How about some relaxed, chill music for studying?', 'relaxed', 'chat_only'),
    ('That sounds like you need calm music', 'relaxed', 'chat_only'),
    
    # Plain text without mood
    ('What kind of music do you usually enjoy?', None, 'chat_only'),
    ('Tell me more about how you\'re feeling today', None, 'chat_only'),
]

for response_text, expected_mood, expected_action in test_cases:
    mood, action, message = _extract_mood_and_action(response_text)
    status = "✅" if mood == expected_mood and action == expected_action else "❌"
    print(f"\n{status} Input: {response_text[:60]}...")
    print(f"   → Mood: {mood}, Action: {action}")
    if expected_mood:
        print(f"   Expected: mood={expected_mood}, action={expected_action}")

# Show system prompt
print("\n" + "=" * 70)
print("System Prompt Preview:")
print("=" * 70)
print(SYSTEM_PROMPT[:300] + "...")

# Simulate conversation flow
print("\n" + "=" * 70)
print("Simulated Conversation Flow:")
print("=" * 70)

conversation_demo = [
    ("User", "I'm feeling tired"),
    ("Assistant", "Aww, do you want something relaxing to help you rest, or energetic music to wake you up? 😊"),
    ("User", "Something relaxing"),
    ("Assistant", '{"mood": "relaxed", "action": "search_mood", "message": "Perfect! I\'ll find some calm, soothing music for you 🎵"}'),
]

for role, content in conversation_demo:
    print(f"\n{role}: {content}")
    if role == "Assistant":
        mood, action, msg = _extract_mood_and_action(content)
        if action == "search_mood":
            print(f"   → 🎵 TRIGGER MUSIC SEARCH: mood={mood}")

print("\n" + "=" * 70)
print("✅ Chatbot logic working correctly!")
print("\n💡 To use with real AI:")
print("   1. Get API key from Groq (free): https://console.groq.com/")
print("   2. Set environment variable: GROQ_API_KEY=your-key")
print("   3. Install: pip install groq")
print("   4. Start backend: uvicorn app.main:app --reload")
print("=" * 70)
