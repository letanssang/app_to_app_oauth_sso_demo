import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'dashboard_page.dart';

class LoginPage extends StatefulWidget {
  final String? initialEmail;
  final String? initialPassword;
  final bool isInitiallyLoggedIn;

  const LoginPage({
    super.key,
    this.initialEmail,
    this.initialPassword,
    this.isInitiallyLoggedIn = false,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;

  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  final _secureStorage = const FlutterSecureStorage();

  bool _isLoading = false;
  String? _errorMessage;
  late bool _isLoggedIn;

  // OAuth Parameters received from Client App
  String? _clientId;
  String? _redirectUri;
  String? _state;
  String? _codeChallenge; // Enabled to support PKCE via Backend Proxy
  String? _lastProcessedLink;

  bool get _isDelegatedLogin => _redirectUri != null && _state != null;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(
      text: widget.initialEmail ?? 'admin@test.com',
    );
    _passwordController = TextEditingController(
      text: widget.initialPassword ?? '',
    );
    _isLoggedIn = widget.isInitiallyLoggedIn;

    _initDeepLinks();
  }

  // _loadSavedCredentials is removed, logic moved to SplashPage

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    // Handle links while app is running
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (Uri? uri) {
        if (uri != null) {
          _handleDeepLink(uri);
        }
      },
      onError: (err) {
        debugPrint('Deep Link Error: $err');
      },
    );

    // Handle initial link if app was closed
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleDeepLink(initialUri);
      }
    } catch (e) {
      debugPrint('Initial Deep Link Error: $e');
    }
  }

  void _handleDeepLink(Uri uri) {
    debugPrint('Received Deep Link: $uri');

    final uriString = uri.toString();
    if (uriString == _lastProcessedLink) {
      debugPrint('Ignoring duplicate deep link');
      return;
    }
    _lastProcessedLink = uriString;

    // Check if it's the intercepted Backend Proxy URL
    if (uri.scheme == 'https' &&
        uri.host == 'bloomygardenshop.com' &&
        uri.path == '/authorize') {
      setState(() {
        _clientId = uri.queryParameters['client_id'];
        _redirectUri = uri.queryParameters['redirect_uri'];
        _state = uri.queryParameters['state'];
        _codeChallenge =
            uri.queryParameters['code_challenge']; // Extract PKCE parameter
      });
      debugPrint('Intercepted App Link Auth Request from: $_clientId');

      // --- SSO Silent Login Check ---
      if (_isLoggedIn) {
        debugPrint(
          'SSO Check: User already logged in. Triggering silent auth.',
        );
        _handleLogin();
      }
    }
  }

  void _handleLogin() async {
    if (_isLoading) return;

    // If already logged in (SSO), bypass form validation since the Form widget might not be in the tree (Dashboard is showing)
    final bool isValid =
        _isLoggedIn || (_formKey.currentState?.validate() ?? false);

    if (isValid) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      try {
        final response = await _executeLoginRequest(
          _emailController.text,
          _passwordController.text,
        );

        if (response.statusCode == 200) {
          final responseData = json.decode(response.body);
          final String authCode = responseData['code'];

          // Save Credentials for SSO (in both scenarios)
          await _secureStorage.write(
            key: 'saved_email',
            value: _emailController.text,
          );
          await _secureStorage.write(
            key: 'saved_password',
            value: _passwordController.text,
          );

          if (mounted) {
            setState(() {
              _isLoggedIn = true;
            });
          }

          if (_isDelegatedLogin) {
            _showConsentDialog(authCode);
          }
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
        } else {
          // Parse Keycloak Error
          String errorMsg = 'Invalid credentials';
          try {
            final errorData = json.decode(response.body);
            errorMsg =
                errorData['error_description'] ??
                errorData['error'] ??
                'Login failed';
          } catch (e) {
            // Ignore parsing errors, stick to default message
          }
          if (mounted) {
            setState(() {
              _errorMessage = errorMsg;
              _isLoading = false;
            });
            if (_isLoggedIn) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(errorMsg),
                  backgroundColor: Colors.red.shade700,
                ),
              );
            }
          }
        }
      } catch (e) {
        if (mounted) {
          final networkErrorMsg =
              'Network error: Could not reach backend server.';
          setState(() {
            _errorMessage = networkErrorMsg;
            _isLoading = false;
          });
          if (_isLoggedIn) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(networkErrorMsg),
                backgroundColor: Colors.red.shade700,
              ),
            );
          }
        }
      }
    }
  }

  Future<http.Response> _executeLoginRequest(
    String username,
    String password,
  ) async {
    final loginUrl = Uri.parse('http://10.83.5.97:8081/login');
    return await http.post(
      loginUrl,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'username': username,
        'password': password,
        if (_codeChallenge != null) 'code_challenge': _codeChallenge!,
      },
    );
  }

  void _showConsentDialog(String authCode) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext dialogContext) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.security, size: 64, color: Colors.teal),
              const SizedBox(height: 16),
              const Text(
                'Authorization Request',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(
                'App ${_clientId ?? 'Client App'} is requesting access to your account.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              const Text(
                'Requested Permissions:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const ListTile(
                leading: Icon(Icons.check_circle, color: Colors.green),
                title: Text('Read your email address'),
                dense: true,
              ),
              const ListTile(
                leading: Icon(Icons.check_circle, color: Colors.green),
                title: Text('Read your basic profile info'),
                dense: true,
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        foregroundColor: Colors.grey.shade700,
                      ),
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                        _rejectAndRedirect();
                      },
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                        _authorizeAndRedirect(authCode);
                      },
                      child: const Text('Allow'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Future<void> _rejectAndRedirect() async {
    if (_redirectUri != null && _state != null) {
      final Uri redirect = Uri.parse(
        _redirectUri!,
      ).replace(queryParameters: {'error': 'access_denied', 'state': _state!});

      try {
        await launchUrl(
          redirect,
          mode: LaunchMode.externalNonBrowserApplication,
        );
      } catch (e) {
        debugPrint('Could not launch callback: $redirect. Error: $e');
      }
    }
  }

  Future<void> _authorizeAndRedirect(String authCode) async {
    // 2. Build the callback URI with the REAL dynamic authorization code
    final Uri redirect = Uri.parse(
      _redirectUri!,
    ).replace(queryParameters: {'code': authCode, 'state': _state!});

    // 3. Launch URI to return back to Client App
    try {
      await launchUrl(redirect, mode: LaunchMode.externalNonBrowserApplication);
    } catch (e) {
      debugPrint('Could not launch callback: $redirect. Error: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not return to Client App.';
        });
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoggedIn) {
      return DashboardPage(
        onLogout: () async {
          await _secureStorage.deleteAll();
          _passwordController.clear();
          setState(() {
            _isLoggedIn = false;
          });
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Provider Login'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.shield, size: 80, color: Colors.teal),
                const SizedBox(height: 24),
                const Text(
                  'Sign In to Continue',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  _isDelegatedLogin
                      ? 'Authorize ${_clientId ?? 'Client App'} to access your account'
                      : 'Sign in to manage your Auth Provider account',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 48),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(color: Colors.red.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                SizedBox(
                  height: 56,
                  child: FilledButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Login', style: TextStyle(fontSize: 18)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
