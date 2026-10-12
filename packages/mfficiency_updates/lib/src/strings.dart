/// Every text the package shows, English by default. Apps with their own
/// translations pass an instance built from them (see README.md).
class UpdateStrings {
  const UpdateStrings({
    this.upToDate = 'Up to date',
    this.notConfigured = 'No update source configured',
    this.failed = 'Could not check for updates',
    this.needsToken = 'Add a GitHub token to check for updates',
    this.badToken =
        'GitHub refused the token. Check that it can read the repository.',
    this.available = _available,
    this.checking = 'Checking…',
    this.checkNow = 'Check for updates',
    this.currentVersion = _currentVersion,
    this.downloadedAt = _downloadedAt,
    this.installedAt = _installedAt,
    this.downloadedReady = _downloadedReady,
    this.neverChecked = 'Not checked yet',
    this.lastChecked = _lastChecked,
    this.pullToCheck = 'Pull down to check for updates',
    this.install = 'Install',
    this.retry = 'Try again',
    this.later = 'Later',
    this.readyBanner = _readyBanner,
    this.downloadFailedBanner = _downloadFailedBanner,
    this.availableBanner = _availableBanner,
    this.downloading = _downloading,
    this.downloadingBackground = _downloadingBackground,
    this.installFailed =
        "The update couldn't be downloaded. Check the connection and try "
            'again.',
    this.allowInstall =
        'Turn on "Allow from this source" in the screen that opened and come '
            'back; the install then starts by itself. Only needed once.',
    this.downloadLinkFailed =
        "Couldn't get the download link from GitHub. Check the token.",
    this.notAvailableInPreview = 'Not available in the browser preview',
    this.versionTitle = _versionTitle,
    this.versionCurrent = 'You are using this version',
    this.versionNotAvailable = _versionNotAvailable,
    this.versionDowngradeNote =
        'Android installs an older version only after the current one is '
            'uninstalled, which removes its data. Export a backup first.',
    this.versionDownload = _versionDownload,
    this.dateTime = _dateTime,
    this.date = _date,
  });

  final String upToDate;
  final String notConfigured;
  final String failed;
  final String needsToken;
  final String badToken;

  /// "Version 1.2.0 (5) available".
  final String Function(String version) available;
  final String checking;
  final String checkNow;

  /// "Current version 1.2.0 (5)".
  final String Function(String version) currentVersion;

  /// "Downloaded 12.10.2026 11:20" (the running build).
  final String Function(String time) downloadedAt;

  /// "Installed 12.10.2026 11:25".
  final String Function(String time) installedAt;

  /// "1.3.0 (6) downloaded 12.10.2026 11:20 · ready to install".
  final String Function(String version, String time) downloadedReady;
  final String neverChecked;

  /// "Last checked 12.10.2026 11:20".
  final String Function(String date) lastChecked;
  final String pullToCheck;
  final String install;
  final String retry;
  final String later;

  /// "Update ready · 1.3.0 (6)".
  final String Function(String version) readyBanner;

  /// "Version 1.3.0 (6) couldn't be downloaded".
  final String Function(String version) downloadFailedBanner;

  /// "Version 1.3.0 (6) is available" (no background download: automatic
  /// checks off, or a release without an APK).
  final String Function(String version) availableBanner;

  /// "Downloading version 1.3.0 (6)…" (progress in the changelog card and
  /// the check tile; " 42 %" is appended).
  final String Function(String version) downloading;

  /// The one SnackBar after a tap that starts a download.
  final String Function(String version) downloadingBackground;
  final String installFailed;
  final String allowInstall;
  final String downloadLinkFailed;
  final String notAvailableInPreview;

  /// Older-versions sheet: "Version 1.0.0".
  final String Function(String version) versionTitle;
  final String versionCurrent;
  final String Function(String version) versionNotAvailable;
  final String versionDowngradeNote;
  final String Function(String version) versionDownload;

  /// Date and time in the app's region format (default dd.MM.yyyy HH:mm).
  final String Function(DateTime time) dateTime;

  /// Date in the app's region format (default dd.MM.yyyy).
  final String Function(DateTime time) date;
}

String _available(String v) => 'Version $v available';
String _currentVersion(String v) => 'Current version $v';
String _downloadedAt(String t) => 'Downloaded $t';
String _installedAt(String t) => 'Installed $t';
String _downloadedReady(String v, String t) =>
    '$v downloaded $t · ready to install';
String _lastChecked(String d) => 'Last checked $d';
String _readyBanner(String v) => 'Update ready · $v';
String _downloadFailedBanner(String v) => "Version $v couldn't be downloaded";
String _availableBanner(String v) => 'Version $v is available';
String _downloading(String v) => 'Downloading version $v…';
String _downloadingBackground(String v) =>
    "Downloading version $v in the background. You'll be asked to install it "
    "when it's ready.";
String _versionTitle(String v) => 'Version $v';
String _versionNotAvailable(String v) =>
    'Version $v is no longer available to download.';
String _versionDownload(String v) => 'Download version $v';

String _two(int n) => n.toString().padLeft(2, '0');
String _date(DateTime d) => '${_two(d.day)}.${_two(d.month)}.${d.year}';
String _dateTime(DateTime d) => '${_date(d)} ${_two(d.hour)}:${_two(d.minute)}';
