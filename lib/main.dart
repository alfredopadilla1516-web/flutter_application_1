import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';

// ⚠️ Coloca tu nueva API key limpia aquí directamente para probar
const String kGeminiApiKey =
    'AQ.Ab8RN6JsYu_dS5nAQC75kL7vey_QGOG3G0NvtOOYOs8TuBQycQ';
const String kModel = 'gemini-1.5-flash';

// ---------- PALETA DE COLORES ----------
const Color kColorPrimary = Color(0xFF7C3AED);
const Color kColorSecondary = Color(0xFFEC4899);
const Color kColorSuccess = Color(0xFF22C55E);
const Color kColorError = Color(0xFFEF4444);
const Color kColorWarning = Color(0xFFF59E0B);
const List<Color> kBackgroundGradient = [
  Color(0xFF312E81),
  Color(0xFF7C3AED),
  Color(0xFFEC4899),
];
const List<Color> kOptionColors = [
  Color(0xFF3B82F6),
  Color(0xFF10B981),
  Color(0xFFF59E0B),
  Color(0xFFEC4899),
];

// ---------- CONFIGURACIÓN DEL RETO POR NIVELES ----------
const int kQuestionsPerLevel = 25;
const int kQuestionsToPass = 15;

class LevelDef {
  final String name;
  final String emoji;
  final String topicPrompt;

  const LevelDef({
    required this.name,
    required this.emoji,
    required this.topicPrompt,
  });
}

const List<LevelDef> kLevels = [
  LevelDef(
    name: 'Cultura general',
    emoji: '🌍',
    topicPrompt: 'cultura general variada, dificultad fácil',
  ),
  LevelDef(
    name: 'Ciencia y naturaleza',
    emoji: '🧪',
    topicPrompt: 'ciencia, biología, física, química, dificultad media',
  ),
  LevelDef(
    name: 'Historia mundial',
    emoji: '🏛️',
    topicPrompt: 'historia mundial, dificultad media-alta',
  ),
  LevelDef(
    name: 'Arte y literatura',
    emoji: '🎨',
    topicPrompt: 'arte, literatura, música clásica, dificultad alta',
  ),
  LevelDef(
    name: 'Reto experto',
    emoji: '🚀',
    topicPrompt: 'mezcla de todos los temas, dificultad muy alta',
  ),
];

void main() {
  runApp(const TriviaApp());
}

class TriviaApp extends StatelessWidget {
  const TriviaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trivia con IA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: kColorPrimary,
        scaffoldBackgroundColor: Colors.transparent,
      ),
      home: const TriviaScreen(),
    );
  }
}

class TriviaQuestion {
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  TriviaQuestion({
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });

  factory TriviaQuestion.fromJson(Map<String, dynamic> json) {
    return TriviaQuestion(
      question: json['question'] as String,
      options: List<String>.from(json['options'] as List),
      correctIndex: json['correct_index'] as int,
      explanation: json['explanation'] as String,
    );
  }
}

class TriviaScreen extends StatefulWidget {
  const TriviaScreen({super.key});

  @override
  State<TriviaScreen> createState() => _TriviaScreenState();
}

class _TriviaScreenState extends State<TriviaScreen> {
  TriviaQuestion? currentQuestion;
  bool isLoading = false;
  String? errorMessage;
  int? selectedIndex;
  bool answered = false;

  int totalScore = 0;
  int totalAnswered = 0;
  int levelIndex = 0;
  int questionsInLevel = 0;
  int correctInLevel = 0;

  bool voiceEnabled = true;
  final List<String> previousQuestions = [];
  final FlutterTts _tts = FlutterTts();

  double speechRate = 0.62;
  List<Map<String, String>> availableVoices = [];
  Map<String, String>? selectedVoice;

  final List<String> _loadingPhrases = [
    'Conectando neuronas artificiales...',
    'Buscando en la enciclopedia galáctica...',
    'Formulando una pregunta desafiante...',
    'Consultando a la IA...',
    'Preparando el siguiente reto...',
  ];
  String _currentLoadingPhrase = 'Cargando...';

