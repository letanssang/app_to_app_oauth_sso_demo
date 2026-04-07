import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import 'oauth_service.dart';

class ClientHomePage extends StatefulWidget {
  const ClientHomePage({super.key});

  @override
  State<ClientHomePage> createState() => _ClientHomePageState();
}

class _ClientHomePageState extends State<ClientHomePage> {
  final OAuthService _oauthService = OAuthService();

  bool _isLoading = false;
  bool _isLoggedIn = false;
  String? _accessToken;

  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  // --- 1. Deep Link Listener (App Links) ---
  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    // Listen while app is running
    _linkSubscription = _appLinks.uriLinkStream.listen((Uri? uri) {
      if (uri != null) {
        _handleCallback(uri);
      }
    });

    // Handle initial link if app was closed
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleCallback(initialUri);
      }
    } catch (e) {
      debugPrint("Initial Link Error: $e");
    }
  }

  String? _lastProcessedCode;

  // --- 2. The Callback Handler ---
  Future<void> _handleCallback(Uri uri) async {
    debugPrint('Received Callback: $uri');
    if (_isLoggedIn) return;
    if (uri.scheme == 'https' &&
        uri.host == 'bloomygardenshop.com' &&
        uri.path == '/callback') {
      final code = uri.queryParameters['code'];
      final state = uri.queryParameters['state'];
      final error = uri.queryParameters['error'];

      if (error != null) {
        setState(() => _isLoading = false);
        if (error == 'access_denied') {
          _showError('Authorization cancelled by user.');
        } else {
          _showError('Auth Error: $error');
        }
        return;
      }

      // Deduplication: Prevent app_links from firing the same link twice
      if (code != null && code == _lastProcessedCode) {
        debugPrint('Ignoring duplicate callback event for code: $code');
        return;
      }
      _lastProcessedCode = code;

      if (state == null) {
        _showError('Auth Error: Missing State parameter from callback');
        return;
      }

      // Validate state safely from Storage to prevent CSRF
      final isValidState = await _oauthService.validateState(state);
      if (!isValidState) {
        _showError(
          'Invalid State! The session might have expired or been manipulated.',
        );
        return;
      }

      if (code != null) {
        await _exchangeCode(code);
      } else {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _exchangeCode(String code) async {
    setState(() => _isLoading = true);
    try {
      final data = await _oauthService.exchangeCodeForToken(code);
      if (mounted) {
        setState(() {
          _accessToken = data['access_token'];
          _isLoggedIn = true;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Login Success!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _showError(e.toString());
    }
  }

  void _showError(String message) {
    debugPrint('Error: $message');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loginAppToApp() async {
    setState(() => _isLoading = true);
    try {
      await _oauthService.launchAuthFlow();
    } catch (e) {
      _showError('Failed to launch Auth flow: $e');
    }
  }

  void _logout() {
    setState(() {
      _isLoggedIn = false;
      _accessToken = null;
      _oauthService.reset();
    });
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Client App'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: _isLoggedIn ? _buildLoggedInView() : _buildLoginView(),
        ),
      ),
    );
  }

  Widget _buildLoginView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.account_circle, size: 100, color: Colors.deepPurple),
        const SizedBox(height: 32),
        const Text(
          'Welcome to Client App',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        const Text(
          'OAuth 2.0 Native Interception',
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
        const SizedBox(height: 48),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton.icon(
            onPressed: _isLoading ? null : _loginAppToApp,
            icon: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.security),
            label: const Text(
              'Login with Auth Provider App',
              style: TextStyle(fontSize: 18),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoggedInView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle, size: 100, color: Colors.green),
        const SizedBox(height: 32),
        const Text(
          'You are logged in!',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Access Token:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                _accessToken ?? 'N/A',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        OutlinedButton.icon(
          onPressed: _logout,
          icon: const Icon(Icons.logout),
          label: const Text('Logout'),
        ),
      ],
    );
  }
}
