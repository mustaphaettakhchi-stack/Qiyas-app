import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../data/app_state.dart';

/// Demande à l'utilisateur de prendre ou choisir des photos, puis les copie
/// dans le stockage durable de l'application. Renvoie les chemins conservés.
Future<List<String>> pickPhotos(BuildContext context, {bool multiple = true}) async {
  final state = context.read<AppState>();
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.photo_camera_outlined),
          title: const Text('Prendre une photo'),
          onTap: () => Navigator.pop(c, ImageSource.camera),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: const Text('Choisir dans la galerie'),
          onTap: () => Navigator.pop(c, ImageSource.gallery),
        ),
      ]),
    ),
  );
  if (source == null) return [];
  final picker = ImagePicker();
  final List<XFile> files;
  if (source == ImageSource.gallery && multiple) {
    files = await picker.pickMultiImage(maxWidth: 1600, imageQuality: 72);
  } else {
    final f = await picker.pickImage(source: source, maxWidth: 1600, imageQuality: 72);
    files = f == null ? [] : [f];
  }
  final kept = <String>[];
  for (final f in files) {
    kept.add(await state.store.keepPhoto(f.path, state.newId()));
  }
  return kept;
}

class PhotoStrip extends StatelessWidget {
  const PhotoStrip({super.key, required this.paths});
  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    if (paths.isEmpty) {
      return Text('Aucune photo pour l\'instant.', style: Theme.of(context).textTheme.bodySmall);
    }
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (final p in paths)
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(p),
            width: 72,
            height: 72,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox(width: 72, height: 72, child: Icon(Icons.broken_image_outlined)),
          ),
        ),
    ]);
  }
}
