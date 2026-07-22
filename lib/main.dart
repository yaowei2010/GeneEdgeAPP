import "dart:async";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";
import "package:provider/provider.dart";
import "package:uuid/uuid.dart";
import "api_service.dart";
import "ble_gateway.dart";
import "bluemagpie_poc_availability.dart";
import "bluemagpie_poc_config.dart";
import "bluemagpie_poc_page.dart";
import "bluemagpie_tts.dart";
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
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _signedIn = false;

  @override
  Widget build(BuildContext context) {
    if (_signedIn) {
      return _SplashGate(
        onLogout: () {
          setState(() => _signedIn = false);
        },
      );
    }
    return _LoginPage(
      onContinue: () {
        setState(() => _signedIn = true);
      },
    );
  }
}

class _LoginPage extends StatefulWidget {
  final VoidCallback onContinue;

  const _LoginPage({required this.onContinue});

  @override
  State<_LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<_LoginPage> {
  final _accountCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _accountCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFEAF4F6),
              Color(0xFFF8FBFD),
              Color(0xFFEFF5FB),
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _LoginBrandHeader(),
                          const SizedBox(height: 28),
                          _LoginCard(
                            accountCtrl: _accountCtrl,
                            passwordCtrl: _passwordCtrl,
                            obscurePassword: _obscurePassword,
                            onTogglePassword: () {
                              setState(
                                () => _obscurePassword = !_obscurePassword,
                              );
                            },
                            onContinue: widget.onContinue,
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            "© 2026 National Cheng Kung University (NCKU), Taiwan. All rights reserved.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 9,
                              height: 1.25,
                              color: Color(0xFF7E96A5),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LoginBrandHeader extends StatelessWidget {
  const _LoginBrandHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x24335C7A),
                blurRadius: 22,
                offset: Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset("icon.jpeg", fit: BoxFit.cover),
        ),
        const SizedBox(height: 18),
        const Text(
          "GeneEdge",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 32,
            height: 1.05,
            fontWeight: FontWeight.w900,
            color: Color(0xFF102F3F),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          "Personal health intelligence",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.25,
            fontWeight: FontWeight.w600,
            color: Color(0xFF5F7585),
          ),
        ),
      ],
    );
  }
}

class _LoginCard extends StatelessWidget {
  final TextEditingController accountCtrl;
  final TextEditingController passwordCtrl;
  final bool obscurePassword;
  final VoidCallback onTogglePassword;
  final VoidCallback onContinue;

  const _LoginCard({
    required this.accountCtrl,
    required this.passwordCtrl,
    required this.obscurePassword,
    required this.onTogglePassword,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD7E4EC)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x17335C7A),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "Welcome back",
            style: TextStyle(
              fontSize: 22,
              height: 1.15,
              fontWeight: FontWeight.w900,
              color: Color(0xFF102F3F),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "Sign in UI is ready. Continue without an account for this pilot.",
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: Color(0xFF607889),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: accountCtrl,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: "Account",
              hintText: "name@example.com",
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: passwordCtrl,
            obscureText: obscurePassword,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onContinue(),
            decoration: InputDecoration(
              labelText: "Password",
              hintText: "Enter password",
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                tooltip: obscurePassword ? "Show password" : "Hide password",
                icon: Icon(
                  obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: onTogglePassword,
              ),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onContinue,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0B5D7A),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text(
              "Continue without account",
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(height: 1, color: const Color(0xFFE3ECF2)),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  "pilot access",
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF7E96A5),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: Container(height: 1, color: const Color(0xFFE3ECF2)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              Icon(
                Icons.verified_user_outlined,
                size: 17,
                color: Color(0xFF4F7B68),
              ),
              SizedBox(width: 7),
              Expanded(
                child: Text(
                  "NCKU GeneEdge pilot environment",
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF607889),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SplashGate extends StatefulWidget {
  final VoidCallback onLogout;

  const _SplashGate({required this.onLogout});

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

  bool get _showBlueMagpiePoc => BlueMagpiePocAvailability.canShowEntry(
        featureEnabled: BlueMagpiePocConfig.enabled,
        debugMode: kDebugMode,
        platform: defaultTargetPlatform,
        // The Android app currently ships only arm64-v8a. Native probe still
        // verifies the runtime ABI before any model work starts.
        isArm64: true,
      );

  void _openBlueMagpiePoc() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BlueMagpiePocPage(tts: BlueMagpieTts()),
      ),
    );
  }

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
      child: ChatRoomPage(
        onLogout: widget.onLogout,
        onOpenBlueMagpiePoc: _showBlueMagpiePoc ? _openBlueMagpiePoc : null,
      ),
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
                  "GeneEdge",
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
