import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";
import "package:provider/provider.dart";
import "package:uuid/uuid.dart";
import "api_service.dart";
import "chat_controller.dart";
import "chat_room_page.dart";
import "local_payload_loader.dart";
import "models.dart";

void main() {
  runApp(const LocalMockApp());
}

class LocalMockApp extends StatefulWidget {
  const LocalMockApp({super.key});

  @override
  State<LocalMockApp> createState() => _LocalMockAppState();
}

class _LocalMockAppState extends State<LocalMockApp> {
  late final Future<Map<String, dynamic>> _payloadFuture = LocalPayloadLoader.load();

  @override
  Widget build(BuildContext context) {
    final api = ApiService("http://140.116.52.137:80");
    final threadId = const Uuid().v4();
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
      ),
      home: FutureBuilder<Map<String, dynamic>>(
        future: _payloadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError || snapshot.data == null) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    "載入 local_payload.json 失敗：${snapshot.error}",
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ),
            );
          }

          final payload = snapshot.data!;
          return ChangeNotifierProvider(
            create: (_) => ChatController(
              api: api,
              threadId: threadId,
              bleGateway: null,
              llmUserId: payload["user_id"]?.toString(),
              preferEdgeBleForLlm: false,
              allowCloudFallbackWhenBleFails: true,
              localMockPayload: payload,
              topic: ChatTopic.alcohol,
              snpList: (payload["SNP_list"] as List? ?? const [])
                  .map((e) => e.toString())
                  .toList(),
            )..load(),
            child: const ChatRoomPage(),
          );
        },
      ),
    );
  }
}
