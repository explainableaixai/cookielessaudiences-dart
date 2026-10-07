import 'package:cookielessaudiences/cookielessaudiences.dart';
import 'package:test/test.dart';

void main() {
  test('labelsFor resolves codes and keeps unknown ones', () {
    final r = {
      'interests': {'tier1': ['INT.a']},
      'purchase_intent': {'codes': ['PI.b', 'PI.c']},
      'labels': {'INT.a': 'A', 'PI.b': 'B'},
    };
    expect(CookielessAudiences.labelsFor(r), ['A', 'B', 'PI.c']);
  });
}
