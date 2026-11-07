import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/platform/android_file_picker.dart';
import '../../client/data/select_photo.dart';
import '../../client/domain/client_photo.dart';
import '../data/community_repository.dart';
import '../domain/community_models.dart';
import 'community_access.dart';

class CommunityPostEditor extends StatefulWidget {
  const CommunityPostEditor({super.key, required this.repository, this.post});
  final CommunityRepository repository;
  final CommunityPost? post;
  @override
  State<CommunityPostEditor> createState() => _CommunityPostEditorState();
}

class _CommunityPostEditorState extends State<CommunityPostEditor> {
  late final _text = TextEditingController(text: widget.post?.text ?? '');
  late String _type = widget.post?.type ?? 'TEXT';
  CommunityMedia? _media;
  bool _busy = false,
      _uncertain = false,
      _uploadUncertain = false,
      _saved = false;
  String? _error;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<ClientPhoto?> _choose() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final result = await pickAndroidFile();
      if (result == null) return null;
      return ClientPhoto.fromBytes(result.name, result.bytes);
    }
    if (kIsWeb) return selectPhoto();
    final controller = TextEditingController();
    final path = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose an image'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Local file path'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Choose'),
          ),
        ],
      ),
    );
    // Keep the controller alive through the dialog's closing animation.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (path == null || path.isEmpty) return null;
    return selectPhoto(path: path);
  }

  Future<void> _upload() async {
    if (_busy || _uncertain || _uploadUncertain || _saved) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    var uploading = false;
    try {
      final photo = await _choose();
      if (photo == null || !mounted) return;
      uploading = true;
      final media = await widget.repository.upload(photo);
      if (mounted) setState(() => _media = media);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Image upload: ${communityErrorMessage(error)}';
          _uploadUncertain = uploading && uncertainCommunityOperation(error);
        });
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.message ?? 'Image selection is unavailable.',
        );
      }
    } on MissingPluginException {
      if (mounted) {
        setState(
          () => _error = 'Image selection is unavailable on this build.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy || _uncertain || _saved) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.post == null) {
        await widget.repository.create(
          type: _type,
          text: _text.text,
          mediaPublicId: _media?.publicId,
        );
      } else {
        await widget.repository.update(
          widget.post!,
          text: _text.text,
          mediaPublicId: _media?.publicId,
        );
      }
      if (mounted) {
        _saved = true;
        Navigator.pop(context, true);
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = communityErrorMessage(error);
          _uncertain = uncertainCommunityOperation(error);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => CommunityAccess(
    repository: widget.repository,
    child: PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.post == null ? 'Create post' : 'Edit post'),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (widget.post == null)
                  DropdownButtonFormField<String>(
                    initialValue: _type,
                    decoration: const InputDecoration(labelText: 'Post type'),
                    items: const [
                      DropdownMenuItem(value: 'TEXT', child: Text('Text')),
                      DropdownMenuItem(value: 'IMAGE', child: Text('Image')),
                    ],
                    onChanged: _busy || _uncertain
                        ? null
                        : (value) => setState(() => _type = value!),
                  )
                else
                  Text('Post type: $_type'),
                const SizedBox(height: 16),
                TextField(
                  controller: _text,
                  enabled: !_busy && !_uncertain,
                  maxLines: 8,
                  maxLength: 5000,
                  decoration: const InputDecoration(
                    labelText: 'Post text',
                    alignLabelWithHint: true,
                  ),
                ),
                const Text(
                  'JPEG, PNG, or WebP, up to 5 MB. Uploading an image does not publish the post.',
                ),
                if (widget.post?.mediaUrl != null)
                  const Text(
                    'The saved image is retained unless replaced. Removing an attached image is not supported.',
                  ),
                if (_media != null) ...[
                  const SizedBox(height: 8),
                  const Text('Image uploaded and ready to attach.'),
                  SelectableText(_media!.url),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _busy || _uncertain || _uploadUncertain || _saved
                        ? null
                        : _upload,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(
                      _media != null || widget.post?.mediaUrl != null
                          ? 'Upload replacement image'
                          : 'Choose and upload image',
                    ),
                  ),
                ),
                if (_error != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_uploadUncertain)
                  const Text(
                    'The upload result is unknown. This API cannot recover an unattached image. Another upload is blocked in this draft; any previously confirmed image remains selected. Saving text without a new image is still possible.',
                  ),
                if (_uncertain)
                  const Text(
                    'The save result could not be confirmed. Go back and check My posts before trying another save.',
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy || _uncertain ? null : _save,
                  child: Text(_busy ? 'Please wait…' : 'Save post'),
                ),
                const Text(
                  'Leaving this editor discards this draft. Uploaded files may remain stored if the post is not saved.',
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
