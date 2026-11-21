/// ============================================================================
/// CONTRATOS CENTRALIZADOS DE INTEGRAÇÃO — OMNI PASSAGEIRO (FLUTTER / DART)
/// Single Source of Truth alinhado 100% ao App Motorista e ao functions.php
/// ============================================================================

/// Configuração Dinâmica do Roteador WordPress (`omni_global_dynamic_router`)
/// Permite alterar em tempo de execução o IP/domínio (ex: 192.168.12.9, 192.168.12.10, servshop.com.br)
/// com persistência em cache local (SharedPreferences).
class OmniRouterConfig {
  static const String defaultBackendHost = '192.168.12.10';
  static const String cacheStorageKey = 'omni_custom_backend_domain_v2';

  static String _configuredInput = defaultBackendHost;

  /// Valor bruto salvo/digitado pelo usuário (ex: 192.168.12.9, 192.168.12.10, servshop.com.br)
  static String get configuredInput => _configuredInput;

  /// Atualiza o host/domínio ativo em memória (chamado ao carregar cache ou clicar em Salvar)
  static void setConfiguredDomain(String rawValue) {
    final normalized = normalizeInput(rawValue);
    _configuredInput = normalized;
  }

  static String normalizeInput(String rawValue) {
    var v = rawValue.trim();
    if (v.isEmpty) return defaultBackendHost;
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    return v.isEmpty ? defaultBackendHost : v;
  }

  static bool _isLocalOrIpHost(String host) {
    final h = host.toLowerCase();
    if (h == 'localhost' || h == '127.0.0.1' || h == '10.0.2.2' || h.endsWith('.local')) {
      return true;
    }
    final ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');
    return ipv4.hasMatch(h);
  }

  static ({String explicitScheme, String cleanPath, String hostOnly}) _parseTarget() {
    var raw = _configuredInput.trim();
    String explicitScheme = '';
    if (raw.toLowerCase().startsWith('https://')) {
      explicitScheme = 'https';
      raw = raw.substring(8);
    } else if (raw.toLowerCase().startsWith('http://')) {
      explicitScheme = 'http';
      raw = raw.substring(7);
    }
    while (raw.endsWith('/')) {
      raw = raw.substring(0, raw.length - 1);
    }
    if (raw.isEmpty) raw = defaultBackendHost;

    final firstSegment = raw.split('/').first;
    final hostOnly = firstSegment.split(':').first;

    String resolved;
    if (raw.toLowerCase().contains('admin-ajax.php')) {
      resolved = raw;
    } else if (raw.contains('/')) {
      resolved = '$raw/wp-admin/admin-ajax.php';
    } else if (_isLocalOrIpHost(hostOnly)) {
      resolved = '$raw/servshop/wp-admin/admin-ajax.php';
    } else {
      resolved = '$raw/wp-admin/admin-ajax.php';
    }

    return (explicitScheme: explicitScheme, cleanPath: resolved, hostOnly: hostOnly);
  }

  /// Host puro extraído do valor configurado (ex: 192.168.12.10 ou servshop.com.br)
  static String get backendHost => _parseTarget().hostOnly;

  /// URLs HTTP e HTTPS montadas dinamicamente a partir do valor salvo
  static String get baseUrl => 'http://${_parseTarget().cleanPath}';
  static String get baseUrlHttps => 'https://${_parseTarget().cleanPath}';

  /// Ordem inteligente de tentativa híbrida:
  /// - Se o usuário especificou `https://` ou domínio externo, tenta HTTPS primeiro e HTTP depois.
  /// - Se é IP LAN/local ou `http://`, tenta HTTP primeiro e HTTPS depois.
  static List<String> get candidateUrls {
    final parsed = _parseTarget();
    final httpUrl = 'http://${parsed.cleanPath}';
    final httpsUrl = 'https://${parsed.cleanPath}';
    if (parsed.explicitScheme == 'https' ||
        (parsed.explicitScheme.isEmpty && !_isLocalOrIpHost(parsed.hostOnly))) {
      return [httpsUrl, httpUrl];
    }
    return [httpUrl, httpsUrl];
  }

  /// Actions registradas no functions.php do WordPress
  static const String actionGetNonce = 'omni_get_router_nonce';
  static const String actionGlobalRouter = 'omni_global_router';

  /// Arquivo PHP e Classe do backend do App Passageiro
  /// Transferir para: C:\laragon\www\servshop\wp-content\plugins\omni-multidropshipping-core\includes\integrations\
  static const String backendFile = 'class-omni-passageiro-backend-pro.php';
  static const String className = 'class_omni_passageiro_backend_pro';

  static const bool allowSelfSignedLocalCert = true;
  static const int timeoutSeconds = 12;
}

/// Nomes oficiais de todas as tabelas SQL (Compartilhadas + Específicas do Passageiro)
class OmniSqlTables {
  // === TABELAS COMPARTILHADAS (PONTE DIRETA COM APP MOTORISTA) ===
  static const String motoristas = 'omni_motoristas';
  static const String veiculos = 'omni_veiculos';
  static const String corridas = 'omni_corridas';
  static const String corridaLances = 'omni_corrida_lances';

  // === TABELAS ESPECÍFICAS DO APP PASSAGEIRO ===
  static const String passageiros = 'omni_passageiros';
  static const String passageiroFavoritos = 'omni_passageiro_favoritos';
  static const String avaliacoes = 'omni_avaliacoes';
  static const String pagamentosPix = 'omni_pagamentos_pix';
  static const String ofertasPrivadas = 'omni_ofertas_privadas';
  static const String suporteTickets = 'omni_suporte_tickets';
}

