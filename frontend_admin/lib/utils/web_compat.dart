import 'web_compat_stub.dart'
    if (dart.library.html) 'web_compat_web.dart' as platform;

/// Interfaccia astratta e unificata per la gestione delle primitive web (storage, download, navigazione)
/// compatibile sia con il browser reale (`dart:html`) sia con l'ambiente test Dart VM (`flutter test`).
class WebCompat {
  /// Legge un valore dal localStorage o storage persistente
  static String? localStorageGet(String key) => platform.localStorageGet(key);

  /// Salva un valore nel localStorage o storage persistente
  static void localStorageSet(String key, String value) => platform.localStorageSet(key, value);

  /// Rimuove una chiave dal localStorage
  static void localStorageRemove(String key) => platform.localStorageRemove(key);

  /// Legge un valore dal sessionStorage o storage di sessione
  static String? sessionStorageGet(String key) => platform.sessionStorageGet(key);

  /// Salva un valore nel sessionStorage
  static void sessionStorageSet(String key, String value) => platform.sessionStorageSet(key, value);

  /// Rimuove una chiave dal sessionStorage
  static void sessionStorageRemove(String key) => platform.sessionStorageRemove(key);

  /// Pulisce l'intero sessionStorage
  static void sessionStorageClear() => platform.sessionStorageClear();

  /// Esegue il download client-side di un buffer di byte
  static void downloadFile(List<int> bytes, String filename, {String mimeType = 'application/octet-stream'}) =>
      platform.downloadFile(bytes, filename, mimeType: mimeType);

  /// Esegue il download a partire da un data URL o stringa Base64
  static void downloadDataUrl(String dataUrl, String filename) =>
      platform.downloadDataUrl(dataUrl, filename);

  /// Notifica un evento personalizzato nella finestra/ambiente
  static void dispatchCustomEvent(String name, {dynamic detail}) =>
      platform.dispatchCustomEvent(name, detail: detail);

  /// Ricarica o reindirizza l'applicazione su un URL/path specifico
  static void reloadWindow(String path) => platform.reloadWindow(path);

  /// Ottiene il path corrente della location
  static String getCurrentPath() => platform.getCurrentPath();
}
