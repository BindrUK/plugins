import 'dart:async';
import 'dart:html';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// The web implementation of [VideoPlayerPlatform].
///
/// This class implements the `package:video_player` functionality for the web.
class VideoPlayerPlugin extends VideoPlayerPlatform {
  /// Registers this class as the default instance of [VideoPlayerPlatform].
  static void registerWith(Registrar registrar) {
    VideoPlayerPlatform.instance = VideoPlayerPlugin();
  }

  Map<int, _VideoPlayer> _videoPlayers = <int, _VideoPlayer>{};

  int _textureCounter = 1;

  @override
  Future<void> init(int maxCacheSize, int maxCacheFileSize) async {
    return _disposeAllPlayers();
  }

  @override
  Future<void> dispose(int textureId) async {
    _videoPlayers[textureId].dispose();
    _videoPlayers.remove(textureId);
    return null;
  }

  void _disposeAllPlayers() {
    _videoPlayers.values
        .forEach((_VideoPlayer videoPlayer) => videoPlayer.dispose());
    _videoPlayers.clear();
  }

  @override
  Future<int> create() async {
    final int textureId = _textureCounter;
    _textureCounter++;

    final _VideoPlayer player = _VideoPlayer(textureId);

    _videoPlayers[textureId] = player;
    return textureId;
  }

  @override
  Future<void> setDataSource(int textureId, DataSource dataSource) async {
    final _VideoPlayer player = _videoPlayers[textureId];

    Uri uri;
    switch (dataSource.sourceType) {
      case DataSourceType.network:
        uri = Uri.parse(dataSource.uri);
        break;
      case DataSourceType.asset:
        String assetUrl = dataSource.asset;
        if (dataSource.package != null && dataSource.package.isNotEmpty) {
          assetUrl = 'packages/${dataSource.package}/$assetUrl';
        }
        // 'webOnlyAssetManager' is only in the web version of dart:ui
        // ignore: undefined_prefixed_name
        assetUrl = ui.webOnlyAssetManager.getAssetUrl(assetUrl);
        uri = Uri.parse(assetUrl);
        break;
      case DataSourceType.file:
        return Future.error(UnimplementedError(
            'web implementation of video_player cannot play local files'));
    }

    player.setDataSource(dataSource.key, uri);
  }

  @override
  Future<void> setLooping(int textureId, bool looping) async {
    return _videoPlayers[textureId].setLooping(looping);
  }

  @override
  Future<void> play(int textureId) async {
    return _videoPlayers[textureId].play();
  }

  @override
  Future<void> pause(int textureId) async {
    return _videoPlayers[textureId].pause();
  }

  @override
  Future<void> setVolume(int textureId, double volume) async {
    return _videoPlayers[textureId].setVolume(volume);
  }

  @override
  Future<void> setMuted(int textureId, bool muted) async {
    return _videoPlayers[textureId].setMuted(muted);
  }

  @override
  Future<void> seekTo(int textureId, Duration position) async {
    return _videoPlayers[textureId].seekTo(position);
  }

  @override
  Future<Duration> getPosition(int textureId) async {
    _videoPlayers[textureId].sendBufferingUpdate();
    return _videoPlayers[textureId].getPosition();
  }

  @override
  Stream<VideoEvent> videoEventsFor(int textureId) {
    return _videoPlayers[textureId].eventController.stream;
  }

  @override
  Widget buildView(int textureId) {
    return HtmlElementView(viewType: 'videoPlayer-$textureId');
  }
}

class _VideoPlayer {
  final StreamController<VideoEvent> eventController =
      StreamController<VideoEvent>();

  final int textureId;
  Uri uri;
  String key;
  VideoElement videoElement;
  bool isInitialized = false;

  _VideoPlayer(this.textureId) {
    videoElement = VideoElement()
      ..autoplay = false
      ..controls = false
      ..style.border = 'none';

    // TODO(hterkelsen): Use initialization parameters once they are available
    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(
        'videoPlayer-$textureId', (int viewId) => videoElement);

    videoElement.onCanPlay.listen((dynamic _) {
      if (!isInitialized) {
        isInitialized = true;
        sendInitialized();
      }
    });
    videoElement.onError.listen((dynamic error) {
      eventController.addError(error);
    });
    videoElement.onEnded.listen((dynamic _) {
      eventController
          .add(VideoEvent(key: key, eventType: VideoEventType.completed));
    });
  }

  void setDataSource(String key, Uri uri) {
    this.key = key;
    this.uri = uri;
    isInitialized = false;
    videoElement.src = uri.toString();
  }

  void sendBufferingUpdate() {
    eventController.add(VideoEvent(
      key: key,
      buffered: _toDurationRange(videoElement.buffered),
      eventType: VideoEventType.bufferingUpdate,
    ));
  }

  void play() {
    videoElement.play();
  }

  void pause() {
    videoElement.pause();
  }

  void setLooping(bool value) {
    videoElement.loop = value;
  }

  void setVolume(double value) {
    videoElement.muted = false;
    videoElement.volume = value;
  }

  void setMuted(bool muted) {
    videoElement.muted = muted;
  }

  void seekTo(Duration position) {
    videoElement.currentTime = position.inMilliseconds.toDouble() / 1000;
  }

  Duration getPosition() {
    return Duration(milliseconds: (videoElement.currentTime * 1000).round());
  }

  void sendInitialized() {
    eventController.add(
      VideoEvent(
        key: key,
        eventType: VideoEventType.initialized,
        duration: Duration(
          milliseconds: (videoElement.duration * 1000).round(),
        ),
        size: Size(
          videoElement.videoWidth.toDouble() ?? 0.0,
          videoElement.videoHeight.toDouble() ?? 0.0,
        ),
      ),
    );
  }

  void dispose() {
    videoElement.removeAttribute('src');
    videoElement.load();
  }

  List<DurationRange> _toDurationRange(TimeRanges buffered) {
    final List<DurationRange> durationRange = <DurationRange>[];
    for (int i = 0; i < buffered.length; i++) {
      durationRange.add(DurationRange(
        Duration(milliseconds: (buffered.start(i) * 1000).round()),
        Duration(milliseconds: (buffered.end(i) * 1000).round()),
      ));
    }
    return durationRange;
  }
}
