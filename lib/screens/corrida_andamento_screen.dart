import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/omni_constants.dart';
import '../models/corrida_model.dart';
import '../state/omni_app_state.dart';
import '../widgets/omni_active_ride.dart';
import '../widgets/omni_map_canvas.dart';

/// Tela Dedicada de Corrida em Andamento — Conectada ao OmniAppState (Sem mocks)
class OmniCorridaAndamentoScreen extends StatelessWidget {
  final OmniCorridaModel corridaInicial;

  const OmniCorridaAndamentoScreen({super.key, required this.corridaInicial});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<OmniAppState>();
    final corrida = appState.corridaAtiva ?? corridaInicial;

    return Scaffold(
      backgroundColor: OmniConstants.darkBackground,
      appBar: AppBar(
        title: const Text('Corrida em Andamento', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 290,
                child: OmniMapCanvas(
                  origemEndereco: corrida.origem.endereco ?? 'Origem',
                  destinoEndereco: corrida.destino.endereco ?? 'Destino',
                  paradas: corrida.paradas.map((p) => p.endereco ?? 'Parada').toList(),
                  motoristas: appState.motoristasOnline,
                  motoristaAtivo: corrida.motorista,
                  emViagem: corrida.status == OmniStatusCorrida.emAndamento,
                  distanciaKm: corrida.distanciaKm,
                  tempoMinutos: corrida.tempoMinutos,
                  onRecenterGps: () => appState.atualizarLocalizacaoGps(),
                ),
              ),
              const SizedBox(height: 16),
              OmniActiveRide(
                corrida: corrida,
                onAvancarStatus: appState.avancarStatusCorrida,
                onCancelar: () async {
                  await appState.cancelarCorridaAtiva();
                  if (context.mounted) Navigator.of(context).pop();
                },
                onFinalizarComAvaliacao: (estrelas) async {
                  await appState.finalizarCorridaComAvaliacao(
                    estrelas: estrelas,
                    gorjeta: 0.0,
                    elogios: const [],
                  );
                  if (context.mounted) Navigator.of(context).pop();
                },
                onFinalizarCompleto: (estrelas, gorjeta, elogios) async {
                  final pts = await appState.finalizarCorridaComAvaliacao(
                    estrelas: estrelas,
                    gorjeta: gorjeta,
                    elogios: elogios,
                  );
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Avaliação de $estrelas estrelas salva! +$pts pontos no OMNI Club.')),
                  );
                },
                onAlterarDestino: appState.alterarDestinoEmViagem,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
