/// Evaluates Harlowe expressions and manages story variables.
///
/// Supports:
/// - Variable access and assignment
/// - Comparison operators (>, <, >=, <=, is, is not)
/// - Boolean logic (and, or, not)
/// - Array operations (contains, does not contain)
/// - Arithmetic operations (+, -, *, /)
class HarloweEvaluator {
  /// The current story variables.
  final Map<String, dynamic> variables;

  /// Creates a new evaluator with the given initial variables.
  HarloweEvaluator(this.variables);

  /// Evaluates a Harlowe expression like "$time >= 900" or "$suspicion < 40"
  bool evaluateExpression(String expression) {
    final trimmed = expression.trim();

    // Handle "not" expressions
    if (trimmed.startsWith('not ')) {
      return !evaluateExpression(trimmed.substring(4));
    }

    // Strip outer parentheses if present (for grouped expressions)
    if (trimmed.startsWith('(') && trimmed.endsWith(')')) {
      // Check if these are balanced outer parentheses
      int depth = 0;
      bool isWrapped = true;
      for (int i = 0; i < trimmed.length - 1; i++) {
        if (trimmed[i] == '(') depth++;
        if (trimmed[i] == ')') depth--;
        if (depth == 0 && i > 0) {
          isWrapped = false;
          break;
        }
      }
      if (isWrapped) {
        return evaluateExpression(trimmed.substring(1, trimmed.length - 1));
      }
    }

    // Handle compound expressions with "and"
    if (trimmed.contains(' and ')) {
      final parts = trimmed.split(' and ');
      return parts.every((part) => evaluateExpression(part.trim()));
    }

    // Handle compound expressions with "or"
    if (trimmed.contains(' or ')) {
      final parts = trimmed.split(' or ');
      return parts.any((part) => evaluateExpression(part));
    }

    // Handle comparison operators - try word-based operators first (with required spaces),
    // then fall back to symbol operators (with optional spaces)
    // Word operators need spaces to avoid matching inside variable names like "suspicionRaisedPassages"
    final wordOperatorPattern = RegExp(
      r'(.+?)\s+(does not contain|is not|is|contains)\s+(.+)',
    );
    // Symbol operators can have optional spaces around them
    final symbolOperatorPattern = RegExp(r'(.+?)\s*(>=|<=|>|<)\s*(.+)');

    // Try word operators first (they're more specific)
    var match = wordOperatorPattern.firstMatch(trimmed);
    match ??= symbolOperatorPattern.firstMatch(trimmed);

    if (match != null) {
      final leftSide = match.group(1)!.trim();
      final operator = match.group(2)!;
      final rightSide = match.group(3)!.trim();

      // For contains operators, get raw variable value (could be List)
      if (operator == 'contains' || operator == 'does not contain') {
        final searchValue = rightSide.replaceAll('"', '');
        // Get raw variable value for arrays
        final rawValue = _getRawVariableValue(leftSide);
        bool containsValue;
        if (rawValue is List) {
          containsValue = rawValue.any(
            (item) => item.toString() == searchValue,
          );
        } else {
          // Handle string contains check
          containsValue = rawValue.toString().contains(searchValue);
        }
        return operator == 'contains' ? containsValue : !containsValue;
      }

      // For 'is' and 'is not', we want to compare the raw value, not just numeric
      if (operator == 'is' || operator == 'is not') {
        final leftRaw = _getRawVariableValue(leftSide);
        final rightRaw = rightSide.replaceAll('"', '');
        // Try numeric comparison first
        final leftNum = _toNumber(leftRaw);
        final rightNum = num.tryParse(rightRaw);
        if (leftNum != null && rightNum != null) {
          return operator == 'is' ? leftNum == rightNum : leftNum != rightNum;
        }
        // Fall back to string comparison
        return operator == 'is'
            ? leftRaw.toString() == rightRaw
            : leftRaw.toString() != rightRaw;
      }

      // Evaluate left side - could be a variable or an expression
      final leftValue = _evaluateNumericExpression(leftSide);
      if (leftValue == null) return false;

      switch (operator) {
        case '>=':
          return _compareNumeric(leftValue, rightSide, (a, b) => a >= b);
        case '<=':
          return _compareNumeric(leftValue, rightSide, (a, b) => a <= b);
        case '>':
          return _compareNumeric(leftValue, rightSide, (a, b) => a > b);
        case '<':
          return _compareNumeric(leftValue, rightSide, (a, b) => a < b);
        default:
          return false;
      }
    }

    // Handle simple boolean variables
    final boolPattern = RegExp(r'\$?(\w+)');
    final boolMatch = boolPattern.firstMatch(trimmed);
    if (boolMatch != null) {
      final varName = boolMatch.group(1)!;
      final value = variables[varName];
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) return value.isNotEmpty;
      return value != null;
    }

