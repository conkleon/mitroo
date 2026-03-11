import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'config/router.dart';
import 'providers/auth_provider.dart';
import 'providers/department_provider.dart';
import 'providers/service_provider.dart';
import 'providers/item_provider.dart';
import 'providers/vehicle_provider.dart';
import 'providers/category_provider.dart';

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

class MitrooApp extends StatelessWidget {
  const MitrooApp({super.key});

  static const _primaryBlue = Color(0xFF1A3C7A);
  static const _accentBlue = Color(0xFF2B5EA7);

  @override
  Widget build(BuildContext context) {
    final baseTextTheme = GoogleFonts.interTextTheme();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => DepartmentProvider()),
        ChangeNotifierProvider(create: (_) => ServiceProvider()),
        ChangeNotifierProvider(create: (_) => ItemProvider()),
        ChangeNotifierProvider(create: (_) => VehicleProvider()),
        ChangeNotifierProvider(create: (_) => CategoryProvider()),
      ],
      child: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          return MaterialApp.router(
            title: 'Mitroo',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              brightness: Brightness.light,
              colorScheme: ColorScheme.fromSeed(
                seedColor: _primaryBlue,
                brightness: Brightness.light,
                primary: _primaryBlue,
                secondary: _accentBlue,
                surface: const Color(0xFFF5F7FA),
                onSurface: const Color(0xFF1A1C1E),
              ),
              scaffoldBackgroundColor: const Color(0xFFF5F7FA),
              textTheme: baseTextTheme,
              cardTheme: CardThemeData(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                color: Colors.white,
                surfaceTintColor: Colors.transparent,
              ),
              appBarTheme: AppBarTheme(
                backgroundColor: const Color(0xFFF5F7FA),
                elevation: 0,
                scrolledUnderElevation: 0,
                centerTitle: false,
                titleTextStyle: baseTextTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1A1C1E),
                ),
                iconTheme: const IconThemeData(color: Color(0xFF1A3C7A)),
              ),
              navigationBarTheme: NavigationBarThemeData(
                backgroundColor: Colors.white,
                elevation: 0,
                height: 64,
                indicatorColor: _primaryBlue.withAlpha(25),
                labelTextStyle: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return baseTextTheme.labelSmall?.copyWith(
                      color: _primaryBlue,
                      fontWeight: FontWeight.w600,
                    );
                  }
                  return baseTextTheme.labelSmall?.copyWith(
                    color: const Color(0xFF6B7280),
                  );
                }),
                iconTheme: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return const IconThemeData(color: Color(0xFF1A3C7A), size: 24);
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
                  borderSide: const BorderSide(color: _primaryBlue, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              filledButtonTheme: FilledButtonThemeData(
                style: FilledButton.styleFrom(
                  backgroundColor: _primaryBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
              ),
              floatingActionButtonTheme: FloatingActionButtonThemeData(
                backgroundColor: _primaryBlue,
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
            routerConfig: appRouter(auth),
          );
        },
      ),
    );
  }
}
