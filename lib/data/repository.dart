/// Veri erişimi: asset yükleme (egzersiz/program kataloğu) + uygulama
/// durumunun yerel JSON dosyasına kalıcılaştırılması.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/models.dart';

class Repository {
  List<Exercise> _exercises = [];
  List<Map<String, dynamic>> _builtinPrograms = [];
  File? _stateFile;

  List<Exercise> get exercises => _exercises;
  List<Map<String, dynamic>> get builtinPrograms => _builtinPrograms;

  Future<void> init() async {
    final exRaw = await rootBundle.loadString('assets/exercises.json');
    _exercises = (jsonDecode(exRaw) as List)
        .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
        .toList();
    final progRaw = await rootBundle.loadString('assets/programs.json');
    _builtinPrograms = (jsonDecode(progRaw) as List).cast<Map<String, dynamic>>();

    final dir = await getApplicationDocumentsDirectory();
    _stateFile = File(p.join(dir.path, 'anatoly_state.json'));
  }

  Future<Map<String, dynamic>?> loadState() async {
    try {
      if (_stateFile != null && await _stateFile!.exists()) {
        final raw = await _stateFile!.readAsString();
        if (raw.trim().isEmpty) return null;
        return jsonDecode(raw) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Future<void> saveState(Map<String, dynamic> json) async {
    if (_stateFile == null) return;
    try {
      final encoded = jsonEncode(json);
      // atomik yazım: önce tmp'ye yaz, sonra rename (yarım/bozuk dosya riskini önler)
      final tmp = File('${_stateFile!.path}.tmp');
      await tmp.writeAsString(encoded, flush: true);
      await tmp.rename(_stateFile!.path);
    } catch (e, st) {
      // serileştirme/IO hatası: sessiz kalma — logla (state kaybı görünür olsun)
      // ignore: avoid_print
      print('Anatoly: durum kaydedilemedi: $e\n$st');
    }
  }
}
