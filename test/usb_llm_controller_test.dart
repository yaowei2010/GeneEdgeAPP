import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geneapp/api_service.dart';
import 'package:geneapp/chat_controller.dart';
import 'package:geneapp/snp_api_payload.dart';
import 'package:geneapp/snp_compute.dart';
import 'snp_api_payload_test.dart' show row;

class UsbLlmApi extends Fake implements ApiService {
  final requests = <Map<String, Object?>>[];
  final replies = <Completer<LlmAskResult>>[];
  @override
  Future<LlmAskResult> askLlm(
      {required String userId,
      required String aggregatedQuery,
      required String topic,
      required List<String> variants,
      int originalVariantCount = 0,
      int noCallCount = 0,
      dynamic yuguard,
      bool debugMode = false}) {
    requests.add({
      'user_id': userId,
      'query': aggregatedQuery,
      'topic': topic,
      'variants': List<String>.of(variants),
      'variant_input_count': originalVariantCount,
      'no_call_count': noCallCount,
      'yuguard': yuguard,
      'debug': debugMode
    });
    final reply = Completer<LlmAskResult>();
    replies.add(reply);
    return reply.future;
  }

  void answer(int index, String answer) => replies[index].complete(LlmAskResult(
      answer: answer,
      url: 'https://example.invalid/v1/ask',
      headers: const {},
      payload: const {},
      statusCode: 200));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final response in [
    {'answer': '測試回覆'},
    {
      'choices': [
        {
          'message': {'content': '測試回覆'}
        }
      ]
    },
  ]) {
    test(
        'real existing askLlm serializes exact USB payload and parses $response',
        () async {
      final payload = SnpApiPayload.build(
          context: const SnpChatContext('u1', '我能喝酒嗎', '酒精'),
          input: const SnpInputIdentity('alcohol', '酒精', 'v1'),
          results: List.generate(77, (i) => row(i, noCall: i >= 70)));
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        expect(request.method, 'POST');
        expect(request.url.toString(), 'https://example.invalid/v1/ask');
        expect(request.headers['content-type'], 'application/json');
        expect(jsonDecode(request.body), payload.request);
          return http.Response(jsonEncode(response), 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
      });
      final chat = ChatController(
          api: ApiService('https://example.invalid/'), threadId: 't');
      chat.llmDebugMode = true;
      expect(
          await http.runWithClient(
              () => chat.askCompletedUsb(payload), () => client),
          '測試回覆');
      expect(calls, 1);
      expect(chat.messages, isEmpty);
      chat.dispose();
    });
  }
  test(
      'USB entry reuses askLlm and preserves 77/70/7 snapshot without history or debug',
      () async {
    final api = UsbLlmApi();
    final chat = ChatController(
        api: api,
        threadId: 'not-u1',
        useLocalComputeMode: true,
        localMockPayload: {
          'variants': ['wrong']
        },
        snpList: [
          'wrong'
        ]);
    chat.llmDebugMode = true;
    final payload = SnpApiPayload.build(
        context: const SnpChatContext('u1', '我能喝酒嗎', '酒精'),
        input: const SnpInputIdentity('alcohol', '酒精', 'v1'),
        results: List.generate(77, (i) => row(i, noCall: i >= 70)));
    final future = chat.askCompletedUsb(payload);
    expect(api.requests.single, {
      'user_id': 'u1',
      'query': '我能喝酒嗎',
      'topic': '酒精',
      'variants': payload.request['variants'],
      'variant_input_count': 77,
      'no_call_count': 7,
      'yuguard': null,
      'debug': false
    });
    api.answer(0, '測試回覆');
    expect(await future, '測試回覆');
    expect(chat.messages, isEmpty);
    chat.dispose();
  });
  test(
      'all no-call sends empty variants; HTTP failure propagates without fallback or persistence',
      () async {
    final api = UsbLlmApi();
    final chat = ChatController(api: api, threadId: 't', snpList: ['wrong']);
    final payload = SnpApiPayload.build(
        context: const SnpChatContext('u1', 'q', '酒精'),
        input: const SnpInputIdentity('a', 'a', 'v1'),
        results: List.generate(77, (i) => row(i, noCall: true)));
    final future = chat.askCompletedUsb(payload);
    expect(api.requests.single['variants'], isEmpty);
    expect(api.requests.single['variant_input_count'], 77);
    expect(api.requests.single['no_call_count'], 77);
    final assertion = expectLater(future, throwsException);
    api.replies.single.completeError(Exception('HTTP 500 private body'));
    await assertion;
    expect(api.requests.length, 1);
    expect(chat.messages, isEmpty);
    chat.dispose();
  });
}
