import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';

class ClientLoader<T> extends StatefulWidget {
  const ClientLoader({
    super.key,
    required this.load,
    required this.builder,
    this.onSkipOnError,
  });
  final Future<T> Function() load;
  final Widget Function(T value) builder;
  final VoidCallback? onSkipOnError;
  @override
  State<ClientLoader<T>> createState() => _ClientLoaderState<T>();
}

class _ClientLoaderState<T> extends State<ClientLoader<T>> {
  late Future<T> _future = widget.load();
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const LoadingView();
      }
      if (snapshot.hasError) {
        final error = ErrorView(
          error: snapshot.error is ApiException
              ? snapshot.error as ApiException
              : const ApiException(
                  kind: ApiErrorKind.invalidResponse,
                  message: 'This information could not be loaded.',
                ),
          onRetry: () => setState(() => _future = widget.load()),
        );
        if (widget.onSkipOnError == null) return error;
        return Column(
          children: [
            Expanded(child: error),
            TextButton(
              onPressed: widget.onSkipOnError,
              child: const Text('Skip for now'),
            ),
          ],
        );
      }
      return widget.builder(snapshot.data as T);
    },
  );
}

class ClientFormLayout extends StatelessWidget {
  const ClientFormLayout({
    super.key,
    required this.title,
    required this.children,
  });
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    ),
  );
}

class ClientErrorNotice extends StatelessWidget {
  const ClientErrorNotice({super.key, required this.error});
  final ApiException? error;
  @override
  Widget build(BuildContext context) => error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Semantics(
            liveRegion: true,
            child: Text(
              [error!.message, ...error!.fieldErrors.values.toSet()].join('\n'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        );
}
