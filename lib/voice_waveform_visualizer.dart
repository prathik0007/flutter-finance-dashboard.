// lib/voice_waveform_visualizer.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A reactive audio visualizer that pulses and renders a bar waveform
/// in real-time as the user's voice amplitude changes.
///
/// The widget is intentionally self-contained: the host only needs to
/// push decibel/amplitude values (0.0-1.0) via [VoiceWaveformVisualizerState.updateAmplitude]
/// and toggle [isListening] to show/hide the sheet.
class VoiceWaveformVisualizer extends StatefulWidget {
  /// Whether the visualizer is currently capturing audio.
  final bool isListening;

  /// Optional label shown under the waveform (e.g. "Listening...").
  final String? hint;

  /// Optional callback fired when the user manually closes the sheet.
  final VoidCallback? onCancel;

  /// Background color of the overlay.
  final Color backgroundColor;

  /// Accent color of the waveform bars.
  final Color accentColor;

  const VoiceWaveformVisualizer({
    super.key,
    required this.isListening,
    this.hint,
    this.onCancel,
    this.backgroundColor = const Color(0xCC0A1A2A),
    this.accentColor = const Color(0xFF26C6DA),
  });

  @override
  VoiceWaveformVisualizerState createState() => VoiceWaveformVisualizerState();
}

