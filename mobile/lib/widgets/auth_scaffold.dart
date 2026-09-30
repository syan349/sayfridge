import 'package:flutter/material.dart';

import 'app_background.dart';
import 'page_scroll_fade.dart';

class AuthScaffold extends StatelessWidget {
  const AuthScaffold({required this.child, this.title, super.key});

  final Widget child;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: [
              if (title == null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12, top: 4),
                    child: _BackButton(),
                  ),
                )
              else
                SizedBox(
                  height: 56,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.only(left: 12),
                          child: _BackButton(),
                        ),
                      ),
                      IgnorePointer(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 60),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                title!,
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineMedium,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(child: PageScrollFade(child: child)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('back-button'),
      onPressed: () => Navigator.of(context).maybePop(),
      icon: const Icon(Icons.arrow_back_ios_new_rounded),
      tooltip: 'Back',
    );
  }
}
