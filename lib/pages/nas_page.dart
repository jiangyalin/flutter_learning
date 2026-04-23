import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/nas/data/nas_client.dart';
import '../features/nas/models/nas_models.dart';

class SynologyNasClient implements NasClient {
  static const String sharedRootPath = '@shared_root';
  static const String _prefsKeyResolvedBaseUri = 'nas.resolved_base_uri';
  static const String _prefsKeySid = 'nas.sid';
  static const String _prefsKeySynoToken = 'nas.syno_token';
  static const String _prefsKeyDid = 'nas.did';
  static const String _prefsKeyCookies = 'nas.cookies';
  static const String _prefsKeyLastUsername = 'nas.last_username';
  static const String _prefsKeyNetworkFingerprint = 'nas.network_fingerprint';

  SynologyNasClient({
    HttpClient? httpClient,
    Uri? quickConnectUri,
    Uri? quickConnectApiUri,
  })  : _httpClient = httpClient ??
            (HttpClient()
              ..connectionTimeout = const Duration(seconds: 10)
              ..badCertificateCallback =
                  (X509Certificate _, String __, int ___) => true),
        _quickConnectUri = quickConnectUri ??
            Uri.parse('https://jyl18725944157.cn6.quickconnect.cn'),
        _quickConnectApiUri = quickConnectApiUri ??
            Uri.parse('https://global.quickconnect.to/Serv.php');

  final HttpClient _httpClient;
  final Uri _quickConnectUri;
  final Uri _quickConnectApiUri;
  final Map<String, Cookie> _cookies = {
    'type': Cookie('type', 'tunnel'),
  };

  Uri? _resolvedBaseUri;
  String? _sid;
  String? _synoToken;
  String? _did;
  String? _lastUsername;
  String? _lastPassword;
  String? _lastNetworkFingerprint;
  String? _downloadStationSid;
  String? _fileStationSid;
  String? _downloadTaskApiPath;
  int? _downloadTaskApiVersion;
  String? _createFolderApiPath;
  int? _createFolderApiVersion;
  Future<void>? _restoreFuture;
  bool _prefsUnavailable = false;
  void Function(String message)? _progressListener;

  @override
  void setProgressListener(void Function(String message)? listener) {
    _progressListener = listener;
  }

  void _reportProgress(String message) {
    debugPrint('NAS progress -> $message');
    _progressListener?.call(message);
  }

  @override
  Future<List<NasFileEntry>> login({
    required String username,
    required String password,
    required String path,
  }) async {
    _reportProgress('正在检查本地登录状态');
    await _restorePersistedSession();
    _lastUsername = username;
    _lastPassword = password;

    if (_hasSession) {
      try {
        _reportProgress('检测到可复用会话，正在验证');
        return await listDirectory(path: path);
      } catch (_) {
        await _clearSession(keepCredentials: true);
      }
    }

    _reportProgress('正在登录群晖');
    await _authenticate(
      username: username,
      password: password,
      forceResolveBaseUri: _resolvedBaseUri == null,
    );
    return listDirectory(path: path);
  }

