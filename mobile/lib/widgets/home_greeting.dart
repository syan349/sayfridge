import 'dart:async';

import 'package:flutter/material.dart';

import 'inventory_visuals.dart';

/// A device-local greeting that refreshes at minute boundaries and on resume.
class HomeGreeting extends StatefulWidget {
  const HomeGreeting({this.now, super.key});

  /// Defaults to the device clock; callers can supply a clock for previews/tests.
  final DateTime Function()? now;

  @override
  State<HomeGreeting> createState() => _HomeGreetingState();
}

class _HomeGreetingState extends State<HomeGreeting>
    with WidgetsBindingObserver {
  Timer? _timer;
  late _GreetingPeriod _period;

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final now = _now;
    _period = _GreetingPeriod.at(now);
    _scheduleUpdate(now);
  }

  void _scheduleUpdate(DateTime now) {
    _timer?.cancel();
    final elapsed = Duration(
      seconds: now.second,
      milliseconds: now.millisecond,
      microseconds: now.microsecond,
    );
    _timer = Timer(const Duration(minutes: 1) - elapsed, _refresh);
  }

  void _refresh() {
    final now = _now;
    final period = _GreetingPeriod.at(now);
    if (period != _period) setState(() => _period = period);
    _scheduleUpdate(now);
  }

  @override
  void didUpdateWidget(HomeGreeting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.now != oldWidget.now) _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(
      context,
    ).style.copyWith(fontSize: 29, fontWeight: FontWeight.w600, height: 1.1);
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    );
    double widthOf(String text) {
      painter.text = TextSpan(text: text, style: style);
      painter.layout();
      return painter.width;
    }

    final prefixWidth = widthOf('Good ');
    final underlineWidth = widthOf(_period.word) + 4;
    painter.dispose();

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Good ${_period.word}', style: style),
          Padding(
            padding: EdgeInsets.only(left: prefixWidth, top: 2),
            child: Image.asset(
              _period.underline,
              width: underlineWidth,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              excludeFromSemantics: true,
            ),
          ),
        ],
      ),
    );
  }
}

enum _GreetingPeriod {
  morning('morning!', HomeAssets.morningLine),
  afternoon('afternoon!', HomeAssets.titleLine),
  evening('evening!', HomeAssets.eveningLine);

  const _GreetingPeriod(this.word, this.underline);

  final String word;
  final String underline;

  static _GreetingPeriod at(DateTime time) {
    if (time.hour >= 5 && time.hour < 12) return morning;
    if (time.hour >= 12 && time.hour < 17) return afternoon;
    return evening;
  }
}