/// Catálogo oficial de métodos PHP (`target_method` sempre em snake_case minúsculo — exigência do sanitize_key())
class OmniBackendMethods {
  static const String systemPing = 'passenger_system_ping';
  static const String systemCheckVersion = 'passenger_system_check_version';
  static const String bootstrapTables = 'passenger_bootstrap_tables';

  // Perfil e favoritos do passageiro
  static const String profileUpsert = 'passenger_profile_upsert';
  static const String favoriteSave = 'passenger_favorite_save';
  static const String tripsHistory = 'passenger_trips_history';

  // Ciclo de vida da corrida (Ponte com Motorista)
  static const String tripRequest = 'passenger_trip_request';
  static const String tripCancel = 'passenger_trip_cancel';
  static const String tripRate = 'passenger_trip_rate';
  static const String tripSos = 'passenger_trip_sos';
  static const String getDriverPublicInfo = 'passenger_get_driver_public_info';

  // Financeiro / Mercado Pago Pix
  static const String walletGeneratePix = 'passenger_wallet_generate_pix';
  static const String walletCheckPix = 'passenger_wallet_check_pix';

  // Marketplace de viagens privadas / Concierge
  static const String privateOfferCreate = 'passenger_private_offer_create';

  // Suporte e protocolos
  static const String supportOpenTicket = 'passenger_support_open_ticket';
}

/// Configuração do Firebase Realtime Database
class OmniRtdbConfig {
  static const String databaseUrl = 'https://catalogo-dropshipping-b9546-default-rtdb.firebaseio.com';
  static const String apiKey = 'AIzaSyDmIkOE4qM-djOhha2_PoIaVGTPo08VYpdae';
}

/// Caminhos (`paths`) oficiais do Firebase RTDB — 100% compatíveis com o App Motorista
class OmniRtdbPaths {
  static const String driversOnlineRoot = 'drivers_online';
  static const String dispatchQueueRoot = 'dispatch_queue';
  static const String tripsRoot = 'trips';
  static const String privateOffersRoot = 'private_offers';
  static const String privateBidsRoot = 'private_bids';
  static const String payoutsRoot = 'payouts';

  static String driverOnline(String driverId) => '$driversOnlineRoot/$driverId';
  static String dispatchOffer(String driverId, String tripId) => '$dispatchQueueRoot/$driverId/$tripId';
  static String trip(String tripId) => '$tripsRoot/$tripId';
  static String tripStatus(String tripId) => '$tripsRoot/$tripId/status';
  static String tripDriverId(String tripId) => '$tripsRoot/$tripId/driver_id';
  static String tripDriverLocation(String tripId) => '$tripsRoot/$tripId/driver_location';
  static String tripChat(String tripId) => '$tripsRoot/$tripId/chat';
  static String tripSos(String tripId) => '$tripsRoot/$tripId/sos';
  static String privateOffer(String offerId) => '$privateOffersRoot/$offerId';
  static String privateBids(String offerId) => '$privateBidsRoot/$offerId';
}

/// Chaves JSON canônicas (snake_case) usadas no Firebase RTDB
class OmniRtdbFields {
  // drivers_online/{driver_id}
  static const String driverId = 'driver_id';
  static const String isOnline = 'is_online';
  static const String lat = 'lat';
  static const String lng = 'lng';
  static const String bearing = 'bearing';
  static const String speedKmh = 'speed_kmh';
  static const String updatedAt = 'updated_at';

  // dispatch_queue/{driver_id}/{trip_id}
  static const String tripId = 'trip_id';
  static const String passengerId = 'passenger_id';
  static const String passengerName = 'passenger_name';
  static const String passengerRating = 'passenger_rating';
  static const String tripType = 'trip_type';
  static const String category = 'category';
  static const String estimatedFare = 'estimated_fare';
  static const String distanceKm = 'distance_km';
  static const String etaMinutes = 'eta_minutes';
  static const String otpCode = 'otp_code';
  static const String origin = 'origin';
  static const String destination = 'destination';
  static const String waypoints = 'waypoints';
  static const String routeProvider = 'route_provider';
  static const String address = 'address';
  static const String createdAt = 'created_at';
  static const String expiresAt = 'expires_at';

  // trips/{trip_id}
  static const String status = 'status';
  static const String driverLocation = 'driver_location';

  // trips/{trip_id}/chat/{push_id}
  static const String senderRole = 'sender_role';
  static const String senderId = 'sender_id';
  static const String text = 'text';
  static const String isRead = 'is_read';

  // trips/{trip_id}/sos
  static const String triggeredBy = 'triggered_by';

  // private_bids/{offer_id}/{bid_id}
  static const String bidId = 'bid_id';
  static const String bidAmount = 'bid_amount';
  static const String message = 'message';
}

/// Máquina de estados canônica compartilhada (App Motorista <-> App Passageiro <-> SQL <-> RTDB)
class OmniTripStatus {
  static const String searching = 'SEARCHING';
  static const String accepted = 'ACCEPTED';
  static const String driverEnRoute = 'DRIVER_EN_ROUTE';
  static const String driverArrived = 'DRIVER_ARRIVED';
  static const String boardingConfirmed = 'BOARDING_CONFIRMED';
  static const String inProgress = 'IN_PROGRESS';
  static const String completed = 'COMPLETED';
  static const String cancelled = 'CANCELLED';
  static const String declined = 'DECLINED';
}
