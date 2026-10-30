// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:async';

/// Implementazione per il browser reale che si interfaccia direttamente con `dart:html`.

String? localStorageGet(String key) {
  try {
    return html.window.localStorage[key];
  } catch (_) {
    return null;
  }
}

void localStorageSet(String key, String value) {
  try {
    html.window.localStorage[key] = value;
  } catch (_) {}
}

void localStorageRemove(String key) {
  try {
    html.window.localStorage.remove(key);
  } catch (_) {}
}

String? sessionStorageGet(String key) {
  try {
    return html.window.sessionStorage[key];
  } catch (_) {
    return null;
  }
}

void sessionStorageSet(String key, String value) {
  try {
    html.window.sessionStorage[key] = value;
  } catch (_) {}
}

void sessionStorageRemove(String key) {
  try {
    html.window.sessionStorage.remove(key);
  } catch (_) {}
}

void sessionStorageClear() {
  try {
    html.window.sessionStorage.clear();
  } catch (_) {}
}

void downloadFile(List<int> bytes, String filename, {String mimeType = 'application/octet-stream'}) {
  try {
    final blob = html.Blob([bytes], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..click();
    Timer(const Duration(seconds: 30), () => html.Url.revokeObjectUrl(url));
  } catch (_) {}
}

void downloadDataUrl(String dataUrl, String filename) {
  try {
    html.AnchorElement(href: dataUrl)
      ..setAttribute('download', filename)
      ..click();
  } catch (_) {}
}

void dispatchCustomEvent(String name, {dynamic detail}) {
  try {
    html.window.dispatchEvent(html.CustomEvent(name, detail: detail));
  } catch (_) {}
}

void reloadWindow(String path) {
  try {
    html.window.location.href = path;
  } catch (_) {}
}

String getCurrentPath() {
  try {
    return html.window.location.pathname ?? '/';
  } catch (_) {
    return '/';
  }
}
