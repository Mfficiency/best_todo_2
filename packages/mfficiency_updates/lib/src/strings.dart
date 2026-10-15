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
    this.rateLimited =
        'GitHub is limiting update checks right now — try again later.',
    this.available = _available,
    this.checking = 'Checking…',
    this.checkNow = 'Check for updates',
    this.currentVersion = _currentVersion,
    this.downloadedAt = _downloadedAt,
    this.installedAt = _installedAt,
    this.downloadedReady = _downloadedReady,
    this.downloadedLabel = 'Downloaded:',
    this.installedLabel = 'Installed:',
    this.lastCheckLabel = 'Last check:',
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
    this.remaining = _remaining,
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
    this.releaseBuilt = _releaseBuilt,
    this.releaseBuildTime = _releaseBuildTime,
    this.releaseApkSize = _releaseApkSize,
    this.dateTime = _dateTime,
    this.date = _date,
  });

  final String upToDate;
  final String notConfigured;
  final String failed;
  final String needsToken;
  final String badToken;

  /// GitHub's rate limit hit: automatic checks pause until it resets.
  final String rateLimited;

  /// "Version 1.2.0 (5) available".
  final String Function(String version) available;
  final String checking;
  final String checkNow;

  /// "Current version 1.2.0 (5)".
  final String Function(String version) currentVersion;

  /// "Downloaded 12.10.2026 11:20" (the running build). The status card
  /// uses [downloadedLabel] instead.
  final String Function(String time) downloadedAt;

  /// "Installed 12.10.2026 11:25". The status card uses [installedLabel].
  final String Function(String time) installedAt;

  /// "1.3.0 (6) downloaded 12.10.2026 11:20 · ready to install".
  final String Function(String version, String time) downloadedReady;

  /// Labels of the status card's time column ("Downloaded:" 12.10.2026
  /// 11:20); the times line up next to them.
  final String downloadedLabel;
  final String installedLabel;
  final String lastCheckLabel;
  final String neverChecked;

  /// "Last checked 12.10.2026 11:20".
  final String Function(String date) lastChecked;

  /// No longer shown (the status card dropped its pull-down hint); kept so
  /// apps that pass it still compile.
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

  /// "00:01:23 remaining", under the progress of a download over 30 s.
  final String Function(String hms) remaining;

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

  /// The changelog's build facts of a version ([ReleaseBuildInfo]):
  /// "Built 15.10.2026 14:02", "Build time 3m 12s", "APK 19.4 MB".
  final String Function(String time) releaseBuilt;
  final String Function(String duration) releaseBuildTime;
  final String Function(String size) releaseApkSize;

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
String _remaining(String t) => '$t remaining';
String _downloadingBackground(String v) =>
    "Downloading version $v in the background. You'll be asked to install it "
    "when it's ready.";
String _versionTitle(String v) => 'Version $v';
String _versionNotAvailable(String v) =>
    'Version $v is no longer available to download.';
String _versionDownload(String v) => 'Download version $v';

String _releaseBuilt(String t) => 'Built $t';
String _releaseBuildTime(String d) => 'Build time $d';
String _releaseApkSize(String s) => 'APK $s';

String _two(int n) => n.toString().padLeft(2, '0');
String _date(DateTime d) => '${_two(d.day)}.${_two(d.month)}.${d.year}';
String _dateTime(DateTime d) => '${_date(d)} ${_two(d.hour)}:${_two(d.minute)}';
