// To run this example, use:
//
// flutter run

import 'dart:async';
import 'dart:developer';

import 'package:audio_service/audio_service.dart';
import 'package:audio_service_example/common.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';
import 'package:video_player/video_player.dart';

// You might want to provide this using dependency injection rather than a
// global variable.
late AudioPlayerHandler _audioHandler;

Future<void> main() async {
  _audioHandler = await AudioService.init(
    builder: () => AudioPlayerHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.ryanheise.myapp.channel.audio',
      androidNotificationChannelName: 'Audio playback',
      androidNotificationOngoing: true,
    ),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audio Service Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  late VideoPlayerController _controller;
  final String _url =
      'https://static.kubaca.net/audioChapter/appChapterVideo/5763dc3d8de5f97877d62d36b9b4daa1.mp4';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _controller = VideoPlayerController.networkUrl(Uri.parse(_url),
        videoPlayerOptions: VideoPlayerOptions(
          allowBackgroundPlayback: true,
        ))
      ..initialize().then((_) {
        _audioHandler.setVideoFunctions(_url, _controller.value.duration,
            _controller.play, _controller.pause, _controller.seekTo, () {
          // stop时
          _controller.seekTo(Duration.zero);
          _controller.pause();
        });

        _audioHandler.initializeStreamController(_controller);
        _audioHandler.playbackState
            .addStream(_audioHandler.streamController.stream);

        setState(() {});
      });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _handleChangeApplifecycleState(state);
    super.didChangeAppLifecycleState(state);
  }

  // ignore: inference_failure_on_function_return_type
  _handleChangeApplifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      log('切换至前台');
    } else if (state == AppLifecycleState.paused) {
      log('切换至后台');
      // 检测到切换至后台时，IOS平台如果在播放状态时,调用AudioService开启后台播放
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        _audioHandler.start();
      }
    }
  }

  @override
  void dispose() {
    _audioHandler.streamController.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: AppBar(
      //   title: const Text('Audio Service Demo'),
      // ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Center(
              child: _controller.value.isInitialized
                  ? AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    )
                  : Container(),
            ),
            // Play/pause/stop buttons.
            StreamBuilder<bool>(
              stream: _audioHandler.playbackState
                  .map((state) => state.playing)
                  .distinct(),
              builder: (context, snapshot) {
                final playing = snapshot.data ?? false;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _button(Icons.fast_rewind, _audioHandler.rewind),
                    if (playing)
                      _button(Icons.pause, _audioHandler.pause)
                    else
                      _button(Icons.play_arrow, _audioHandler.play),
                    _button(Icons.stop, _audioHandler.stop),
                    _button(Icons.fast_forward, _audioHandler.fastForward),
                  ],
                );
              },
            ),
            // A seek bar.
            StreamBuilder<MediaState>(
              stream: _mediaStateStream,
              builder: (context, snapshot) {
                final mediaState = snapshot.data;
                return SeekBar(
                  duration: mediaState?.mediaItem?.duration ?? Duration.zero,
                  position: mediaState?.position ?? Duration.zero,
                  onChangeEnd: (newPosition) {
                    _audioHandler.seek(newPosition);
                  },
                );
              },
            ),
            // Display the processing state.
            StreamBuilder<AudioProcessingState>(
              stream: _audioHandler.playbackState
                  .map((state) => state.processingState)
                  .distinct(),
              builder: (context, snapshot) {
                final processingState =
                    snapshot.data ?? AudioProcessingState.idle;
                return Text(
                    // ignore: deprecated_member_use
                    "Processing state: ${describeEnum(processingState)}");
              },
            ),
          ],
        ),
      ),
    );
  }

  /// A stream reporting the combined state of the current media item and its
  /// current position.
  Stream<MediaState> get _mediaStateStream =>
      Rx.combineLatest2<MediaItem?, Duration, MediaState>(
          _audioHandler.mediaItem,
          AudioService.position,
          (mediaItem, position) => MediaState(mediaItem, position));

  IconButton _button(IconData iconData, VoidCallback onPressed) => IconButton(
        icon: Icon(iconData),
        iconSize: 64.0,
        onPressed: onPressed,
      );
}

class MediaState {
  final MediaItem? mediaItem;
  final Duration position;

  MediaState(this.mediaItem, this.position);
}

/// An [AudioHandler] for playing a single item.
class AudioPlayerHandler extends BaseAudioHandler with SeekHandler {
  late StreamController<PlaybackState> streamController;

  Function? _videoPlay;
  Function? _videoPause;
  Function? _videoSeek;
  Function? _videoStop;

