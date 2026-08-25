import 'package:uuid/uuid.dart';

/// A file or text note attached to a [Task]. File-backed attachments (image,
/// pdf) keep their bytes on disk under the app's documents dir —
/// [relativePath] is relative to that dir (see `AttachmentStorageService`) so
/// the whole documents tree stays portable across an export/import or a
/// device move; text attachments carry their content inline in [text] and
/// need no file at all.
class Attachment {
  static final Uuid _uuid = const Uuid();

  static String newUid() => _uuid.v4();

  static const String typeText = 'text';
  static const String typeImage = 'image';
  static const String typePdf = 'pdf';

  String uid;
  String type;

  /// Inline content for [typeText]; unused for file-backed types.
  String text;

  /// Original file name, shown in the UI. Unused for [typeText].
  String fileName;

  /// Path to the copied file, relative to the app documents dir. Null for
  /// [typeText].
  String? relativePath;

  DateTime createdAt;

  Attachment({
    String? uid,
    required this.type,
    this.text = '',
    this.fileName = '',
    this.relativePath,
    DateTime? createdAt,
  })  : uid = uid ?? Attachment.newUid(),
        createdAt = createdAt ?? DateTime.now();

  factory Attachment.fromJson(Map<String, dynamic> json) => Attachment(
        uid: json['uid'] as String?,
        type: json['type'] as String? ?? typeText,
        text: json['text'] as String? ?? '',
        fileName: json['fileName'] as String? ?? '',
        relativePath: json['relativePath'] as String?,
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String? ?? '')
            : null,
      );

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'type': type,
        if (text.isNotEmpty) 'text': text,
        if (fileName.isNotEmpty) 'fileName': fileName,
        if (relativePath != null) 'relativePath': relativePath,
        'createdAt': createdAt.toIso8601String(),
      };
}
