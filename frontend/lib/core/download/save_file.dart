import 'save_file_stub.dart' if (dart.library.js_interop) 'save_file_web.dart';

/// Отдаёт файл пользователю: в браузере — обычное скачивание.
Future<void> saveFile(String name, List<int> bytes, String mime) =>
    saveFileImpl(name, bytes, mime);