  void setVideoFunctions(String url, Duration? duration, Function play,
      Function pause, Function seek, Function stop) {
    mediaItem.add(_getMediaItem(url, duration));
    _videoPlay = play;
    _videoPause = pause;
    _videoSeek = seek;
    _videoStop = stop;
  }

  bool _isPlaying() => playbackState.value.playing;

  void start() => {if (_isPlaying()) play()};

  MediaItem _getMediaItem(String url, Duration? duration) {
    return MediaItem(
      id: url,
      album: "Science Friday",
      title: "A Salute To Head-Scratching Science",
      artist: "Science Friday and WNYC Studios",
      duration: duration ?? const Duration(milliseconds: 5739820),
      artUri: Uri.parse(
          'https://media.wnyc.org/i/1400/1400/l/80/1/ScienceFriday_WNYCStudios_1400.jpg'),
    );
  }

  /// Initialise our audio handler.
  AudioPlayerHandler() {
    AudioSession.instance.then((session) {
      session.configure(const AudioSessionConfiguration.speech());
    });
  }

  // In this simple example, we handle only 4 actions: play, pause, seek and
  // stop. Any button press from the Flutter UI, notification, lock screen or
  // headset will be routed through to these 4 methods so that you can handle
  // your audio playback logic in one place.

  @override
  Future<void> play() async => _videoPlay!();

  @override
  Future<void> pause() async => _videoPause!();

  @override
  Future<void> seek(Duration position) async => _videoSeek!(position);

  @override
  Future<void> stop() async => _videoStop!();

  void initializeStreamController(
      VideoPlayerController? videoPlayerController) {
    bool isPlaying() => videoPlayerController?.value.isPlaying ?? false;

    AudioProcessingState processingState() {
      if (videoPlayerController == null) return AudioProcessingState.idle;
      if (videoPlayerController.value.isBuffering) {
        return AudioProcessingState.buffering;
      }
      if (videoPlayerController.value.isInitialized) {
        return AudioProcessingState.ready;
      }
      return AudioProcessingState.idle;
    }

    Duration bufferedPosition() {
      if (videoPlayerController != null &&
          videoPlayerController.value.buffered.isNotEmpty) {
        return videoPlayerController.value.buffered.last.end;
      } else {
        return Duration.zero;
      }
    }

    void addVideoEvent() {
      streamController.add(PlaybackState(
        controls: [
          MediaControl.rewind,
          isPlaying() ? MediaControl.pause : MediaControl.play,
          MediaControl.stop,
          MediaControl.fastForward,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 3],
        processingState: processingState(),
        playing: isPlaying(),
        updatePosition: videoPlayerController?.value.position ?? Duration.zero,
        bufferedPosition: bufferedPosition(),
        speed: videoPlayerController?.value.playbackSpeed ?? 1.0,
      ));
    }

    void startStream() {
      videoPlayerController?.addListener(addVideoEvent);
    }

    void stopStream() {
      videoPlayerController?.removeListener(addVideoEvent);
    }

    streamController = StreamController<PlaybackState>(
      onListen: startStream,
      onPause: stopStream,
      onResume: startStream,
      onCancel: stopStream,
      sync: true,
    );
  }

  /// Transform a just_audio event into an audio_service state.
  ///
  /// This method is used from the constructor. Every event received from the
  /// just_audio player will be transformed into an audio_service state so that
  /// it can be broadcast to audio_service clients.
  // PlaybackState _transformEvent(PlaybackEvent event) {
  //   return PlaybackState(
  //     controls: [
  //       MediaControl.rewind,
  //       if (_player.playing) MediaControl.pause else MediaControl.play,
  //       MediaControl.stop,
  //       MediaControl.fastForward,
  //     ],
  //     systemActions: const {
  //       MediaAction.seek,
  //       MediaAction.seekForward,
  //       MediaAction.seekBackward,
  //     },
  //     androidCompactActionIndices: const [0, 1, 3],
  //     processingState: const {
  //       ProcessingState.idle: AudioProcessingState.idle,
  //       ProcessingState.loading: AudioProcessingState.loading,
  //       ProcessingState.buffering: AudioProcessingState.buffering,
  //       ProcessingState.ready: AudioProcessingState.ready,
  //       ProcessingState.completed: AudioProcessingState.completed,
  //     }[_player.processingState]!,
  //     playing: _player.playing,
  //     updatePosition: _player.position,
  //     bufferedPosition: _player.bufferedPosition,
  //     speed: _player.speed,
  //     queueIndex: event.currentIndex,
  //   );
  // }
}
