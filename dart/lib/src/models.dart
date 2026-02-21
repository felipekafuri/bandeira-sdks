class BandeiraConfig {
  const BandeiraConfig({
    required this.url,
    required this.token,
    this.pollInterval = const Duration(seconds: 15),
    this.streaming = false,
  });

  final String url;
  final String token;
  final Duration pollInterval;

  /// Enable real-time flag updates via SSE instead of polling.
  final bool streaming;
}

class BandeiraContext {
  const BandeiraContext({
    this.userId = '',
    this.sessionId = '',
    this.remoteAddress = '',
    this.properties = const <String, String>{},
  });

  final String userId;
  final String sessionId;
  final String remoteAddress;
  final Map<String, String> properties;
}
