import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/splash_screen.dart';
import '../features/login/login_page.dart';
import '../features/home/home_page.dart';
import '../features/tqr/tqr_connect_page.dart';
class AppRouter {
  static final router = GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(path: '/', redirect: (_, __) => '/login'),
      GoRoute(path: '/login', builder: (_, __) => LoginPage()),
      GoRoute(path: '/home', builder: (_, __) => HomePage()),
      GoRoute(path: '/tqr-connect', builder: (_, __) => TqrConnectPage()),

    ],
  );

}
