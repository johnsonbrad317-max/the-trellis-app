import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trellis/widgets/bookplate_date_picker.dart';

/// Hosts a button that opens the picker and records what it resolved to.
Widget _host(void Function(BuildContext) onTap) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: GestureDetector(
              onTap: () => onTap(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

Finder _day(int year, int month, int day) =>
    find.byKey(ValueKey('bookplate-day-$year-$month-$day'));

void main() {
  // A fixed mid-month window so every case is independent of today's date.
  final initial = DateTime(2030, 6, 15);
  final first = DateTime(2030, 6, 10);
  final last = DateTime(2030, 7, 20);

  Future<void> open(WidgetTester tester, void Function(DateTime?) onResult) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host((context) async {
      onResult(await showBookplateDatePicker(
        context,
        initialDate: initial,
        firstDate: first,
        lastDate: last,
      ));
    }));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('Set returns the initial selection', (tester) async {
    DateTime? result;
    var resolved = false;
    await open(tester, (value) {
      result = value;
      resolved = true;
    });

    expect(find.text('Choose a Date'), findsOneWidget);
    expect(find.text('June 2030'), findsOneWidget);

    await tester.tap(find.text('Set'));
    await tester.pumpAndSettle();
    expect(resolved, isTrue);
    expect(result, DateTime(2030, 6, 15));
  });

  testWidgets('tapping another day then Set returns that day', (tester) async {
    DateTime? result;
    await open(tester, (value) => result = value);

    await tester.tap(_day(2030, 6, 22));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set'));
    await tester.pumpAndSettle();
    expect(result, DateTime(2030, 6, 22));
  });

  testWidgets('a day outside the range cannot be selected', (tester) async {
    DateTime? result;
    await open(tester, (value) => result = value);

    // June 5 is before firstDate (June 10).
    await tester.tap(_day(2030, 6, 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set'));
    await tester.pumpAndSettle();
    expect(result, DateTime(2030, 6, 15));
  });

  testWidgets('month navigation moves between months and stops at the range', (tester) async {
    DateTime? result;
    await open(tester, (value) => result = value);

    // Forward into July, pick a day there.
    await tester.tap(find.bySemanticsLabel('Next month'));
    await tester.pumpAndSettle();
    expect(find.text('July 2030'), findsOneWidget);
    expect(find.text('June 2030'), findsNothing);

    await tester.tap(_day(2030, 7, 4));
    await tester.pumpAndSettle();

    // July 25 is after lastDate (July 20): inert.
    await tester.tap(_day(2030, 7, 25));
    await tester.pumpAndSettle();

    // No month beyond July is reachable.
    await tester.tap(find.bySemanticsLabel('Next month'));
    await tester.pumpAndSettle();
    expect(find.text('July 2030'), findsOneWidget);
    expect(find.text('August 2030'), findsNothing);

    // Back to June, and no earlier than June.
    await tester.tap(find.bySemanticsLabel('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text('June 2030'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text('June 2030'), findsOneWidget);
    expect(find.text('May 2030'), findsNothing);

    // The pick made in July survives navigating back and Set.
    await tester.tap(find.text('Set'));
    await tester.pumpAndSettle();
    expect(result, DateTime(2030, 7, 4));
  });

  testWidgets('Cancel resolves to null', (tester) async {
    DateTime? result = DateTime(2000);
    await open(tester, (value) => result = value);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
