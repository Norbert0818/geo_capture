import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

class AuthShell extends StatelessWidget {
  const AuthShell({
    super.key,
    required this.locale,
    required this.onLocaleChanged,
    required this.child,
    this.enabled = true,
  });

  final Locale locale;
  final ValueChanged<Locale> onLocaleChanged;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      Text(t.appTitle, style: theme.textTheme.titleLarge),
                      Tooltip(
                        message: t.language,
                        child: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'en', label: Text('EN')),
                            ButtonSegment(value: 'ro', label: Text('RO')),
                          ],
                          selected: {locale.languageCode},
                          showSelectedIcon: false,
                          onSelectionChanged: enabled
                              ? (values) =>
                                    onLocaleChanged(Locale(values.single))
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Card(
                    margin: EdgeInsets.zero,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                      side: BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: child,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
