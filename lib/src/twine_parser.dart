import 'dart:math';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'harlowe_evaluator.dart';
import 'models/passage.dart';

/// Optional callback for debug logging.
typedef DebugLogger = void Function(String message);

/// Parses and processes Twine story HTML files.
///
/// Supports the Harlowe story format, including:
/// - Variable assignments with (set:)
/// - Conditionals with (if:), (else-if:), (else:)
/// - Print macros with (print:)
/// - Links with [[text|target]] syntax
class TwineParser {
  /// Map of passage names to parsed passages.
  Map<String, Passage> passages = {};
  final Map<String, Element> _rawPassages = {};

  /// Header content if a passage is tagged with "header".
  String? headerContent;

  /// The Harlowe expression evaluator.
  late HarloweEvaluator evaluator;

  /// Optional debug logger for tracing evaluation.
  DebugLogger? debugLogger;

  /// Whether to enable debug logging.
  bool debugMode = false;

  /// List of visited passage names for (visited:) macro evaluation.
  List<String> _visitedPassages = [];


  /// Creates a new TwineParser with optional debug settings.
  TwineParser({this.debugMode = false, this.debugLogger});

  void _debugPrint(String message) {
    if (debugMode && debugLogger != null) {
      debugLogger!(message);
    }
  }

  // Test helper methods - expose internal methods for testing
  String testEvaluateConditionals(String content) =>
      _evaluateConditionals(content);
  String testCleanContent(String content) => _cleanContent(content);

  /// Extracts individual (set:...) commands from content, properly handling nested parentheses.
  /// If topLevelOnly is true, skips set commands that are inside square brackets (conditional branches).
  List<String> _extractSetCommands(
    String content, {
    bool topLevelOnly = false,
  }) {
    final commands = <String>[];
    var index = 0;

    while (index < content.length) {
      final setIndex = content.indexOf('(set:', index);
      if (setIndex == -1) break;

      // If topLevelOnly, check if we're inside square brackets
      if (topLevelOnly) {
        int bracketDepth = 0;
        for (int i = 0; i < setIndex; i++) {
          if (content[i] == '[') bracketDepth++;
          if (content[i] == ']') bracketDepth--;
        }
        if (bracketDepth > 0) {
          // This set command is inside a conditional branch, skip it
          index = setIndex + 5;
          continue;
        }
      }

      // Count parentheses to find the matching close paren
      var parenCount = 1;
      var endIndex = setIndex + 5; // Start after '(set:'

      while (endIndex < content.length && parenCount > 0) {
        if (content[endIndex] == '(') parenCount++;
        if (content[endIndex] == ')') parenCount--;
        endIndex++;
      }

      if (parenCount == 0) {
        // Extract the set command without the (set: and )
        final command = content.substring(setIndex + 5, endIndex - 1).trim();
        commands.add(command);
      }

      index = endIndex;
    }

    return commands;
  }

  /// Executes (set:) commands in content and removes them, returning the cleaned content.
  String _executeAndRemoveSetCommands(String content) {
    // Execute all set commands in this content
    final setCommands = _extractSetCommands(content);
    for (var setCommand in setCommands) {
      // Match arithmetic with explicit variable or 'it' keyword
      final arithmeticPattern = RegExp(
        r'\$(\w+)\s+to\s+(?:\$(\w+)|it)\s*([+\-*/])\s*(?:\$\w+|\d+)',
      );
      if (arithmeticPattern.hasMatch(setCommand)) {
        evaluator.executeArithmeticSet(setCommand);
      } else {
        evaluator.executeSetCommand(setCommand);
      }
    }

    // Remove all set commands from content
    var cleaned = content;
    var index = 0;
    while (index < cleaned.length) {
      final setIndex = cleaned.indexOf('(set:', index);
      if (setIndex == -1) break;

      var startIndex = setIndex;
      if (setIndex > 0 && cleaned[setIndex - 1] == '{') {
        startIndex = setIndex - 1;
      }

      var parenCount = 1;
      var endIndex = setIndex + 5;

      while (endIndex < cleaned.length && parenCount > 0) {
        if (cleaned[endIndex] == '(') parenCount++;
        if (cleaned[endIndex] == ')') parenCount--;
        endIndex++;
      }

      if (endIndex < cleaned.length && cleaned[endIndex] == '}') {
        endIndex++;
      }

      // Also remove trailing newline if present
      if (endIndex < cleaned.length && cleaned[endIndex] == '\n') {
        endIndex++;
      }

      cleaned = cleaned.substring(0, startIndex) + cleaned.substring(endIndex);
      index = startIndex;
    }

    return cleaned;
  }

  /// Parses a Twine story from HTML content.
  ///
  /// This should be called before accessing passages.
  Future<void> parseStory(String htmlContent) async {
    final document = html_parser.parse(htmlContent);
    final passageElements = document.querySelectorAll('tw-passagedata');

    for (var element in passageElements) {
      final name = element.attributes['name'] ?? '';
      _rawPassages[name] = element;

      // Handle Header passage specially (tagged with "header")
      final tags = element.attributes['tags'] ?? '';
      if (tags.contains('header') || tags.contains('footer')) {
        continue; // Skip adding header/footer to regular passages
      }

      // Parse once without game state for initial load
      final passage = _parsePassage(element);
      passages[passage.name] = passage;
    }
  }

