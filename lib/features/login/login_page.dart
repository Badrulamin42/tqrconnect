import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

class LoginPage extends StatefulWidget {
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _storage = FlutterSecureStorage();
  bool _obscurePassword = true;
  bool _isLoading = false;

  final dio = Dio();
  final cookieJar = CookieJar();


// Save token manually to cookies after login


  final _formKey = GlobalKey<FormState>();
  late AnimationController _logoController;

  @override
  void initState() {
    super.initState();
    _loadEmail();
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _logoController.forward();
    dio.interceptors.add(CookieManager(cookieJar));
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _logoController.dispose();
    super.dispose();
  }
  void _loadEmail() async {
    final savedEmail = await _storage.read(key: 'user_email');
    if (savedEmail != null) {
      setState(() {
        _emailController.text = savedEmail;
      });
    }
  }

  Future<void> _login(BuildContext context) async {
  if (!_formKey.currentState!.validate()) return;

  FocusScope.of(context).unfocus();
  setState(() => _isLoading = true);

  try {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    // Attach cookie manager before request
    dio.interceptors.clear();
    dio.interceptors.add(CookieManager(cookieJar));

    final response = await dio.post(
    'https://192.168.0.203/api/account/login',
    data: {
    'Email': email,
    'PasswordHash': password,
    },
    options: Options(
    headers: { 'Content-Type': 'application/json' },
    validateStatus: (_) => true, // prevent Dio from throwing on non-200
    ),
    );
    final data = response.data;
    if (response.statusCode == 200) {
    final token = data['token'];

    // Read the expiration date string directly from the 'expires' field
    final expiryDateString = data['expires'] as String?;

    if (expiryDateString != null) {
      await _storage.write(key: 'token_expiry', value: expiryDateString);
      print("🔒 Token expiry date received from server: $expiryDateString");
    } else {
      print("⚠️ 'expires' field was not found in the login response. No expiry date stored.");
    }
    print("exp : $expiryDateString}");
    print('data: ${data}');
    // Save secure values for later use
    await _storage.write(key: 'auth_token', value: token);
    await _storage.write(key: 'user_email', value: email);
    await _storage.write(key: 'user_id', value: data['user']['Id'].toString());
    await _storage.write(key: 'user_fullname', value: data['user']['FullName']);

    // Clear previous outlet data before fetching new ones
    await _storage.delete(key: 'outlets');
    await _storage.delete(key: 'selected_outlet');

    // Optional: log outlet-user
    final outletRes = await dio.get(
      'https://192.168.0.203/api/mobile/outlet-user',
      options: Options(
        headers: {
          'Authorization': 'Bearer $token',
        },
      ),
    );
    if (response.statusCode == 200) {
      //outlets & credits
      await _storage.write(
        key: 'outlets',
        value: jsonEncode(outletRes.data), // Convert Map to JSON string
      );
    }
    else {
      print('Login failed: ${outletRes.statusCode}');

      throw Exception('Login failed');
    }

    print('Outlet: ${outletRes.data}');

    if (!mounted) return;
    context.go('/home');
    } else {
    print('Login failed: ${response.statusCode}');
    print('Response body: ${response.data}');
    throw Exception('Login failed');
    }
    } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Login failed: ${e.toString()}')),

    );
    print('Login failed: ${e.toString()}');
    } finally {
    setState(() => _isLoading = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Form(

                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [

                      // Logo with animation
                      FadeTransition(
                        opacity: _logoController,
                        child: Image.asset(
                          'assets/images/logo.png',
                          height: 125,
                        ),
                      ),
                      const SizedBox(height: 5),

                      Text(
                        'Welcome Back',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.primaryColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please login to continue',
                        style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 32),

                      // Email field
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (value) =>
                        value == null || value.isEmpty ? 'Please enter email' : null,
                      ),
                      const SizedBox(height: 16),

                      // Password field with toggle
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_off : Icons.visibility,
                            ),
                            onPressed: () {
                              setState(() => _obscurePassword = !_obscurePassword);
                            },
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (value) =>
                        value == null || value.isEmpty ? 'Please enter password' : null,
                      ),
                      const SizedBox(height: 24),

                      // Login button or loading
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : () => _login(context),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isLoading
                              ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                              : Text('Login', style: TextStyle(fontSize: 16)),
                        ),
                      ),
                      const SizedBox(height: 16),

                      TextButton(
                        onPressed: () {},
                        child: Text(
                          "Forgot password?",
                          style: TextStyle(color: theme.primaryColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

          ),
        ),
      ),
    );
  }
}