  LevelDef get currentLevel => kLevels[levelIndex];

  @override
  void initState() {
    super.initState();
    _setupTts();
    _fetchNewQuestion();
  }

  Future<void> _setupTts() async {
    await _tts.setLanguage('es-ES');
    await _tts.setSpeechRate(speechRate);
    await _tts.setPitch(1.0);
    await _tts.awaitSpeakCompletion(true);
    await _loadVoices();
  }

  Future<void> _loadVoices() async {
    try {
      final voices = await _tts.getVoices;
      final List<Map<String, String>> spanishVoices = [];
      for (final v in voices) {
        final map = Map<String, dynamic>.from(v as Map);
        final locale = (map['locale'] ?? map['identifier'] ?? '').toString();
        final name = (map['name'] ?? '').toString();
        if (locale.toLowerCase().contains('es') ||
            name.toLowerCase().contains('spanish')) {
          spanishVoices.add({'name': name, 'locale': locale});
        }
      }
      Map<String, String>? femaleVoice;
      for (final v in spanishVoices) {
        final n = v['name']!.toLowerCase();
        if (n.contains('female') ||
            n.contains('mujer') ||
            n.contains('helena')) {
          femaleVoice = v;
          break;
        }
      }
      setState(() {
        availableVoices = spanishVoices;
        selectedVoice =
            femaleVoice ??
            (spanishVoices.isNotEmpty ? spanishVoices.first : null);
      });
      if (selectedVoice != null) {
        await _tts.setVoice({
          'name': selectedVoice!['name']!,
          'locale': selectedVoice!['locale']!,
        });
      }
    } catch (e) {
      debugPrint('No se pudieron cargar las voces: $e');
    }
  }

  Future<void> _applyVoice(Map<String, String> voice) async {
    setState(() => selectedVoice = voice);
    await _tts.setVoice({'name': voice['name']!, 'locale': voice['locale']!});
  }

  Future<void> _applySpeechRate(double rate) async {
    setState(() => speechRate = rate);
    await _tts.setSpeechRate(rate);
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _speak(String text) async {
    if (!voiceEnabled) return;
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> _speakQuestion(TriviaQuestion q) async {
    if (!voiceEnabled) return;
    final letras = ['A', 'B', 'C', 'D'];
    final buffer = StringBuffer(q.question);
    for (int i = 0; i < q.options.length; i++) {
      buffer.write('. Opción ${letras[i]}: ${q.options[i]}.');
    }
    await _speak(buffer.toString());
  }

  Future<void> _fetchNewQuestion() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
      answered = false;
      selectedIndex = null;
      _currentLoadingPhrase =
          _loadingPhrases[Random().nextInt(_loadingPhrases.length)];
    });