  Passage _parsePassage(Element element, {Map<String, dynamic>? gameState, List<String>? visitedPassages}) {
    final name = element.attributes['name'] ?? '';
    final tags = element.attributes['tags'];
    final rawContent = element.text;

    // Set visited passages for (visited:) macro evaluation
    _visitedPassages = visitedPassages ?? [];

    // Initialize evaluator with a COPY of game state to avoid modifying the original
    final initialState = gameState != null
        ? Map<String, dynamic>.from(gameState)
        : <String, dynamic>{};
    evaluator = HarloweEvaluator(Map<String, dynamic>.from(initialState));

    // Clean content by evaluating Harlowe macros in the correct order:
    // 1. Execute (set:) commands first to update variables
    // 2. Then evaluate conditionals based on updated variables
    // This ensures conditionals see the current passage's state changes
    final cleanedContent = _cleanContent(rawContent);

    // IMPORTANT: Capture state changes AFTER _cleanContent runs, which includes
    // all (set:) commands - both top-level AND inside conditionals
    final stateChanges = <String, dynamic>{};
    if (gameState != null) {
      for (var key in evaluator.variables.keys) {
        final initial = initialState[key];
        final current = evaluator.variables[key];
        // For Maps, we need deep comparison
        bool isDifferent = false;
        if (initial is Map && current is Map) {
          isDifferent = initial.length != current.length ||
              !initial.keys.every(
                (k) => current.containsKey(k) && initial[k] == current[k],
              );
        } else {
          isDifferent = initial != current;
        }
        if (isDifferent) {
          stateChanges[key] = evaluator.variables[key];
          _debugPrint('[STATE_CHANGES] $key changed: $initial -> $current');
        }
      }
      if (stateChanges.isNotEmpty) {
        _debugPrint('[STATE_CHANGES] Passage "$name" changes: $stateChanges');
      }
    }

    // Extract choices from cleaned content (after (set:) and conditionals are processed)
    // We need to re-process just to extract choices since _cleanContent removes links
    // Re-initialize evaluator with the UPDATED state (not initial) so choices see current values
    evaluator = HarloweEvaluator(
      Map<String, dynamic>.from(evaluator.variables),
    );
    var contentForChoices = rawContent;

    // Execute ONLY top-level (set:) commands first - use helper to handle nested parentheses
    // Set commands inside conditionals will be executed when those branches are evaluated
    final setCommands = _extractSetCommands(
      contentForChoices,
      topLevelOnly: true,
    );
    for (var setCommand in setCommands) {
      // Try arithmetic first (with explicit variable or 'it'), then simple assignment
      final arithmeticPattern = RegExp(
        r'\$(\w+)\s+to\s+(?:\$(\w+)|it)\s*([+\-*/])\s*(?:\$\w+|\d+)',
      );
      if (arithmeticPattern.hasMatch(setCommand)) {
        evaluator.executeArithmeticSet(setCommand);
      } else {
        evaluator.executeSetCommand(setCommand);
      }
    }

    // Remove only top-level set commands from content
    var index = 0;
    while (index < contentForChoices.length) {
      final setIndex = contentForChoices.indexOf('(set:', index);
      if (setIndex == -1) break;

      // Check if this is inside a conditional branch (skip if so)
      int bracketDepth = 0;
      for (int i = 0; i < setIndex; i++) {
        if (contentForChoices[i] == '[') bracketDepth++;
        if (contentForChoices[i] == ']') bracketDepth--;
      }
      if (bracketDepth > 0) {
        // Skip set commands inside conditional branches
        index = setIndex + 5;
        continue;
      }

      var startIndex = setIndex;
      if (setIndex > 0 && contentForChoices[setIndex - 1] == '{') {
        startIndex = setIndex - 1;
      }

      var parenCount = 1;
      var endIndex = setIndex + 5;

      while (endIndex < contentForChoices.length && parenCount > 0) {
        if (contentForChoices[endIndex] == '(') parenCount++;
        if (contentForChoices[endIndex] == ')') parenCount--;
        endIndex++;
      }

      if (endIndex < contentForChoices.length &&
          contentForChoices[endIndex] == '}') {
        endIndex++;
      }

      contentForChoices = contentForChoices.substring(0, startIndex) +
          contentForChoices.substring(endIndex);
      index = startIndex;
    }

    // Then evaluate conditionals
    contentForChoices = _evaluateConditionals(contentForChoices);

    // Now extract choices from the processed content
    final choices = _extractChoices(contentForChoices);

    return Passage(
      name: name,
      content: cleanedContent,
      choices: choices,
      tags: tags,
      stateChanges: stateChanges.isNotEmpty ? stateChanges : null,
    );
  }