  @override
  Future<List<NasFileEntry>?> restoreSession({required String path}) async {
    _reportProgress('正在恢复本地会话');
    await _restorePersistedSession();
    if (!_hasSession) {
      return null;
    }

    try {
      return await listDirectory(path: path);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<NasFileEntry>> listDirectory({required String path}) async {
    await _restorePersistedSession();
    if (_synoToken == null) {
      throw Exception('尚未登录');
    }

    if (path == sharedRootPath) {
      _reportProgress('正在加载共享目录');
      return _extractSharedFolderEntries(
        await _listShareRequest(),
      );
    }

    try {
      _reportProgress('正在加载文件目录');
      return await _listDirectoryWithRetry(path: path);
    } on SynologyApiException catch (error) {
      if (error.code == 408 && path == '/home/Drive') {
        debugPrint(
          'NAS list fallback -> /home/Drive not found, loading shared folders',
        );
        return _extractSharedFolderEntries(
          await _listShareRequest(),
        );
      }
      rethrow;
    }
  }

  @override
  Future<List<NasDownloadTask>> listDownloadTasks() async {
    _reportProgress('正在加载下载任务');
    await _restorePersistedSession();

    final apiInfo = await _getDownloadTaskApiInfo();
    return _listDownloadTasksWithRetry(
      apiInfo: apiInfo,
      allowReauth: true,
    );
  }

  @override
  Future<void> createFolder({
    required String parentPath,
    required String folderName,
  }) async {
    _reportProgress('正在创建文件夹');
    await _restorePersistedSession();
    if (_synoToken == null || _synoToken!.isEmpty) {
      throw const SynologyApiException('尚未登录');
    }

    final sanitizedParentPath = _normalizeParentPath(parentPath);
    final sanitizedFolderName = folderName.trim();
    if (sanitizedFolderName.isEmpty) {
      throw const SynologyApiException('文件夹名称不能为空');
    }
    if (sanitizedFolderName == '.' || sanitizedFolderName == '..') {
      throw const SynologyApiException('文件夹名称不合法');
    }
    if (sanitizedFolderName.contains('/')) {
      throw const SynologyApiException('文件夹名称不能包含 /');
    }

    final targetPath = sanitizedParentPath == '/'
        ? '/$sanitizedFolderName'
        : '$sanitizedParentPath/$sanitizedFolderName';
    if (await _checkFolderExists(targetPath)) {
      throw const SynologyApiException('文件夹已存在', code: 409);
    }

    try {
      await _createFolder(
        parentPath: sanitizedParentPath,
        folderName: sanitizedFolderName,
      );
    } on SynologyApiException catch (error) {
      if (<int>{101, 119}.contains(error.code)) {
        final exists = await _waitAndCheckFolderExists(targetPath);
        if (exists) {
          return;
        }
      }
      rethrow;
    }

    final created = await _waitAndCheckFolderExists(targetPath);
    if (!created) {
      throw SynologyApiException('创建文件夹后仍不可访问：$targetPath');
    }
  }

  @override
  Future<void> createDownloadTask({
    required String destination,
    required String url,
  }) async {
    _reportProgress('正在创建下载任务');
    await _restorePersistedSession();

    final normalizedDestination = _normalizeDownloadDestination(destination);
    final ensuredAbsoluteDestination = await _ensureDownloadDestinationFolder(
      normalizedDestination.absolutePath,
    );
    final usableDownloadStationDestination =
        ensuredAbsoluteDestination.startsWith('/')
            ? ensuredAbsoluteDestination.substring(1)
            : ensuredAbsoluteDestination;

    final apiInfo = await _getDownloadTaskApiInfo();
    await _createDownloadTaskWithRetry(
      apiInfo: apiInfo,
      destination: usableDownloadStationDestination,
      fallbackDestination: ensuredAbsoluteDestination,
      url: url,
      allowReauth: true,
    );
  }

  @override
  Future<void> deleteDownloadTask({required String taskId}) async {
    _reportProgress('正在删除下载任务');
    await _restorePersistedSession();

    final apiInfo = await _getDownloadTaskApiInfo();
    await _deleteDownloadTaskWithRetry(
      apiInfo: apiInfo,
      taskId: taskId,
      allowReauth: true,
    );
  }

  Future<List<NasFileEntry>> _listDirectoryWithRetry({
    required String path,
    bool allowReauth = true,
  }) async {
    try {
      final entries = _extractFileEntries(
        await _listRequest(folderPath: path),
      );
      await _persistSession();
      return entries;
    } on SynologyApiException catch (error) {
      if (allowReauth && _isSessionExpired(error) && _hasSavedCredentials) {
        debugPrint('NAS session expired, re-authenticating');
        await _clearSession(keepCredentials: true);
        await _authenticate(
          username: _lastUsername!,
          password: _lastPassword!,
          forceResolveBaseUri: false,
        );
        return _listDirectoryWithRetry(path: path, allowReauth: false);
      }
      rethrow;
    }
  }

  Future<List<NasDownloadTask>> _listDownloadTasksWithRetry({
    required ({String path, int version}) apiInfo,
    required bool allowReauth,
  }) async {
    try {
      final activeSid = _downloadStationSid ?? _sid;
      if (activeSid == null || activeSid.isEmpty) {
        throw const SynologyApiException('尚未登录下载管理模块');
      }
      final body = await _sendRequest(
        uri: _buildWebApiUri(apiInfo.path),
        queryParameters: {
          'api': 'SYNO.DownloadStation.Task',
          'version': apiInfo.version.toString(),
          'method': 'list',
          'additional': 'detail,transfer',
          'offset': '0',
          'limit': '1000',
          '_sid': activeSid,
        },
      );
      final success = body['success'] == true;
      if (!success) {
        throw _parseApiError(body, fallbackMessage: '下载任务加载失败');
      }
      final data = body['data'];
      if (data is! Map<String, dynamic>) {
        return const [];
      }
      final tasks = data['tasks'];
      if (tasks is! List) {
        return const [];
      }
      return tasks
          .whereType<Map<String, dynamic>>()
          .map(NasDownloadTask.fromJson)
          .toList();
    } on SynologyApiException catch (error) {
      final needsDedicatedSession = _downloadStationSid == null &&
          <int>{101, 102, 103, 104}.contains(error.code);
      if (allowReauth &&
          (_isSessionExpired(error) || needsDedicatedSession) &&
          _hasSavedCredentials) {
        debugPrint(
            'NAS Download Station session unavailable, re-authenticating');
        _downloadStationSid = null;
        await _ensureDownloadStationSession(forceRelogin: true);
        return _listDownloadTasksWithRetry(
          apiInfo: apiInfo,
          allowReauth: false,
        );
      }
      rethrow;
    }
  }

  Future<void> _createDownloadTaskWithRetry({
    required ({String path, int version}) apiInfo,
    required String destination,
    required String? fallbackDestination,
    required String url,
    required bool allowReauth,
  }) async {
    try {
      final activeSid = _downloadStationSid ?? _sid;
      if (activeSid == null || activeSid.isEmpty) {
        throw const SynologyApiException('尚未登录下载管理模块');
      }
      final body = await _sendPostRequest(
        uri: _buildWebApiUri(apiInfo.path),
        formFields: {
          'api': 'SYNO.DownloadStation.Task',
          'version': apiInfo.version.toString(),
          'method': 'create',
          'destination': destination,
          'uri': url,
          '_sid': activeSid,
        },
      );
      final success = body['success'] == true;
      if (!success) {
        throw _parseApiError(body, fallbackMessage: '下载任务创建失败');
      }
    } on SynologyApiException catch (error) {
      if (error.code == 403 &&
          fallbackDestination != null &&
          fallbackDestination != destination) {
        debugPrint(
          'NAS create task destination denied, retrying with $fallbackDestination',
        );
        _reportProgress('正在使用绝对路径重试下载任务');
        return _createDownloadTaskWithRetry(
          apiInfo: apiInfo,
          destination: fallbackDestination,
          fallbackDestination: null,
          url: url,
          allowReauth: allowReauth,
        );
      }

      final needsDedicatedSession = _downloadStationSid == null &&
          <int>{101, 102, 103, 104}.contains(error.code);
      if (allowReauth &&
          (_isSessionExpired(error) || needsDedicatedSession) &&
          _hasSavedCredentials) {
        debugPrint(
            'NAS Download Station session unavailable during create, re-authenticating');
        _downloadStationSid = null;
        await _ensureDownloadStationSession(forceRelogin: true);
        return _createDownloadTaskWithRetry(
          apiInfo: apiInfo,
          destination: destination,
          fallbackDestination: fallbackDestination,
          url: url,
          allowReauth: false,
        );
      }
      rethrow;
    }
  }

  Future<void> _deleteDownloadTaskWithRetry({
    required ({String path, int version}) apiInfo,
    required String taskId,
    required bool allowReauth,
  }) async {
    try {
      final activeSid = _downloadStationSid ?? _sid;
      if (activeSid == null || activeSid.isEmpty) {
        throw const SynologyApiException('尚未登录下载管理模块');
      }
      final body = await _sendPostRequest(
        uri: _buildWebApiUri(apiInfo.path),
        formFields: {
          'api': 'SYNO.DownloadStation.Task',
          'version': apiInfo.version.toString(),
          'method': 'delete',
          'id': taskId,
          'force_complete': 'false',
          '_sid': activeSid,
        },
      );
      final success = body['success'] == true;
      if (!success) {
        throw _parseApiError(body, fallbackMessage: '下载任务删除失败');
      }
    } on SynologyApiException catch (error) {
      final needsDedicatedSession = _downloadStationSid == null &&
          <int>{101, 102, 103, 104, 105}.contains(error.code);
      if (allowReauth &&
          (_isSessionExpired(error) || needsDedicatedSession) &&
          _hasSavedCredentials) {
        debugPrint(
            'NAS Download Station session unavailable during delete, re-authenticating');
        _downloadStationSid = null;
        await _ensureDownloadStationSession(forceRelogin: true);
        return _deleteDownloadTaskWithRetry(
          apiInfo: apiInfo,
          taskId: taskId,
          allowReauth: false,
        );
      }
      rethrow;
    }
  }

  ({String absolutePath, String downloadStationPath})
      _normalizeDownloadDestination(
    String destination,
  ) {
    final parts = destination
        .trim()
        .split('/')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      throw const SynologyApiException('目的地文件夹地址不能为空');
    }

    final normalized = parts.join('/');
    return (
      absolutePath: '/$normalized',
      downloadStationPath: normalized,
    );
  }

  String _normalizeParentPath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty ||
        trimmed == SynologyNasClient.sharedRootPath ||
        trimmed == '@shared_root') {
      throw const SynologyApiException('请先进入具体共享目录后再创建文件夹');
    }
    if (trimmed == '/') {
      return '/';
    }
    final segments = trimmed
        .split('/')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (segments.isEmpty) {
      throw const SynologyApiException('父级目录无效');
    }
    return '/${segments.join('/')}';
  }

  Future<String> _ensureDownloadDestinationFolder(String absolutePath) async {
    final parts = absolutePath
        .trim()
        .split('/')
        .where((part) => part.trim().isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      throw const SynologyApiException('目的地文件夹地址不能为空');
    }

    if (_synoToken == null || _synoToken!.isEmpty) {
      throw const SynologyApiException('尚未获取 Synology Token');
    }

    _reportProgress('正在确认目的地文件夹');
    var currentPath = '';
    for (final segment in parts) {
      final nextPath = '$currentPath/$segment';
      final exists = await _checkFolderExists(nextPath);
      if (exists) {
        currentPath = nextPath;
        continue;
      }

      final parentPath = currentPath.isEmpty ? '/' : currentPath;
      try {
        await _createFolder(parentPath: parentPath, folderName: segment);
      } on SynologyApiException catch (error) {
        if (<int>{101, 119}.contains(error.code)) {
          final eventuallyExists = await _waitAndCheckChildFolderExists(
            parentPath: parentPath,
            folderName: segment,
          );
          if (eventuallyExists) {
            currentPath = nextPath;
            continue;
          }
        }
        throw SynologyApiException(
          '无法创建目标目录：$nextPath，请检查 NAS 写入权限或路径合法性',
          code: error.code,
        );
      }

      final created = await _waitAndCheckFolderExists(nextPath);
      if (!created) {
        throw SynologyApiException('目标目录创建后仍不可访问：$nextPath');
      }
      currentPath = nextPath;
    }
    return currentPath.isEmpty ? absolutePath : currentPath;
  }

  Future<bool> _waitAndCheckFolderExists(
    String absolutePath, {
    int retries = 3,
    Duration interval = const Duration(milliseconds: 250),
  }) async {
    for (var i = 0; i < retries; i++) {
      final exists = await _checkFolderExists(absolutePath);
      if (exists) {
        return true;
      }
      if (i < retries - 1) {
        await Future<void>.delayed(interval);
      }
    }
    return false;
  }

  Future<bool> _waitAndCheckChildFolderExists({
    required String parentPath,
    required String folderName,
    int retries = 3,
    Duration interval = const Duration(milliseconds: 250),
  }) async {
    for (var i = 0; i < retries; i++) {
      try {
        final body = await _listRequest(folderPath: parentPath);
        final data = body['data'];
        if (data is Map<String, dynamic>) {
          final files = data['files'];
          if (files is List) {
            final found = files.whereType<Map<String, dynamic>>().any((item) {
              return item['isdir'] == true &&
                  item['name']?.toString() == folderName;
            });
            if (found) {
              return true;
            }
          }
        }
      } on SynologyApiException {
        // Ignore and retry.
      }
      if (i < retries - 1) {
        await Future<void>.delayed(interval);
      }
    }
    return false;
  }

  bool _isFolderAlreadyExistsError(SynologyApiException error) {
    return <int>{407, 409, 414, 418}.contains(error.code);
  }

  bool _shouldProbeExistingFolder(SynologyApiException error) {
    // Keep this conservative: only "already exists"-like codes should be treated
    // as soft-success. 119 is often session/validation related and should not be
    // swallowed.
    return false;
  }

  Future<bool> _checkFolderExists(String absolutePath) async {
    _reportProgress('正在检查目的地文件夹是否已存在');
    try {
      final body = await _listRequest(folderPath: absolutePath);
      return body['success'] == true;
    } on SynologyApiException catch (error) {
      // 408 is commonly returned when folder path does not exist.
      if (error.code == 408) {
        return false;
      }
      rethrow;
    }
  }

  Future<void> _createFolder({
    required String parentPath,
    required String folderName,
  }) async {
    final apiInfo = await _getCreateFolderApiInfo();
    final uri = _buildWebApiUri(apiInfo.path);
    final preferJson = apiInfo.requestFormat?.toUpperCase() == 'JSON';
    SynologyApiException? lastError;
    await _ensureFileStationSession();
    final sid = _fileStationSid ?? _sid;

    Future<bool> tryBody(Map<String, dynamic> body) async {
      if (body['success'] == true) {
        return true;
      }
      final error = _parseApiError(body, fallbackMessage: '目的地文件夹创建失败');
      if (_isFolderAlreadyExistsError(error) ||
          _shouldProbeExistingFolder(error)) {
        return true;
      }
      lastError = error;
      return false;
    }

    Future<bool> tryJsonAttempts(int version) async {
      final attempts = <Map<String, dynamic>>[
        {
          'api': 'SYNO.FileStation.CreateFolder',
          'version': version,
          'method': 'create',
          'folder_path': parentPath,
          'name': folderName,
          'force_parent': false,
          if (_synoToken != null && _synoToken!.isNotEmpty)
            'SynoToken': _synoToken!,
        },
        {
          'api': 'SYNO.FileStation.CreateFolder',
          'version': version,
          'method': 'create',
          'folder_path': parentPath,
          'name': folderName,
          'force_parent': false,
          if (sid != null && sid.isNotEmpty) '_sid': sid,
          if (_synoToken != null && _synoToken!.isNotEmpty)
            'SynoToken': _synoToken!,
        },
        {
          'api': 'SYNO.FileStation.CreateFolder',
          'version': version,
          'method': 'create',
          'folder_path': parentPath,
          'name': folderName,
          'force_parent': 'false',
          'SynoToken': _synoToken!,
        },
        {
          'api': 'SYNO.FileStation.CreateFolder',
          'version': version.toString(),
          'method': 'create',
          'folder_path': parentPath,
          'name': [folderName],
          'force_parent': 'true',
          if (sid != null && sid.isNotEmpty) '_sid': sid,
        },
        {
          'api': 'SYNO.FileStation.CreateFolder',
          'version': version,
          'method': 'create',
          'folder_path': [parentPath],
          'name': [folderName],
          'force_parent': 'false',
          if (sid != null && sid.isNotEmpty) '_sid': sid,
          if (_synoToken != null && _synoToken!.isNotEmpty)
            'SynoToken': _synoToken!,
        },
        {
          'api': 'SYNO.FileStation.CreateFolder',
          'version': version,
          'method': 'create',
          'folder_path': [parentPath],
          'name': [folderName],
          'force_parent': 'true',
          'SynoToken': _synoToken!,
        },
        {
          'api': 'SYNO.FileStation.CreateFolder',
          'version': version.toString(),
          'method': 'create',
          'folder_path': [parentPath],
          'name': folderName,
          'force_parent': 'true',
          if (sid != null && sid.isNotEmpty) '_sid': sid,
          if (_synoToken != null && _synoToken!.isNotEmpty)
            'SynoToken': _synoToken!,
        },
      ];

      for (final attempt in attempts) {
        final jsonBody = await _sendPostJsonRequest(
          uri: uri,
          jsonBody: attempt,
        );
        if (await tryBody(jsonBody)) {
          return true;
        }
      }
      return false;
    }

    List<Map<String, String>> buildFormAttempts(int version) {
      return <Map<String, String>>[
        {
          'folder_path': parentPath,
          'name': folderName,
          'version': version.toString(),
          'force_parent': 'false',
          if (_synoToken != null && _synoToken!.isNotEmpty)
            'SynoToken': _synoToken!,
        },
        {
          'folder_path': parentPath,
          'name': folderName,
          'version': version.toString(),
          'force_parent': 'false',
          if (sid != null && sid.isNotEmpty) '_sid': sid,
          if (_synoToken != null && _synoToken!.isNotEmpty)
            'SynoToken': _synoToken!,
        },
        {
          'folder_path': parentPath,
          'name': folderName,
          'version': version.toString(),
          'force_parent': 'true',
          if (sid != null && sid.isNotEmpty) '_sid': sid,
          if (_synoToken != null && _synoToken!.isNotEmpty)
            'SynoToken': _synoToken!,
        },
        // Synology workaround: quoted raw values for some DSM versions/relay paths.
        {
          'folder_path': '"$parentPath"',
          'name': '"$folderName"',
          'version': version.toString(),
          'force_parent': 'false',
          if (sid != null && sid.isNotEmpty) '_sid': sid,
          if (_synoToken != null && _synoToken!.isNotEmpty)
            'SynoToken': _synoToken!,
        },
        {
          'folder_path': jsonEncode([parentPath]),
          'name': jsonEncode([folderName]),
          'version': version.toString(),
          'force_parent': 'false',
          if (sid != null && sid.isNotEmpty) '_sid': sid,
          if (_synoToken != null && _synoToken!.isNotEmpty)
            'SynoToken': _synoToken!,
        },
        {
          'folder_path': jsonEncode([parentPath]),
          'name': jsonEncode([folderName]),
          'version': version.toString(),
          'force_parent': 'true',
          if (sid != null && sid.isNotEmpty) '_sid': sid,
          if (_synoToken != null && _synoToken!.isNotEmpty)
            'SynoToken': _synoToken!,
        },
      ];
    }

    Future<bool> tryFormAttempts(int version) async {
      for (final attempt in buildFormAttempts(version)) {
        final formBody = await _sendPostRequest(
          uri: uri,
          formFields: {
            'api': 'SYNO.FileStation.CreateFolder',
            'version': attempt['version']!,
            'method': 'create',
            'folder_path': attempt['folder_path']!,
            'name': attempt['name']!,
            'force_parent': attempt['force_parent']!,
            if (attempt.containsKey('_sid')) '_sid': attempt['_sid']!,
            if (attempt.containsKey('SynoToken'))
              'SynoToken': attempt['SynoToken']!,
          },
        );
        if (await tryBody(formBody)) {
          return true;
        }
      }
      return false;
    }

    final versionsToTry = <int>{apiInfo.version, 1};
    for (final version in versionsToTry) {
      if (preferJson) {
        if (await tryJsonAttempts(version)) return;
        if (await tryFormAttempts(version)) return;
      } else {
        if (await tryFormAttempts(version)) return;
        if (await tryJsonAttempts(version)) return;
      }
    }

    if (lastError?.code == 119) {
      // Session invalid: refresh a dedicated FileStation sid then retry once.
      await _ensureFileStationSession(forceRelogin: true);
      final refreshedSid = _fileStationSid ?? _sid;
      for (final version in versionsToTry) {
        final retryFormBody = await _sendPostRequest(
          uri: uri,
          formFields: {
            'api': 'SYNO.FileStation.CreateFolder',
            'version': version.toString(),
            'method': 'create',
            'folder_path': parentPath,
            'name': folderName,
            'force_parent': 'false',
            if (refreshedSid != null && refreshedSid.isNotEmpty)
              '_sid': refreshedSid,
            if (_synoToken != null && _synoToken!.isNotEmpty)
              'SynoToken': _synoToken!,
          },
        );
        if (await tryBody(retryFormBody)) {
          return;
        }
      }
    }

    throw lastError ?? const SynologyApiException('目的地文件夹创建失败');
  }

  Future<({String path, int version, String? requestFormat})>
      _getCreateFolderApiInfo() async {
    if (_createFolderApiPath != null && _createFolderApiVersion != null) {
      return (
        path: _createFolderApiPath!,
        version: _createFolderApiVersion!,
        requestFormat: null,
      );
    }

    final body = await _sendRequest(
      uri: _buildWebApiUri('query.cgi'),
      queryParameters: {
        'api': 'SYNO.API.Info',
        'version': '1',
        'method': 'query',
        'query': 'SYNO.FileStation.CreateFolder',
      },
    );
    final success = body['success'] == true;
    if (!success) {
      // Fallback to conservative default used previously.
      _createFolderApiPath = 'entry.cgi';
      _createFolderApiVersion = 2;
      return (
        path: _createFolderApiPath!,
        version: _createFolderApiVersion!,
        requestFormat: null,
      );
    }

    final data = body['data'];
    if (data is! Map<String, dynamic>) {
      _createFolderApiPath = 'entry.cgi';
      _createFolderApiVersion = 2;
      return (
        path: _createFolderApiPath!,
        version: _createFolderApiVersion!,
        requestFormat: null,
      );
    }
    final apiInfo = data['SYNO.FileStation.CreateFolder'];
    if (apiInfo is! Map<String, dynamic>) {
      _createFolderApiPath = 'entry.cgi';
      _createFolderApiVersion = 2;
      return (
        path: _createFolderApiPath!,
        version: _createFolderApiVersion!,
        requestFormat: null,
      );
    }

    final path = apiInfo['path']?.toString();
    final maxVersion = apiInfo['maxVersion'];
    final requestFormat = apiInfo['requestFormat']?.toString();
    if (path == null || path.isEmpty || maxVersion is! num) {
      _createFolderApiPath = 'entry.cgi';
      _createFolderApiVersion = 2;
      return (
        path: _createFolderApiPath!,
        version: _createFolderApiVersion!,
        requestFormat: requestFormat,
      );
    }

    _createFolderApiPath = path;
    _createFolderApiVersion = maxVersion.toInt();
    return (
      path: _createFolderApiPath!,
      version: _createFolderApiVersion!,
      requestFormat: requestFormat,
    );
  }

  Future<Map<String, dynamic>> _listRequest({required String? folderPath}) {
    final queryParameters = <String, String>{
      'api': 'SYNO.FileStation.List',
      'offset': '0',
      'limit': '1000',
      'sort_by': 'mtime',
      'sort_direction': 'DESC',
      'action': 'list',
      'check_dir': 'true',
      'additional':
          '["real_path","size","time","type","description","indexed"]',
      'filetype': 'all',
      'method': 'list',
      'version': '2',
      'SynoToken': _synoToken!,
    };

    if (folderPath != null && folderPath.isNotEmpty) {
      queryParameters['folder_path'] = folderPath;
    }

    return _sendRequest(
      uri: _buildWebApiUri('entry.cgi'),
      queryParameters: queryParameters,
    ).then((body) {
      final success = body['success'] == true;
      if (!success) {
        throw _parseApiError(body, fallbackMessage: '目录加载失败');
      }
      return body;
    });
  }

  Future<Map<String, dynamic>> _listShareRequest() {
    Future<Map<String, dynamic>> request({
      required Uri uri,
      required String version,
    }) {
      final queryParameters = <String, String>{
        'api': 'SYNO.FileStation.List',
        'method': 'list_share',
        'version': version,
        'offset': '0',
        'limit': '1000',
        'sort_by': 'name',
        'sort_direction': 'ASC',
        'SynoToken': _synoToken!,
      };

      return _sendRequest(
        uri: uri,
        queryParameters: queryParameters,
      ).then((body) {
        final success = body['success'] == true;
        if (!success) {
          throw _parseApiError(body, fallbackMessage: '共享目录加载失败');
        }
        unawaited(_persistSession());
        return body;
      });
    }

    return request(
      uri: _buildWebApiUri('entry.cgi'),
      version: '2',
    ).catchError((Object firstError) {
      debugPrint(
        'NAS share list via entry.cgi failed, retrying with version 1',
      );
      return request(
        uri: _buildWebApiUri('entry.cgi'),
        version: '1',
      ).catchError((Object secondError) {
        debugPrint(
          'NAS share list via entry.cgi failed again, retrying legacy file_share.cgi',
        );
        return request(
          uri: _buildWebApiUri('FileStation/file_share.cgi'),
          version: '1',
        );
      });
    });
  }

  List<NasFileEntry> _extractFileEntries(Map<String, dynamic> listBody) {
    final data = listBody['data'];
    if (data is! Map<String, dynamic>) {
      return const [];
    }

    final files = data['files'];
    if (files is! List) {
      return const [];
    }

    return files
        .whereType<Map<String, dynamic>>()
        .map(NasFileEntry.fromJson)
        .toList();
  }

  List<NasFileEntry> _extractSharedFolderEntries(
      Map<String, dynamic> listBody) {
    final data = listBody['data'];
    if (data is! Map<String, dynamic>) {
      return const [];
    }

    final shares = data['shares'];
    if (shares is! List) {
      return const [];
    }

    return shares.whereType<Map<String, dynamic>>().map((json) {
      final path = (json['path'] ?? json['real_path'] ?? '').toString();
      return NasFileEntry(
        name: (json['name'] ?? '').toString(),
        path: path,
        isDirectory: true,
        sizeLabel: NasFileEntry.formatSizeLabel(json['additional']),
        modifiedAtLabel: NasFileEntry.formatModifiedLabel(
          json['additional'] is Map<String, dynamic>
              ? (json['additional'] as Map<String, dynamic>)['time']
              : null,
        ),
      );
    }).toList();
  }

  @override
  Future<void> logout() async {
    await _restorePersistedSession();
    if (_sid == null) {
      return;
    }

    try {
      await _sendRequest(
        uri: _buildWebApiUri('auth.cgi'),
        queryParameters: {
          'api': 'SYNO.API.Auth',
          'version': '6',
          'method': 'logout',
          '_sid': _sid!,
        },
      );
      if (_downloadStationSid != null) {
        await _sendRequest(
          uri: _buildWebApiUri('auth.cgi'),
          queryParameters: {
            'api': 'SYNO.API.Auth',
            'version': '1',
            'method': 'logout',
            'session': 'DownloadStation',
            'sid': _downloadStationSid!,
          },
        );
      }
    } catch (_) {
      // Ignore logout failures to avoid affecting page exit.
    } finally {
      await _clearSession(keepCredentials: false);
    }
  }

  bool get _hasSession =>
      _sid != null &&
      _sid!.isNotEmpty &&
      _synoToken != null &&
      _synoToken!.isNotEmpty;

  bool get _hasSavedCredentials =>
      _lastUsername != null &&
      _lastUsername!.isNotEmpty &&
      _lastPassword != null &&
      _lastPassword!.isNotEmpty;

  Future<void> _authenticate({
    required String username,
    required String password,
    required bool forceResolveBaseUri,
  }) async {
    final networkChanged = await _hasNetworkFingerprintChanged();
    if (forceResolveBaseUri || _resolvedBaseUri == null || networkChanged) {
      if (networkChanged) {
        _reportProgress('检测到网络环境变化，正在重新探测群晖地址');
      }
      _reportProgress('正在解析 QuickConnect 地址');
      _resolvedBaseUri = await _resolveDsmBaseUri();
    }

    _reportProgress('正在请求登录凭证');
    Map<String, dynamic> loginBody;
    try {
      loginBody = await _sendRequest(
        uri: _buildWebApiUri('auth.cgi'),
        queryParameters: {
          'api': 'SYNO.API.Auth',
          'version': '6',
          'method': 'login',
          'account': username,
          'passwd': password,
          'enable_syno_token': 'yes',
        },
      );
    } catch (error) {
      if (!_isRecoverableProbeError(error) || forceResolveBaseUri) {
        rethrow;
      }
      _reportProgress('已缓存地址不可用，正在重新探测群晖地址');
      _resolvedBaseUri = await _resolveDsmBaseUri();
      loginBody = await _sendRequest(
        uri: _buildWebApiUri('auth.cgi'),
        queryParameters: {
          'api': 'SYNO.API.Auth',
          'version': '6',
          'method': 'login',
          'account': username,
          'passwd': password,
          'enable_syno_token': 'yes',
        },
      );
    }

    final success = loginBody['success'] == true;
    if (!success) {
      throw _parseApiError(loginBody, fallbackMessage: '登录失败');
    }

    final data = loginBody['data'];
    if (data is! Map<String, dynamic>) {
      throw Exception('登录响应格式不正确');
    }

    _sid = data['sid']?.toString();
    _synoToken = data['synotoken']?.toString();
    _did = data['did']?.toString();
    if (_sid == null || _synoToken == null) {
      throw Exception('登录凭证缺失');
    }
    _reportProgress('登录成功，正在保存会话');
    await _persistSession();
  }

  bool _isRecoverableProbeError(Object error) {
    return error is SocketException ||
        error is TimeoutException ||
        error is HandshakeException;
  }

  Future<void> _clearSession({required bool keepCredentials}) async {
    _sid = null;
    _synoToken = null;
    _did = null;
    _downloadStationSid = null;
    _fileStationSid = null;
    _downloadTaskApiPath = null;
    _downloadTaskApiVersion = null;
    if (!keepCredentials) {
      _lastUsername = null;
      _lastPassword = null;
      _resolvedBaseUri = null;
      _lastNetworkFingerprint = null;
    }
    _cookies.clear();
    _cookies['type'] = Cookie('type', 'tunnel');
    await _removePersistedSession(keepCredentials: keepCredentials);
  }

  bool _isSessionExpired(SynologyApiException error) {
    return switch (error.code) {
      105 || 106 || 107 || 119 => true,
      _ => false,
    };
  }

  Future<void> _ensureDownloadStationSession(
      {bool forceRelogin = false}) async {
    if (!forceRelogin &&
        _downloadStationSid != null &&
        _downloadStationSid!.isNotEmpty) {
      return;
    }
    if (!forceRelogin && _sid != null && _sid!.isNotEmpty) {
      _downloadStationSid = _sid;
      _reportProgress('正在复用当前登录会话');
      return;
    }
    if (!_hasSavedCredentials) {
      throw const SynologyApiException('缺少 Download Station 登录凭证');
    }
    _reportProgress('正在登录下载管理模块');
    _resolvedBaseUri ??= await _resolveDsmBaseUri();
    final body = await _sendRequest(
      uri: _buildWebApiUri('entry.cgi'),
      queryParameters: {
        'api': 'SYNO.API.Auth',
        'version': '6',
        'method': 'login',
        'account': _lastUsername!,
        'passwd': _lastPassword!,
        'session': 'DownloadStation',
        'format': 'sid',
      },
    );
    final success = body['success'] == true;
    if (!success) {
      throw _parseApiError(body, fallbackMessage: '下载管理登录失败');
    }
    final data = body['data'];
    if (data is! Map<String, dynamic>) {
      throw const SynologyApiException('下载管理登录响应格式不正确');
    }
    _downloadStationSid = data['sid']?.toString();
    if (_downloadStationSid == null || _downloadStationSid!.isEmpty) {
      throw const SynologyApiException('下载管理会话缺失');
    }
    _reportProgress('下载管理模块已连接');
  }

  Future<void> _ensureFileStationSession({bool forceRelogin = false}) async {
    if (!forceRelogin &&
        _fileStationSid != null &&
        _fileStationSid!.isNotEmpty) {
      return;
    }
    if (!_hasSavedCredentials) {
      throw const SynologyApiException('缺少 FileStation 登录凭证');
    }
    _resolvedBaseUri ??= await _resolveDsmBaseUri();
    final body = await _sendRequest(
      uri: _buildWebApiUri('entry.cgi'),
      queryParameters: {
        'api': 'SYNO.API.Auth',
        'version': '6',
        'method': 'login',
        'account': _lastUsername!,
        'passwd': _lastPassword!,
        'session': 'FileStation',
        'format': 'sid',
      },
    );
    final success = body['success'] == true;
    if (!success) {
      throw _parseApiError(body, fallbackMessage: 'FileStation 登录失败');
    }
    final data = body['data'];
    if (data is! Map<String, dynamic>) {
      throw const SynologyApiException('FileStation 登录响应格式不正确');
    }
    _fileStationSid = data['sid']?.toString();
    if (_fileStationSid == null || _fileStationSid!.isEmpty) {
      throw const SynologyApiException('FileStation 会话缺失');
    }
  }

  Future<({String path, int version})> _getDownloadTaskApiInfo() async {
    if (_downloadTaskApiPath != null && _downloadTaskApiVersion != null) {
      return (path: _downloadTaskApiPath!, version: _downloadTaskApiVersion!);
    }

    _reportProgress('正在查询下载管理接口');
    final body = await _sendRequest(
      uri: _buildWebApiUri('query.cgi'),
      queryParameters: {
        'api': 'SYNO.API.Info',
        'version': '1',
        'method': 'query',
        'query': 'SYNO.DownloadStation.Task',
      },
    );
    final success = body['success'] == true;
    if (!success) {
      throw _parseApiError(body, fallbackMessage: '下载管理 API 查询失败');
    }

    final data = body['data'];
    if (data is! Map<String, dynamic>) {
      throw const SynologyApiException('下载管理 API 响应格式不正确');
    }
    final apiInfo = data['SYNO.DownloadStation.Task'];
    if (apiInfo is! Map<String, dynamic>) {
      throw const SynologyApiException('未找到 Download Station Task API');
    }
    final path = apiInfo['path']?.toString();
    final maxVersion = apiInfo['maxVersion'];
    if (path == null || path.isEmpty || maxVersion is! num) {
      throw const SynologyApiException('Download Station Task API 信息不完整');
    }
    _downloadTaskApiPath = path;
    _downloadTaskApiVersion = maxVersion.toInt();
    return (path: _downloadTaskApiPath!, version: _downloadTaskApiVersion!);
  }

  Future<void> _restorePersistedSession() {
    return _restoreFuture ??= _restorePersistedSessionInternal();
  }

  Future<void> _restorePersistedSessionInternal() async {
    final prefs = await _obtainPreferences();
    if (prefs == null) {
      return;
    }

    await prefs.remove('nas.last_password');
    _lastUsername ??= prefs.getString(_prefsKeyLastUsername);

    final baseUriText = prefs.getString(_prefsKeyResolvedBaseUri);
    if (_resolvedBaseUri == null &&
        baseUriText != null &&
        baseUriText.isNotEmpty) {
      _resolvedBaseUri = Uri.tryParse(baseUriText);
    }

    _sid ??= prefs.getString(_prefsKeySid);
    _synoToken ??= prefs.getString(_prefsKeySynoToken);
    _did ??= prefs.getString(_prefsKeyDid);
    _lastNetworkFingerprint ??= prefs.getString(_prefsKeyNetworkFingerprint);

    final encodedCookies = prefs.getString(_prefsKeyCookies);
    if (encodedCookies != null &&
        encodedCookies.isNotEmpty &&
        (_cookies.length == 1 && _cookies['type']?.value == 'tunnel')) {
      final decoded = jsonDecode(encodedCookies);
      if (decoded is List) {
        for (final item in decoded.whereType<Map<String, dynamic>>()) {
          final name = item['name']?.toString();
          final value = item['value']?.toString();
          if (name == null || name.isEmpty || value == null) {
            continue;
          }
          _cookies[name] = Cookie(name, value);
        }
      }
    }
  }

  Future<void> _persistSession() async {
    final prefs = await _obtainPreferences();
    if (prefs == null) {
      return;
    }
    if (_resolvedBaseUri != null) {
      await prefs.setString(
          _prefsKeyResolvedBaseUri, _resolvedBaseUri.toString());
    }
    if (_sid != null) {
      await prefs.setString(_prefsKeySid, _sid!);
    }
    if (_synoToken != null) {
      await prefs.setString(_prefsKeySynoToken, _synoToken!);
    }
    if (_did != null) {
      await prefs.setString(_prefsKeyDid, _did!);
    }
    if (_lastUsername != null) {
      await prefs.setString(_prefsKeyLastUsername, _lastUsername!);
    }
    _lastNetworkFingerprint ??= await _computeNetworkFingerprint();
    if (_lastNetworkFingerprint != null) {
      await prefs.setString(
          _prefsKeyNetworkFingerprint, _lastNetworkFingerprint!);
    }

    final cookies = _cookies.values
        .map((cookie) => {'name': cookie.name, 'value': cookie.value})
        .toList();
    await prefs.setString(_prefsKeyCookies, jsonEncode(cookies));
  }

  Future<void> _removePersistedSession({required bool keepCredentials}) async {
    final prefs = await _obtainPreferences();
    if (prefs == null) {
      return;
    }
    await prefs.remove(_prefsKeySid);
    await prefs.remove(_prefsKeySynoToken);
    await prefs.remove(_prefsKeyDid);
    await prefs.remove(_prefsKeyCookies);
    await prefs.remove(_prefsKeyNetworkFingerprint);
    if (!keepCredentials) {
      await prefs.remove(_prefsKeyResolvedBaseUri);
      await prefs.remove(_prefsKeyLastUsername);
    }
  }

  Future<bool> _hasNetworkFingerprintChanged() async {
    final current = await _computeNetworkFingerprint();
    if (current == null || current.isEmpty) {
      return false;
    }
    final previous = _lastNetworkFingerprint;
    _lastNetworkFingerprint = current;
    if (previous == null || previous.isEmpty) {
      return false;
    }
    return previous != current;
  }

  Future<String?> _computeNetworkFingerprint() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.any,
      );
      final tokens = <String>[];
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final value = address.address.trim();
          if (value.isEmpty) {
            continue;
          }
          tokens.add('${interface.name}:$value');
        }
      }
      if (tokens.isEmpty) {
        return null;
      }
      tokens.sort();
      return tokens.join('|');
    } catch (_) {
      return null;
    }
  }

  Future<SharedPreferences?> _obtainPreferences() async {
    if (_prefsUnavailable) {
      return null;
    }

    try {
      return await SharedPreferences.getInstance();
    } on PlatformException catch (error) {
      _prefsUnavailable = true;
      debugPrint('NAS shared_preferences unavailable -> $error');
      return null;
    } on MissingPluginException catch (error) {
      _prefsUnavailable = true;
      debugPrint('NAS shared_preferences plugin missing -> $error');
      return null;
    }
  }

  Future<Map<String, dynamic>> _sendRequest({
    required Uri uri,
    required Map<String, String> queryParameters,
  }) async {
    final requestUri = uri.replace(queryParameters: queryParameters);
    debugPrint('NAS request -> GET ${_redactUri(requestUri)}');
    final request = await _httpClient.getUrl(requestUri);

    final cookieHeader = _cookieHeader;
    if (cookieHeader.isNotEmpty) {
      request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
      debugPrint('NAS request cookies -> ${_redactCookieHeader(cookieHeader)}');
    }

    final response = await request.close();
    for (final cookie in response.cookies) {
      _cookies[cookie.name] = cookie;
    }

    final responseBody = await utf8.decodeStream(response);
    debugPrint(
        'NAS response <- ${response.statusCode} ${_redactUri(requestUri)}');
    debugPrint('NAS response body <- ${_redactResponseBody(responseBody)}');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        '请求失败: ${response.statusCode}',
        uri: requestUri,
      );
    }

    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('响应格式不正确');
    }

    return decoded;
  }

  Future<Map<String, dynamic>> _sendPostRequest({
    required Uri uri,
    required Map<String, String> formFields,
  }) async {
    debugPrint('NAS request -> POST $uri');
    debugPrint(
      'NAS request body -> ${_redactQueryParameters(formFields)}',
    );
    final request = await _httpClient.postUrl(uri);
    request.headers.set(
      HttpHeaders.contentTypeHeader,
      'application/x-www-form-urlencoded; charset=utf-8',
    );

    final cookieHeader = _cookieHeader;
    if (cookieHeader.isNotEmpty) {
      request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
      debugPrint('NAS request cookies -> ${_redactCookieHeader(cookieHeader)}');
    }

    request.write(Uri(queryParameters: formFields).query);
    final response = await request.close();
    for (final cookie in response.cookies) {
      _cookies[cookie.name] = cookie;
    }

    final responseBody = await utf8.decodeStream(response);
    debugPrint('NAS response <- ${response.statusCode} $uri');
    debugPrint('NAS response body <- ${_redactResponseBody(responseBody)}');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        '请求失败: ${response.statusCode}',
        uri: uri,
      );
    }

    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('响应格式不正确');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> _sendPostJsonRequest({
    required Uri uri,
    required Map<String, dynamic> jsonBody,
  }) async {
    debugPrint('NAS request -> POST $uri');
    debugPrint(
      'NAS request body (json) -> ${_redactResponseBody(jsonEncode(jsonBody))}',
    );
    final request = await _httpClient.postUrl(uri);
    request.headers.set(
      HttpHeaders.contentTypeHeader,
      'application/json; charset=utf-8',
    );

    final cookieHeader = _cookieHeader;
    if (cookieHeader.isNotEmpty) {
      request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
      debugPrint('NAS request cookies -> ${_redactCookieHeader(cookieHeader)}');
    }

    request.write(jsonEncode(jsonBody));
    final response = await request.close();
    for (final cookie in response.cookies) {
      _cookies[cookie.name] = cookie;
    }

    final responseBody = await utf8.decodeStream(response);
    debugPrint('NAS response <- ${response.statusCode} $uri');
    debugPrint('NAS response body <- ${_redactResponseBody(responseBody)}');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        '请求失败: ${response.statusCode}',
        uri: uri,
      );
    }

    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('响应格式不正确');
    }
    return decoded;
  }

  Uri _buildWebApiUri(String fileName) {
    final base = _resolvedBaseUri;
    if (base == null) {
      throw const SynologyApiException('尚未解析到 DSM 地址');
    }
    return base.replace(path: '${base.path}/$fileName');
  }

  Future<Uri> _resolveDsmBaseUri() async {
    final quickConnectId = _extractQuickConnectId(_quickConnectUri.host);
    final payload = [
      {
        'version': 1,
        'command': 'get_server_info',
        'stop_when_error': false,
        'stop_when_success': false,
        'id': 'dsm_portal_https',
        'serverID': quickConnectId,
      },
      {
        'version': 1,
        'command': 'get_server_info',
        'stop_when_error': false,
        'stop_when_success': false,
        'id': 'dsm_portal',
        'serverID': quickConnectId,
      },
    ];

    _reportProgress('正在请求 QuickConnect 服务信息');
    final serverInfos = await _requestQuickConnectServers(
      uri: _quickConnectApiUri,
      payload: payload,
    );

    final successCandidate =
        serverInfos.cast<Map<String, dynamic>?>().firstWhere(
              (item) => item?['errno'] == 0,
              orElse: () => null,
            );

    if (successCandidate == null) {
      final firstError = serverInfos.isNotEmpty ? serverInfos.first : null;
      final code = firstError?['errno'] is num
          ? (firstError!['errno'] as num).toInt()
          : null;
      throw SynologyApiException('QuickConnect 未返回可用服务信息', code: code);
    }

    final server = successCandidate['server'];
    final service = successCandidate['service'];
    if (server is! Map<String, dynamic> || service is! Map<String, dynamic>) {
      throw const SynologyApiException('QuickConnect 服务信息不完整');
    }

    final uriCandidates = _buildCandidateBaseUris(
      server: server,
      service: service,
      smartdns: successCandidate['smartdns'],
    );

    if (uriCandidates.isEmpty) {
      throw const SynologyApiException('QuickConnect 已解析，但未返回可探测地址');
    }

    _reportProgress('正在并行探测群晖地址（${uriCandidates.length}个候选）');
    final best = await _probeBestCandidateUri(uriCandidates);
    if (best != null) {
      _reportProgress(
        '已找到可用地址：${_formatProbeTarget(best.uri)}（${best.latency.inMilliseconds}ms）',
      );
      debugPrint(
          'NAS quickconnect resolved DSM -> ${best.uri} (${best.latency.inMilliseconds}ms)');
      return best.uri;
    }

    throw const SynologyApiException('QuickConnect 已解析，但未找到可访问的 DSM 地址');
  }

  Future<({Uri uri, Duration latency})?> _probeBestCandidateUri(
    List<Uri> uriCandidates,
  ) async {
    final futures = uriCandidates.map((candidate) async {
      final stopwatch = Stopwatch()..start();
      final reachable = await _canReachAuthApi(candidate);
      stopwatch.stop();
      if (!reachable) {
        return null;
      }
      return (uri: candidate, latency: stopwatch.elapsed);
    }).toList();

    final results = await Future.wait(futures);
    final successful = results
        .whereType<({Uri uri, Duration latency})>()
        .toList(growable: false);
    if (successful.isEmpty) {
      return null;
    }
    final sorted = successful.toList()
      ..sort((a, b) => a.latency.compareTo(b.latency));
    return sorted.first;
  }

  Future<List<Map<String, dynamic>>> _requestQuickConnectServers({
    required Uri uri,
    required List<Map<String, Object>> payload,
  }) async {
    debugPrint('NAS quickconnect resolve -> POST $uri');
    debugPrint('NAS quickconnect payload -> ${jsonEncode(payload)}');

    final request = await _httpClient.postUrl(uri);
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.add(utf8.encode(jsonEncode(payload)));

    final response = await request.close();
    final responseBody = await utf8.decodeStream(response);
    debugPrint('NAS quickconnect response <- ${response.statusCode} $uri');
    debugPrint('NAS quickconnect body <- $responseBody');

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SynologyApiException(
        'QuickConnect 解析失败: ${response.statusCode}',
      );
    }

    final decoded = jsonDecode(responseBody);
    if (decoded is! List) {
      throw const SynologyApiException('QuickConnect 响应格式不正确');
    }

    final candidates = decoded.whereType<Map<String, dynamic>>().toList();
    final successCandidate =
        candidates.cast<Map<String, dynamic>?>().firstWhere(
              (item) => item?['errno'] == 0,
              orElse: () => null,
            );
    if (successCandidate != null) {
      return candidates;
    }

    final retryUri = _extractRetryQuickConnectUri(candidates, currentUri: uri);
    if (retryUri != null) {
      return _requestQuickConnectServers(uri: retryUri, payload: payload);
    }

    return candidates;
  }

  Uri? _extractRetryQuickConnectUri(
    List<Map<String, dynamic>> candidates, {
    required Uri currentUri,
  }) {
    for (final candidate in candidates) {
      final sites = candidate['sites'];
      if (sites is! List) {
        continue;
      }

      for (final site in sites.whereType<String>()) {
        if (site.isEmpty || site == currentUri.host) {
          continue;
        }

        return Uri(
          scheme: currentUri.scheme,
          host: site,
          path: currentUri.path,
        );
      }
    }

    return null;
  }

  List<Uri> _buildCandidateBaseUris({
    required Map<String, dynamic> server,
    required Map<String, dynamic> service,
    required dynamic smartdns,
  }) {
    final candidates = <Uri>[];

    void addCandidate(String? host, int? port) {
      if (host == null || host.isEmpty || port == null || port <= 0) {
        return;
      }
      final candidate = Uri(
        scheme: 'https',
        host: host,
        port: port,
        path: '/webapi',
      );
      if (!candidates.contains(candidate)) {
        candidates.add(candidate);
      }
    }

    final securePort = _readSecurePort(service);
    final dsmPort = _readPort(service);

    if (smartdns is Map<String, dynamic>) {
      if (smartdns['lan'] is List) {
        for (final host in (smartdns['lan'] as List).whereType<String>()) {
          addCandidate(host, securePort);
          addCandidate(host, dsmPort);
        }
      }
      if (smartdns['host'] is String) {
        addCandidate(smartdns['host'] as String, securePort);
        addCandidate(smartdns['host'] as String, dsmPort);
      }
    }

    if (service['relay_dn'] is String) {
      addCandidate(service['relay_dn'] as String, _readRelayPort(service));
      addCandidate(service['relay_dn'] as String, securePort);
    }

    if (service['https_ip'] is String) {
      addCandidate(service['https_ip'] as String, securePort);
    }

    if (server['ddns'] is String && server['ddns'] != 'NULL') {
      addCandidate(server['ddns'] as String, dsmPort);
      addCandidate(server['ddns'] as String, securePort);
    }

    if (server['external'] is Map<String, dynamic> &&
        (server['external'] as Map<String, dynamic>)['ip'] is String) {
      addCandidate(
        (server['external'] as Map<String, dynamic>)['ip'] as String,
        dsmPort,
      );
      addCandidate(
        (server['external'] as Map<String, dynamic>)['ip'] as String,
        securePort,
      );
    }

    final pingpongDesc = service['pingpong_desc'];
    if (pingpongDesc is List) {
      for (final item in pingpongDesc.whereType<String>()) {
        final segments = item.split(':');
        final host = segments.first.trim();
        final port = segments.length > 1 ? int.tryParse(segments.last) : null;
        addCandidate(host, port ?? securePort);
      }
    }

    debugPrint('NAS quickconnect candidates -> ${candidates.join(', ')}');
    return candidates;
  }

  int _readPort(Map<String, dynamic> service) {
    final extPort = service['ext_port'];
    if (extPort is num && extPort > 0) {
      return extPort.toInt();
    }

    final port = service['port'];
    if (port is num && port > 0) {
      return port.toInt();
    }

    return 5001;
  }

  int _readSecurePort(Map<String, dynamic> service) {
    final httpsPort = service['https_port'];
    if (httpsPort is num && httpsPort > 0) {
      return httpsPort.toInt();
    }
    return _readPort(service);
  }

  int _readRelayPort(Map<String, dynamic> service) {
    final relayPort = service['relay_port'];
    if (relayPort is num && relayPort > 0) {
      return relayPort.toInt();
    }
    return _readSecurePort(service);
  }

  Future<bool> _canReachAuthApi(Uri baseUri) async {
    final uri = baseUri.replace(
      path: '${baseUri.path}/query.cgi',
      queryParameters: {
        'api': 'SYNO.API.Info',
        'version': '1',
        'method': 'query',
        'query': 'SYNO.API.Auth',
      },
    );

    try {
      debugPrint('NAS probe -> GET $uri');
      final request = await _httpClient.getUrl(uri).timeout(
            const Duration(seconds: 4),
          );
      final response = await request.close();
      final responseBody = await utf8.decodeStream(response).timeout(
            const Duration(seconds: 4),
          );
      debugPrint('NAS probe response <- ${response.statusCode} $uri');
      debugPrint('NAS probe body <- $responseBody');

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }

      final decoded = jsonDecode(responseBody);
      return decoded is Map<String, dynamic> && decoded['success'] == true;
    } catch (_) {
      debugPrint('NAS probe failed <- $uri');
      return false;
    }
  }

  String _extractQuickConnectId(String host) {
    final parts = host.split('.');
    if (parts.isEmpty || parts.first.isEmpty) {
      throw const SynologyApiException('QuickConnect 域名无效');
    }
    return parts.first;
  }

  String _formatProbeTarget(Uri uri) {
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.host}$port';
  }

  String get _cookieHeader => _cookies.values
      .map((cookie) => '${cookie.name}=${cookie.value}')
      .join('; ');

  Uri _redactUri(Uri uri) {
    if (uri.queryParameters.isEmpty) {
      return uri;
    }
    return uri.replace(
      queryParameters: _redactQueryMap(uri.queryParameters),
    );
  }

  String _redactQueryParameters(Map<String, String> queryParameters) {
    return Uri(queryParameters: _redactQueryMap(queryParameters)).query;
  }

  Map<String, String> _redactQueryMap(Map<String, String> queryParameters) {
    const sensitiveKeys = {
      'passwd',
      'sid',
      '_sid',
      'SynoToken',
      'synotoken',
      'token',
    };
    return queryParameters.map((key, value) {
      if (sensitiveKeys.contains(key)) {
        return MapEntry(key, '***');
      }
      return MapEntry(key, value);
    });
  }

  String _redactCookieHeader(String cookieHeader) {
    const sensitiveCookieNames = {'id', 'did'};
    return cookieHeader.split(';').map((part) {
      final trimmed = part.trim();
      final separator = trimmed.indexOf('=');
      if (separator <= 0) {
        return trimmed;
      }
      final name = trimmed.substring(0, separator);
      if (sensitiveCookieNames.contains(name)) {
        return '$name=***';
      }
      return trimmed;
    }).join('; ');
  }

  String _redactResponseBody(String responseBody) {
    return responseBody
        .replaceAllMapped(
          RegExp(r'"(sid|synotoken|did)"\s*:\s*"[^"]*"'),
          (match) => '"${match.group(1)}":"***"',
        )
        .replaceAllMapped(
          RegExp(r'"(id)"\s*:\s*"[^"]{16,}"'),
          (match) => '"${match.group(1)}":"***"',
        );
  }

  SynologyApiException _parseApiError(
    Map<String, dynamic> body, {
    required String fallbackMessage,
  }) {
    final error = body['error'];
    final code = error is Map<String, dynamic> && error['code'] is num
        ? (error['code'] as num).toInt()
        : null;
    return SynologyApiException(fallbackMessage, code: code);
  }
}

