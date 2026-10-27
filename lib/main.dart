import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;

const _proxyUrl = String.fromEnvironment('AI_PROXY_URL');
const _background = Color(0xFF050A12);
const _panel = Color(0xFF0B1422);
const _blue = Color(0xFF28C7FF);
const _muted = Color(0xFF8DA3B8);

void main() {
  runApp(const JarvisApp());
}

class JarvisApp extends StatelessWidget {
  const JarvisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JARVIS AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const ChatScreen(),
    );
  }
}

enum AssistantLanguage {
  english('English', 'en-US', 'EN'),
  tamil('தமிழ்', 'ta-IN', 'தமிழ்');

  const AssistantLanguage(this.label, this.locale, this.shortLabel);

  final String label;
  final String locale;
  final String shortLabel;
}

class ChatMessage {
  const ChatMessage({
    required this.text,
    required this.isUser,
    this.isError = false,
  });

  final String text;
  final bool isUser;
  final bool isError;
}

class AiProxyException implements Exception {
  const AiProxyException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _speech = stt.SpeechToText();
  final _tts = FlutterTts();
  final _httpClient = http.Client();
  final List<ChatMessage> _messages = [
    const ChatMessage(
      text:
          'Hello. I am JARVIS, your personal assistant. Ask me something, '
          'or try “help” to see what I can do offline.',
      isUser: false,
    ),
  ];
  final List<Map<String, String>> _conversation = [];

  AssistantLanguage _language = AssistantLanguage.english;
  bool _isSending = false;
  bool _isListening = false;
  bool _speechAvailable = false;

  Uri? get _proxyUri {
    final uri = Uri.tryParse(_proxyUrl.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return null;
    }
    return uri;
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _httpClient.close();
    unawaited(_speech.cancel());
    unawaited(_tts.stop());
    super.dispose();
  }

  void _addMessage(ChatMessage message) {
    setState(() => _messages.add(message));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isSending) return;

    _inputController.clear();
    _addMessage(ChatMessage(text: text, isUser: true));
    setState(() => _isSending = true);