    return false;
  }

  bool _compareNumeric(
    dynamic leftValue,
    String rightSide,
    bool Function(num, num) compare,
  ) {
    final left = _toNumber(leftValue);
    final right = _evaluateNumericExpression(rightSide);

    if (left == null || right == null) return false;
    return compare(left, right);
  }

  num? _toNumber(dynamic value) {
    if (value is num) return value;
    if (value is String) {
      return num.tryParse(value);
    }
    return null;
  }

  /// Gets the raw variable value without any conversion (for arrays, strings, etc.)
  dynamic _getRawVariableValue(String expr) {
    final trimmed = expr.trim();
    if (trimmed.startsWith('\$')) {
      final varName = trimmed.substring(1);
      return variables[varName];
    }
    // If wrapped in parentheses like ($evidence), strip them
    if (trimmed.startsWith('(\$') && trimmed.endsWith(')')) {
      final varName = trimmed.substring(2, trimmed.length - 1);
      return variables[varName];
    }
    return trimmed;
  }

  /// Evaluates numeric expressions like ($time - 960) or simple numbers
  num? _evaluateNumericExpression(String expr) {
    final trimmed = expr.trim();

    // Handle parenthetical expressions like ($time - 960)
    final exprPattern = RegExp(r'\(\$(\w+)\s*([+\-*/])\s*(\d+)\)');
    final exprMatch = exprPattern.firstMatch(trimmed);
    if (exprMatch != null) {
      final varName = exprMatch.group(1)!;
      final operator = exprMatch.group(2)!;
      final operand = int.parse(exprMatch.group(3)!);
      final varValue = variables[varName];

      if (varValue is num) {
        switch (operator) {
          case '+':
            return varValue + operand;
          case '-':
            return varValue - operand;
          case '*':
            return varValue * operand;
          case '/':
            return varValue / operand;
        }
      }
      return null;
    }

    // Handle simple variable references
    if (trimmed.startsWith('\$')) {
      final varName = trimmed.substring(1);
      final value = variables[varName];
      return _toNumber(value);
    }

    // Handle plain numbers
    return num.tryParse(trimmed);
  }

  /// Updates a variable value.
  void setVariable(String name, dynamic value) {
    variables[name] = value;
  }

  /// Parses a (set:...) command and updates variables.
  void executeSetCommand(String command) {
    // Pattern: $varName to value
    final pattern = RegExp(r'\$?(\w+)\s+to\s+(.+)');
    final match = pattern.firstMatch(command);

    if (match != null) {
      final varName = match.group(1)!;
      final valueStr = match.group(2)!.trim();

      // Handle array concatenation: $array + (a: "item1", "item2")
      final arrayConcatPattern = RegExp(
        r'\$(\w+)\s*\+\s*\(a:\s*(.+?)\)\s*$',
        dotAll: true,
      );
      final concatMatch = arrayConcatPattern.firstMatch(valueStr);
      if (concatMatch != null) {
        final sourceVar = concatMatch.group(1)!;
        final itemsStr = concatMatch.group(2)!;

        // Get existing array or create new one
        final existingArray = variables[sourceVar];
        final List<dynamic> currentList =
            existingArray is List ? List.from(existingArray) : [];

        // Parse items from (a: ...) - handle quoted strings
        final items = <String>[];
        final itemPattern = RegExp(r'"([^"]*)"');
        for (var itemMatch in itemPattern.allMatches(itemsStr)) {
          items.add(itemMatch.group(1)!);
        }

        // Add new items to array
        currentList.addAll(items);
        setVariable(varName, currentList);
        return;
      }

      // Handle data map concatenation: $map + (dm: "key1", "value1", "key2", "value2")
      final dmConcatPattern = RegExp(
        r'\$(\w+)\s*\+\s*\(dm:\s*(.+?)\)\s*$',
        dotAll: true,
      );
      final dmMatch = dmConcatPattern.firstMatch(valueStr);
      if (dmMatch != null) {
        final sourceVar = dmMatch.group(1)!;
        final pairsStr = dmMatch.group(2)!;

        // Get existing map or create new one
        final existingMap = variables[sourceVar];
        final Map<String, dynamic> currentMap =
            existingMap is Map ? Map<String, dynamic>.from(existingMap) : {};

        // Parse key-value pairs from (dm: "key", "value", ...)
        final items = <String>[];
        final itemPattern = RegExp(r'"([^"]*)"');
        for (var itemMatch in itemPattern.allMatches(pairsStr)) {
          items.add(itemMatch.group(1)!);
        }

        // Add pairs to map (key1, value1, key2, value2, ...)
        for (var i = 0; i < items.length - 1; i += 2) {
          currentMap[items[i]] = items[i + 1];
        }

        setVariable(varName, currentMap);
        return;
      }

      // Handle array constructor (a:) - with or without initial values
      if (valueStr.startsWith('(a:')) {
        // Check if it's (a:) with values like (a: "item1", "item2")
        final arrayWithValuesMatch = RegExp(
          r'\(a:\s*(.+?)\s*\)$',
          dotAll: true,
        ).firstMatch(valueStr);
        
        if (arrayWithValuesMatch != null) {
          final itemsStr = arrayWithValuesMatch.group(1)!;
          final items = <String>[];
          final itemPattern = RegExp(r'"([^"]*)"');
          for (var itemMatch in itemPattern.allMatches(itemsStr)) {
            items.add(itemMatch.group(1)!);
          }
          if (items.isNotEmpty) {
            setVariable(varName, items);
            return;
          }
        }
        // Empty array if no items found
        setVariable(varName, []);
        return;
      }

      // Handle data map constructor (dm:)
      if (valueStr.startsWith('(dm:')) {
        setVariable(varName, {}); // Empty map
        return;
      }

      // Try to parse as number
      final numValue = num.tryParse(valueStr);
      if (numValue != null) {
        setVariable(varName, numValue);
        return;
      }

      // Check for boolean
      if (valueStr == 'true') {
        setVariable(varName, true);
        return;
      }
      if (valueStr == 'false') {
        setVariable(varName, false);
        return;
      }

      // Handle string (remove quotes)
      setVariable(varName, valueStr.replaceAll('"', '').replaceAll("'", ''));
    }
  }

  /// Parses a (set:...) command with arithmetic operations.
  void executeArithmeticSet(String command) {
    // Pattern: (set: $varName to $varName + value)
    final pattern = RegExp(r'\$(\w+)\s+to\s+\$(\w+)\s*([+\-*/])\s*(\d+)');
    final match = pattern.firstMatch(command);

    if (match != null) {
      final varName = match.group(1)!;
      final sourceVar = match.group(2)!;
      final operator = match.group(3)!;
      final operand = num.parse(match.group(4)!);

      final currentValue = _toNumber(variables[sourceVar]) ?? 0;

      num newValue;
      switch (operator) {
        case '+':
          newValue = currentValue + operand;
          break;
        case '-':
          newValue = currentValue - operand;
          break;
        case '*':
          newValue = currentValue * operand;
          break;
        case '/':
          newValue = currentValue / operand;
          break;
        default:
          return;
      }

      setVariable(varName, newValue);
    }
  }
}