  List<Choice> _extractChoices(String content) {
    final choices = <Choice>[];

    // Match [[[Display Text|Target]]] (triple brackets for conditional links)
    // or [[Display Text|Target]] (double brackets for normal links)
    // Supports |, ->, and <- as separators
    final tripleLinkPattern = RegExp(r'\[\[\[([^\]]+)\]\]\]');
    final doubleLinkPattern = RegExp(r'\[\[([^\]]+)\]\]');

    // First try triple bracket links
    final tripleMatches = tripleLinkPattern.allMatches(content);
    for (var match in tripleMatches) {
      final linkText = match.group(1)!.trim();
      final (displayText, target) = _parseLinkText(linkText);
      choices.add(Choice(text: displayText, targetPassage: target));
    }

    // Then try double bracket links (but skip if they're part of triple brackets)
    final doubleMatches = doubleLinkPattern.allMatches(content);
    for (var match in doubleMatches) {
      // Check if this is part of a triple bracket by looking at context
      final start = match.start;
      final end = match.end;
      if (start > 0 && content[start - 1] == '[') continue; // Part of [[[
      if (end < content.length && content[end] == ']') continue; // Part of ]]]

      final linkText = match.group(1)!.trim();
      final (displayText, target) = _parseLinkText(linkText);
      choices.add(Choice(text: displayText, targetPassage: target));
    }

    return choices;
  }

  /// Parses link text and returns (displayText, targetPassage).
  /// Supports |, ->, and <- as separators.
  (String, String) _parseLinkText(String linkText) {
    if (linkText.contains('->')) {
      final parts = linkText.split('->');
      return (parts[0].trim(), parts[1].trim());
    } else if (linkText.contains('<-')) {
      final parts = linkText.split('<-');
      return (parts[1].trim(), parts[0].trim());
    } else if (linkText.contains('|')) {
      final parts = linkText.split('|');
      return (parts[0].trim(), parts[1].trim());
    } else {
      return (linkText.trim(), linkText.trim());
    }
  }

