// Hybrid AIService implementation
// Uses Firebase Functions for chat and Render.com API for food analysis

import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:cloud_functions/cloud_functions.dart';
import '../services/food_analyzer_api.dart';
import '../models/ingredient_item.dart';

class AIService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  bool _hasInitializationError = false;

  /// Stream for receiving real-time token updates
  StreamController<String>? _streamController;

  /// Begin streaming AI response and return a stream of token chunks
  Stream<String> streamAIResponse(List<Map<String, dynamic>> messages) {
    // Create a stream controller
    _streamController = StreamController<String>();

    // Start the streaming process
    _getStreamingResponse(messages);

    // Return the stream for the UI to listen to
    return _streamController!.stream;
  }

  /// Private method to handle streaming response
  Future<void> _getStreamingResponse(
      List<Map<String, dynamic>> messages) async {
    try {
      // Check if we had initialization errors before
      if (_hasInitializationError) {
        throw Exception("Firebase functions not available - using fallback");
      }

      print(
          "AI Service: Preparing streaming request with ${messages.length} messages");

      // Create a flat structure for the messages
      final List<Map<String, String>> safeMessages = [];

      // Add a system message with formatting instructions
      safeMessages.add({
        'role': 'system',
        'content': 'You are a premium fitness and nutrition coach inside the Fitly app. All responses must follow these rules:\n\n'
            '1. Be clear, concise, and easy to follow.\n\n'
            '2. Use bold section headers with double asterisks (e.g., **Nutrition Tips:**, **Workout Plan:**, **Progress Tips:**).\n\n'
            '3. Use single asterisks for medium emphasis text (e.g., *Important:*, *Note:*, *Remember:*).\n\n'
            '4. Break info into short bullet points — each line should feel tight and useful.\n\n'
            '5. Avoid paragraphs or long explanations. Aim for a clean, modern premium app tone.\n\n'
            '6. All numbers must be rounded and practical (e.g., 3-5x/week, 100g chicken = 165 cal).\n\n'
            '7. Include actionable tips or structure when relevant (e.g., meals, routines, mindset).\n\n'
            '8. Never over-explain. No motivational fluff. Just smart, efficient advice.\n\n'
            '9. Keep formatting consistent across all answers (bullets, bold labels, calorie info etc).\n\n'
            '10. CRITICALLY IMPORTANT: Insert EXACTLY ONE empty line after EVERY heading.\n\n'
            '11. DO NOT use markdown syntax with # or ### symbols anywhere.\n\n'
            '12. DO NOT use quotation marks around examples or anywhere else in your response.\n\n'
            '13. Example structure:\n\n'
            '**Goal Plan:**\n\n'
            '- Calories: Target 300–500 kcal deficit/day\n'
            '- Protein: Prioritize *lean sources* (e.g., chicken, eggs)\n'
            '- Veggies: Half plate; spinach/broccoli are low cal\n\n'
            '**Training:**\n\n'
            '- Cardio: 3–5x/week (burns 150–300 kcal/session)\n'
            '- Strength: 2–3x/week (preserve muscle)\n\n'
            '**Tips:**\n\n'
            '- Track food *daily*\n'
            '- Sleep 7–9 hrs/night\n'
            '- Weigh once/week only\n\n'
            'Always respond in this format unless asked to be casual or conversational.'
      });

      // Add the user messages
      for (final msg in messages) {
        safeMessages.add({
          'role': (msg['role'] ?? 'user').toString(),
          'content': (msg['content'] ?? '').toString(),
        });
      }

      try {
        // Create a direct streaming implementation using the function
        final streamController = StreamController<String>();

        // Use Firebase Functions SDK to set up streaming listener
        final callable = _functions.httpsCallable(
          'streamAIResponse',
          options: HttpsCallableOptions(
            timeout: const Duration(seconds: 60),
          ),
        );

        // Set up real-time streaming
        callable.call({'messages': safeMessages}).then((result) {
          final data = result.data as Map<String, dynamic>;

          if (data['success'] == true) {
            // If we already received chunks in result, process them immediately
            if (data.containsKey('chunks') &&
                data['chunks'] is List &&
                (data['chunks'] as List).isNotEmpty) {
              print(
                  "Received ${(data['chunks'] as List).length} chunks in response");

              // Instead of adding chunks all at once, add them with a tiny delay
              // to simulate the streaming effect
              _streamChunksWithDelay(
                  data['chunks'] as List, _streamController!);
            }
            // If there's just fullContent, simulate typing it out
            else if (data.containsKey('fullContent') &&
                data['fullContent'] is String) {
              _simulateStreaming(
                  data['fullContent'] as String, _streamController!);
            }
            // If there's just content, simulate typing it out
            else if (data.containsKey('content') && data['content'] is String) {
              _simulateStreaming(data['content'] as String, _streamController!);
            } else {
              throw Exception('No content found in response');
            }
          } else {
            throw Exception(
                'API request failed: ${data['error'] ?? 'Unknown error'}');
          }
        }).catchError((error) {
          print('AI Service: Streaming function call error: $error');
          // Mark that we had an initialization error so we don't try again
          _hasInitializationError = true;
          // Fallback to non-streaming approach
          _fallbackToNonStreaming(safeMessages, _streamController!);
        });
      } catch (callError) {
        print('AI Service: Initial function call error: $callError');
        // Mark that we had an initialization error so we don't try again
        _hasInitializationError = true;
        // Fallback to non-streaming approach
        _fallbackToNonStreaming(safeMessages, _streamController!);
      }
    } catch (e) {
      print('AI Service: Error: $e');
      if (_streamController != null && !_streamController!.isClosed) {
        // Use the fallback content for demo purposes
        _simulateStreamingWithFallbackContent(_streamController!);
      }
    }
  }

  /// Stream chunks from a list with a minimal delay between each
  void _streamChunksWithDelay(
      List chunks, StreamController<String> controller) async {
    if (_streamController == null || _streamController!.isClosed) return;

    for (final chunk in chunks) {
      if (_streamController!.isClosed) return;

      // Add chunk to the stream
      controller.add(chunk.toString());

      // Add a tiny delay to make it feel like real-time typing
      // This makes it feel more natural than dumping all at once
      await Future.delayed(Duration(milliseconds: 10));
    }

    // Close the stream when done
    if (!_streamController!.isClosed) {
      controller.close();
    }
  }

  /// Fallback to non-streaming approach on error
  Future<void> _fallbackToNonStreaming(List<Map<String, String>> safeMessages,
      StreamController<String> controller) async {
    try {
      print("Falling back to non-streaming approach");

      final HttpsCallable callable = _functions.httpsCallable(
        'getAIResponse',
        options: HttpsCallableOptions(
          timeout: const Duration(seconds: 60),
        ),
      );

      final result = await callable.call({'messages': safeMessages});
      final data = result.data as Map<String, dynamic>;

      if (data['success'] == true &&
          (data['content'] is String || data['fullContent'] is String)) {
        final content =
            data['content'] as String? ?? data['fullContent'] as String;
        _simulateStreaming(content, controller);
      } else {
        throw Exception('Non-streaming fallback also failed');
      }
    } catch (fallbackError) {
      print('AI Service: Fallback also failed: $fallbackError');
      if (_streamController != null && !_streamController!.isClosed) {
        // Use the fallback content for demo purposes
        _simulateStreamingWithFallbackContent(controller);
      }
    }
  }

  /// Simulate streaming response by breaking content into chunks
  void _simulateStreaming(
      String content, StreamController<String> controller) async {
    if (_streamController == null || _streamController!.isClosed) return;

    // Break the content into chunks (words)
    final words = content.split(' ');

    for (int i = 0; i < words.length; i++) {
      if (_streamController!.isClosed) return;

      // Stream 2-5 words at a time to simulate natural typing
      final chunkSize = 2 + (i % 4); // Varies between 2-5 for natural feel
      final endIndex =
          (i + chunkSize < words.length) ? i + chunkSize : words.length;
      final chunk = words.sublist(i, endIndex).join(' ') + ' ';

      controller.add(chunk);
      i = endIndex -
          1; // Move the index forward (minus 1 because the loop will increment)

      // Add a tiny delay to make it feel like real-time typing
      await Future.delayed(Duration(milliseconds: 15 + (chunk.length ~/ 5)));
    }

    // Close the stream when done
    if (!_streamController!.isClosed) {
      controller.close();
    }
  }

  /// Fallback content for demo purposes
  void _simulateStreamingWithFallbackContent(
      StreamController<String> controller) async {
    // Predefined fallback response for when all else fails
    const fallbackContent = '''**Fitness Plan:**

- Focus on 3-4 workouts per week (45 min sessions)
- Alternate between strength training and cardio
- Aim for 7,500-10,000 steps daily
- Include 2 active recovery days (light walking, yoga)

**Nutrition Tips:**

- Maintain caloric deficit of 300-500 calories daily
- Protein goal: 1.6-2g per kg of bodyweight 
- Stay hydrated (2-3 liters water daily)
- Prioritize whole foods over supplements

**Progress Tips:**

- Take weekly progress photos
- Track measurements monthly
- Adjust calories as needed
- *Remember:* Consistency beats perfection!
''';

    _simulateStreaming(fallbackContent, controller);
  }

  /// Function to analyze a food image using Render.com API
  Future<Map<String, dynamic>> analyzeFoodImage(Uint8List imageBytes) async {
    try {
      // Use the FoodAnalyzerApi class to call the Render.com API
      final nutritionResponse = await FoodAnalyzerApi.analyzeFoodImage(imageBytes);
      
      // Convert NutritionResponse to Map<String, dynamic> for backward compatibility
      return nutritionResponse.toJson();
    } catch (e) {
      print('AI Service: Error analyzing food: $e');

      // Fallback to simple response in case of error
      return {
        'text':
            'Sorry, I couldn\'t analyze this image. Please try again with a clearer photo of your food.'
      };
    }
  }

  /// Dispose method to clean up resources
  void dispose() {
    if (_streamController != null && !_streamController!.isClosed) {
      _streamController!.close();
    }
  }
}
