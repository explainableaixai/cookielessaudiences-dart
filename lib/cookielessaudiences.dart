// Client for the Cookieless Audiences API.

import 'dart:convert';

import 'package:http/http.dart' as http;

const _base = 'https://www.cookielessaudiences.com';

const _statusText = <int, String>{
  400: 'Bad request, check the parameters',
  401: 'Invalid API key',
  403: 'Key not active or monthly credits used up',
  407: 'Missing data_type, must be url or text',
  410: 'Not enough content in the page or text',
  411: 'The URL content could not be fetched',
  500: 'General error, check the request or contact support',
};

/// Thrown when the JSON body carries a status other than 200.
class CookielessAudiencesException implements Exception {
  CookielessAudiencesException(this.status, this.message, [this.body]);
  final int status;
  final String message;
  final Map<String, dynamic>? body;

  @override
  String toString() => 'CookielessAudiencesException($status): $message';
}

class CookielessAudiences {
  CookielessAudiences(this.apiKey, {http.Client? client, this.timeout = const Duration(seconds: 120)})
      : _client = client ?? http.Client();

  final String apiKey;
  final Duration timeout;
  final http.Client _client;

  Future<Map<String, dynamic>> _post(String path, Map<String, String> form) async {
    final res = await _client.post(Uri.parse('$_base$path'), body: form).timeout(timeout);
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw CookielessAudiencesException(res.statusCode, 'Response was not a JSON object');
    }
    final status = decoded['status'] is int ? decoded['status'] as int : 200;
    if (status != 200) {
      throw CookielessAudiencesException(status, _statusText[status] ?? 'API error', decoded);
    }
    return decoded;
  }

  /// Page-level audience segmentation. Set [structured] to false for the legacy free-text shape.
  Future<Map<String, dynamic>> segment(String url, {bool structured = true}) {
    return _post('/api/audience/segment.php', {
      'query': url,
      'api_key': apiKey,
      if (structured) 'format': 'structured',
    });
  }

  /// IAB content categorization of a URL.
  Future<Map<String, dynamic>> categorize(String url, {bool confidence = true, bool rootFallback = false}) {
    return _post('/api/iab/iab_web_content_filtering.php', {
      'query': url,
      'api_key': apiKey,
      'data_type': 'url',
      if (confidence) 'confidence': '1',
      if (rootFallback) 'use_domain_as_basis_of_categorization_for_insufficient_subdomain_content': '1',
    });
  }

  /// IAB content categorization of plain text.
  Future<Map<String, dynamic>> categorizeText(String text, {bool confidence = true}) {
    return _post('/api/iab/iab_content_filtering.php', {
      'query': text,
      'api_key': apiKey,
      'data_type': 'text',
      if (confidence) 'confidence': '1',
    });
  }

  /// Public vocabularies, no API key needed.
  static Future<Map<String, dynamic>> vocabularies({http.Client? client}) async {
    final res = await (client ?? http.Client()).get(Uri.parse('$_base/api/audience/filters.php'));
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  /// Readable labels for the INT.* and PI.* codes of a structured response.
  static List<String> labelsFor(Map<String, dynamic> result) {
    final names = (result['labels'] as Map?) ?? const {};
    final out = <String>[];
    for (final group in ['interests', 'purchase_intent']) {
      final block = result[group];
      if (block is! Map) continue;
      for (final key in ['tier1', 'tier2', 'codes']) {
        final list = block[key];
        if (list is List) {
          for (final code in list) {
            out.add((names[code] ?? code).toString());
          }
        }
      }
    }
    return out;
  }

  void close() => _client.close();
}
