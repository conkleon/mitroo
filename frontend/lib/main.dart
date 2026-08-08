import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:go_router/go_router.dart';

import 'config/router.dart';
import 'providers/auth_provider.dart';
import 'providers/department_provider.dart';
import 'providers/service_provider.dart';
import 'providers/item_provider.dart';
import 'providers/vehicle_provider.dart';

import 'providers/category_provider.dart';
import 'providers/sync_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/victim_provider.dart';
import 'providers/mission_report_provider.dart';
import 'providers/connectivity_provider.dart';
import 'providers/pwa_provider.dart';
import 'services/pwa_service.dart';
import 'theme/theme.dart';

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
        ChangeNotifierProvider(create: (_) => MissionReportProvider()),
        ChangeNotifierProvider(create: (_) => ConnectivityProvider()),
      ],
      child: MaterialApp.router(
        title: 'R.C.D.',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.brandPrimary,
            brightness: Brightness.light,
            primary: AppColors.brandPrimary,
            secondary: AppColors.brandAccent,
            surface: Colors.white,
            onSurface: AppColors.ink,
          ),
          scaffoldBackgroundColor: Colors.white,
          textTheme: baseTextTheme,
          cardTheme: CardThemeData(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.r14,
              side: const BorderSide(color: AppColors.gray200),
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
              fontSize: AppFontSize.xl5,
              fontWeight: AppFontWeight.bold,
              color: AppColors.ink,
              letterSpacing: -0.5,
            ),
            iconTheme: const IconThemeData(color: AppColors.brandPrimary),
          ),
          navigationBarTheme: NavigationBarThemeData(
            backgroundColor: Colors.white,
            elevation: 0,
            height: 56,
            indicatorColor: AppColors.brandPrimary.withAlpha(25),
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return baseTextTheme.labelSmall?.copyWith(
                  color: AppColors.brandPrimary,
                  fontWeight: AppFontWeight.semibold,
                );
              }
              return baseTextTheme.labelSmall?.copyWith(
                color: AppColors.gray500,
              );
            }),
            iconTheme: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const IconThemeData(color: AppColors.brandPrimary, size: 24);
              }
              return const IconThemeData(color: AppColors.gray500, size: 24);
            }),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: AppRadius.r12,
              borderSide: const BorderSide(color: AppColors.borderSubtle),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppRadius.r12,
              borderSide: const BorderSide(color: AppColors.borderSubtle),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: AppRadius.r12,
              borderSide: const BorderSide(color: AppColors.brandPrimary, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brandPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.r12,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
          ),
          floatingActionButtonTheme: FloatingActionButtonThemeData(
            backgroundColor: AppColors.brandPrimary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.r16,
            ),
          ),
          dividerTheme: const DividerThemeData(
            color: AppColors.divider,
            thickness: 1,
          ),
        ),
        themeMode: ThemeMode.light,
        routerConfig: _router,
      ),
    );
  }
}
