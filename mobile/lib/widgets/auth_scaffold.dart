import 'package:flutter/material.dart';

import 'app_background.dart';
import 'page_scroll_fade.dart';
import 'page_back_button.dart';

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
                    padding: const EdgeInsets.only(left: 25, top: 4),
                    child: PageBackButton(key: Key('back-button')),
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
                          padding: EdgeInsets.only(left: 25),
                          child: PageBackButton(key: Key('back-button')),
                        ),
                      ),
                      IgnorePointer(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 73),
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
