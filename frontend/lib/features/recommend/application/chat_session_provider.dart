import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

/// Model for chat message
class ChatMessage {
  final String role; // 'user' or 'assistant'
  final String content;
  final DateTime timestamp;

  ChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      role: json['role'] as String,
      content: json['content'] as String,
      timestamp: json['timestamp'] != null 
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
    );
  }
}

/// Chat state that persists across widget rebuilds
class ChatState {
  final String sessionId;
  final List<ChatMessage> messages;
  final String? detectedMood;
  final bool isLoading;

  ChatState({
    required this.sessionId,
    this.messages = const [],
    this.detectedMood,
    this.isLoading = false,
  });

  ChatState copyWith({
    String? sessionId,
    List<ChatMessage>? messages,
    String? detectedMood,
    bool? isLoading,
    bool clearMood = false,  // Explicit flag to clear mood
  }) {
    return ChatState(
      sessionId: sessionId ?? this.sessionId,
      messages: messages ?? this.messages,
      detectedMood: clearMood ? null : (detectedMood ?? this.detectedMood),
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// Notifier for managing chat state
class ChatStateNotifier extends StateNotifier<ChatState> {
  ChatStateNotifier() : super(ChatState(sessionId: const Uuid().v4()));

  void addMessage(ChatMessage message) {
    state = state.copyWith(
      messages: [...state.messages, message],
    );
  }

  void setMessages(List<ChatMessage> messages) {
    state = state.copyWith(messages: messages);
  }

  void setMood(String? mood) {
    state = state.copyWith(detectedMood: mood);
  }

  void clearMood() {
    state = state.copyWith(clearMood: true);
  }

  void setLoading(bool loading) {
    state = state.copyWith(isLoading: loading);
  }

  void reset() {
    state = ChatState(sessionId: const Uuid().v4());
  }
}

/// Provider for chat state (persists across widget rebuilds)
/// Using regular StateNotifierProvider (not autoDispose) to keep state alive
final chatStateProvider = StateNotifierProvider<ChatStateNotifier, ChatState>((ref) {
  return ChatStateNotifier();
});

/// Provides a persistent chat session ID that survives widget rebuilds
/// This ensures conversation history is maintained when reopening the chatbot
final chatSessionProvider = StateProvider<String>((ref) {
  return const Uuid().v4();
});

/// Provider to reset chat session (creates new session ID)
final resetChatSessionProvider = Provider<void Function()>((ref) {
  return () {
    ref.read(chatSessionProvider.notifier).state = const Uuid().v4();
  };
});
