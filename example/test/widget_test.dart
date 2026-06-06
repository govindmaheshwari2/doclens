import 'package:flutter_test/flutter_test.dart';
import 'package:doclens_example/main.dart';

void main() {
  testWidgets('Showroom home renders the masthead and first card',
      (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pump();
    expect(find.textContaining('DOCLENS'), findsOneWidget);
    expect(find.text('Drop-in scanner'), findsOneWidget);
  });
}
