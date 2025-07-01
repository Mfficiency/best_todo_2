import 'package:flutter/material.dart';
import '../config.dart';
import 'package:flutter/foundation.dart';

class AppLocalizations {
  final Locale locale;
  const AppLocalizations(this.locale);

  static const Map<String, Map<String, dynamic>> _localizedValues = {
    'en': {
      'appTitle': 'Best Todo 2',
      'menu': 'Menu',
      'about': 'About',
      'settings': 'Settings',
      'changelog': 'Changelog',
      'deletedItems': 'Deleted Items',
      'addTask': 'Add task',
      'notifications': 'Enable notifications',
      'swipe': 'Swipe left to delete',
      'language': 'Language',
      'tabs': ['Today','Tomorrow','Day After Tomorrow','Next Week'],
      'cancel': 'Cancel',
      'taskDetails': 'Task Details',
      'note': 'Note',
      'label': 'Label',
      'due': 'Due',
      'completed': 'Completed',
      'yes': 'Yes',
      'no': 'No',
      'reschedule': 'Reschedule',
      'deleted': 'Deleted "{task}"',
      'aboutBody': 'Best Todo 2 v{version}\nRunning in {mode} mode',
      'restore': 'Restore',
      'development': 'Development',
      'production': 'Production',
    },
    'es': {
      'appTitle': 'Mejor Tareas 2',
      'menu': 'Men\u00fa',
      'about': 'Acerca de',
      'settings': 'Configuraci\u00f3n',
      'changelog': 'Registro de cambios',
      'deletedItems': 'Elementos eliminados',
      'addTask': 'Agregar tarea',
      'notifications': 'Habilitar notificaciones',
      'swipe': 'Deslizar a la izquierda para eliminar',
      'language': 'Idioma',
      'tabs': ['Hoy','Ma\u00f1ana','Pasado ma\u00f1ana','Pr\u00f3xima semana'],
      'cancel': 'Cancelar',
      'taskDetails': 'Detalles de la tarea',
      'note': 'Nota',
      'label': 'Etiqueta',
      'due': 'Vencimiento',
      'completed': 'Completado',
      'yes': 'Sí',
      'reschedule': 'Reprogramar',
      'no': 'No',
      'deleted': 'Se elimin\u00f3 "{task}"',
      'aboutBody': 'Best Todo 2 v{version}\nEjecut\u00e1ndose en modo {mode}',
      'restore': 'Restaurar',
      'development': 'Desarrollo',
      'production': 'Producci\u00f3n',
    },
    'fr': {
      'appTitle': 'Meilleur Todo 2',
      'menu': 'Menu',
      'about': '\u00c0 propos',
      'settings': 'Param\u00e8tres',
      'changelog': 'Journal des modifications',
      'deletedItems': '\u00c9l\u00e9ments supprim\u00e9s',
      'addTask': 'Ajouter une t\u00e2che',
      'notifications': 'Activer les notifications',
      'swipe': 'Glisser \u00e0 gauche pour supprimer',
      'language': 'Langue',
      'tabs': ['Aujourd\u2019hui','Demain','Apr\u00e8s-demain','La semaine prochaine'],
      'cancel': 'Annuler',
      'taskDetails': 'D\u00e9tails de la t\u00e2che',
      'note': 'Note',
      'label': '\u00c9tiquette',
      'due': '\u00c9ch\u00e9ance',
      'completed': 'Termin\u00e9',
      'reschedule': 'Replanifier',
      'yes': 'Oui',
      'no': 'Non',
      'deleted': 'Supprim\u00e9 "{task}"',
      'aboutBody': 'Best Todo 2 v{version}\nEx\u00e9cut\u00e9 en mode {mode}',
      'restore': 'Restaurer',
      'development': 'D\u00e9veloppement',
      'production': 'Production',
    },
  };

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  String _string(String key) {
    final lang = locale.languageCode;
    return (_localizedValues[lang] ?? _localizedValues['en'])![key] as String;
  }

  List<String> get tabs {
    final lang = locale.languageCode;
    return List<String>.from(
      (_localizedValues[lang] ?? _localizedValues['en'])!['tabs'] ??
          _localizedValues['en']!['tabs'],
    );
  }

  String get appTitle => _string('appTitle');
  String get menu => _string('menu');
  String get about => _string('about');
  String get settings => _string('settings');
  String get changelog => _string('changelog');
  String get deletedItems => _string('deletedItems');
  String get addTask => _string('addTask');
  String get enableNotifications => _string('notifications');
  String get swipeLeftDelete => _string('swipe');
  String get language => _string('language');
  String get taskDetails => _string('taskDetails');
  String get cancel => _string('cancel');
  String get restore => _string('restore');
  String get note => _string('note');
  String get label => _string('label');
  String get reschedule => _string('reschedule');
  String get due => _string('due');
  String get completed => _string('completed');
  String get yes => _string('yes');
  String get no => _string('no');
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return Config.supportedLocales
        .any((l) => l.languageCode == locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture(AppLocalizations(locale));
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) => false;
}