  String _cleanContent(String content) {
    var cleaned = content;

    // IMPORTANT: Only process TOP-LEVEL (set:...) commands before evaluating conditionals.
    // Set commands inside conditional branches will be handled when the branch is selected.
    final setCommands = _extractSetCommands(cleaned, topLevelOnly: true);
    for (var setCommand in setCommands) {
      // Try arithmetic first (with explicit variable or 'it'), then simple assignment
      final arithmeticPattern = RegExp(
        r'\$(\w+)\s+to\s+(?:\$(\w+)|it)\s*([+\-*/])\s*(?:\$\w+|\d+)',
      );
      if (arithmeticPattern.hasMatch(setCommand)) {
        evaluator.executeArithmeticSet(setCommand);
      } else {
        evaluator.executeSetCommand(setCommand);
      }
    }

    // Remove only top-level set commands from content (including wrapping braces)
    // Set commands inside conditionals will be removed when the branch is processed
    var index = 0;
    while (index < cleaned.length) {
      final setIndex = cleaned.indexOf('(set:', index);
      if (setIndex == -1) break;

      // Check if this is inside a conditional branch (skip if so)
      int bracketDepth = 0;
      for (int i = 0; i < setIndex; i++) {
        if (cleaned[i] == '[') bracketDepth++;
        if (cleaned[i] == ']') bracketDepth--;
      }
      if (bracketDepth > 0) {
        // Skip set commands inside conditional branches
        index = setIndex + 5;
        continue;
      }

      // Check if there's a brace before the set command
      var startIndex = setIndex;
      if (setIndex > 0 && cleaned[setIndex - 1] == '{') {
        startIndex = setIndex - 1;
      }

      // Count parentheses to find the matching close paren
      var parenCount = 1;
      var endIndex = setIndex + 5; // Start after '(set:'

      while (endIndex < cleaned.length && parenCount > 0) {
        if (cleaned[endIndex] == '(') parenCount++;
        if (cleaned[endIndex] == ')') parenCount--;
        endIndex++;
      }

      // Check if there's a brace after the set command
      if (endIndex < cleaned.length && cleaned[endIndex] == '}') {
        endIndex++;
      }

      // Remove this set command
      cleaned = cleaned.substring(0, startIndex) + cleaned.substring(endIndex);
      index = startIndex;
    }

    // Remove surrounding braces from conditional structures {(if:...)[...][...]}
    // Need to carefully handle nested braces like {(print: ...)}
    while (cleaned.contains('{(if:') || cleaned.contains('{(unless:')) {
      final openingPattern = cleaned.contains('{(if:') ? '{(if:' : '{(unless:';
      final startIndex = cleaned.indexOf(openingPattern);
      if (startIndex == -1) break;

      // Find the matching closing brace by counting brackets
      int braceCount = 1;
      int endIndex = startIndex + 1;

      while (endIndex < cleaned.length && braceCount > 0) {
        if (cleaned[endIndex] == '{') braceCount++;
        if (cleaned[endIndex] == '}') {
          braceCount--;
          if (braceCount == 0) break;
        }
        endIndex++;
      }

      if (braceCount == 0 && endIndex < cleaned.length) {
        // Remove the outer braces: {content} -> content
        final innerContent = cleaned.substring(startIndex + 1, endIndex);
        cleaned = cleaned.substring(0, startIndex) +
            innerContent +
            cleaned.substring(endIndex + 1);
      } else {
        break; // Couldn't find matching brace
      }
    }

    // NOW evaluate conditionals AFTER (set:) commands have been processed
    cleaned = _evaluateConditionals(cleaned);

    // Remove any remaining braces (used for grouping in Harlowe)
    cleaned = cleaned.replaceAll('{', '').replaceAll('}', '');

    // Remove stat display lines - handle full format with all three stats
    // Must happen AFTER conditionals are evaluated so time shows as "9:5 PM" not "(if:...)"
    // Format: **Suspicion:** X/100 | **Time:** X:XX PM | **Film:** X/30
    // The regex matches from **Suspicion:** to the end of the line (either **Film:** or **Time:** at the end)
    cleaned = cleaned.replaceAll(
      RegExp(
        r'\*\*Suspicion:\*\*.*?(?:\*\*Film:\*\*.*?/\d+|\*\*Time:\*\*.*?(?:PM|Midnight))(?:\s*\|\s*\*\*Film:\*\*.*?/\d+)?',
        multiLine: true,
        dotAll: true,
      ),
      '',
    );

    // NOW remove link syntax after conditionals are evaluated
    cleaned = cleaned.replaceAll(RegExp(r'\[\[.*?\]\]', dotAll: true), '');

    // Remove (print:...) macros and replace with evaluated values
    cleaned = _processPrintMacros(cleaned);

    // Convert Harlowe italic syntax //text// to Markdown *text*
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'//(.+?)//'),
      (match) => '*${match.group(1)}*',
    );

    // Replace variable displays like $suspicion with actual values
    cleaned = cleaned.replaceAllMapped(RegExp(r'\$(\w+)'), (match) {
      final varName = match.group(1)!;
      final value = evaluator.variables[varName];
      if (value != null) {
        return value.toString();
      }
      return match.group(0)!;
    });

    // Clean up any remaining Harlowe data structure syntax
    cleaned = cleaned.replaceAll(RegExp(r'\(a:\)'), ''); // empty array
    cleaned = cleaned.replaceAll(RegExp(r'\(dm:\)'), ''); // empty data map
    cleaned = cleaned.replaceAll(RegExp(r'\(a:.*?\)'), '[]'); // arrays
    cleaned = cleaned.replaceAll(RegExp(r'\(dm:.*?\)'), '{}'); // data maps

    // Clean up excessive whitespace
    cleaned = cleaned.replaceAll(RegExp(r'\n\s*\n\s*\n+'), '\n\n');
    cleaned = cleaned.replaceAll(RegExp(r'^\s+$', multiLine: true), '');
    cleaned = cleaned.trim();

    return cleaned;
  }

  String _processPrintMacros(String content) {
    var result = content;

    // Manually handle nested parentheses by counting brackets
    while (result.contains('(print:')) {
      final startIndex = result.indexOf('(print:');
      if (startIndex == -1) break;

      // Find matching closing paren
      int parenCount = 0;
      int endIndex = startIndex;
      for (int i = startIndex; i < result.length; i++) {
        if (result[i] == '(') parenCount++;
        if (result[i] == ')') {
          parenCount--;
          if (parenCount == 0) {
            endIndex = i;
            break;
          }
        }
      }

      if (endIndex <= startIndex) break; // Couldn't find matching paren

      final fullMatch = result.substring(startIndex, endIndex + 1);
      final expression = fullMatch
          .substring(7, fullMatch.length - 1)
          .trim(); // Remove "(print:" and ")"

      String replacement = _evaluatePrintExpression(expression);

      result = result.replaceFirst(fullMatch, replacement);
    }

    return result;
  }

  String _evaluateConditionals(String content) {
    var result = content;

    // Handle (if:...)[...](else-if:...)[...](else:)[...] chains
    // Use a more flexible approach that counts brackets
    int maxIterations = 20;
    while (maxIterations > 0) {
      bool foundMatch = false;

      // Look for (if: - then manually find the condition by counting parens
      final ifIndex = result.indexOf('(if:');
      if (ifIndex != -1) {
        // Find the closing paren of (if:...) by counting parentheses
        int parenCount = 1;
        int conditionStart = ifIndex + 4; // After "(if:"
        int conditionEnd = conditionStart;

        while (conditionEnd < result.length && parenCount > 0) {
          if (result[conditionEnd] == '(') parenCount++;
          if (result[conditionEnd] == ')') parenCount--;
          if (parenCount == 0) break;
          conditionEnd++;
        }

        if (conditionEnd < result.length && result[conditionEnd] == ')') {
          final condition =
              result.substring(conditionStart, conditionEnd).trim();

          // Now find the opening bracket [ after the condition
          int bracketStart = conditionEnd + 1;
          while (bracketStart < result.length && result[bracketStart] != '[') {
            bracketStart++;
          }

          if (bracketStart < result.length) {
            final contentStart = bracketStart + 1;

            // Find matching closing bracket by counting
            int bracketCount = 1;
            int contentEnd = contentStart;
            while (contentEnd < result.length && bracketCount > 0) {
              if (result[contentEnd] == '[') bracketCount++;
              if (result[contentEnd] == ']') bracketCount--;
              contentEnd++;
            }

            if (bracketCount == 0) {
              final ifContent = result.substring(contentStart, contentEnd - 1);

              // Collect all branches: (else-if:...)[ and (else:)[
              final branches = <Map<String, dynamic>>[];
              branches.add({'condition': condition, 'content': ifContent});

              int searchPos = contentEnd;
              while (searchPos < result.length) {
                // Skip leading whitespace
                while (searchPos < result.length &&
                    (result[searchPos] == ' ' ||
                        result[searchPos] == '\n' ||
                        result[searchPos] == '\t' ||
                        result[searchPos] == '\r')) {
                  searchPos++;
                }

                // Check for (else-if: condition)[
                if (searchPos + 8 < result.length &&
                    result.substring(searchPos, searchPos + 8) == '(else-if') {
                  // Find the condition by counting parens
                  int elseIfParenCount = 1;
                  int elseIfCondStart = searchPos + 9; // After "(else-if:"
                  int elseIfCondEnd = elseIfCondStart;

                  while (
                      elseIfCondEnd < result.length && elseIfParenCount > 0) {
                    if (result[elseIfCondEnd] == '(') elseIfParenCount++;
                    if (result[elseIfCondEnd] == ')') elseIfParenCount--;
                    if (elseIfParenCount == 0) break;
                    elseIfCondEnd++;
                  }

                  if (elseIfCondEnd < result.length &&
                      result[elseIfCondEnd] == ')') {
                    final elseIfCondition =
                        result.substring(elseIfCondStart, elseIfCondEnd).trim();

                    // Find the opening bracket
                    int elseIfBracketStart = elseIfCondEnd + 1;
                    while (elseIfBracketStart < result.length &&
                        result[elseIfBracketStart] != '[') {
                      elseIfBracketStart++;
                    }

                    if (elseIfBracketStart < result.length) {
                      final elseIfContentStart = elseIfBracketStart + 1;
                      bracketCount = 1;
                      int elseIfContentEnd = elseIfContentStart;
                      while (elseIfContentEnd < result.length &&
                          bracketCount > 0) {
                        if (result[elseIfContentEnd] == '[') bracketCount++;
                        if (result[elseIfContentEnd] == ']') bracketCount--;
                        elseIfContentEnd++;
                      }
                      final elseIfContent = result.substring(
                        elseIfContentStart,
                        elseIfContentEnd - 1,
                      );
                      branches.add({
                        'condition': elseIfCondition,
                        'content': elseIfContent,
                      });
                      searchPos = elseIfContentEnd;
                      continue;
                    }
                  }
                }

                // Check for (else:)[
                final elseMatch = RegExp(
                  r'^\s*\(else:\)\s*\[',
                ).firstMatch(result.substring(searchPos));
                if (elseMatch != null) {
                  final elseContentStart = searchPos + elseMatch.end;
                  bracketCount = 1;
                  int elseContentEnd = elseContentStart;
                  while (elseContentEnd < result.length && bracketCount > 0) {
                    if (result[elseContentEnd] == '[') bracketCount++;
                    if (result[elseContentEnd] == ']') bracketCount--;
                    elseContentEnd++;
                  }
                  final elseContent = result.substring(
                    elseContentStart,
                    elseContentEnd - 1,
                  );
                  branches.add({
                    'condition': null,
                    'content': elseContent,
                  }); // null = else (always true)
                  searchPos = elseContentEnd;
                } else if (searchPos < result.length &&
                    result[searchPos] == '[' && (searchPos + 1 >= result.length || result[searchPos + 1] != '[')) {
                  // Implicit else branch: just [...] without (else:)
                  final implicitElseStart = searchPos + 1;
                  bracketCount = 1;
                  int implicitElseEnd = implicitElseStart;
                  while (implicitElseEnd < result.length && bracketCount > 0) {
                    if (result[implicitElseEnd] == '[') bracketCount++;
                    if (result[implicitElseEnd] == ']') bracketCount--;
                    implicitElseEnd++;
                  }
                  final implicitElseContent = result.substring(
                    implicitElseStart,
                    implicitElseEnd - 1,
                  );
                  branches.add({
                    'condition': null,
                    'content': implicitElseContent,
                  });
                  searchPos = implicitElseEnd;
                }
                break; // No more else-if or else
              }

              // Find which branch to use
              String replacement = '';
              for (var branch in branches) {
                final branchCondition = branch['condition'];
                if (branchCondition == null) {
                  // This is the else branch - only use as fallback
                  replacement = branch['content'] as String;
                  break;
                } else {
                  final conditionResult = evaluator.evaluateExpression(
                    branchCondition as String,
                  );
                  _debugPrint(
                    '[CONDITIONAL] Evaluating: "$branchCondition" => $conditionResult',
                  );
                  if (conditionResult) {
                    replacement = branch['content'] as String;
                    break;
                  }
                }
              }

              // Recursively evaluate any nested conditionals in the selected branch
              replacement = _evaluateConditionals(replacement);

              // Execute any (set:) commands in the selected branch
              replacement = _executeAndRemoveSetCommands(replacement);

              // Process any (print:) macros in the selected branch
              replacement = _processPrintMacros(replacement);

              result = result.substring(0, ifIndex) +
                  replacement +
                  result.substring(searchPos);
              foundMatch = true;
            }
          }
        }
      }

      if (!foundMatch) break;
      maxIterations--;
    }


    // Handle (visited:...)[...] macros for checking passage visit history
    maxIterations = 20;
    while (maxIterations > 0) {
      bool foundMatch = false;
      
      final visitedIndex = result.indexOf('(visited:');
      if (visitedIndex != -1) {
        // Find the closing paren of (visited:...) by counting parentheses
        int parenCount = 1;
        int argStart = visitedIndex + 9; // After "(visited:"
        int argEnd = argStart;
        
        while (argEnd < result.length && parenCount > 0) {
          if (result[argEnd] == '(') parenCount++;
          if (result[argEnd] == ')') parenCount--;
          if (parenCount == 0) break;
          argEnd++;
        }
        
        if (argEnd < result.length && result[argEnd] == ')') {
          final visitedArg = result.substring(argStart, argEnd).trim();
          
          // Now find the opening bracket [ after the closing paren
          int bracketStart = argEnd + 1;
          while (bracketStart < result.length && result[bracketStart] != '[') {
            bracketStart++;
          }
          
          if (bracketStart < result.length) {
            final contentStart = bracketStart + 1;
            
            // Find matching closing bracket by counting
            int bracketCount = 1;
            int contentEnd = contentStart;
            while (contentEnd < result.length && bracketCount > 0) {
              if (result[contentEnd] == '[') bracketCount++;
              if (result[contentEnd] == ']') bracketCount--;
              contentEnd++;
            }
            
            if (bracketCount == 0) {
              final visitedContent = result.substring(contentStart, contentEnd - 1);
              
              // Evaluate whether the passage has been visited
              bool isVisited = _evaluateVisitedMacro(visitedArg);
              
              _debugPrint('[VISITED] Evaluating: "$visitedArg" => $isVisited');
              
              // Replace with content if visited, otherwise empty
              final replacement = isVisited ? _evaluateConditionals(visitedContent) : '';
              
              result = result.substring(0, visitedIndex) +
                  replacement +
                  result.substring(contentEnd);
              foundMatch = true;
            }
          }
        }
      }
      
      if (!foundMatch) break;
      maxIterations--;
    }

    // Clean up any remaining orphaned (else:) or (else-if:) blocks
    // Must use bracket counting since content may have nested brackets (links)
    result = _removeOrphanedBranches(result);

    return result;
  }

  /// Removes orphaned (else:)[...] and (else-if:...)[...] blocks using bracket counting
  String _removeOrphanedBranches(String content) {
    var result = content;

    // Remove (else:)[...] blocks with proper bracket counting
    while (true) {
      final elseMatch = RegExp(r'\(else:\)\[').firstMatch(result);
      if (elseMatch == null) break;

      final bracketStart = elseMatch.end - 1; // Position of [
      int bracketCount = 1;
      int contentEnd = bracketStart + 1;

      while (contentEnd < result.length && bracketCount > 0) {
        if (result[contentEnd] == '[') bracketCount++;
        if (result[contentEnd] == ']') bracketCount--;
        contentEnd++;
      }

      if (bracketCount == 0) {
        result =
            result.substring(0, elseMatch.start) + result.substring(contentEnd);
      } else {
        break; // Unbalanced brackets, stop
      }
    }

    // Remove (else-if:...)[...] blocks with proper bracket counting
    while (true) {
      final elseIfMatch = RegExp(r'\(else-if:').firstMatch(result);
      if (elseIfMatch == null) break;

      // Find matching ) for the condition
      int parenCount = 1;
      int condEnd = elseIfMatch.end;
      while (condEnd < result.length && parenCount > 0) {
        if (result[condEnd] == '(') parenCount++;
        if (result[condEnd] == ')') parenCount--;
        condEnd++;
      }

      if (parenCount != 0 || condEnd >= result.length) break;

      // Find the [ after )
      int bracketStart = condEnd;
      while (bracketStart < result.length && result[bracketStart] != '[') {
        bracketStart++;
      }

      if (bracketStart >= result.length) break;

      int bracketCount = 1;
      int contentEnd = bracketStart + 1;

      while (contentEnd < result.length && bracketCount > 0) {
        if (result[contentEnd] == '[') bracketCount++;
        if (result[contentEnd] == ']') bracketCount--;
        contentEnd++;
      }

      if (bracketCount == 0) {
        result = result.substring(0, elseIfMatch.start) +
            result.substring(contentEnd);
      } else {
        break; // Unbalanced brackets, stop
      }
    }

    return result;
  }

  /// Evaluates a (visited:) macro argument to determine if passage(s) have been visited.
  ///
  /// Supports:
  /// - Simple passage name: "mountain"
  /// - Lambda with where clause: where its tags contains "Forest"
  bool _evaluateVisitedMacro(String arg) {
    final trimmed = arg.trim();
    
    // Handle simple quoted passage name: "passageName"
    if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
      final passageName = trimmed.substring(1, trimmed.length - 1);
      return _visitedPassages.contains(passageName);
    }
    
    // Handle "where" lambda: where its tags contains "Forest"
    if (trimmed.startsWith('where ')) {
      final condition = trimmed.substring(6).trim(); // After "where "
      
      // For each visited passage, check if it matches the condition
      for (final passageName in _visitedPassages) {
        if (_passageMatchesCondition(passageName, condition)) {
          return true;
        }
      }
      return false;
    }
    
    // Default: treat as unquoted passage name
    return _visitedPassages.contains(trimmed);
  }

  /// Checks if a passage matches a where condition.
  ///
  /// Supports conditions like:
  /// - its tags contains "Forest"
  bool _passageMatchesCondition(String passageName, String condition) {
    // Get the passage's tags
    final element = _rawPassages[passageName];
    if (element == null) return false;
    
    final tags = element.attributes['tags'] ?? '';
    
    // Parse "its tags contains \"value\""
    final tagsContainsPattern = RegExp(r'its\s+tags\s+contains\s+"([^"]+)"');
    final match = tagsContainsPattern.firstMatch(condition);
    if (match != null) {
      final searchTag = match.group(1)!;
      // Tags are space-separated
      final tagList = tags.split(RegExp(r'\s+'));
      return tagList.any((tag) => tag.contains(searchTag));
    }
    
    return false;
  }


  String _evaluatePrintExpression(String expression) {
    // Check for comparison expressions - these should return empty in (print:) context
    if (expression.contains('<') ||
        expression.contains('>') ||
        expression.contains('==')) {
      return '';
    }

    // Handle possessive array access: $array's (random: min, max) or $array's index
    // Pattern: $varName's (random: min, max)
    final possessiveRandomMatch = RegExp(
      r"\$(\w+)'s\s*\(random:\s*(\d+)\s*,\s*(\d+)\s*\)",
    ).firstMatch(expression);
    if (possessiveRandomMatch != null) {
      final varName = possessiveRandomMatch.group(1)!;
      final minVal = int.parse(possessiveRandomMatch.group(2)!);
      final maxVal = int.parse(possessiveRandomMatch.group(3)!);
      final varValue = evaluator.variables[varName];

      if (varValue is List && varValue.isNotEmpty) {
        // Harlowe uses 1-based indexing
        final random = Random();
        final index = random.nextInt(maxVal - minVal + 1) + minVal;
        // Convert to 0-based index
        if (index >= 1 && index <= varValue.length) {
          return varValue[index - 1].toString();
        }
      }
      return '';
    }

    // Handle possessive array access with numeric index: $array's 1
    final possessiveIndexMatch = RegExp(
      r"\$(\w+)'s\s*(\d+)",
    ).firstMatch(expression);
    if (possessiveIndexMatch != null) {
      final varName = possessiveIndexMatch.group(1)!;
      final index = int.parse(possessiveIndexMatch.group(2)!);
      final varValue = evaluator.variables[varName];

      if (varValue is List && varValue.isNotEmpty) {
        // Harlowe uses 1-based indexing
        if (index >= 1 && index <= varValue.length) {
          return varValue[index - 1].toString();
        }
      }
      return '';
    }

    // Handle standalone (random: min, max) macro
    final randomMatch = RegExp(
      r'\(random:\s*(\d+)\s*,\s*(\d+)\s*\)',
    ).firstMatch(expression);
    if (randomMatch != null) {
      final minVal = int.parse(randomMatch.group(1)!);
      final maxVal = int.parse(randomMatch.group(2)!);
      final random = Random();
      final result = random.nextInt(maxVal - minVal + 1) + minVal;
      return result.toString();
    }

    // Check for complex expressions with parentheses like ($time - 900) % 60
    final complexMatch = RegExp(
      r'\(([^)]+)\)\s*%\s*(\d+)',
    ).firstMatch(expression);
    if (complexMatch != null) {
      final innerExpr = complexMatch.group(1)!;
      final modValue = int.parse(complexMatch.group(2)!);

      // Evaluate the inner expression first
      final innerArithMatch = RegExp(
        r'\$(\w+)\s*([+\-*/])\s*(\d+)',
      ).firstMatch(innerExpr);
      if (innerArithMatch != null) {
        final varName = innerArithMatch.group(1)!;
        final operator = innerArithMatch.group(2)!;
        final operand = int.parse(innerArithMatch.group(3)!);
        final varValue = evaluator.variables[varName];

        if (varValue is int) {
          int calcResult;
          switch (operator) {
            case '+':
              calcResult = varValue + operand;
              break;
            case '-':
              calcResult = varValue - operand;
              break;
            case '*':
              calcResult = varValue * operand;
              break;
            case '/':
              calcResult = varValue ~/ operand;
              break;
            default:
              return '';
          }
          return (calcResult % modValue).toString();
        }
      }
    }

    // Check for complex nested expressions like: 9 + (($time - 900) / 60)
    final nestedArithMatch = RegExp(
      r'(\d+)\s*([+\-*/])\s*\(\(([^)]+)\)\s*([+\-*/])\s*(\d+)\)',
    ).firstMatch(expression);
    if (nestedArithMatch != null) {
      final baseValue = int.parse(nestedArithMatch.group(1)!);
      final outerOp = nestedArithMatch.group(2)!;
      final innerExpr = nestedArithMatch.group(3)!;
      final innerOp = nestedArithMatch.group(4)!;
      final innerOperand = int.parse(nestedArithMatch.group(5)!);

      // Parse the inner expression: $time - 900
      final innerVarMatch = RegExp(
        r'\$(\w+)\s*([+\-*/])\s*(\d+)',
      ).firstMatch(innerExpr);
      if (innerVarMatch != null) {
        final varName = innerVarMatch.group(1)!;
        final innerVarOp = innerVarMatch.group(2)!;
        final innerVarOperand = int.parse(innerVarMatch.group(3)!);
        final varValue = evaluator.variables[varName];

        if (varValue is int) {
          // Calculate inner expression
          int innerResult;
          switch (innerVarOp) {
            case '+':
              innerResult = varValue + innerVarOperand;
              break;
            case '-':
              innerResult = varValue - innerVarOperand;
              break;
            case '*':
              innerResult = varValue * innerVarOperand;
              break;
            case '/':
              innerResult = varValue ~/ innerVarOperand;
              break;
            default:
              return '';
          }

          // Apply the division or other operation
          int finalInner;
          switch (innerOp) {
            case '+':
              finalInner = innerResult + innerOperand;
              break;
            case '-':
              finalInner = innerResult - innerOperand;
              break;
            case '*':
              finalInner = innerResult * innerOperand;
              break;
            case '/':
              finalInner = innerResult ~/ innerOperand;
              break;
            default:
              return '';
          }

          // Apply the outer operation
          int finalResult;
          switch (outerOp) {
            case '+':
              finalResult = baseValue + finalInner;
              break;
            case '-':
              finalResult = baseValue - finalInner;
              break;
            case '*':
              finalResult = baseValue * finalInner;
              break;
            case '/':
              finalResult = baseValue ~/ finalInner;
              break;
            default:
              return '';
          }

          return finalResult.toString();
        }
      }
    }

    // Check for arithmetic expressions like $time - 900
    final arithmeticMatch = RegExp(
      r'\$(\w+)\s*([+\-*/])\s*(\d+)',
    ).firstMatch(expression);
    if (arithmeticMatch != null) {
      final varName = arithmeticMatch.group(1)!;
      final operator = arithmeticMatch.group(2)!;
      final operand = int.parse(arithmeticMatch.group(3)!);
      final varValue = evaluator.variables[varName];

      if (varValue is int) {
        switch (operator) {
          case '+':
            return (varValue + operand).toString();
          case '-':
            return (varValue - operand).toString();
          case '*':
            return (varValue * operand).toString();
          case '/':
            return (varValue ~/ operand).toString();
        }
      }
    }

    // Simple variable reference like $time
    final simpleVarMatch = RegExp(r'^\$(\w+)$').firstMatch(expression);
    if (simpleVarMatch != null) {
      final varName = simpleVarMatch.group(1)!;
      final value = evaluator.variables[varName];
      return value?.toString() ?? '';
    }

    return '';
  }

  /// Gets a passage by name, optionally re-evaluating with current game state.
  ///
  /// If [gameState] is provided, the passage will be re-parsed with
  /// those variables to evaluate conditionals correctly.
  Passage? getPassage(String name, {Map<String, dynamic>? gameState, List<String>? visitedPassages}) {
    if (gameState != null && _rawPassages.containsKey(name)) {
      // Re-parse with current game state
      return _parsePassage(_rawPassages[name]!, gameState: gameState, visitedPassages: visitedPassages);
    }
    return passages[name];
  }

  /// Gets the starting passage of the story.
  ///
  /// Returns the passage named "Start" if it exists, otherwise the first passage.
  Passage getStartPassage() {
    return passages['Start'] ?? passages.values.first;
  }

  /// Gets the header content if a passage is tagged with "header".
  ///
  /// The header will be evaluated with the current [gameState] if provided.
  String? getHeader({Map<String, dynamic>? gameState}) {
    // Find passage with "header" tag
    Element? headerElement;
    for (var entry in _rawPassages.entries) {
      final tags = entry.value.attributes['tags'] ?? '';
      if (tags.contains('header')) {
        headerElement = entry.value;
        break;
      }
    }

    if (headerElement == null) {
      return null;
    }

    final rawContent = headerElement.text;

    // Initialize evaluator with current game state
    final state = gameState != null
        ? Map<String, dynamic>.from(gameState)
        : <String, dynamic>{};
    evaluator = HarloweEvaluator(Map<String, dynamic>.from(state));

    // Clean and evaluate the header content
    return _cleanContent(rawContent);
  }
}