    try {
      final reply = _proxyUrl.isEmpty
          ? _offlineReply(text)
          : await _onlineReply(text);
      if (!mounted) return;
      _addMessage(ChatMessage(text: reply, isUser: false));
      if (_proxyUrl.isNotEmpty) {
        _conversation
          ..add({'role': 'user', 'content': text})
          ..add({'role': 'assistant', 'content': reply});
        while (_conversation.length > 12) {
          _conversation.removeAt(0);
          _conversation.removeAt(0);
        }
      }
    } on AiProxyException catch (error) {
      if (mounted) {
        _addMessage(
          ChatMessage(text: error.message, isUser: false, isError: true),
        );
      }
    } on http.ClientException {
      if (mounted) {
        _addMessage(
          const ChatMessage(
            text:
                'I could not reach the AI service. Check your internet '
                'connection and try again. Your message was not sent.',
            isUser: false,
            isError: true,
          ),
        );
      }
    } on TimeoutException {
      if (mounted) {
        _addMessage(
          const ChatMessage(
            text: 'The AI service took too long to respond. Please try again.',
            isUser: false,
            isError: true,
          ),
        );
      }
    } on FormatException {
      if (mounted) {
        _addMessage(
          const ChatMessage(
            text:
                'The AI service sent an invalid reply. Check the proxy setup.',
            isUser: false,
            isError: true,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<String> _onlineReply(String text) async {
    final uri = _proxyUri;
    if (uri == null) {
      throw const AiProxyException(
        'The AI proxy address is invalid. Set AI_PROXY_URL to your HTTPS '
        'Cloudflare Worker address and rebuild the app.',
      );
    }

    final messages = [
      ..._conversation,
      {'role': 'user', 'content': text},
    ];
    final response = await _httpClient
        .post(
          uri,
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({
            'messages': messages,
            'language': _language == AssistantLanguage.tamil
                ? 'Tamil'
                : 'English',
          }),
        )
        .timeout(const Duration(seconds: 45));

    if (response.statusCode != 200) {
      throw AiProxyException(
        'The AI service returned an error (${response.statusCode}). '
        'Please try again later.',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['reply'] is! String) {
      throw const AiProxyException(
        'The AI service sent an unexpected reply. Check the proxy setup.',
      );
    }
    return (decoded['reply'] as String).trim();
  }

  String _offlineReply(String prompt) {
    final normalized = prompt.toLowerCase();
    final isTamil = _language == AssistantLanguage.tamil;

    if (normalized.contains('help') ||
        normalized.contains('உதவி') ||
        normalized.contains('what can you do')) {
      return isTamil
          ? 'இணையமின்றி, “நேரம்” அல்லது “தேதி” என்று கேட்கலாம். AI உரையாடலுக்கு '
                'இணைய இணைப்பும் அமைக்கப்பட்ட AI சேவையும் தேவை.'
          : 'Offline, I can tell you the time or date and show this help. '
                'For AI chat, connect to the internet and configure the secure '
                'AI service.';
    }
    if (normalized.contains('time') || normalized.contains('நேரம்')) {
      final now = DateTime.now();
      final time =
          '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}';
      return isTamil ? 'இப்போது நேரம் $time.' : 'The time is $time.';
    }
    if (normalized.contains('date') || normalized.contains('தேதி')) {
      final now = DateTime.now();
      final date =
          '${now.day.toString().padLeft(2, '0')}/'
          '${now.month.toString().padLeft(2, '0')}/${now.year}';
      return isTamil ? 'இன்றைய தேதி $date.' : 'Today is $date.';
    }
    return isTamil
        ? 'நான் இப்போது ஆஃப்லைனில் இருக்கிறேன். “உதவி”, “நேரம்” அல்லது “தேதி” '
              'என்று முயற்சிக்கவும். AI உரையாடலுக்கு இணைய இணைப்பு தேவை.'
        : 'I am offline right now. Try “help”, “time”, or “date”. '
              'AI chat needs an internet connection and a configured AI service.';
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      return;
    }

    _speechAvailable = await _speech.initialize(
      onStatus: (status) {
        if (!mounted) return;
        setState(() => _isListening = status == 'listening');
      },
      onError: (error) {
        if (!mounted) return;
        setState(() => _isListening = false);
        _showNotice('Microphone error: ${error.errorMsg}');
      },
    );

    if (!_speechAvailable) {
      if (mounted) {
        _showNotice(
          'Speech recognition is unavailable. Check microphone permission '
          'and your device speech service.',
        );
      }
      return;
    }

    await _speech.listen(
      listenOptions: stt.SpeechListenOptions(
        localeId: _language.locale,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
      ),
      onResult: (result) {
        if (!mounted) return;
        setState(() => _inputController.text = result.recognizedWords);
      },
    );
    if (mounted) setState(() => _isListening = true);
  }

  Future<void> _speak(String text) async {
    try {
      await _tts.setLanguage(_language.locale);
      await _tts.speak(text);
    } on PlatformException {
      if (mounted) {
        _showNotice(
          'Text-to-speech is not available for ${_language.label} on this '
          'device. Install a matching voice in Android settings.',
        );
      }
    }
  }

  void _showNotice(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final proxyConfigured = _proxyUrl.isNotEmpty;
    final proxyInvalid = proxyConfigured && _proxyUri == null;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(proxyConfigured, proxyInvalid),
            Expanded(child: _buildMessages()),
            if (_isSending) const _ThinkingIndicator(),
            _buildComposer(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool proxyConfigured, bool proxyInvalid) {
    final status = proxyInvalid
        ? 'CHECK AI URL'
        : proxyConfigured
        ? 'AI PROXY READY'
        : 'OFFLINE READY';
    final statusColor = proxyInvalid
        ? Colors.orangeAccent
        : proxyConfigured
        ? _blue
        : _muted;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF13243A))),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _blue.withValues(alpha: 0.1),
              border: Border.all(color: _blue.withValues(alpha: 0.55)),
              boxShadow: [
                BoxShadow(color: _blue.withValues(alpha: 0.25), blurRadius: 18),
              ],
            ),
            child: const Icon(Icons.blur_on, color: _blue, size: 29),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'JARVIS AI',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'PERSONAL ASSISTANT',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 9,
                    letterSpacing: 1.6,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              DropdownButtonHideUnderline(
                child: DropdownButton<AssistantLanguage>(
                  key: const ValueKey('language-selector'),
                  value: _language,
                  dropdownColor: _panel,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  items: AssistantLanguage.values
                      .map(
                        (language) => DropdownMenuItem(
                          value: language,
                          child: Text(language.shortLabel),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _language = value);
                  },
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 7, color: statusColor),
                  const SizedBox(width: 5),
                  Text(
                    status,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 8,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 20),
      itemCount: _messages.length,
      itemBuilder: (context, index) => _MessageBubble(
        message: _messages[index],
        onSpeak: () => _speak(_messages[index].text),
      ),
    );
  }

  Widget _buildComposer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: const BoxDecoration(
        color: _background,
        border: Border(top: BorderSide(color: Color(0xFF13243A))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            onPressed: _toggleListening,
            tooltip: _isListening ? 'Stop listening' : 'Use microphone',
            color: _isListening ? Colors.redAccent : _blue,
            icon: Icon(_isListening ? Icons.mic : Icons.mic_none),
          ),
          Expanded(
            child: TextField(
              key: const ValueKey('chat-input'),
              controller: _inputController,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: _language == AssistantLanguage.tamil
                    ? 'JARVIS-ஐக் கேளுங்கள்...'
                    : 'Ask JARVIS anything...',
                hintStyle: const TextStyle(color: _muted, fontSize: 13),
                filled: true,
                fillColor: _panel,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _blue.withValues(alpha: 0.14),
              boxShadow: [
                BoxShadow(color: _blue.withValues(alpha: 0.15), blurRadius: 14),
              ],
            ),
            child: IconButton(
              onPressed: _isSending ? null : _sendMessage,
              tooltip: 'Send message',
              color: _blue,
              icon: const Icon(Icons.arrow_upward),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.onSpeak});

  final ChatMessage message;
  final VoidCallback onSpeak;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final bubbleColor = message.isError
        ? const Color(0xFF301A1C)
        : isUser
        ? const Color(0xFF102943)
        : _panel;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 330),
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(15, 12, 10, 9),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(18).copyWith(
            bottomRight: isUser ? const Radius.circular(5) : null,
            bottomLeft: isUser ? null : const Radius.circular(5),
          ),
          border: Border.all(
            color: message.isError
                ? Colors.redAccent.withValues(alpha: 0.35)
                : isUser
                ? _blue.withValues(alpha: 0.25)
                : const Color(0xFF1A2B40),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.text,
              style: TextStyle(
                color: message.isError ? Colors.orange[100] : Colors.white,
                height: 1.45,
                fontSize: 14,
              ),
            ),
            if (!isUser && !message.isError)
              Align(
                alignment: Alignment.bottomRight,
                child: IconButton(
                  onPressed: onSpeak,
                  tooltip: 'Read reply aloud',
                  visualDensity: VisualDensity.compact,
                  iconSize: 17,
                  color: _muted,
                  icon: const Icon(Icons.volume_up_outlined),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ThinkingIndicator extends StatelessWidget {
  const _ThinkingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: _blue),
          ),
          SizedBox(width: 10),
          Text(
            'JARVIS is thinking...',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
