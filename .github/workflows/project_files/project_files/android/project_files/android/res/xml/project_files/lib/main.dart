import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:open_filex/open_filex.dart';

void main() {
  runApp(const DownloaderApp());
}

class DownloaderApp extends StatelessWidget {
  const DownloaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Downloader',
      theme: ThemeData(primarySwatch: Colors.deepPurple),
      home: const DownloaderHomePage(),
    );
  }
}

class DownloaderHomePage extends StatefulWidget {
  const DownloaderHomePage({super.key});

  @override
  State<DownloaderHomePage> createState() => _DownloaderHomePageState();
}

class _DownloaderHomePageState extends State<DownloaderHomePage> {
  final TextEditingController _urlController = TextEditingController();
  final List<_DownloadTask> _downloads = [];
  String _backendUrl = "";
  late SharedPreferences _prefs;

  @override
  void initState() {
    super.initState();
    _initPrefs();
    _listenForSharedLinks();
  }

  void _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    setState(() {
      _backendUrl = _prefs.getString('backend_url') ?? "";
    });
  }

  void _listenForSharedLinks() {
    ReceiveSharingIntent.getTextStream().listen((String? value) {
      if (value != null && value.isNotEmpty) {
        setState(() {
          _urlController.text = value;
        });
      }
    });
    ReceiveSharingIntent.getInitialText().then((String? value) {
      if (value != null && value.isNotEmpty) {
        setState(() {
          _urlController.text = value;
        });
      }
    });
  }

  Future<void> _startDownload(String url) async {
    if (_backendUrl.isEmpty) {
      _showError("Please set your backend URL in settings.");
      return;
    }
    if (url.isEmpty) {
      _showError("Please paste a video link.");
      return;
    }
    var dir = await getExternalStorageDirectory();
    if (dir == null) {
      _showError("Could not get storage directory.");
      return;
    }
    await Permission.storage.request();
    var task = _DownloadTask(url: url, progress: 0);
    setState(() {
      _downloads.add(task);
    });
    try {
      var infoRes = await http.get(Uri.parse("$_backendUrl/info?url=$url"));
      String? thumb;
      if (infoRes.statusCode == 200) {
        var info = jsonDecode(infoRes.body);
        thumb = info['thumbnail'];
      }
      task.thumbnailUrl = thumb;
      var res = await http.post(Uri.parse("$_backendUrl/download"), body: {"url": url});
      if (res.statusCode == 200) {
        String filePath = "${dir.path}/${DateTime.now().millisecondsSinceEpoch}.mp4";
        File file = File(filePath);
        await file.writeAsBytes(res.bodyBytes);
        task.localPath = filePath;
        task.progress = 100;
        setState(() {});
      } else {
        _showError("Download failed.");
      }
    } catch (e) {
      _showError("Error: $e");
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _openSettings() {
    TextEditingController ctrl = TextEditingController(text: _backendUrl);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Backend URL"),
          content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: "http://IP:5000")),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            TextButton(
              onPressed: () {
                setState(() {
                  _backendUrl = ctrl.text.trim();
                  _prefs.setString('backend_url', _backendUrl);
                });
                Navigator.pop(ctx);
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTaskTile(_DownloadTask task) {
    return ListTile(
      leading: task.thumbnailUrl != null
          ? Image.network(task.thumbnailUrl!, width: 64, height: 64, fit: BoxFit.cover)
          : const Icon(Icons.video_file),
      title: Text(task.url),
      subtitle: task.progress < 100
          ? LinearProgressIndicator(value: task.progress / 100)
          : const Text("Downloaded"),
      trailing: task.localPath != null
          ? IconButton(
              icon: const Icon(Icons.play_arrow),
              onPressed: () {
                OpenFilex.open(task.localPath!);
              },
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Video Downloader"),
        actions: [
          IconButton(icon: const Icon(Icons.settings), onPressed: _openSettings),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(child: TextField(controller: _urlController, decoration: const InputDecoration(hintText: "Paste link here"))),
                IconButton(icon: const Icon(Icons.download), onPressed: () => _startDownload(_urlController.text)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: _downloads.map(_buildTaskTile).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadTask {
  final String url;
  String? thumbnailUrl;
  String? localPath;
  int progress;

  _DownloadTask({required this.url, required this.progress});
}
