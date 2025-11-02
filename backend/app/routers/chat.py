"""
Conversational Chatbot for Music Recommendations
Supports OpenAI, Gemini, and Groq APIs with conversation history
"""
from typing import List, Optional, Dict, Any
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
import os
import json
from datetime import datetime

router = APIRouter(prefix="/chat", tags=["chat"])

# In-memory conversation storage (session_id -> messages)
# In production, use Redis or database
_conversations: Dict[str, List[Dict[str, str]]] = {}

class ChatMessage(BaseModel):
    role: str  # 'user' or 'assistant'
    content: str
    timestamp: Optional[str] = None

class ChatRequest(BaseModel):
    session_id: str
    message: str
    provider: Optional[str] = "openai"  # openai, gemini, groq
    include_music_context: Optional[bool] = True

class ChatResponse(BaseModel):
    session_id: str
    message: str
    mood: Optional[str] = None
    suggested_action: Optional[str] = None  # 'search_mood', 'refine_query', 'chat_only'
    history: List[ChatMessage]

# System prompt for music recommendation assistant
SYSTEM_PROMPT = """You are a friendly music recommendation assistant. Your role is to:
1. Chat naturally with users about their music preferences and current mood
2. Ask clarifying questions if needed (e.g., "Do you want something energetic or calm?")
3. Detect when the user wants music recommendations
4. Extract mood keywords: energetic, relaxed, angry, sad

When you detect the user wants music, respond with a JSON object:
{"mood": "energetic|relaxed|angry|sad", "action": "search_mood", "message": "your friendly response"}

Otherwise, just chat naturally and ask follow-up questions.

Examples:
User: "I'm feeling tired"
You: "Aww, do you want something relaxing to help you rest, or energetic music to wake you up? 😊"

User: "Something to help me focus on work"
You: {"mood": "relaxed", "action": "search_mood", "message": "Great! I'll find some calm, focused music for you 🎵"}

Be conversational, warm, and helpful. Use emojis occasionally."""

def _get_conversation(session_id: str) -> List[Dict[str, str]]:
    """Get or create conversation history for a session"""
    if session_id not in _conversations:
        _conversations[session_id] = [
            {"role": "system", "content": SYSTEM_PROMPT}
        ]
    return _conversations[session_id]

def _chat_with_openai(messages: List[Dict[str, str]]) -> str:
    """Call OpenAI ChatGPT API"""
    try:
        import openai
        api_key = os.environ.get('OPENAI_API_KEY')
        if not api_key:
            return "⚠️ OpenAI API key not configured. Set OPENAI_API_KEY environment variable."
        
        openai.api_key = api_key
        response = openai.ChatCompletion.create(
            model=os.environ.get('OPENAI_MODEL', 'gpt-3.5-turbo'),
            messages=messages,
            max_tokens=300,
            temperature=0.7
        )
        return response['choices'][0]['message']['content']
    except Exception as e:
        return f"❌ OpenAI error: {str(e)}"

def _chat_with_gemini(messages: List[Dict[str, str]]) -> str:
    """Call Google Gemini API"""
    try:
        import google.generativeai as genai
        api_key = os.environ.get('GEMINI_API_KEY')
        if not api_key:
            return "⚠️ Gemini API key not configured. Set GEMINI_API_KEY environment variable."
        
        genai.configure(api_key=api_key)
        model = genai.GenerativeModel('gemini-pro')
        
        # Convert messages to Gemini format (combine system + conversation)
        prompt = "\n".join([
            f"{msg['role']}: {msg['content']}" 
            for msg in messages if msg['role'] != 'system'
        ])
        system = next((m['content'] for m in messages if m['role'] == 'system'), '')
        full_prompt = f"{system}\n\nConversation:\n{prompt}\nassistant:"
        
        response = model.generate_content(full_prompt)
        return response.text
    except Exception as e:
        return f"❌ Gemini error: {str(e)}"