class NasPage extends StatefulWidget {
  NasPage({
    super.key,
    NasClient? client,
    this.openDownloadManagerOnReady = false,
    this.initialDownloadDestination,
  }) : client = client ?? _sharedClient;

  final NasClient client;
  final bool openDownloadManagerOnReady;
  final String? initialDownloadDestination;

  static final SynologyNasClient _sharedClient = SynologyNasClient();

  @override
  State<NasPage> createState() => _NasPageState();
}

class _NasPageState extends State<NasPage> {
  final TextEditingController _usernameController = TextEditingController(
    text: '18725944157',
  );
  final TextEditingController _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _submitting = false;
  bool _loggedIn = false;
  bool _showFileManager = false;
  bool _showDownloadManager = false;
  bool _downloadLoading = false;
  String _currentPath = SynologyNasClient.sharedRootPath;
  String? _errorMessage;
  String? _progressMessage;
  List<NasFileEntry> _entries = const [];
  List<NasDownloadTask> _downloadTasks = const [];
  NasDownloadTaskFilter _downloadFilter = NasDownloadTaskFilter.all;
  late bool _pendingInitialDownloadDialog;

  @override
  void initState() {
    super.initState();
    _pendingInitialDownloadDialog = widget.openDownloadManagerOnReady &&
        widget.initialDownloadDestination != null &&
        widget.initialDownloadDestination!.trim().isNotEmpty;
    widget.client.setProgressListener((message) {
      if (!mounted) {
        return;
      }
      setState(() {
        _progressMessage = message;
      });
    });
    unawaited(_restoreSessionIfAvailable());
  }

