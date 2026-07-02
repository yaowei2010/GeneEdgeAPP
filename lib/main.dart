import "dart:async";
import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";
import "package:provider/provider.dart";
import "package:uuid/uuid.dart";
import "api_service.dart";
import "ble_gateway.dart";
import "chat_controller.dart";
import "chat_room_page.dart";
import "local_payload_loader.dart";
import "models.dart";

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF0B5D7A),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF2F6FA),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: baseTheme.copyWith(
        textTheme: GoogleFonts.plusJakartaSansTextTheme(baseTheme.textTheme),
        appBarTheme: AppBarTheme(
          centerTitle: false,
          elevation: 0,
          backgroundColor: const Color(0xFFE8F1F7),
          foregroundColor: const Color(0xFF123447),
          titleTextStyle: GoogleFonts.plusJakartaSans(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF123447),
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color:
                  baseTheme.colorScheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: baseTheme.colorScheme.primary,
              width: 1.2,
            ),
          ),
        ),
      ),
      home: const _SplashGate(),
    );
  }
}

class _SplashGate extends StatefulWidget {
  const _SplashGate();

  @override
  State<_SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<_SplashGate> {
  late final ApiService _api = ApiService("http://140.116.52.137:80");
  late final BleGateway _ble = BleGateway();
  late final String _threadId = const Uuid().v4();
  static const String _customLlmUserId = "takeshi_demo_user_001";
  Map<String, dynamic>? _payload;
  bool _ready = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadPayload();
    _timer = Timer(const Duration(milliseconds: 1700), () {
      if (!mounted) return;
      setState(() => _ready = true);
    });
  }

  Future<void> _loadPayload() async {
    try {
      final p = await LocalPayloadLoader.load();
      if (!mounted) return;
      setState(() => _payload = p);
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _payload == null) return const _SplashPage();
    return ChangeNotifierProvider(
      create: (_) => ChatController(
        api: _api,
        bleGateway: _ble,
        llmUserId: _customLlmUserId,
        preferEdgeBleForLlm: true,
        localMockPayload: _payload,
        useLocalComputeMode: false,
        threadId: _threadId,
        topic: ChatTopic.alcohol,
        snpList: const [],
      )..load(),
      child: const ChatRoomPage(),
    );
  }
}

class _SplashPage extends StatefulWidget {
  const _SplashPage();

  @override
  State<_SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<_SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _runCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);
  late final Animation<Offset> _runOffset = Tween<Offset>(
    begin: const Offset(-0.85, 0),
    end: const Offset(0.85, 0),
  ).animate(CurvedAnimation(parent: _runCtrl, curve: Curves.easeInOut));

  @override
  void dispose() {
    _runCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFF5FB),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 128,
                  height: 128,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x26335C7A),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset("icon.jpeg", fit: BoxFit.cover),
                ),
                const SizedBox(height: 22),
                const Text(
                  "GeneEdgeRobot",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF123447),
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  width: 210,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFFCEE0EE)),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Positioned(
                        left: 16,
                        child: Text(
                          "Loading...",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF4A6980),
                          ),
                        ),
                      ),
                      SlideTransition(
                        position: _runOffset,
                        child: const Icon(
                          Icons.directions_run_rounded,
                          size: 24,
                          color: Color(0xFF0B5D7A),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
