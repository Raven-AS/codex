import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/platform/android_file_picker.dart';
import '../data/client_repository.dart';
import '../data/select_photo.dart';
import '../domain/client_photo.dart';
import 'client_widgets.dart';

class PhotoEditor extends StatefulWidget {
  const PhotoEditor({
    super.key,
    required this.repository,
    required this.photo,
    required this.onChanged,
    this.onContinue,
  }) : upload = null,
       remove = null,
       title = 'Profile photo';

  const PhotoEditor.forUpload({
    super.key,
    required this.upload,
    required this.remove,
    required this.photo,
    required this.onChanged,
    this.title = 'Profile photo',
    this.onContinue,
  }) : repository = null;
  final ClientRepository? repository;
  final Future<String?> Function(ClientPhoto photo)? upload;
  final Future<String?> Function()? remove;
  final String title;
  final String? photo;
  final Future<void> Function() onChanged;
  final VoidCallback? onContinue;
  @override
  State<PhotoEditor> createState() => _PhotoEditorState();
}

class _PhotoEditorState extends State<PhotoEditor> {
  ClientPhoto? _selected;
  late String? _current = widget.photo;
  bool _busy = false;
  bool _needsRefresh = false;
  ApiException? _error;
  String? _message;

  @override
  void didUpdateWidget(covariant PhotoEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photo != widget.photo) _current = widget.photo;
  }

  Future<void> _refresh() async {
    await widget.onChanged();
    if (!mounted) return;
    setState(() {
      _needsRefresh = false;
      _selected = null;
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } on PlatformException catch (e) {
      if (mounted) {
        setState(
          () => _error = ApiException(
            kind: ApiErrorKind.unsupported,
            message: e.message ?? 'Photo selection is unavailable.',
          ),
        );
      }
    } on MissingPluginException {
      if (mounted) {
        setState(
          () => _error = const ApiException(
            kind: ApiErrorKind.unsupported,
            message: 'This build does not provide the Android document picker.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick() => _run(() async {
    ClientPhoto? result;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final selected = await pickAndroidFile();
      if (selected == null) return;
      result = ClientPhoto.fromBytes(selected.name, selected.bytes);
    } else if (kIsWeb) {
      result = await selectPhoto();
    } else {
      final path = await showDialog<String>(
        context: context,
        builder: (_) => const _PhotoPathDialog(),
      );
      if (path == null) return;
      result = await selectPhoto(path: path);
    }
    if (mounted && result != null) setState(() => _selected = result);
  });

  Future<void> _upload() => _run(() async {
    final photo = _selected;
    if (photo == null || _needsRefresh) return;
    setState(() => _needsRefresh = true);
    final url =
        await (widget.upload?.call(photo) ??
            widget.repository!.uploadPhoto(photo));
    if (!mounted) return;
    setState(() {
      _current = url;
      _selected = null;
      _message = '${widget.title} saved.';
    });
    await _refresh();
  });
  Future<void> _remove() => _run(() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${widget.title.toLowerCase()}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _needsRefresh) return;
    setState(() => _needsRefresh = true);
    final url =
        await (widget.remove?.call() ?? widget.repository!.removePhoto());
    if (!mounted) return;
    setState(() {
      _current = url;
      _selected = null;
      _message = url == null
          ? '${widget.title} removed.'
          : 'The server returned a profile photo.';
    });
    await _refresh();
  });
  @override
  Widget build(BuildContext context) => ClientFormLayout(
    title: widget.title,
    children: [
      const Text(
        'Choose a JPEG, PNG, or WebP photo up to 5 MB. Review it before uploading.',
      ),
      const SizedBox(height: 16),
      ClientErrorNotice(error: _error),
      if (_message != null) Text(_message!),
      if (_needsRefresh) ...[
        const Text(
          'Refresh the profile before another photo operation. The previous operation may have reached the server.',
        ),
        FilledButton(
          onPressed: _busy ? null : () => _run(_refresh),
          child: const Text('Refresh profile'),
        ),
      ],
      Center(
        child: SizedBox.square(
          dimension: 144,
          child: _selected != null
              ? Image.memory(
                  _selected!.bytes,
                  cacheWidth: 288,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.broken_image_outlined, size: 72),
                )
              : ProfilePhoto(url: _current),
        ),
      ),
      if (_selected != null)
        Text('Selected: ${_selected!.name}', textAlign: TextAlign.center),
      const SizedBox(height: 16),
      OutlinedButton(
        onPressed: _busy || _needsRefresh ? null : _pick,
        child: const Text('Choose photo'),
      ),
      if (_selected != null) ...[
        FilledButton(
          onPressed: _busy || _needsRefresh ? null : _upload,
          child: const Text('Upload selected photo'),
        ),
        TextButton(
          onPressed: _busy ? null : () => setState(() => _selected = null),
          child: const Text('Discard selection'),
        ),
      ],
      if (_current != null)
        TextButton(
          onPressed: _busy || _needsRefresh ? null : _remove,
          child: const Text('Remove current photo'),
        ),
      if (_busy)
        const LinearProgressIndicator(semanticsLabel: 'Updating photo'),
      if (widget.onContinue != null)
        TextButton(
          onPressed: _busy ? null : widget.onContinue,
          child: const Text('Finish onboarding'),
        ),
    ],
  );
}

class ProfilePhoto extends StatelessWidget {
  const ProfilePhoto({super.key, required this.url});
  final String? url;
  @override
  Widget build(BuildContext context) => url == null
      ? const Icon(Icons.person_outline, size: 80)
      : Image.network(
          url!,
          cacheWidth: 288,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              const Icon(Icons.broken_image_outlined, size: 80),
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : const Center(child: CircularProgressIndicator()),
        );
}

class _PhotoPathDialog extends StatefulWidget {
  const _PhotoPathDialog();
  @override
  State<_PhotoPathDialog> createState() => _PhotoPathDialogState();
}

class _PhotoPathDialogState extends State<_PhotoPathDialog> {
  final _path = TextEditingController();
  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Choose a local photo'),
    content: SizedBox(
      width: 400,
      child: TextField(
        controller: _path,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Readable file path',
          hintText: '/home/you/Pictures/photo.jpg',
        ),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _path.text),
        child: const Text('Choose'),
      ),
    ],
  );
}
