# twine_parser

A Dart library for parsing and evaluating Twine stories, with support for the Harlowe story format.

## Features

- Parse Twine story HTML files exported from Twine 2
- Evaluate Harlowe expressions and macros
- Variable management and state tracking
- Conditional evaluation (`(if:)`, `(else-if:)`, `(else:)`)
- Array and data map operations
- Link extraction for navigation

## Getting Started

Add `twine_parser` to your `pubspec.yaml`:

```yaml
dependencies:
  twine_parser: ^0.1.0
```

## Usage

### Basic Usage

```dart
import 'package:twine_parser/twine_parser.dart';

void main() async {
  final parser = TwineParser();
  
  // Load your Twine story HTML
  final storyHtml = await File('my_story.html').readAsString();
  await parser.parseStory(storyHtml);
  
  // Get the starting passage
  final startPassage = parser.getStartPassage();
  print('Story begins: ${startPassage.name}');
  print(startPassage.content);
  
  // Get available choices
  for (final choice in startPassage.choices) {
    print('-> ${choice.text} (leads to: ${choice.targetPassage})');
  }
}
```

### With Game State

```dart
// Create a game state map
final gameState = <String, dynamic>{
  'playerName': 'Alice',
  'score': 10,
  'inventory': ['key', 'torch'],
};

// Get a passage with the current state
final passage = parser.getPassage('Room 1', gameState: gameState);

// Apply any state changes from the passage
if (passage?.stateChanges != null) {
  gameState.addAll(passage!.stateChanges!);
}
```

### Using the Evaluator Directly

```dart
final evaluator = HarloweEvaluator({
  'score': 50,
  'hasKey': true,
  'items': ['sword', 'shield'],
});

// Evaluate expressions
print(evaluator.evaluateExpression('\$score > 30')); // true
print(evaluator.evaluateExpression('\$hasKey')); // true
print(evaluator.evaluateExpression('\$items contains "sword"')); // true

// Set variables
evaluator.executeSetCommand('\$score to 100');
evaluator.executeArithmeticSet('\$score to \$score + 10');
```

## Supported Harlowe Features

### Variables
- `$variable` - Access variable value
- `(set: $variable to value)` - Set variable

### Conditionals
- `(if: condition)[content]`
- `(else-if: condition)[content]`
- `(else:)[content]`

### Comparisons
- `is`, `is not` - Equality
- `>`, `<`, `>=`, `<=` - Numeric comparison
- `contains`, `does not contain` - Array/string membership

### Boolean Logic
- `and`, `or`, `not`

### Data Structures
- `(a: item1, item2)` - Arrays
- `(dm: "key", "value")` - Data maps

### Links
- `[[Display Text|Target]]` - Standard links
- `[[Target]]` - Links where text equals target

## License

MIT License - see [LICENSE](LICENSE) for details.
