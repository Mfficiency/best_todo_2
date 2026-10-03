import 'package:flutter/material.dart';

import '../models/youtube_feed.dart';
import '../services/youtube_feed_service.dart';
import 'playback_speed_sheet.dart';
import 'subpage_app_bar.dart';

/// Subscriptions → Feed settings: what the feed hides, and SponsorBlock.
class YoutubeFeedSettingsPage extends StatelessWidget {
  const YoutubeFeedSettingsPage({super.key, this.service});

  final YoutubeFeedService? service;

  @override
  Widget build(BuildContext context) {
    final feed = service ?? YoutubeFeedService.instance;
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Feed settings'),
      body: ValueListenableBuilder<YoutubeFeedSettings>(
        valueListenable: feed.settings,
        builder: (context, settings, _) {
          void update(YoutubeFeedSettings value) => feed.updateSettings(value);
          return ListView(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.short_text),
                title: const Text('Hide Shorts'),
                value: settings.hideShorts,
                onChanged: (v) => update(settings.copyWith(hideShorts: v)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.live_tv_outlined),
                title: const Text('Hide livestreams'),
                subtitle: const Text(
                    "Live, upcoming and past streams — what a channel lists "
                    'under its Live tab'),
                value: settings.hideLivestreams,
                onChanged: (v) =>
                    update(settings.copyWith(hideLivestreams: v)),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.speed),
                title: const Text('Default playback speed'),
                subtitle: Text('${formatSpeed(settings.playbackSpeed)} — '
                    'change it while playing with the speed button on Now '
                    'Playing'),
                onTap: () =>
                    showPlaybackSpeedSheet(context, forDefault: true),
              ),
              const Divider(),
              SwitchListTile(
                secondary: const Icon(Icons.fast_forward_outlined),
                title: const Text('SponsorBlock'),
                subtitle: const Text(
                    'Skip sponsor reads and other segments the SponsorBlock '
                    'community marked (sponsor.ajay.app)'),
                value: settings.sponsorBlockEnabled,
                onChanged: (v) =>
                    update(settings.copyWith(sponsorBlockEnabled: v)),
              ),
              if (settings.sponsorBlockEnabled)
                for (final category in SponsorBlockCategory.values)
                  CheckboxListTile(
                    contentPadding: const EdgeInsets.only(left: 72, right: 16),
                    title: Text(category.label),
                    value: settings.sponsorBlockCategories.contains(category),
                    onChanged: (checked) {
                      final categories = {...settings.sponsorBlockCategories};
                      if (checked == true) {
                        categories.add(category);
                      } else {
                        categories.remove(category);
                      }
                      update(settings.copyWith(
                          sponsorBlockCategories: categories));
                    },
                  ),
            ],
          );
        },
      ),
    );
  }
}
