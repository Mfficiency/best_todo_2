import 'package:flutter/material.dart';
import '../config.dart';
import '../l10n/app_localizations.dart';

class SettingsPage extends StatefulWidget {
  final VoidCallback? onSettingsChanged;
  final ValueChanged<Locale>? onLanguageChanged;
  const SettingsPage({Key? key, this.onSettingsChanged, this.onLanguageChanged})
      : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _notifications = false;
  bool _swipeLeftDelete = Config.swipeLeftDelete;
  late Locale _selectedLocale;

  @override
  void initState() {
    super.initState();
    _selectedLocale = WidgetsBinding.instance.platformDispatcher.locale;
    if (!Config.supportedLocales.contains(_selectedLocale)) {
      _selectedLocale = Config.supportedLocales.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        children: [
          SwitchListTile(
            title: Text(l10n.enableNotifications),
            value: _notifications,
            onChanged: (val) => setState(() => _notifications = val),
          ),
          SwitchListTile(
            title: Text(l10n.swipeLeftDelete),
            value: _swipeLeftDelete,
            onChanged: (val) {
              setState(() => _swipeLeftDelete = val);
              Config.swipeLeftDelete = val;
              widget.onSettingsChanged?.call();
            },
          ),
          ListTile(
            title: Text(l10n.language),
            trailing: DropdownButton<Locale>(
              value: _selectedLocale,
              onChanged: (Locale? val) {
                if (val == null) return;
                setState(() => _selectedLocale = val);
                widget.onLanguageChanged?.call(val);
              },
              items: Config.supportedLocales.map((locale) {
                final name =
                    Config.localeNames[locale.languageCode] ?? locale.toString();
                return DropdownMenuItem(
                  value: locale,
                  child: Text(name),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
