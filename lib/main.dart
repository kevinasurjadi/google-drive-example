import 'dart:developer';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lorem/flutter_lorem.dart';
import 'package:google_drive_example/constant.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Google Drive Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Flutter Google Drive Example'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late GoogleSignIn? _googleSignIn;
  late Dio _dio;
  late ValueNotifier<bool> _isUploading;
  late ValueNotifier<double> _uploadProgress;
  late ValueNotifier<bool> _isDownloading;
  late ValueNotifier<double> _downloadProgress;
  late ValueNotifier<String?> _fileId;

  GoogleSignInAccount? _account;

  @override
  void initState() {
    _googleSignIn = GoogleSignIn.standard(scopes: [
      kGoogleSignInDriveFileScope,
      kGoogleSignInDriveResourceScope,
    ]);
    _dio = Dio(
      BaseOptions(
        baseUrl: 'https://www.googleapis.com',
      ),
    );
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (requestOptions, handler) {
        log('${requestOptions.method} ${requestOptions.baseUrl}${requestOptions.path}');
        log('---');
        log('Query parameters: ${requestOptions.queryParameters}');
        log('Header: ${requestOptions.headers}');
        log('Body: ${requestOptions.data}');
        handler.next(requestOptions);
      },
      onResponse: (response, handler) {
        log('${response.statusCode} ${response.requestOptions.baseUrl}${response.requestOptions.path}');
        log('---');
        log('Body: ${response.data}');
        handler.next(response);
      },
      onError: (dioError, handler) {
        log('${dioError.type}');
        switch (dioError.type) {
          case DioErrorType.response:
            log('${dioError.response!.statusCode} ${dioError.response!.requestOptions.baseUrl}${dioError.response!.requestOptions.path}');
            log('---');
            log('Body: ${dioError.response!.data}');
            break;
          default:
        }
      },
    ));
    _isUploading = ValueNotifier(false);
    _uploadProgress = ValueNotifier(0);
    _isDownloading = ValueNotifier(false);
    _downloadProgress = ValueNotifier(0);
    _fileId = ValueNotifier(null);
    super.initState();
  }

  @override
  void dispose() {
    _signOut();
    _isUploading.dispose();
    _uploadProgress.dispose();
    _isDownloading.dispose();
    _downloadProgress.dispose();
    _fileId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () async {
                await _signIn(context);
                await _upload();
                await _signOut();
              },
              child: const Text('Upload file'),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: _isUploading,
              builder: (context, isUploading, _) => isUploading
                  ? ValueListenableBuilder<double>(
                      valueListenable: _uploadProgress,
                      builder: (context, progress, _) {
                        return Text('Uploading your data...${progress * 100}%');
                      },
                    )
                  : const SizedBox(),
            ),
            ValueListenableBuilder<String?>(
                valueListenable: _fileId,
                builder: (context, value, child) {
                  return ElevatedButton(
                    onPressed: () async {
                      if (value != null) {
                        await _signIn(context);
                        await _download(value);
                        await _signOut();
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('You must upload file first!'),
                          ),
                        );
                      }
                    },
                    child: const Text('Download file'),
                  );
                }),
          ],
        ),
      ),
    );
  }

  Future<void> _signIn(context) async {
    _account = await _googleSignIn!.signIn();
    if (_account == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign in Canceled or Failed')));
    } else {
      var authHeaders = await _account!.authHeaders;
      _dio.options.headers.addAll(authHeaders);
      setState(() {});
    }
  }

  Future<Response> _createFolder(String name) async {
    return await _dio.post(
      '/drive/v3/files',
      data: {
        'name': name,
        'mimeType': 'application/vnd.google-apps.folder',
      },
    );
  }

  Future<void> _upload() async {
    _isUploading.value = true;
    var createFolderResult = await _createFolder('GoogleDriveExampleFolder');
    log('$createFolderResult');

    var metaResult =
        await _dio.post('/upload/drive/v3/files', queryParameters: {
      'uploadType': 'resumable',
    }, data: {
      'parents': [createFolderResult.data['id']],
      'name': '${const Uuid().v4()}.txt',
      'mimeType': 'text/plain',
    });

    var fileToUpload = lorem();
    var uploadUrl = metaResult.headers.value('Location');
    var response = await _dio.put(
      uploadUrl!,
      options: Options(headers: {'content-length': fileToUpload.length}),
      data: fileToUpload,
      onSendProgress: (count, total) {
        log('count: $count, total: $total');
        _uploadProgress.value = count / total;
        if (count / total == 1) {
          _isUploading.value = false;
        }
      },
    );
    _fileId.value = response.data['id'];
  }

  Future<void> _download(String fileId) async {
    _isDownloading.value = true;
    var getFileResult = await _dio.get(
      '/drive/v3/files/$fileId',
      queryParameters: {
        'fields':
            'id,name,kind,mimeType,description,properties,appProperties,spaces,createdTime,modifiedTime,size'
      },
    );
    log('$getFileResult');

    String path = join((await getTemporaryDirectory()).path, 'sbcrypto.txt');
    await _dio.download(
      '/drive/v3/files/$fileId',
      path,
      queryParameters: {'alt': 'media'},
      options: Options(headers: {HttpHeaders.acceptEncodingHeader: '*'}),
      onReceiveProgress: (count, total) {
        log('count: $count, total: $total');
        _downloadProgress.value = count / total;
        if (count / total == 1) {
          _isDownloading.value = false;
        }
      },
    );
  }

  Future<void> _signOut() async {
    await _googleSignIn?.disconnect();
    await _googleSignIn?.signOut();
    _dio.options.headers = {};
    setState(() {
      _account = null;
    });
  }
}
