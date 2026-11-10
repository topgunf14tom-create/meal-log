import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

/// 端末内の文字認識（ML Kit・日本語）。通信なし・API料金なし。
/// 栄養成分表示の読み取りの「加速装置」で、読めなかったら Haiku の転記に回す。
class OcrService {
  /// 読み取った文字列。失敗したら null（その場合は呼び出し側が Haiku にフォールバックする）
  Future<String?> readText(Uint8List jpeg) async {
    File? tmp;
    TextRecognizer? recognizer;
    try {
      final dir = await getTemporaryDirectory();
      tmp = File('${dir.path}/ocr_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tmp.writeAsBytes(jpeg, flush: true);
      recognizer = TextRecognizer(script: TextRecognitionScript.japanese);
      final result = await recognizer.processImage(InputImage.fromFilePath(tmp.path));
      return result.text;
    } catch (_) {
      return null;
    } finally {
      await recognizer?.close();
      try {
        await tmp?.delete();
      } catch (_) {}
    }
  }
}