    try {
      final avoidList = previousQuestions.isEmpty
          ? ''
          : ' Evita repetir estas preguntas ya usadas: ${previousQuestions.join(" | ")}.';

      final prompt =
          '''
Genera UNA pregunta de trivia en español sobre ${currentLevel.topicPrompt}.$avoidList
Responde ÚNICAMENTE con un objeto JSON válido, sin texto adicional ni bloques de código, con este formato exacto:
{
  "question": "texto de la pregunta",
  "options": ["opción A", "opción B", "opción C", "opción D"],
  "correct_index": 0,
  "explanation": "breve explicación de por qué es correcta"
}
''';

      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$kModel:generateContent?key=$kGeminiApiKey',
      );

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt},
              ],
            },
          ],
          'generationConfig': {
            'temperature': 0.9,
            'responseMimeType': 'application/json',
          },
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Error de la API (${response.statusCode})');
      }

      final data = jsonDecode(response.body);
      final textContent =
          data['candidates'][0]['content']['parts'][0]['text'] as String;
      final cleanJson = textContent
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();
      final questionJson = jsonDecode(cleanJson);
      final newQuestion = TriviaQuestion.fromJson(questionJson);

      setState(() {
        currentQuestion = newQuestion;
        previousQuestions.add(newQuestion.question);
        isLoading = false;
      });

      _speakQuestion(newQuestion);
    } catch (e) {
      setState(() {
        errorMessage =
            'No se pudo generar la pregunta. Revisa tu conexión o API Key.';
        isLoading = false;
      });
    }
  }

  void _selectAnswer(int index) {
    if (answered) return;
    final correct = index == currentQuestion!.correctIndex;

    setState(() {
      selectedIndex = index;
      answered = true;
      totalAnswered++;
      questionsInLevel++;
      if (correct) {
        totalScore++;
        correctInLevel++;
      }
    });

    final letras = ['A', 'B', 'C', 'D'];
    final String spokenMessage;
    if (correct) {
      spokenMessage = '¡Correcto! La razón es: ${currentQuestion!.explanation}';
    } else {
      final correctLetter = letras[currentQuestion!.correctIndex];
      final correctText =
          currentQuestion!.options[currentQuestion!.correctIndex];
      spokenMessage =
          'Incorrecto. La respuesta correcta era la opción $correctLetter: $correctText. La razón es: ${currentQuestion!.explanation}';
    }
    _speak(spokenMessage);
  }

  void _onNextPressed() {
    if (questionsInLevel >= kQuestionsPerLevel) {
      _showLevelResult();
    } else {
      _fetchNewQuestion();
    }
  }

  void _showLevelResult() {
    final passed = correctInLevel >= kQuestionsToPass;
    final isLastLevel = levelIndex == kLevels.length - 1;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            passed
                ? (isLastLevel ? '🏆 ¡Reto completado!' : '🎉 ¡Nivel superado!')
                : '💥 Perdiste',
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Acertaste $correctInLevel de $kQuestionsPerLevel preguntas.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                passed
                    ? (isLastLevel
                          ? 'Completaste todos los niveles disponibles. ¡Eres un experto!'
                          : 'Avanzas al nivel: ${kLevels[levelIndex + 1].emoji} ${kLevels[levelIndex + 1].name}')
                    : 'Necesitabas al menos $kQuestionsToPass correctas. Vuelves a intentar: ${currentLevel.emoji} ${currentLevel.name}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: passed ? kColorSuccess : kColorError,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          actions: [
            Center(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: kColorPrimary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  setState(() {
                    if (passed && !isLastLevel) levelIndex++;
                    questionsInLevel = 0;
                    correctInLevel = 0;
                    previousQuestions.clear();
                  });
                  _fetchNewQuestion();
                },
                child: const Text(
                  'Continuar',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _openVoiceSettings() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text('🎙️ Ajustes de voz'),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Velocidad',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Slider(
                      value: speechRate,
                      min: 0.3,
                      max: 1.0,
                      divisions: 14,
                      activeColor: kColorPrimary,
                      label: speechRate.toStringAsFixed(2),
                      onChanged: (value) {
                        setDialogState(() {});
                        _applySpeechRate(value);
                      },
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Voz',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    if (availableVoices.isEmpty)
                      const Text(
                        'No se encontraron voces en español en este dispositivo/navegador.',
                      )
                    else
                      DropdownButton<Map<String, String>>(
                        isExpanded: true,
                        value: selectedVoice,
                        items: availableVoices.map((v) {
                          return DropdownMenuItem(
                            value: v,
                            child: Text(
                              v['name'] ?? 'Voz sin nombre',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setDialogState(() {});
                          _applyVoice(v);
                        },
                      ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Probar voz'),
                      onPressed: () =>
                          _speak('Hola, así sueno yo leyendo las preguntas.'),
                    ),
                  ],
                ),
              ),
              actions: [
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: kColorPrimary),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cerrar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: kBackgroundGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              _buildLevelProgress(),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: _buildBody(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          const Text('🧠', style: TextStyle(fontSize: 26)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Trivia con IA',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          _iconPill(icon: Icons.settings_voice, onTap: _openVoiceSettings),
          const SizedBox(width: 8),
          _iconPill(
            icon: voiceEnabled ? Icons.volume_up : Icons.volume_off,
            onTap: () {
              setState(() => voiceEnabled = !voiceEnabled);
              if (!voiceEnabled) _tts.stop();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLevelProgress() {
    final progress = questionsInLevel / kQuestionsPerLevel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  '${currentLevel.emoji} ${currentLevel.name}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const Spacer(),
                Text(
                  '$questionsInLevel/$kQuestionsPerLevel',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Colors.white.withOpacity(0.2),
                valueColor: AlwaysStoppedAnimation(
                  correctInLevel >= kQuestionsToPass
                      ? kColorSuccess
                      : kColorSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconPill({required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return Center(
        child: TweenAnimationBuilder(
          tween: Tween<double>(begin: 0.8, end: 1.2),
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOut,
          builder: (context, scale, child) {
            return Transform.scale(scale: scale, child: child);
          },
          onEnd: () {
            if (mounted && isLoading) setState(() {});
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.smart_toy, size: 64, color: Colors.white),
              const SizedBox(height: 24),
              Text(
                _currentLoadingPhrase,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (errorMessage != null) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: kColorError, size: 48),
              const SizedBox(height: 16),
              Text(
                errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: kColorError),
              ),
              const SizedBox(height: 24),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: kColorPrimary),
                onPressed: _fetchNewQuestion,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (currentQuestion == null) return const SizedBox.shrink();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.0, 0.2),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: SingleChildScrollView(
        key: ValueKey(currentQuestion!.question),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildQuestionCard(),
            const SizedBox(height: 18),
            ...List.generate(
              currentQuestion!.options.length,
              (index) => _buildOptionButton(index),
            ),
            if (answered) ...[
              const SizedBox(height: 16),
              _buildExplanationCard(),
              const SizedBox(height: 20),
              _buildNextButton(),
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              currentQuestion!.question,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E1B4B),
              ),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _speakQuestion(currentQuestion!),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: kColorPrimary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.replay, color: kColorPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionButton(int index) {
    final option = currentQuestion!.options[index];
    final letras = ['A', 'B', 'C', 'D'];
    final baseColor = kOptionColors[index % kOptionColors.length];

    Color bg = baseColor;
    double opacity = 1.0;
    double scale = 1.0;

    if (answered) {
      if (index == currentQuestion!.correctIndex) {
        bg = kColorSuccess;
        scale = 1.02;
      } else if (index == selectedIndex) {
        bg = kColorError;
      } else {
        opacity = 0.45;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: opacity,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: answered ? null : () => _selectAnswer(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 18,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: bg.withOpacity(0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        letras[index],
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        option,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (answered && index == currentQuestion!.correctIndex)
                      const Icon(Icons.check_circle, color: Colors.white),
                    if (answered &&
                        index == selectedIndex &&
                        index != currentQuestion!.correctIndex)
                      const Icon(Icons.cancel, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExplanationCard() {
    final correct = selectedIndex == currentQuestion!.correctIndex;
    final color = correct ? kColorSuccess : kColorWarning;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            correct ? Icons.emoji_events : Icons.lightbulb,
            color: color,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  correct
                      ? '¡Correcto! 🎉'
                      : 'La respuesta era "${currentQuestion!.options[currentQuestion!.correctIndex]}"',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  currentQuestion!.explanation,
                  style: const TextStyle(color: Color(0xFF1E1B4B)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNextButton() {
    final isLastQuestionOfLevel = questionsInLevel >= kQuestionsPerLevel;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [kColorSecondary, kColorPrimary],
        ),
        boxShadow: [
          BoxShadow(
            color: kColorPrimary.withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _onNextPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  isLastQuestionOfLevel
                      ? 'Ver resultado'
                      : 'Siguiente pregunta',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  isLastQuestionOfLevel ? Icons.flag : Icons.arrow_forward,
                  color: Colors.white,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
