import 'package:test/test.dart';
import 'package:twine_parser/twine_parser.dart';

void main() {
  group('HarloweEvaluator', () {
    group('evaluateExpression', () {
      test('evaluates numeric comparisons', () {
        final evaluator = HarloweEvaluator({'score': 50});

        expect(evaluator.evaluateExpression('\$score > 30'), isTrue);
        expect(evaluator.evaluateExpression('\$score < 30'), isFalse);
        expect(evaluator.evaluateExpression('\$score >= 50'), isTrue);
        expect(evaluator.evaluateExpression('\$score <= 50'), isTrue);
      });

      test('evaluates equality comparisons', () {
        final evaluator = HarloweEvaluator({'name': 'Alice', 'score': 100});

        expect(evaluator.evaluateExpression('\$name is "Alice"'), isTrue);
        expect(evaluator.evaluateExpression('\$name is not "Bob"'), isTrue);
        expect(evaluator.evaluateExpression('\$score is 100'), isTrue);
      });

      test('evaluates boolean variables', () {
        final evaluator = HarloweEvaluator({'hasKey': true, 'isDead': false});

        expect(evaluator.evaluateExpression('\$hasKey'), isTrue);
        expect(evaluator.evaluateExpression('\$isDead'), isFalse);
        expect(evaluator.evaluateExpression('not \$isDead'), isTrue);
      });

      test('evaluates compound expressions with and', () {
        final evaluator = HarloweEvaluator({'a': true, 'b': true, 'c': false});

        expect(evaluator.evaluateExpression('\$a and \$b'), isTrue);
        expect(evaluator.evaluateExpression('\$a and \$c'), isFalse);
      });

      test('evaluates compound expressions with or', () {
        final evaluator = HarloweEvaluator({'a': true, 'b': false});

        expect(evaluator.evaluateExpression('\$a or \$b'), isTrue);
        expect(evaluator.evaluateExpression('\$b or \$b'), isFalse);
      });

      test('evaluates array contains', () {
        final evaluator = HarloweEvaluator({
          'items': ['sword', 'shield', 'potion'],
        });

        expect(
            evaluator.evaluateExpression('\$items contains "sword"'), isTrue);
        expect(
          evaluator.evaluateExpression('\$items does not contain "helmet"'),
          isTrue,
        );
        expect(
          evaluator.evaluateExpression('\$items contains "helmet"'),
          isFalse,
        );
      });

      test('handles parenthetical expressions', () {
        final evaluator = HarloweEvaluator({'time': 960});

        expect(
          evaluator.evaluateExpression('(\$time - 900) >= 60'),
          isTrue,
        );
      });
    });

    group('executeSetCommand', () {
      test('sets numeric values', () {
        final evaluator = HarloweEvaluator({});
        evaluator.executeSetCommand('\$score to 100');
        expect(evaluator.variables['score'], equals(100));
      });

      test('sets string values', () {
        final evaluator = HarloweEvaluator({});
        evaluator.executeSetCommand('\$name to "Alice"');
        expect(evaluator.variables['name'], equals('Alice'));
      });

      test('sets boolean values', () {
        final evaluator = HarloweEvaluator({});
        evaluator.executeSetCommand('\$hasKey to true');
        expect(evaluator.variables['hasKey'], isTrue);
      });

      test('creates empty arrays', () {
        final evaluator = HarloweEvaluator({});
        evaluator.executeSetCommand('\$items to (a:)');
        expect(evaluator.variables['items'], equals([]));
      });

      test('creates empty data maps', () {
        final evaluator = HarloweEvaluator({});
        evaluator.executeSetCommand('\$data to (dm:)');
        expect(evaluator.variables['data'], equals({}));
      });
    });

    group('executeArithmeticSet', () {
      test('adds to variable', () {
        final evaluator = HarloweEvaluator({'score': 50});
        evaluator.executeArithmeticSet('\$score to \$score + 10');
        expect(evaluator.variables['score'], equals(60));
      });

      test('subtracts from variable', () {
        final evaluator = HarloweEvaluator({'health': 100});
        evaluator.executeArithmeticSet('\$health to \$health - 25');
        expect(evaluator.variables['health'], equals(75));
      });

      test('multiplies variable', () {
        final evaluator = HarloweEvaluator({'multiplier': 5});
        evaluator.executeArithmeticSet('\$multiplier to \$multiplier * 3');
        expect(evaluator.variables['multiplier'], equals(15));
      });
    });
  });

  group('TwineParser', () {
    test('parses a simple story', () async {
      final parser = TwineParser();
      const storyHtml = '''
        <tw-storydata>
          <tw-passagedata name="Start">
            Welcome to the story!
            [[Continue|Room 1]]
          </tw-passagedata>
          <tw-passagedata name="Room 1">
            You are in a room.
            [[Go back|Start]]
          </tw-passagedata>
        </tw-storydata>
      ''';

      await parser.parseStory(storyHtml);

      expect(parser.passages.length, equals(2));
      expect(parser.passages['Start'], isNotNull);
      expect(parser.passages['Room 1'], isNotNull);
    });

    test('extracts choices from passages', () async {
      final parser = TwineParser();
      const storyHtml = '''
        <tw-storydata>
          <tw-passagedata name="Start">
            Choose your path:
            [[Go left|Left Path]]
            [[Go right|Right Path]]
          </tw-passagedata>
          <tw-passagedata name="Left Path">Left!</tw-passagedata>
          <tw-passagedata name="Right Path">Right!</tw-passagedata>
        </tw-storydata>
      ''';

      await parser.parseStory(storyHtml);

      final startPassage = parser.passages['Start']!;
      expect(startPassage.choices.length, equals(2));
      expect(startPassage.choices[0].text, equals('Go left'));
      expect(startPassage.choices[0].targetPassage, equals('Left Path'));
    });

    test('extracts choices with arrow syntax', () async {
      final parser = TwineParser();
      const storyHtml = '''
        <tw-storydata>
          <tw-passagedata name="Start">
            Choose:
            [[Nod again.->You nod politely.]]
            [[Step back.]]
          </tw-passagedata>
          <tw-passagedata name="You nod politely.">You nodded.</tw-passagedata>
          <tw-passagedata name="Step back.">You stepped back.</tw-passagedata>
        </tw-storydata>
      ''';

      await parser.parseStory(storyHtml);

      final startPassage = parser.passages['Start']!;
      expect(startPassage.choices.length, equals(2));
      // Arrow syntax: display text is before ->, target is after
      expect(startPassage.choices[0].text, equals('Nod again.'));
      expect(startPassage.choices[0].targetPassage, equals('You nod politely.'));
      // No separator: both display and target are the same
      expect(startPassage.choices[1].text, equals('Step back.'));
      expect(startPassage.choices[1].targetPassage, equals('Step back.'));
    });

    test('getStartPassage returns Start passage', () async {
      final parser = TwineParser();
      const storyHtml = '''
        <tw-storydata>
          <tw-passagedata name="Intro">Intro</tw-passagedata>
          <tw-passagedata name="Start">Start</tw-passagedata>
        </tw-storydata>
      ''';

      await parser.parseStory(storyHtml);

      final start = parser.getStartPassage();
      expect(start.name, equals('Start'));
    });

    group('array and random macros', () {
      test('evaluates (print:) with possessive array access using random', () async {
        final parser = TwineParser();
        const storyHtml = '''
          <tw-storydata>
            <tw-passagedata name="Start">
              (set: \$response to (a: "moans", "howls", "cowers", "looms", "menaces", "seethes"))
              The figure (print: \$response's (random: 1, 6)) in response.
            </tw-passagedata>
          </tw-storydata>
        ''';

        await parser.parseStory(storyHtml);

        final startPassage = parser.passages['Start']!;
        // The content should contain one of the response words
        final possibleResponses = ['moans', 'howls', 'cowers', 'looms', 'menaces', 'seethes'];
        final containsResponse = possibleResponses.any(
          (response) => startPassage.content.contains('The figure $response in response.'),
        );
        expect(containsResponse, isTrue,
            reason: 'Content should contain one of the array values: ${startPassage.content}');
      });

      test('evaluates possessive array access with fixed index', () async {
        final parser = TwineParser();
        const storyHtml = '''
          <tw-storydata>
            <tw-passagedata name="Start">
              (set: \$items to (a: "sword", "shield", "potion"))
              You have a (print: \$items's 1).
            </tw-passagedata>
          </tw-storydata>
        ''';

        await parser.parseStory(storyHtml);

        final startPassage = parser.passages['Start']!;
        expect(startPassage.content.contains('You have a sword.'), isTrue,
            reason: 'Content: ${startPassage.content}');
      });

      test('evaluates standalone random macro in print', () async {
        final parser = TwineParser();
        const storyHtml = '''
          <tw-storydata>
            <tw-passagedata name="Start">
              You rolled a (print: (random: 1, 6))!
            </tw-passagedata>
          </tw-storydata>
        ''';

        await parser.parseStory(storyHtml);

        final startPassage = parser.passages['Start']!;
        // The content should contain a number between 1 and 6
        final match = RegExp(r'You rolled a (\d+)!').firstMatch(startPassage.content);
        expect(match, isNotNull, reason: 'Content: ${startPassage.content}');
        if (match != null) {
          final number = int.parse(match.group(1)!);
          expect(number >= 1 && number <= 6, isTrue,
              reason: 'Random number should be between 1 and 6, got $number');
        }
      });

      test('sets array variable with (a:) macro', () async {
        final parser = TwineParser();
        const storyHtml = '''
          <tw-storydata>
            <tw-passagedata name="Start">
              (set: \$response to (a: "moans", "howls", "seethes"))
              Done
              [[Continue|Next]]
            </tw-passagedata>
            <tw-passagedata name="Next">
              Test
            </tw-passagedata>
          </tw-storydata>
        ''';

        await parser.parseStory(storyHtml);

        // Get the passage with game state to capture the state changes
        final startPassage = parser.getPassage('Start', gameState: {});
        expect(startPassage, isNotNull);
        expect(startPassage!.stateChanges, isNotNull);
        expect(startPassage.stateChanges!['response'], isA<List>());
        expect(startPassage.stateChanges!['response'], 
            equals(['moans', 'howls', 'seethes']));
      });
    });
  });
}