def _chat_with_groq(messages: List[Dict[str, str]]) -> str:
    """Call Groq API (Llama 3)"""
    try:
        from groq import Groq
        api_key = os.environ.get('GROQ_API_KEY')
        if not api_key:
            return "⚠️ Groq API key not configured. Set GROQ_API_KEY environment variable."
        
        client = Groq(api_key=api_key)
        response = client.chat.completions.create(
            model="llama-3.3-70b-versatile",  # Updated model
            messages=messages,
            max_tokens=300,
            temperature=0.7
        )
        return response.choices[0].message.content
    except Exception as e:
        return f"❌ Groq error: {str(e)}"

def _extract_mood_and_action(response_text: str) -> tuple[Optional[str], Optional[str], str]:
    """Extract mood and action from LLM response if it's JSON format"""
    try:
        # Try to parse as JSON
        data = json.loads(response_text)
        mood = data.get('mood')
        action = data.get('action', 'chat_only')
        message = data.get('message', response_text)
        return mood, action, message
    except:
        # Not JSON, just regular chat response
        # Try to detect mood keywords in text
        text_lower = response_text.lower()
        detected_mood = None
        if 'energetic' in text_lower or 'energy' in text_lower:
            detected_mood = 'energetic'
        elif 'relaxed' in text_lower or 'calm' in text_lower or 'chill' in text_lower:
            detected_mood = 'relaxed'
        elif 'angry' in text_lower or 'intense' in text_lower:
            detected_mood = 'angry'
        elif 'sad' in text_lower or 'melancholic' in text_lower:
            detected_mood = 'sad'
        
        return detected_mood, 'chat_only', response_text

@router.post('/send', response_model=ChatResponse)
def send_message(req: ChatRequest):
    """
    Send a message to the conversational chatbot
    Supports multi-turn conversations with context
    """
    # Get conversation history
    conversation = _get_conversation(req.session_id)
    
    # Add user message to history
    user_msg = {"role": "user", "content": req.message}
    conversation.append(user_msg)
    
    # Call appropriate LLM
    provider = req.provider.lower()
    if provider == "openai":
        assistant_response = _chat_with_openai(conversation)
    elif provider == "gemini":
        assistant_response = _chat_with_gemini(conversation)
    elif provider == "groq":
        assistant_response = _chat_with_groq(conversation)
    else:
        raise HTTPException(status_code=400, detail=f"Unknown provider: {provider}")
    
    # Extract mood and action
    mood, action, message = _extract_mood_and_action(assistant_response)
    
    # Add assistant response to history
    assistant_msg = {"role": "assistant", "content": message}
    conversation.append(assistant_msg)
    
    # Limit conversation history to last 20 messages (to avoid token limits)
    if len(conversation) > 21:  # 1 system + 20 messages
        conversation = [conversation[0]] + conversation[-20:]
        _conversations[req.session_id] = conversation
    
    # Convert to ChatMessage format with timestamps
    history = [
        ChatMessage(
            role=msg["role"],
            content=msg["content"],
            timestamp=datetime.now().isoformat()
        )
        for msg in conversation[1:]  # Skip system message
    ]
    
    return ChatResponse(
        session_id=req.session_id,
        message=message,
        mood=mood,
        suggested_action=action,
        history=history
    )

@router.delete('/clear/{session_id}')
def clear_conversation(session_id: str):
    """Clear conversation history for a session"""
    if session_id in _conversations:
        del _conversations[session_id]
    return {"message": f"Conversation {session_id} cleared"}

@router.get('/history/{session_id}')
def get_history(session_id: str):
    """Get conversation history for a session"""
    conversation = _get_conversation(session_id)
    history = [
        ChatMessage(
            role=msg["role"],
            content=msg["content"],
            timestamp=datetime.now().isoformat()
        )
        for msg in conversation[1:]  # Skip system message
    ]
    return {"session_id": session_id, "history": history}
