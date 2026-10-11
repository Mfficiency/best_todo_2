import 'dart:io';

/// How Best Music reaches YouTube for a video's audio. YouTube ties every
/// stream URL to the IP address that asked for it, and on some networks
/// (typically home Wi-Fi with both IPv4 and IPv6) it flags one of those
/// addresses as a bot — "Sign in to confirm you're not a bot" — or the
/// player request and the audio download leave on different address
/// families, so the audio answers 403. Mobile data, on a different address,
/// works. So resolving walks these routes until one plays
/// (`Mp3DownloaderService._resolveStream`), and the chunks are then fetched
/// over the *same* route:
/// - [system]: whatever the phone picks (dual-stack, happy eyeballs);
/// - [ipv4] / [ipv6]: every connection pinned to one address family, so
///   the player request and the audio come from the same address — yt-dlp's
///   `--force-ipv4` fix for the same problem;
/// - [invidious]: a public Invidious server fetches the audio for us
///   (`local=true`), so YouTube only ever sees that server's address.
enum YoutubeRoute {
  system('phone default'),
  ipv4('IPv4 only'),
  ipv6('IPv6 only'),
  invidious('through Invidious');

  const YoutubeRoute(this.label);

  final String label;

  /// The address family a pinned route connects over; null = any.
  InternetAddressType? get addressType => switch (this) {
        YoutubeRoute.ipv4 => InternetAddressType.IPv4,
        YoutubeRoute.ipv6 => InternetAddressType.IPv6,
        _ => null,
      };

  /// The route that last played something, tried first next time (so a
  /// blocked Wi-Fi doesn't cost the full walk for every video). In memory
  /// only — a different network may well need a different route.
  static YoutubeRoute? lastWorking;

  /// Routes in the order to try: the last working one first.
  static List<YoutubeRoute> tryOrder() {
    final first = lastWorking;
    return [
      if (first != null) first,
      for (final r in values)
        if (r != first) r,
    ];
  }
}

/// An [HttpClient] whose connections all go over [route]'s address family
/// (TLS still checked against the real host name). [YoutubeRoute.system]
/// and [YoutubeRoute.invidious] get a plain client.
HttpClient httpClientForRoute(YoutubeRoute route) {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  final type = route.addressType;
  if (type == null) return client;
  client.connectionFactory = (uri, proxyHost, proxyPort) async {
    final host = proxyHost ?? uri.host;
    final port = proxyPort ?? uri.port;
    final addresses = await InternetAddress.lookup(host, type: type);
    if (addresses.isEmpty) {
      throw SocketException('No ${route.label} address for $host');
    }
    final task = await Socket.startConnect(addresses.first, port);
    if (uri.scheme != 'https' || proxyHost != null) return task;
    // A direct https connection: the factory has to do TLS itself.
    return ConnectionTask.fromSocket(
      task.socket.then((socket) => SecureSocket.secure(socket, host: uri.host)),
      task.cancel,
    );
  };
  return client;
}
