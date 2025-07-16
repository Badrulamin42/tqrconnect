import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/splash_screen.dart';
import '../features/login/login_page.dart';
import '../features/home/home_page.dart';
import '../features/tqr/tqr_connect_page.dart';
import '../../models/outlet.dart';

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
      GoRoute(
        path: '/home',
        builder: (context, state) {
          final outlets = state.extra is List<Outlet> ? state.extra as List<Outlet> : null;
          return HomePage(outlets: outlets); // ✅ outlets may be null
        },
      ),

      GoRoute(
        path: '/tqr-connect',
        builder: (context, state) {
          final selectedOutlet = state.extra as Outlet;
          return TqrConnectPage(selectedOutlet: selectedOutlet);
        },
      ),


    ],
  );

}