  @override
  void dispose() {
    widget.client.setProgressListener(null);
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _restoreSessionIfAvailable() async {
    setState(() {
      _submitting = true;
      _errorMessage = null;
      _progressMessage = '正在恢复本地会话';
    });

    try {
      final entries = await widget.client.restoreSession(path: _currentPath);
      if (!mounted || entries == null) {
        return;
      }

      setState(() {
        _entries = entries;
        _loggedIn = true;
        _showFileManager = false;
        _showDownloadManager = widget.openDownloadManagerOnReady;
        _progressMessage = null;
      });
      if (widget.openDownloadManagerOnReady) {
        unawaited(
          _openDownloadManager(
            showCreateDialog: _pendingInitialDownloadDialog,
          ),
        );
      }
    } catch (_) {
      // Ignore restore errors and keep login page visible.
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<void> _handleLogin() async {
    FocusScope.of(context).unfocus();

    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = '请输入用户名和密码';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
      _progressMessage = '正在准备登录';
    });

    try {
      final entries = await widget.client.login(
        username: username,
        password: password,
        path: _currentPath,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _entries = entries;
        _loggedIn = true;
        _showFileManager = false;
        _showDownloadManager = widget.openDownloadManagerOnReady;
        _progressMessage = null;
      });
      if (widget.openDownloadManagerOnReady) {
        unawaited(
          _openDownloadManager(
            showCreateDialog: _pendingInitialDownloadDialog,
          ),
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = error.toString();
        _progressMessage = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<void> _loadDirectory({required String path}) async {
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final entries = await widget.client.listDirectory(path: path);
      if (!mounted) {
        return;
      }

      setState(() {
        _entries = entries;
        _currentPath = path;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<void> _openEntry(NasFileEntry entry) async {
    if (!entry.isDirectory || _submitting) {
      return;
    }
    await _loadDirectory(path: entry.path);
  }

  Future<void> _openDownloadManager({bool showCreateDialog = false}) async {
    setState(() {
      _showDownloadManager = true;
      _showFileManager = false;
    });
    await _loadDownloadTasks();
    if (!mounted || !showCreateDialog || !_pendingInitialDownloadDialog) {
      return;
    }
    _pendingInitialDownloadDialog = false;
    await _waitNextFrame();
    if (!mounted || !_showDownloadManager) {
      return;
    }
    await _showCreateDownloadDialog(
      initialDestination: widget.initialDownloadDestination,
    );
  }

  Future<void> _waitNextFrame() {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    return completer.future;
  }

  Future<void> _loadDownloadTasks() async {
    setState(() {
      _downloadLoading = true;
      _errorMessage = null;
    });

    try {
      final tasks = await widget.client.listDownloadTasks();
      if (!mounted) {
        return;
      }
      setState(() {
        _downloadTasks = tasks;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _downloadLoading = false;
        });
      }
    }
  }

  Future<void> _showCreateDownloadDialog({String? initialDestination}) async {
    final destinationController = TextEditingController(
      text: initialDestination ?? '',
    );
    final urlController = TextEditingController();
    String? dialogError;

    final task = await showDialog<({String destination, String url})>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('添加下载任务'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: destinationController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: '目的地文件夹',
                        hintText: '例如 /video、/剧集、/downloads',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: urlController,
                      decoration: const InputDecoration(
                        labelText: '下载 URL',
                        hintText: '请输入 http(s)、magnet 等下载链接',
                      ),
                    ),
                    if (dialogError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        dialogError!,
                        style: const TextStyle(
                          color: Color(0xFFDC2626),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    final destination = destinationController.text.trim();
                    final url = urlController.text.trim();
                    if (destination.isEmpty) {
                      setDialogState(() {
                        dialogError = '请输入目的地文件夹地址';
                      });
                      return;
                    }
                    if (url.isEmpty) {
                      setDialogState(() {
                        dialogError = '请输入下载链接';
                      });
                      return;
                    }
                    Navigator.pop(
                      context,
                      (destination: destination, url: url),
                    );
                  },
                  child: const Text('创建'),
                ),
              ],
            );
          },
        );
      },
    );

    destinationController.dispose();
    urlController.dispose();

    if (task == null || task.url.isEmpty || task.destination.isEmpty) {
      return;
    }

    setState(() {
      _downloadLoading = true;
      _errorMessage = null;
    });

    try {
      await widget.client.createDownloadTask(
        destination: task.destination,
        url: task.url,
      );
      if (!mounted) {
        return;
      }
      await _loadDownloadTasks();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.toString();
        _downloadLoading = false;
      });
    }
  }

  Future<void> _showCreateFolderDialog() async {
    if (_submitting) {
      return;
    }
    if (_currentPath == SynologyNasClient.sharedRootPath) {
      setState(() {
        _errorMessage = '请先进入具体共享目录后再创建文件夹';
      });
      return;
    }

    final nameController = TextEditingController();
    String? dialogError;

    final folderName = await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('新建文件夹'),
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '当前目录：$_pathLabel',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: '文件夹名称',
                        hintText: '请输入名称',
                      ),
                    ),
                    if (dialogError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        dialogError!,
                        style: const TextStyle(
                          color: Color(0xFFDC2626),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      setDialogState(() {
                        dialogError = '请输入文件夹名称';
                      });
                      return;
                    }
                    if (name.contains('/')) {
                      setDialogState(() {
                        dialogError = '文件夹名称不能包含 /';
                      });
                      return;
                    }
                    Navigator.pop(context, name);
                  },
                  child: const Text('创建'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    if (folderName == null || folderName.isEmpty) {
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      await widget.client.createFolder(
        parentPath: _currentPath,
        folderName: folderName,
      );
      if (!mounted) {
        return;
      }
      await _loadDirectory(path: _currentPath);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.toString();
        _submitting = false;
      });
    }
  }

  Future<void> _confirmDeleteDownloadTask(NasDownloadTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除下载任务'),
          content: Text('确定要删除“${task.title}”吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _downloadLoading = true;
      _errorMessage = null;
    });

    try {
      await widget.client.deleteDownloadTask(taskId: task.id);
      if (!mounted) {
        return;
      }
      await _loadDownloadTasks();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.toString();
        _downloadLoading = false;
      });
    }
  }

  Future<void> _goParent() async {
    if (_currentPath == SynologyNasClient.sharedRootPath ||
        _currentPath == '/' ||
        _currentPath.isEmpty ||
        _submitting) {
      return;
    }

    final segments =
        _currentPath.split('/').where((item) => item.isNotEmpty).toList();
    if (segments.isEmpty) {
      return;
    }
    segments.removeLast();
    final parentPath = segments.isEmpty
        ? SynologyNasClient.sharedRootPath
        : '/${segments.join('/')}';
    await _loadDirectory(path: parentPath);
  }

  String get _pathLabel {
    if (_currentPath == SynologyNasClient.sharedRootPath) {
      return '共享目录';
    }
    return _currentPath;
  }

  List<NasDownloadTask> get _filteredDownloadTasks {
    return switch (_downloadFilter) {
      NasDownloadTaskFilter.all => _downloadTasks,
      NasDownloadTaskFilter.downloading =>
        _downloadTasks.where((task) => task.status == 'downloading').toList(),
      NasDownloadTaskFilter.completed => _downloadTasks
          .where(
              (task) => task.status == 'finished' || task.status == 'seeding')
          .toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final body = !_loggedIn
        ? _buildLoginView()
        : _showFileManager
            ? _buildDirectoryView()
            : _showDownloadManager
                ? _buildDownloadManagerView()
                : _buildMenuView();
    return Scaffold(
      appBar: AppBar(title: const Text('NAS')),
      body: body,
    );
  }

  Widget _buildMenuView() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          key: const ValueKey('nas-menu'),
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'NAS',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '请选择要进入的功能模块',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: Color(0xFF667085),
                ),
              ),
              const SizedBox(height: 24),
              _NasMenuCard(
                title: '文件管理',
                subtitle: '浏览共享目录和文件列表',
                icon: Icons.folder_copy_rounded,
                color: const Color(0xFF2563EB),
                onTap: _submitting
                    ? null
                    : () {
                        setState(() {
                          _showFileManager = true;
                          _showDownloadManager = false;
                        });
                      },
              ),
              const SizedBox(height: 16),
              _NasMenuCard(
                title: '下载管理',
                subtitle: '查看和管理下载任务',
                icon: Icons.download_rounded,
                color: const Color(0xFF10B981),
                onTap: _submitting ? null : _openDownloadManager,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginView() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          key: const ValueKey('nas-login'),
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE4E7EC)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.06),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.storage_rounded,
                size: 52,
                color: Color(0xFF2563EB),
              ),
              const SizedBox(height: 16),
              const Text(
                'NAS 登录',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '直接请求群晖接口，登录后展示文件目录。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: Color(0xFF667085),
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _usernameController,
                keyboardType: TextInputType.text,
                decoration: InputDecoration(
                  labelText: '用户名',
                  hintText: '请输入用户名',
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: '密码',
                  hintText: '请输入密码',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                    ),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: Color(0xFFDC2626),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (_submitting && _progressMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _progressMessage!,
                          style: const TextStyle(
                            color: Color(0xFF1D4ED8),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _submitting ? null : _handleLogin,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        '登录',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDirectoryView() {
    return Column(
      key: const ValueKey('nas-directory'),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Color(0xFFE5E7EB)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _pathLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '返回菜单',
                    onPressed: _submitting
                        ? null
                        : () {
                            setState(() {
                              _showFileManager = false;
                            });
                          },
                    icon: const Icon(Icons.dashboard_customize_rounded),
                  ),
                  IconButton(
                    tooltip: '返回上级',
                    onPressed:
                        _currentPath == SynologyNasClient.sharedRootPath ||
                                _currentPath == '/'
                            ? null
                            : _goParent,
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                  IconButton(
                    tooltip: '新建文件夹',
                    onPressed: _submitting ? null : _showCreateFolderDialog,
                    icon: const Icon(Icons.create_new_folder_rounded),
                  ),
                  IconButton(
                    tooltip: '刷新',
                    onPressed: _submitting
                        ? null
                        : () => _loadDirectory(path: _currentPath),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '文件目录',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        if (_errorMessage != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: const Color(0xFFFEF2F2),
            child: Text(
              _errorMessage!,
              style: const TextStyle(
                color: Color(0xFFDC2626),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Expanded(
          child: Stack(
            children: [
              if (_entries.isEmpty && !_submitting)
                const Center(
                  child: Text(
                    '当前目录为空',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _entries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final entry = _entries[index];
                    return _NasEntryTile(
                      entry: entry,
                      onTap: () => _openEntry(entry),
                    );
                  },
                ),
              if (_submitting)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Color(0x66FFFFFF),
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadManagerView() {
    final filteredTasks = _filteredDownloadTasks;
    return Padding(
      key: const ValueKey('nas-download-manager'),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '下载管理',
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF111827),
                                ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _submitting
                          ? null
                          : () {
                              setState(() {
                                _showDownloadManager = false;
                              });
                            },
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text('返回菜单'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '任务列表',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                    ),
                    IconButton(
                      tooltip: '刷新任务',
                      onPressed: _downloadLoading ? null : _loadDownloadTasks,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed:
                          _downloadLoading ? null : _showCreateDownloadDialog,
                      icon: const Icon(Icons.add_link_rounded),
                      label: const Text('添加任务'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: NasDownloadTaskFilter.values.map((filter) {
                    final selected = _downloadFilter == filter;
                    final count = switch (filter) {
                      NasDownloadTaskFilter.all => _downloadTasks.length,
                      NasDownloadTaskFilter.downloading => _downloadTasks
                          .where((task) => task.status == 'downloading')
                          .length,
                      NasDownloadTaskFilter.completed => _downloadTasks
                          .where(
                            (task) =>
                                task.status == 'finished' ||
                                task.status == 'seeding',
                          )
                          .length,
                    };
                    return ChoiceChip(
                      selected: selected,
                      label: Text('${filter.label} $count'),
                      onSelected: (_) {
                        setState(() {
                          _downloadFilter = filter;
                        });
                      },
                      selectedColor: const Color(0xFFD1FAE5),
                      labelStyle: TextStyle(
                        color: selected
                            ? const Color(0xFF047857)
                            : const Color(0xFF475467),
                        fontWeight: FontWeight.w800,
                      ),
                      side: BorderSide(
                        color: selected
                            ? const Color(0xFF10B981)
                            : const Color(0xFFE5E7EB),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                if (_errorMessage != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: Color(0xFFDC2626),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Stack(
                  children: [
                    if (filteredTasks.isEmpty && !_downloadLoading)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.downloading_rounded,
                              size: 52,
                              color: Color(0xFF10B981),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _downloadTasks.isEmpty
                                  ? '暂无下载任务'
                                  : '暂无${_downloadFilter.label}任务',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF111827),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _downloadTasks.isEmpty
                                  ? '点击右上角“添加任务”，可以通过 URL 创建新的下载任务。'
                                  : '切换上方筛选条件，可以查看其他状态的下载任务。',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.6,
                                color: Color(0xFF667085),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ListView.separated(
                        itemCount: filteredTasks.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final task = filteredTasks[index];
                          return _NasDownloadTaskTile(
                            task: task,
                            onDelete: () => _confirmDeleteDownloadTask(task),
                          );
                        },
                      ),
                    if (_downloadLoading)
                      const Positioned.fill(
                        child: ColoredBox(
                          color: Color(0x66FFFFFF),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NasMenuCard extends StatelessWidget {
  const _NasMenuCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: Color(0xFF667085),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 18,
                color: Color(0xFF98A2B3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NasEntryTile extends StatelessWidget {
  const _NasEntryTile({
    required this.entry,
    required this.onTap,
  });

  final NasFileEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = [
      if (entry.modifiedAtLabel != null) entry.modifiedAtLabel!,
      if (entry.sizeLabel != null && !entry.isDirectory) entry.sizeLabel!,
    ];

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: entry.isDirectory ? onTap : null,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: entry.isDirectory
                      ? const Color(0xFFFFF7ED)
                      : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  entry.isDirectory
                      ? Icons.folder_rounded
                      : Icons.insert_drive_file_rounded,
                  color: entry.isDirectory
                      ? const Color(0xFFEA580C)
                      : const Color(0xFF2563EB),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name.isEmpty ? '未命名' : entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                    if (subtitleParts.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitleParts.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (entry.isDirectory)
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF94A3B8),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NasDownloadTaskTile extends StatelessWidget {
  const _NasDownloadTaskTile({
    required this.task,
    required this.onDelete,
  });

  final NasDownloadTask task;
  final VoidCallback onDelete;

  Color get _statusColor {
    switch (task.status) {
      case 'downloading':
        return const Color(0xFF2563EB);
      case 'finished':
      case 'seeding':
        return const Color(0xFF10B981);
      case 'paused':
      case 'waiting':
        return const Color(0xFFF59E0B);
      case 'error':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFF64748B);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtitleParts = [
      if (task.downloadedLabel != null && task.sizeLabel != null)
        '${task.downloadedLabel} / ${task.sizeLabel}',
      if (task.speedLabel != null) task.speedLabel!,
      if (task.destination != null && task.destination!.isNotEmpty)
        task.destination!,
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF3),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.download_for_offline_rounded,
              color: Color(0xFF10B981),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        task.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF111827),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      tooltip: '删除任务',
                      onPressed: onDelete,
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        task.statusLabel,
                        style: TextStyle(
                          color: _statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '类型：${task.type}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF667085),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitleParts.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitleParts.join(' · '),
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: Color(0xFF667085),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
