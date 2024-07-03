import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _urlController = TextEditingController();
  bool permissionGranted = false;
  bool showDetails = false;
  String videoTitle = '';
  String videoThumbnail = '';
  int audioSize = 0;
  List<MuxedStreamInfo> muxedStreams = [];
  AudioOnlyStreamInfo? audioStreamInfo;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    getStoragePermission();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('YouTube Downloader'),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                'Enter YouTube URL:',
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 20),
              Container(
                width: 300,
                child: TextField(
                  controller: _urlController,
                  decoration: InputDecoration(
                    hintText: 'https://www.youtube.com/watch?v=... or https://youtube.com/shorts/... or https://youtu.be/...',
                  ),
                ),
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: permissionGranted ? () async {
                  String videoUrl = _urlController.text; // Get user input
                  await fetchVideoDetails(videoUrl);
                } : null,
                child: Text('Fetch Details'),
              ),
              SizedBox(height: 20),
              showDetails ? Column(
                children: [
                  Image.network(videoThumbnail),
                  Text('Title: $videoTitle'),
                  Text('Audio Size: ${(audioSize / (1024 * 1024)).toStringAsFixed(2)} MB'),
                  ElevatedButton(
                    onPressed: permissionGranted ? () {
                      String videoUrl = _urlController.text;
                      _downloadAudio(videoUrl);
                    } : null,
                    child: Text('Download MP3'),
                  ),
                  SizedBox(
                    height: 200, // Adjust height as needed
                    child: ListView(
                      shrinkWrap: true,
                      children: muxedStreams.map((info) => ListTile(
                        title: Text('${info.videoQualityLabel} (${info.size.totalMegaBytes.toStringAsFixed(2)} MB)'),
                        trailing: ElevatedButton(
                          onPressed: permissionGranted ? () {
                            String videoUrl = _urlController.text;
                            _downloadVideo(videoUrl, info);
                          } : null,
                          child: Text('Download MP4 ${info.videoQualityLabel}'),
                        ),
                      )).toList(),
                    ),
                  ),
                ],
              ) : Container(),
            ],
          ),
        ),
      ),
    );
  }

  String extractVideoId(String url) {
    if (url.contains('youtube.com/shorts/')) {
      return url.split('youtube.com/shorts/')[1].split('?').first;
    } else if (url.contains('youtu.be/')) {
      return url.split('youtu.be/')[1].split('?').first;
    } else if (url.contains('youtube.com/watch?v=')) {
      return url.split('youtube.com/watch?v=')[1].split('&').first;
    } else {
      throw ArgumentError('Invalid YouTube video ID or URL');
    }
  }

  Future<void> fetchVideoDetails(String url) async {
    var ytExplode = YoutubeExplode();
    try {
      String videoId = extractVideoId(url);
      var video = await ytExplode.videos.get(videoId);
      var manifest = await ytExplode.videos.streamsClient.getManifest(video.id);
      audioStreamInfo = manifest.audioOnly.first;

      setState(() {
        videoTitle = video.title;
        videoThumbnail = video.thumbnails.standardResUrl;
        audioSize = audioStreamInfo!.size.totalBytes;
        muxedStreams = manifest.muxed
            .where((info) => ['240p', '360p', '480p', '720p', '1080p'].contains(info.videoQualityLabel))
            .toList();
        showDetails = true;
      });
    } catch (e) {
      print('Error: $e');
    } finally {
      ytExplode.close();
    }
  }

  Future<void> _downloadVideo(String url, MuxedStreamInfo videoStreamInfo) async {
    var ytExplode = YoutubeExplode();
    try {
      String videoId = extractVideoId(url);
      var video = await ytExplode.videos.get(videoId);
      var manifest = await ytExplode.videos.streamsClient.getManifest(video.id);

      var directory = await getExternalStorageDirectory();
      var safeDirPath = directory?.path ?? '/storage/emulated/0/Download';
      await Directory(safeDirPath).create(recursive: true);

      var sanitizedTitle = video.title.replaceAll(RegExp(r'[^\w\s-]'), '');
      var videoStream = ytExplode.videos.streamsClient.get(videoStreamInfo);
      var videoFilePath = '$safeDirPath/$sanitizedTitle ${videoStreamInfo.videoQualityLabel}.mp4';
      await saveStreamToFile(videoStream, videoFilePath);
      print('Download complete: $videoFilePath');
    } catch (e) {
      print('Error: $e');
    } finally {
      ytExplode.close();
    }
  }

  Future<void> _downloadAudio(String url) async {
    var ytExplode = YoutubeExplode();
    try {
      String videoId = extractVideoId(url);
      var video = await ytExplode.videos.get(videoId);
      var manifest = await ytExplode.videos.streamsClient.getManifest(video.id);
      var audioStreamInfo = manifest.audioOnly.first;

      var directory = await getExternalStorageDirectory();
      var safeDirPath = directory?.path ?? '/storage/emulated/0/Download';
      await Directory(safeDirPath).create(recursive: true);

      var sanitizedTitle = video.title.replaceAll(RegExp(r'[^\w\s-]'), '');
      var audioStream = ytExplode.videos.streamsClient.get(audioStreamInfo);
      var audioFilePath = '$safeDirPath/$sanitizedTitle.mp3';
      await saveStreamToFile(audioStream, audioFilePath);
      print('Download complete: $audioFilePath');
    } catch (e) {
      print('Error: $e');
    } finally {
      ytExplode.close();
    }
  }

  Future<void> saveStreamToFile(Stream<List<int>> stream, String filePath) async {
    var file = File(filePath);
    var sink = file.openWrite();
    await stream.pipe(sink);
    await sink.close();
  }

  Future<void> getStoragePermission() async {
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      var status = await Permission.photos.request();
      if (status.isGranted) {
        setState(() {
          permissionGranted = true;
        });
      } else if (status.isPermanentlyDenied) {
        await openAppSettings();
      } else {
        setState(() {
          permissionGranted = false;
        });
      }
    } else {
      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;

      Permission permission;
      if (androidInfo.version.sdkInt >= 33) {
        permission = Permission.photos;
      } else {
        permission = Permission.storage;
      }

      PermissionStatus status = await permission.request();

      if (status.isGranted) {
        setState(() {
          permissionGranted = true;
        });
      } else if (status.isPermanentlyDenied) {
        await openAppSettings();
      } else {
        setState(() {
          permissionGranted = false;
        });
      }
    }
  }
}
