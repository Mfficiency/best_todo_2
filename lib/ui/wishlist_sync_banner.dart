import 'package:flutter/material.dart';

/// Offers to connect this app's Wishlist with the other BestToDo-family
/// app's via [SharedWishlistStore] (see that file's doc for the "why").
/// Shown by the two Wishlist pages only while not yet connected and not
/// dismissed; the page itself owns that decision and hides this widget once
/// either callback fires, so this widget carries no visibility state of its
/// own beyond its "connecting" spinner.
class WishlistSyncBanner extends StatefulWidget {
  final String otherAppName;

  /// Requests the permission and returns whether it was granted.
  final Future<bool> Function() onConnect;
  final VoidCallback onDismiss;

  const WishlistSyncBanner({
    super.key,
    required this.otherAppName,
    required this.onConnect,
    required this.onDismiss,
  });

  @override
  State<WishlistSyncBanner> createState() => _WishlistSyncBannerState();
}

class _WishlistSyncBannerState extends State<WishlistSyncBanner> {
  bool _connecting = false;

  Future<void> _handleConnect() async {
    setState(() => _connecting = true);
    final granted = await widget.onConnect();
    if (!mounted) return;
    setState(() => _connecting = false);
    if (!granted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Permission not granted — you can try again anytime'),
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.sync),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Connect this Wishlist with ${widget.otherAppName} so '
                    'items show up in both apps.',
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton(
                        onPressed: _connecting ? null : widget.onDismiss,
                        child: const Text('Not now'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _connecting ? null : _handleConnect,
                        child: _connecting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Connect'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
