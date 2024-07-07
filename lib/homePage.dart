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
  bool isLoading = false;
  String videoTitle = '';
  String videoThumbnail = '';
  int audioSize = 0;
  List<MuxedStreamInfo> muxedStreams = [];
  AudioOnlyStreamInfo? audioStreamInfo;
  double downloadProgress = 0.0;

  late double width, height;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    getStoragePermission();
    width = MediaQuery.of(context).size.width;
    height = MediaQuery.of(context).size.height;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('YouTube Downloader'),
      ),
      body: Stack(
        children: [
          Center(
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
                        hintText: 'Enter YouTube URL',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10.0),
                        ),
                        filled: true,
                        fillColor: Colors.grey[200],
                        contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                      ),
                    ),
                  ),
                  SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: permissionGranted && !isLoading ? () async {
                      String videoUrl = _urlController.text; // Get user input
                      await fetchVideoDetails(videoUrl);
                    } : null,
                    child: Text('Download Video'),
                  ),
                ],
              ),
            ),
          ),
          if (isLoading)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 10),
                    Text('Loading...', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
        ],
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
    setState(() {
      isLoading = true;
    });

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
        muxedStreams = manifest.muxed.toList();
        isLoading = false;
        showVideoDetails(context);
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      print('Error: $e');
    } finally {
      ytExplode.close();
    }
  }

  void showVideoDetails(BuildContext context) {
    width = MediaQuery.of(context).size.width;
    height = MediaQuery.of(context).size.height;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black.withOpacity(0.7), // Add a dark background
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Stack(
              children: [
                DraggableScrollableSheet(
                  initialChildSize: 0.8,
                  minChildSize: 0.4,
                  maxChildSize: 0.8,
                  builder: (context, scrollController) {
                    return SingleChildScrollView(
                      controller: scrollController,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Image.network(videoThumbnail),
                            Text('Title: $videoTitle', style: TextStyle(color: Colors.white)),
                            ListTile(
                              title: Text('Audio (${(audioSize / (1024 * 1024)).toStringAsFixed(2)} MB )', style: TextStyle(color: Colors.white)),
                              trailing: ElevatedButton(
                                onPressed: permissionGranted ? () {
                                  String videoUrl = _urlController.text;
                                  _downloadAudio(videoUrl, setModalState);
                                } : null,
                                child: Text('Download MP3'),
                              ),
                            ),
                            SizedBox(
                              height: 200,
                              child: ListView(
                                shrinkWrap: true,
                                children: muxedStreams.map((info) => ListTile(
                                  title: Text('${info.videoQualityLabel} (${info.size.totalMegaBytes.toStringAsFixed(2)} MB)', style: TextStyle(color: Colors.white)),
                                  trailing: ElevatedButton(
                                    onPressed: permissionGranted ? () {
                                      String videoUrl = _urlController.text;
                                      _downloadVideo(videoUrl, info, setModalState);
                                    } : null,
                                    child: Text('Download  ${info.videoQualityLabel}'),
                                  ),
                                )).toList(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                if (isLoading)
                  Center(
                    child: Container(
                      width: width,
                      color: Colors.black.withOpacity(0.7),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 10),
                          Text('Downloading...', style: TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }


  Future<String> _downloadVideo(String url, MuxedStreamInfo videoStreamInfo, StateSetter setModalState) async {
    var ytExplode = YoutubeExplode();
    try {
      setModalState(() {
        isLoading = true; // Show progress bar
      });

      String? videoId = extractVideoId(url);
      var video = await ytExplode.videos.get(videoId);

      var sanitizedTitle = video.title.replaceAll(RegExp(r'[^\w\s-]'), ''); // Remove invalid characters
      var videoStream = ytExplode.videos.streamsClient.get(videoStreamInfo);
      var videoFileName = '$sanitizedTitle ${videoStreamInfo.videoQualityLabel}.mp4';

      var directory = await getExternalStorageDirectory();
      if (directory == null) {
        throw Exception("Could not get the external storage directory");
      }
      var downloadsDirectory = Directory('/storage/emulated/0/Download');
      if (!await downloadsDirectory.exists()) {
        await downloadsDirectory.create(recursive: true);
      }
      var videoFilePath = '${downloadsDirectory.path}/$videoFileName';

      // Update: track download progress
      var file = await saveStreamToFileWithProgress(videoStream, videoFilePath, setModalState);

      setModalState(() {
        isLoading = false; // Hide progress bar
      });
      showDownloadCompleteDialog('Video downloaded');
      return file.path; // Return the file path
    } catch (e) {
      print('Error in _downloadVideo: $e');
      rethrow; // Rethrow to handle it in the caller function
    } finally {
      ytExplode.close();
    }
  }

  Future<String> _downloadAudio(String url, StateSetter setModalState) async {
    var ytExplode = YoutubeExplode();
    try {
      setModalState(() {
        isLoading = true; // Show progress bar
      });

      String videoId = extractVideoId(url);
      var video = await ytExplode.videos.get(videoId);
      var manifest = await ytExplode.videos.streamsClient.getManifest(video.id);
      var audioStreamInfo = manifest.audioOnly.first;

      var sanitizedTitle = video.title.replaceAll(RegExp(r'[^\w\s-]'), ''); // Remove invalid characters
      var audioStream = ytExplode.videos.streamsClient.get(audioStreamInfo);
      var audioFileName = '$sanitizedTitle.mp3';

      var directory = await getExternalStorageDirectory();
      if (directory == null) {
        throw Exception("Could not get the external storage directory");
      }
      var downloadsDirectory = Directory('/storage/emulated/0/Download');
      if (!await downloadsDirectory.exists()) {
        await downloadsDirectory.create(recursive: true);
      }
      var audioFilePath = '${downloadsDirectory.path}/$audioFileName';

      // Update: track download progress
      var file = await saveStreamToFileWithProgress(audioStream, audioFilePath, setModalState);

      setModalState(() {
        isLoading = false; // Hide progress bar
      });
      showDownloadCompleteDialog('Audio downloaded');
      return file.path; // Return the file path
    } catch (e) {
      print('Error in _downloadAudio: $e');
      rethrow; // Rethrow to handle it in the caller function
    } finally {
      ytExplode.close();
    }
  }


  Future<File> saveStreamToFileWithProgress(Stream<List<int>> stream, String filePath, StateSetter setModalState) async {
    var file = File(filePath);
    var sink = file.openWrite();

    var totalBytes = 0;
    var contentLength = 0;

    // Buffer the stream data to a list to calculate total length
    List<int> buffer = [];
    await for (var data in stream) {
      buffer.addAll(data);
      contentLength += data.length;
    }

    // Create a new stream from the buffered data
    Stream<List<int>> newStream = Stream.fromIterable([buffer]);

    // Write the stream to file and update progress
    await for (var data in newStream) {
      totalBytes += data.length;
      sink.add(data);
      setModalState(() {
        downloadProgress = contentLength > 0 ? totalBytes / contentLength : 0.0;
      });
      print('Download progress: ${totalBytes} bytes');
    }

    await sink.close();
    return file;
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

  void showDownloadCompleteDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Download Complete'),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text('OK'),
          ),
        ],
      ),
    );
  }
}
