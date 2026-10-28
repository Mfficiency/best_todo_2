// Locks down a `flutter build web` of the approvals website (SPEC §4.2k)
// before `deploy-web.yml` publishes it. GitHub Pages can't send response
// headers, so the policy goes into index.html as <meta> tags:
//
// * Content-Security-Policy: scripts only from the site itself (no inline
//   script, no eval — WebAssembly for CanvasKit aside), network only to the
//   site and api.todoist.com, no plugins, no forms, no <base> hijacking.
//   Stops injected or third-party code from reading the token or sending it
//   anywhere. (Framing is refused by the app itself: frame-ancestors doesn't
//   work from a <meta> tag.)
// * Referrer-Policy no-referrer, robots noindex/nofollow (+ robots.txt).
// * The build is made with `--pwa-strategy=none`, whose service worker is an
//   empty file: nothing is cached offline, every visit loads the current
//   build. (Deleting the file would only make the loader wait for it.)
//
// Usage: dart run tool/harden_approvals_site.dart [build/web]
import 'dart:io';

const csp = "default-src 'none'; "
    "script-src 'self' 'wasm-unsafe-eval'; "
    "connect-src 'self' https://api.todoist.com https://fonts.gstatic.com; "
    "font-src 'self' data: https://fonts.gstatic.com; "
    "img-src 'self' data: blob:; "
    "style-src 'self' 'unsafe-inline'; "
    "manifest-src 'self'; "
    "worker-src 'self' blob:; "
    "base-uri 'self'; "
    "form-action 'none'; "
    "object-src 'none'";

void main(List<String> args) {
  final dir = Directory(args.isEmpty ? 'build/web' : args.first);
  final index = File('${dir.path}/index.html');
  if (!index.existsSync()) {
    stderr.writeln('No ${index.path} — run flutter build web first');
    exit(1);
  }
  var html = index.readAsStringSync();
  const anchor = '<meta charset="UTF-8">';
  if (!html.contains(anchor)) {
    stderr.writeln('index.html has no $anchor to anchor the policy on');
    exit(1);
  }
  html = html
      .replaceFirst(
        anchor,
        '$anchor\n'
        '  <meta http-equiv="Content-Security-Policy" content="$csp">\n'
        '  <meta name="referrer" content="no-referrer">\n'
        '  <meta name="robots" content="noindex, nofollow">',
      )
      .replaceFirst(
        RegExp(r'<meta name="description" content="[^"]*">'),
        '<meta name="description" content="Private page">',
      )
      .replaceFirst('<title>BestToDo</title>', '<title>Approvals</title>');
  index.writeAsStringSync(html);
  File('${dir.path}/robots.txt').writeAsStringSync('User-agent: *\nDisallow: /\n');
  stdout.writeln('Hardened ${index.path}');
}
