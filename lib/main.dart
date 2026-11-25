import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
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
import 'tools/passenger_notification_service.dart';
import 'widgets/omni_campaigns_sheet.dart';

final GlobalKey<NavigatorState> omniNavigatorKey = GlobalKey<NavigatorState>();

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

  if (!kIsWeb) {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      FirebaseMessaging.onBackgroundMessage(omniFirebaseMessagingBackgroundHandler);
    } catch (_) {}
  }

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
      navigatorKey: omniNavigatorKey,
      title: OmniConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: OmniTheme.darkTheme,
      builder: (context, child) {
        return _OmniGlobalNotificationHost(
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const OmniSplashScreen(),
    );
  }
}

/// Overlay global Heads-Up exibido no topo da tela em qualquer rota quando chega campanha ou push
class _OmniGlobalNotificationHost extends StatefulWidget {
  final Widget child;

  const _OmniGlobalNotificationHost({required this.child});

  @override
  State<_OmniGlobalNotificationHost> createState() =>
      _OmniGlobalNotificationHostState();
}

class _OmniGlobalNotificationHostState
    extends State<_OmniGlobalNotificationHost> {
  StreamSubscription<OmniDeepLinkCupomEvent>? _bannerSub;
  Timer? _autoDismissTimer;
  OmniDeepLinkCupomEvent? _bannerAtivo;

  @override
  void initState() {
    super.initState();
    _bannerSub = OmniPassengerNotificationService.onForegroundBanner.listen((ev) {
      if (!mounted) return;
      _autoDismissTimer?.cancel();
      setState(() => _bannerAtivo = ev);
      _autoDismissTimer = Timer(const Duration(seconds: 6), () {
        if (mounted) {
          setState(() => _bannerAtivo = null);
        }
      });
    });
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _bannerSub?.cancel();
    super.dispose();
  }

  void _abrirOfertaBanner(OmniDeepLinkCupomEvent ev) {
    _autoDismissTimer?.cancel();
    setState(() => _bannerAtivo = null);
    final navCtx = omniNavigatorKey.currentContext;
    if (navCtx == null) return;
    showOmniCampaignsSheet(
      navCtx,
      highlightedCoupon: ev.cupomCodigo,
      onApplyCoupon: (camp) {
        final messenger = ScaffoldMessenger.maybeOf(navCtx);
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              'Cupom ${camp.codigoCupom.isNotEmpty ? camp.codigoCupom : camp.titulo} (${camp.resumoDesconto}) selecionado! Abra sua corrida para aplicar.',
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final banner = _bannerAtivo;
    return Stack(
      children: [
        widget.child,
        if (banner != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Material(
                  color: Colors.transparent,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: -28.0, end: 0.0),
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    builder: (context, offsetY, child) => Transform.translate(
                      offset: Offset(0, offsetY),
                      child: child,
                    ),
                    child: InkWell(
                      onTap: () => _abrirOfertaBanner(banner),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: OmniConstants.darkCard,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: OmniConstants.neonCyan,
                            width: 1.4,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: OmniConstants.neonCyan.withValues(alpha: 0.28),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: const BoxDecoration(
                                color: OmniConstants.neonCyan,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.notifications_active_rounded,
                                color: Colors.black,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    (banner.titulo ?? '').trim().isNotEmpty
                                        ? banner.titulo!.trim()
                                        : 'Promoção OMNI',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: OmniConstants.neonCyan,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                    ),
                                  ),
                                  if ((banner.mensagem ?? '').trim().isNotEmpty)
                                    Text(
                                      banner.mensagem!.trim(),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (banner.cupomCodigo.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: OmniConstants.neonCyan.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: OmniConstants.neonCyan.withValues(alpha: 0.5),
                                  ),
                                ),
                                child: Text(
                                  banner.cupomCodigo,
                                  style: const TextStyle(
                                    color: OmniConstants.neonCyan,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 10.5,
                                  ),
                                ),
                              ),
                            ],
                            IconButton(
                              onPressed: () {
                                _autoDismissTimer?.cancel();
                                setState(() => _bannerAtivo = null);
                              },
                              icon: const Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: Colors.white60,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
