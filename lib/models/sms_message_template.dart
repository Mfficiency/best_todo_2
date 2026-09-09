/// A named, reusable SMS body a recipient can be pointed at instead of the
/// single global default template ([SmsReportConfig.template]). Supports the
/// same `{hello} {nickname} {completed} {uncompleted} {date} {list}` tokens.
class SmsMessageTemplate {
  String id;
  String name;
  String body;

  SmsMessageTemplate({
    required this.id,
    required this.name,
    required this.body,
  });

  factory SmsMessageTemplate.fromJson(Map<String, dynamic> json) =>
      SmsMessageTemplate(
        id: (json['id'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        body: (json['body'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'body': body,
      };
}
