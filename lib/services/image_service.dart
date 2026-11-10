import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/image_hash.dart';

/// 撮影・選択した写真を API 送信用に縮小・圧縮する（EXIF・位置情報は削除）
class ImageService {
  final _picker = ImagePicker();

  Future<Uint8List?> pick(ImageSource source, {required int maxSide, required int quality}) async {
    final x = await _picker.pickImage(
      source: source,
      maxWidth: maxSide.toDouble(),
      maxHeight: maxSide.toDouble(),
      imageQuality: 95,
    );
    if (x == null) return null;

    Uint8List? out;
    try {
      // 長辺は image_picker で maxSide 以下に縮小済み。ここで JPEG 再圧縮と EXIF 削除を行う
      out = await FlutterImageCompress.compressWithFile(
        x.path,
        minWidth: maxSide,
        minHeight: maxSide,
        quality: quality,
        format: CompressFormat.jpeg,
        keepExif: false,
      );
    } catch (_) {
      out = null;
    }
    return out ?? await x.readAsBytes();
  }

  /// 圧縮後の画像をサムネイルとしてアプリ専用領域に保存する
  static Future<String> saveThumb(Uint8List bytes) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'photos'));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, '${DateTime.now().millisecondsSinceEpoch}.jpg'));
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// 写真の dHash（写真の再利用判定用）。失敗したら null
  static Future<String?> photoHash(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 9, targetHeight: 8);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      frame.image.dispose();
      codec.dispose();
      if (data == null) return null;
      return dHashFromGray(grayFromRgba(data.buffer.asUint8List()));
    } catch (_) {
      return null;
    }
  }

  static Future<void> deleteFile(String? path) async {
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

/// 画像バイト列の先頭から media_type を判定
String mediaTypeOf(Uint8List bytes) {
  if (bytes.length >= 4 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
    return 'image/png';
  }
  if (bytes.length >= 12 && bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
    return 'image/webp';
  }
  return 'image/jpeg';
}
