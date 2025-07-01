import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

class LoginPage extends StatefulWidget {
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  final _formKey = GlobalKey<FormState>();
  late AnimationController _logoController;

  @override
  void initState() {
    super.initState();
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _logoController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _logoController.dispose();
    super.dispose();
  }

  void _login(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus(); // 👉 This dismisses the keyboard
    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      // await FirebaseAuth.instance.signInWithEmailAndPassword(
      //   email: email,
      //   password: password,
      // );

      await Future.delayed(Duration(seconds: 2)); // Fake delay

      if (!mounted) return;
      context.go('/home');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login failed: ${e.toString()}')),
      );
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
