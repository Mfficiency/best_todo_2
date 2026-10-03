import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../models/youtube_feed.dart';
import '../services/youtube_feed_service.dart';
import 'estimated_progress_bar.dart';
import 'subpage_app_bar.dart';

/// Subscriptions → Channels: search YouTube channels by name to subscribe,
/// import a Tubular/NewPipe subscriptions export, and unsubscribe.
class YoutubeChannelsPage extends StatefulWidget {
  const YoutubeChannelsPage({super.key, this.service});

  final YoutubeFeedService? service;

  @override
  State<YoutubeChannelsPage> createState() => _YoutubeChannelsPageState();
}

class _YoutubeChannelsPageState extends State<YoutubeChannelsPage> {
  late final YoutubeFeedService _service =
      widget.service ?? YoutubeFeedService.instance;
  final TextEditingController _query = TextEditingController();

  List<YoutubeChannel>? _results;
  bool _searching = false;
  bool _importing = false;
  String? _error;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await _service.searchChannels(query);
      if (!mounted) return;
      setState(() => _results = results);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Search failed: $e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _clearSearch() {
    _query.clear();
    setState(() {
      _results = null;
      _error = null;
    });
  }

  Future<void> _import() async {
    final file = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'Tubular/NewPipe export', extensions: ['json']),
    ]);
    if (file == null || !mounted) return;
    setState(() => _importing = true);
    String message;
    try {
      final result = await _service.importNewPipe(await file.readAsString());
      message = 'Imported ${result.added} channel'
          '${result.added == 1 ? '' : 's'}'
          '${result.alreadySubscribed > 0 ? ', ${result.alreadySubscribed} already subscribed' : ''}'
          '${result.skipped > 0 ? ', ${result.skipped} skipped' : ''}';
      if (result.added > 0) _service.refresh();
    } catch (e) {
      message = "Couldn't import: $e";
    } finally {
      if (mounted) setState(() => _importing = false);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _unsubscribe(YoutubeChannel channel) async {
    await _service.unsubscribe(channel.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Unsubscribed from ${channel.name}'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => _service.subscribe(channel),
      ),
    ));
  }

  Widget _avatar(YoutubeChannel channel) {
    final url = channel.avatarUrl;
    return CircleAvatar(
      backgroundImage: url == null ? null : NetworkImage(url),
      onBackgroundImageError: url == null ? null : (_, __) {},
      child: url == null
          ? Text(channel.name.isEmpty ? '?' : channel.name[0].toUpperCase())
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Scaffold(
      appBar: buildSubpageAppBar(
        context,
        title: 'Channels',
        actions: [
          IconButton(
            tooltip: 'Import from Tubular/NewPipe',
            icon: const Icon(Icons.file_upload_outlined),
            onPressed: _importing ? null : _import,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _query,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: 'Search YouTube channels',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: results != null
                    ? IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.clear),
                        onPressed: _clearSearch,
                      )
                    : IconButton(
                        tooltip: 'Search',
                        icon: const Icon(Icons.arrow_forward),
                        onPressed: _search,
                      ),
              ),
            ),
          ),
          EstimatedProgressBar(active: _searching || _importing),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(
            child: ValueListenableBuilder<List<YoutubeChannel>>(
              valueListenable: _service.subscriptions,
              builder: (context, subs, _) {
                if (results != null) {
                  if (results.isEmpty) {
                    return const Center(child: Text('No channels found'));
                  }
                  return ListView(children: [
                    for (final channel in results)
                      ListTile(
                        leading: _avatar(channel),
                        title: Text(channel.name),
                        trailing: _service.isSubscribed(channel.id)
                            ? const OutlinedButton(
                                onPressed: null,
                                child: Text('Subscribed'),
                              )
                            : FilledButton(
                                onPressed: () => _service.subscribe(channel),
                                child: const Text('Subscribe'),
                              ),
                      ),
                  ]);
                }
                if (subs.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Search for a channel above, or import your '
                        'subscriptions from Tubular/NewPipe (Settings → '
                        'Content → Export subscriptions there, then the '
                        'upload button here).',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView(children: [
                  ListTile(
                    dense: true,
                    title: Text('Subscribed (${subs.length})'),
                  ),
                  for (final channel in subs)
                    ListTile(
                      leading: _avatar(channel),
                      title: Text(channel.name),
                      trailing: IconButton(
                        tooltip: 'Unsubscribe',
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () => _unsubscribe(channel),
                      ),
                    ),
                ]);
              },
            ),
          ),
        ],
      ),
    );
  }
}
