import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'package:go_router/go_router.dart';

import 'config/router.dart';
import 'providers/auth_provider.dart';
import 'providers/category_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/department_provider.dart';
import 'providers/item_provider.dart';
import 'providers/pwa_provider.dart';
import 'providers/service_provider.dart';
import 'providers/sync_provider.dart';
import 'providers/vehicle_provider.dart';
import 'providers/victim_provider.dart';
import 'services/pwa_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('el_GR', null);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const MitrooApp());
}

class MitrooApp extends StatefulWidget {
  const MitrooApp({super.key});

  @override
  State<MitrooApp> createState() => _MitrooAppState();
}

class _MitrooAppState extends State<MitrooApp> {
  static const _primaryRed = Color(0xFFC62828);
  static const _accentRed = Color(0xFFE53935);

  late final AuthProvider _authProvider;
  late final PwaProvider _pwaProvider;
  late final GoRouter _router;
  StreamSubscription<String>? _navSub;

  @override
  void initState() {
    super.initState();
    _authProvider = AuthProvider();
    _pwaProvider = PwaProvider();
    _router = appRouter(_authProvider);

    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await PwaService.init(_pwaProvider);
        _navSub = PwaService.navigateStream.listen(_router.go);
      });
    }
  }

  @override
  void dispose() {
    _navSub?.cancel();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseTextTheme = GoogleFonts.interTextTheme();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _authProvider),
        ChangeNotifierProvider.value(value: _pwaProvider),
        ChangeNotifierProvider(create: (_) => DepartmentProvider()),
        ChangeNotifierProvider(create: (_) => ServiceProvider()),
        ChangeNotifierProvider(create: (_) => ItemProvider()),
        ChangeNotifierProvider(create: (_) => VehicleProvider()),
        ChangeNotifierProvider(create: (_) => CategoryProvider()),
        ChangeNotifierProvider(create: (_) => SyncProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => VictimProvider()),
      ],
      child: MaterialApp.router(
        title: 'R.C.D.',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          colorScheme: ColorScheme.fromSeed(
            seedColor: _primaryRed,
            brightness: Brightness.light,
            primary: _primaryRed,
            secondary: _accentRed,
            surface: Colors.white,
            onSurface: const Color(0xFF1A1C1E),
          ),
          scaffoldBackgroundColor: Colors.white,
          textTheme: baseTextTheme,
          cardTheme: CardThemeData(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            color: Colors.white,
            surfaceTintColor: Colors.transparent,
            margin: EdgeInsets.zero,
          ),
          appBarTheme: AppBarTheme(
            backgroundColor: Colors.white,
            elevation: 0,
            scrolledUnderElevation: 0,
            centerTitle: false,
            titleTextStyle: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1C1E),
              letterSpacing: -0.5,
            ),
            iconTheme: const IconThemeData(color: Color(0xFFC62828)),
          ),
          navigationBarTheme: NavigationBarThemeData(
            backgroundColor: Colors.white,
            elevation: 0,
            height: 56,
            indicatorColor: _primaryRed.withAlpha(25),
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return baseTextTheme.labelSmall?.copyWith(
                  color: _primaryRed,
                  fontWeight: FontWeight.w600,
                );
              }
              return baseTextTheme.labelSmall
                  ?.copyWith(color: const Color(0xFF6B7280));
            }),
            iconTheme: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const IconThemeData(color: Color(0xFFC62828), size: 24);
              }
              return const IconThemeData(color: Color(0xFF6B7280), size: 24);
            }),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _primaryRed, width: 1.5),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: _primaryRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
          ),
          floatingActionButtonTheme: FloatingActionButtonThemeData(
            backgroundColor: _primaryRed,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          dividerTheme: const DividerThemeData(
            color: Color(0xFFE8ECF0),
            thickness: 1,
          ),
        ),
        themeMode: ThemeMode.light,
        routerConfig: _router,
      ),
    );
  }
}
