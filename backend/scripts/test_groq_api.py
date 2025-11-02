"""
Test Groq API connection
Run this after setting GROQ_API_KEY environment variable
"""
import os

print("=" * 70)
print("Testing Groq API Connection")
print("=" * 70)

# Check if API key is set
api_key = os.environ.get('GROQ_API_KEY')
if not api_key:
    print("\n❌ GROQ_API_KEY not found in environment variables!")
    print("\n📝 To fix this:")
    print("   PowerShell: $env:GROQ_API_KEY='gsk_YOUR_KEY_HERE'")
    print("   CMD:        set GROQ_API_KEY=gsk_YOUR_KEY_HERE")
    print("   Or create .env file in backend/ folder")
    print("\n🔑 Get free key from: https://console.groq.com/")
    exit(1)

print(f"\n✅ API Key found: {api_key[:20]}...{api_key[-4:]}")

# Try to import groq
try:
    from groq import Groq
    print("✅ Groq package installed")
except ImportError:
    print("\n❌ Groq package not installed!")
    print("   Install with: pip install groq")
    exit(1)

# Test API call
print("\n🔄 Testing API call...")
try:
    client = Groq(api_key=api_key)
    
    # Simple test message
    response = client.chat.completions.create(
        model="llama-3.3-70b-versatile",  # Updated model
        messages=[
            {"role": "system", "content": "You are a helpful assistant."},
            {"role": "user", "content": "Say 'Hello! API is working!' in a fun way."}
        ],
        max_tokens=100,
        temperature=0.7
    )
    
    bot_response = response.choices[0].message.content
    print(f"\n✅ API Response:")
    print(f"   {bot_response}")
    
    print("\n" + "=" * 70)
    print("🎉 SUCCESS! Groq API is working perfectly!")
    print("=" * 70)
    print("\n💡 Next steps:")
    print("   1. Start backend: cd C:\\musicapp\\backend")
    print("   2. Run: uvicorn app.main:app --reload --host 0.0.0.0 --port 8000")
    print("   3. Test chat endpoint (see test_chat_api.py)")
    
except Exception as e:
    print(f"\n❌ API Error: {e}")
    print("\n🔍 Possible issues:")
    print("   - Invalid API key")
    print("   - Network connection problem")
    print("   - Rate limit exceeded")
    print("   - Check https://console.groq.com/ for key status")
