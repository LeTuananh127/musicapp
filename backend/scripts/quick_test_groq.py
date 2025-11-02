"""
Quick Groq API Test - Test connection and chat
Run after: pip install groq
"""
import os

print("=" * 70)
print("GROQ API - Quick Test")
print("=" * 70)

# Step 1: Check API key
api_key = os.environ.get('GROQ_API_KEY')
if not api_key:
    print("\n[ERROR] GROQ_API_KEY not set!")
    print("\nSet it with:")
    print('  PowerShell: $env:GROQ_API_KEY="gsk_YOUR_KEY"')
    print('  CMD:        set GROQ_API_KEY=gsk_YOUR_KEY')
    exit(1)

print(f"\n[OK] API Key found: {api_key[:20]}...{api_key[-4:]}")

# Step 2: Check package
try:
    from groq import Groq
    print("[OK] Groq package installed")
except ImportError:
    print("\n[ERROR] Groq package not installed!")
    print("Install with: pip install groq")
    exit(1)

# Step 3: Test simple API call
print("\n" + "=" * 70)
print("Testing API Call...")
print("=" * 70)

try:
    client = Groq(api_key=api_key)
    
    response = client.chat.completions.create(
        model="llama-3.3-70b-versatile",  # Updated model
        messages=[
            {"role": "system", "content": "You are a helpful music assistant."},
            {"role": "user", "content": "I'm feeling tired. What kind of music should I listen to?"}
        ],
        max_tokens=150,
        temperature=0.7
    )
    
    bot_reply = response.choices[0].message.content
    
    print("\n[USER] I'm feeling tired. What kind of music should I listen to?")
    print(f"\n[BOT] {bot_reply}")
    
    print("\n" + "=" * 70)
    print("[SUCCESS] Groq API is working!")
    print("=" * 70)
    
    print("\n[NEXT STEPS]")
    print("1. Start backend: uvicorn app.main:app --reload")
    print("2. Test chat API: python scripts/test_chat_api.py")
    print("3. Or use PowerShell: .\\test_chat_api.ps1")
    
except Exception as e:
    print(f"\n[ERROR] API call failed: {e}")
    print("\n[TROUBLESHOOTING]")
    print("- Check your API key at https://console.groq.com/")
    print("- Verify internet connection")
    print("- Check rate limits (30 requests/minute)")
