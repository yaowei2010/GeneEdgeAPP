enum Role { system, user, assistant }

enum ChatTopic {
  alcohol("alcohol", "酒精"),
  medication("medication", "藥物"),
  memory("memory", "記憶"),
  mentalState("mental_state", "心理狀態"),
  hypertension("hypertension", "高血壓"),
  lipids("lipids", "血脂"),
  nutrition("nutrition", "營養");

  const ChatTopic(this.key, this.label);
  final String key;
  final String label;

  static ChatTopic fromInput(String input) {
    final normalized = input.trim().toLowerCase();
    switch (normalized) {
      case "alcohol":
      case "酒精":
        return ChatTopic.alcohol;
      case "nccn":
      case "藥物":
      case "medication":
      case "drug":
        return ChatTopic.medication;
      case "gene_variant":
      case "gene-variant":
      case "記憶":
      case "memory":
        return ChatTopic.memory;
      case "心理":
      case "心理狀態":
      case "mental":
      case "mental_state":
      case "mood":
        return ChatTopic.mentalState;
      case "高血壓":
      case "hypertension":
      case "bp":
        return ChatTopic.hypertension;
      case "血脂":
      case "lipid":
      case "lipids":
        return ChatTopic.lipids;
      case "general":
      case "營養":
      case "nutrition":
        return ChatTopic.nutrition;
      default:
        throw ArgumentError("Unknown topic: $input");
    }
  }
}

class RagChunk {
  final String source;
  final String content;
  final double? score;

  RagChunk({
    required this.source,
    required this.content,
    this.score,
  });
}

class ToolResult {
  final String tool;
  final String content;

  ToolResult({
    required this.tool,
    required this.content,
  });
}

enum CommandType { help, topic, reset, logpath, unknown }

class ParsedCommand {
  final CommandType type;
  final List<String> args;

  ParsedCommand({
    required this.type,
    this.args = const [],
  });
}

class ChatMessage {
  final String id;
  final Role role;
  final String content;
  final DateTime createdAt;
  final bool isTyping;
  final Map<String, dynamic>? meta;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.isTyping = false,
    this.meta,
  });

  Map<String, dynamic> toJson() => {
        "id": id,
        "role": role.name,
        "content": content,
        "createdAt": createdAt.toIso8601String(),
        "isTyping": isTyping,
        "meta": meta,
      };

  static ChatMessage fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j["id"] as String,
        role: Role.values.firstWhere((r) => r.name == j["role"]),
        content: j["content"] as String,
        createdAt: DateTime.parse(j["createdAt"] as String),
        isTyping: (j["isTyping"] as bool?) ?? false,
        meta: (j["meta"] as Map?)?.cast<String, dynamic>(),
      );
}
