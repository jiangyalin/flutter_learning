import '../models/nas_models.dart';

abstract class NasClient {
  void setProgressListener(void Function(String message)? listener);

  Future<List<NasFileEntry>> login({
    required String username,
    required String password,
    required String path,
  });

  Future<List<NasFileEntry>?> restoreSession({required String path});

  Future<List<NasFileEntry>> listDirectory({required String path});

  Future<List<NasDownloadTask>> listDownloadTasks();

  Future<void> createFolder({
    required String parentPath,
    required String folderName,
  });

  Future<void> createDownloadTask({
    required String destination,
    required String url,
  });

  Future<void> deleteDownloadTask({required String taskId});

  Future<void> logout();
}
