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
  List<MuxedStreamInfo> videoQualities = [];

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
                    hintText: 'https://www.youtube.com/watch?v=...',
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
                  ...videoQualities.map((info) => ListTile(
                    title: Text('${info.videoQualityLabel} (${info.size.totalMegaBytes.toStringAsFixed(2)} MB)'),
                    trailing: ElevatedButton(
                      onPressed: permissionGranted ? () {
                        _downloadVideo(videoTitle, info);
                      } : null,
                      child: Text('Download MP4 ${info.videoQualityLabel}'),
                    ),
                  )).toList(),
                  Text('Audio Size: ${(audioSize / (1024 * 1024)).toStringAsFixed(2)} MB'),
                  ElevatedButton(
                    onPressed: permissionGranted ? () {
                      String videoUrl = _urlController.text;
                      _downloadAudio(videoUrl);
                    } : null,
                    child: Text('Download MP3'),
                  ),
                ],
              ) : Container(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> fetchVideoDetails(String url) async {
    var ytExplode = YoutubeExplode();
    try {
      var video = await ytExplode.videos.get(url);
      var manifest = await ytExplode.videos.streamsClient.getManifest(video.id);
      var audioStreamInfo = manifest.audioOnly.withHighestBitrate();

      // Print all available muxed stream qualities
      print('Available qualities:');
      for (var stream in manifest.muxed) {
        print('${stream.videoQualityLabel} - ${stream.videoResolution}');
      }

      List<MuxedStreamInfo> availableQualities = manifest.muxed.toList();
      availableQualities.sort((a, b) => b.videoQuality.index.compareTo(a.videoQuality.index));

      setState(() {
        videoTitle = video.title;
        videoThumbnail = video.thumbnails.highResUrl;
        audioSize = audioStreamInfo.size.totalBytes;
        videoQualities = availableQualities;
        showDetails = true;
      });
    } catch (e) {
      print('Error fetching video details: $e');
      // Show an error message to the user
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching video details. Please try again.')),
      );
    } finally {
      ytExplode.close();
    }
  }

  Future<void> _downloadVideo(String title, MuxedStreamInfo videoStreamInfo) async {
    var ytExplode = YoutubeExplode();
    try {
      var directory = await getExternalStorageDirectory();
      var safeDirPath = directory?.path ?? '/storage/emulated/0/Download';
      await Directory(safeDirPath).create(recursive: true);

      var sanitizedTitle = title.replaceAll(RegExp(r'[^\w\s-]'), '');
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
      var video = await ytExplode.videos.get(url);
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
