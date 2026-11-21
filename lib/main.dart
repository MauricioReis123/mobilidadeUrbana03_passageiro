import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'constants/omni_constants.dart';
import 'screens/splash_screen.dart';
import 'state/omni_app_state.dart';
import 'theme/omni_theme.dart';
import 'tools/backends_service.dart';
import 'tools/firebase_service.dart';
import 'tools/local_http_overrides.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await OmniBackendUniversal.carregarDominioDoCache();
  configurarHttpLocalOverrides();

  // Configura barra de status e navegação para estética Neon Luxuoso
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: OmniConstants.darkBackground,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Inicializa serviços de infraestrutura
  await OmniFirebaseService.inicializar();

  runApp(
    ChangeNotifierProvider(
      create: (_) => OmniAppState()..inicializar(),
      child: const OmniPassageiroApp(),
    ),
  );
}

class OmniPassageiroApp extends StatelessWidget {
  const OmniPassageiroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: OmniConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: OmniTheme.darkTheme,
      home: const OmniSplashScreen(),
    );
  }
}
