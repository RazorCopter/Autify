import 'dart:async';

/// Implementazione in-memory per ambienti non-browser (Dart VM, widget testing, CI headless).
final Map<String, String> _mockLocalStorage = {};
final Map<String, String> _mockSessionStorage = {};
final List<Map<String, dynamic>> _dispatchedEvents = [];
final List<Map<String, dynamic>> _downloadedFiles = [];

String? localStorageGet(String key) => _mockLocalStorage[key];

void localStorageSet(String key, String value) {
  _mockLocalStorage[key] = value;
}

void localStorageRemove(String key) {
  _mockLocalStorage.remove(key);
}

String? sessionStorageGet(String key) => _mockSessionStorage[key];

void sessionStorageSet(String key, String value) {
  _mockSessionStorage[key] = value;
}

void sessionStorageRemove(String key) {
  _mockSessionStorage.remove(key);
}

void sessionStorageClear() {
  _mockSessionStorage.clear();
}

void downloadFile(List<int> bytes, String filename, {String mimeType = 'application/octet-stream'}) {
  _downloadedFiles.add({
    'filename': filename,
    'bytes': bytes,
    'mimeType': mimeType,
  });
}

void downloadDataUrl(String dataUrl, String filename) {
  _downloadedFiles.add({
    'filename': filename,
    'dataUrl': dataUrl,
  });
}

void dispatchCustomEvent(String name, {dynamic detail}) {
  _dispatchedEvents.add({
    'name': name,
    'detail': detail,
  });
}

void reloadWindow(String path) {
  // No-op in test environment
}

String getCurrentPath() => '/';

/// Utility per ispezionare o azzerare lo stato durante i test unitari
void clearMockStorage() {
  _mockLocalStorage.clear();
  _mockSessionStorage.clear();
  _dispatchedEvents.clear();
  _downloadedFiles.clear();
}

List<Map<String, dynamic>> getDownloadedFiles() => List.unmodifiable(_downloadedFiles);
List<Map<String, dynamic>> getDispatchedEvents() => List.unmodifiable(_dispatchedEvents);