/// Public state class so the host can grab a `GlobalKey<VoiceWaveformVisualizerState>`
/// and push live decibel/amplitude updates directly into the animating layout.
class VoiceWaveformVisualizerState extends State<VoiceWaveformVisualizer>
    with TickerProviderStateMixin {
  /// Latest amplitude in [0.0, 1.0] coming from the audio engine.
  double _level = 0.0;

  /// Rolling history of recent levels — powers the trailing waveform tail.
  final List<double> _history = List<double>.filled(40, 0.0);

  /// Drives the always-on pulse animation (works even when level is ~0).
  late final AnimationController _pulseController;

  /// Drives the smooth tween between successive level values.
  late final AnimationController _levelController;
  late Animation<double> _levelAnimation;
  double _previousLevel = 0.0;

  Timer? _idleFallbackTimer;
  final math.Random _rng = math.Random();
  DateTime? _lastPushedAt;

  /// Whether the host is currently feeding us live amplitude samples.
  bool _acceptingInput = true;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    _levelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      value: 0.0,
    );
    _levelAnimation = AlwaysStoppedAnimation(0.0);
    _levelController.addListener(() {
      if (mounted) setState(() {});
    });

    // Gentle synthetic motion so the bars never go fully flat while idle.
    _idleFallbackTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (!mounted) return;
      if (!widget.isListening) return;
      if (!_acceptingInput) return;
      // If the host hasn't pushed a real level recently, animate softly.
      if (_lastPushedAt == null ||
          DateTime.now().difference(_lastPushedAt!).inMilliseconds > 200) {
        final synth = 0.05 + _rng.nextDouble() * 0.08;
        _absorbLevel(synth);
      }
    });
  }

  @override
  void didUpdateWidget(covariant VoiceWaveformVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isListening != oldWidget.isListening) {
      if (!widget.isListening) {
        _acceptingInput = false;
        // Drain smoothly back to zero so the overlay doesn't snap closed.
        _previousLevel = _level;
        _levelAnimation = Tween<double>(begin: _previousLevel, end: 0.0)
            .animate(
              CurvedAnimation(parent: _levelController, curve: Curves.easeOut),
            );
        _levelController
          ..reset()
          ..forward();
      } else {
        // Re-arm for a new session.
        _levelController.value = 0.0;
        _previousLevel = 0.0;
        _level = 0.0;
        for (int i = 0; i < _history.length; i++) {
          _history[i] = 0.0;
        }
        _acceptingInput = true;
        _lastPushedAt = null;
      }
    }
  }

  @override
  void dispose() {
    _idleFallbackTimer?.cancel();
    _pulseController.dispose();
    _levelController.dispose();
    super.dispose();
  }

  /// Public API: push a new decibel/amplitude sample in [0.0, 1.0] from the
  /// audio engine. The host (microphone FAB handler) should call this on
  /// every audio-frame callback.
  ///
  /// Returns `true` if the value was accepted, `false` if the visualizer
  /// is currently dismissing and ignoring input.
  bool updateAmplitude(double amplitude) {
    if (!mounted) return false;
    if (!_acceptingInput) return false;
    final clamped = amplitude.clamp(0.0, 1.0);
    _lastPushedAt = DateTime.now();
    _absorbLevel(clamped);
    return true;
  }

  /// Backwards-compatible alias for [updateAmplitude] (older code used
  /// `updateLevel`).
  bool updateLevel(double amplitude) => updateAmplitude(amplitude);

  void _absorbLevel(double next) {
    _previousLevel = _level;
    _level = next;
    // Shift the history ring.
    if (_history.isNotEmpty) {
      _history.removeAt(0);
      _history.add(next);
    }

    _levelAnimation = Tween<double>(begin: _previousLevel, end: next).animate(
      CurvedAnimation(parent: _levelController, curve: Curves.easeOutCubic),
    );
    _levelController
      ..stop()
      ..value = 0.0
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final displayed = _levelController.isAnimating
        ? _levelAnimation.value
        : _level;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: widget.isListening ? 1.0 : 0.0,
      child: IgnorePointer(
        ignoring: !widget.isListening,
        child: Container(
          color: widget.backgroundColor,
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                _MicPulse(
                  controller: _pulseController,
                  level: displayed,
                  color: widget.accentColor,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  height: 110,
                  child: _WaveformBars(
                    history: _history,
                    color: widget.accentColor,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  widget.hint ?? 'Listening...',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tap cancel to stop',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 11,
                  ),
                ),
                const Spacer(),
                if (widget.onCancel != null)
                  TextButton.icon(
                    onPressed: widget.onCancel,
                    icon: const Icon(Icons.close, color: Colors.white70),
                    label: const Text(
                      'Cancel',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Outer animated ring + central mic dot that pulses with the user's level.
class _MicPulse extends StatelessWidget {
  final AnimationController controller;
  final double level;
  final Color color;

  const _MicPulse({
    required this.controller,
    required this.level,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, _) {
        final t = controller.value; // 0..1
        // Two rings, phase-shifted for a continuous breathing effect.
        final ring1 = 90 + 40 * t + 30 * level;
        final ring2 = 90 + 40 * (1 - t) + 30 * level;
        return SizedBox(
          width: 220,
          height: 220,
          child: Stack(
            alignment: Alignment.center,
            children: [
              _ring(ring1, color.withValues(alpha: 0.20)),
              _ring(ring2, color.withValues(alpha: 0.12)),
              Container(
                width: 86 + 24 * level,
                height: 86 + 24 * level,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.mic, size: 40, color: color),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _ring(double size, Color c) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: c, width: 2),
    ),
  );
}

/// Mirrored bar visualizer driven by [_history].
class _WaveformBars extends StatelessWidget {
  final List<double> history;
  final Color color;

  const _WaveformBars({required this.history, required this.color});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final n = history.length;
        final barWidth = (constraints.maxWidth / n).clamp(2.0, 6.0);
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(n, (i) {
            final v = history[i].clamp(0.05, 1.0);
            final h = 14 + 80 * v; // bars go from 14px to ~94px tall
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                curve: Curves.easeOutCubic,
                width: barWidth,
                height: h,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.4 + 0.6 * v),
                  borderRadius: BorderRadius.circular(barWidth / 2),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

/// Helper to mount the visualizer as a fullscreen modal sheet with a
/// handle to a `GlobalKey<VoiceWaveformVisualizerState>` so the host
/// can push amplitude values into it.
Future<void> showVoiceVisualizerSheet(
  BuildContext context, {
  required GlobalKey<VoiceWaveformVisualizerState> visualizerKey,
  required bool isListening,
  String? hint,
  VoidCallback? onCancel,
  Color accentColor = const Color(0xFF26C6DA),
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (sheetContext) {
      return FractionallySizedBox(
        heightFactor: 0.55,
        child: VoiceWaveformVisualizer(
          key: visualizerKey,
          isListening: isListening,
          hint: hint,
          onCancel: onCancel,
          accentColor: accentColor,
        ),
      );
    },
  );
}
