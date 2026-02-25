import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'constants.dart';

class OAuthService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const String _keyCodeVerifier = 'oauth_code_verifier';
  static const String _keyStateParam = 'oauth_state_param';

  // --- 1. PKCE Helpers ---
  String _generateCodeVerifier() {
    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    return base64UrlEncode(values).replaceAll('=', '');
  }

  String _generateCodeChallenge(String codeVerifier) {
    final bytes = ascii.encode(codeVerifier);
    final digest = sha256.convert(bytes);
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  String _generateState() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    return base64UrlEncode(values).replaceAll('=', '');
  }

  // --- 2. Launch Auth URL ---
  Future<void> launchAuthFlow() async {
    // Step A: Generate PKCE & State
    final codeVerifier = _generateCodeVerifier();
    final codeChallenge = _generateCodeChallenge(codeVerifier);
    final stateParam = _generateState();

    // Securely Store State & Verifier to survive OS App Link transitions
    await _storage.write(key: _keyCodeVerifier, value: codeVerifier);
    await _storage.write(key: _keyStateParam, value: stateParam);

    // Step B: Build Authorization URL (Points to the verified App Link domain)
    final authUrl =
        Uri.https(AppConstants.authorizeDomain, AppConstants.authorizePath, {
          'response_type': 'code',
          'client_id': AppConstants.clientId,
          'redirect_uri': AppConstants.redirectUri,
          'scope': AppConstants.scopes,
          'state': stateParam,
          'code_challenge': codeChallenge,
          'code_challenge_method': 'S256',
        });

    // Step C: Launch URL in EXTERNAL APPLICATION mode to force OS Interception
    if (await canLaunchUrl(authUrl)) {
      await launchUrl(authUrl, mode: LaunchMode.externalNonBrowserApplication);
    } else {
      throw Exception('Could not launch $authUrl');
    }
  }

  // --- 3. Validate State ---
  Future<bool> validateState(String incomingState) async {
    final savedState = await _storage.read(key: _keyStateParam);
    return savedState == incomingState;
  }

  // --- 4. Exchange Code for Token ---
  Future<Map<String, dynamic>> exchangeCodeForToken(String code) async {
    final codeVerifier = await _storage.read(key: _keyCodeVerifier);

    if (codeVerifier == null) {
      throw Exception(
        'No secure code verifier found. The session may have expired.',
      );
    }

    final tokenUrl = Uri.parse('http://${AppConstants.tokenHost}:8081/token');

    final response = await http.post(
      tokenUrl,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'authorization_code',
        'client_id': AppConstants.clientId,
        'redirect_uri': AppConstants.redirectUri,
        'code': code,
        'code_verifier': codeVerifier,
      },
    );

    // Clean up stored PKCE secrets after use
    await reset();

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception(
        'Token Exchange Failed: ${response.statusCode} - ${response.body}',
      );
    }
  }

  Future<void> reset() async {
    await _storage.delete(key: _keyCodeVerifier);
    await _storage.delete(key: _keyStateParam);
  }
}
