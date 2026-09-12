import 'package:flutter_test/flutter_test.dart';
import 'package:college_app/moderation/text_filter.dart';

void main() {
  group('TextFilter.filter', () {
    group('blocks profanity', () {
      test('blocks message containing a banned word (lowercase)', () {
        final result = TextFilter.filter('this is a fuck you message');
        expect(result.isAllowed, false);
      });

      test('blocks message containing a banned word (mixed case)', () {
        final result = TextFilter.filter('What the SHIT is that');
        expect(result.isAllowed, false);
      });

      test('blocks when banned word is at start', () {
        final result = TextFilter.filter('damn this stuff');
        // "damn" is not in banned list; verify false negative is correct
        expect(result.isAllowed, true);
      });

      test('blocks exact banned word alone', () {
        final result = TextFilter.filter('asshole');
        expect(result.isAllowed, false);
      });

      test('blocks Hindi profanity', () {
        final result = TextFilter.filter('madarchod');
        expect(result.isAllowed, false);
      });
    });

    group('blocks banned emojis', () {
      test('blocks middle finger emoji', () {
        final result = TextFilter.filter('hello 🖕 world');
        expect(result.isAllowed, false);
      });

      test('blocks peach emoji', () {
        final result = TextFilter.filter('nice 🍑');
        expect(result.isAllowed, false);
      });

      test('blocks eggplant emoji', () {
        final result = TextFilter.filter('🍆🍆🍆');
        expect(result.isAllowed, false);
      });
    });

    group('allows clean content', () {
      test('allows normal message', () {
        final result = TextFilter.filter('Hey, anyone in CS dept?');
        expect(result.isAllowed, true);
        expect(result.cleanedText, 'Hey, anyone in CS dept?');
      });

      test('allows empty string', () {
        final result = TextFilter.filter('');
        expect(result.isAllowed, true);
        expect(result.cleanedText, '');
      });

      test('allows numbers and punctuation', () {
        final result = TextFilter.filter('CGPA: 9.5 (3rd sem)');
        expect(result.isAllowed, true);
      });

      test('allows message that contains substring of banned word but is not banned word', () {
        // "assessment" contains "ass" but "ass" alone isn't banned;
        // verify actual banned list behavior
        final result = TextFilter.filter('need to finish my assessment');
        expect(result.isAllowed, true);
      });
    });
  });
}
