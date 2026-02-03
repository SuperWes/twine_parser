/// Represents a single passage in a Twine story.
class Passage {
  /// The unique name/identifier of the passage.
  final String name;

  /// The processed content of the passage (with macros evaluated).
  final String content;

  /// The list of choices/links available in this passage.
  final List<Choice> choices;

  /// Optional tags associated with this passage (e.g., "header", "footer").
  final String? tags;

  /// State changes that should be applied when entering this passage.
  final Map<String, dynamic>? stateChanges;

  Passage({
    required this.name,
    required this.content,
    required this.choices,
    this.tags,
    this.stateChanges,
  });

  @override
  String toString() => 'Passage($name)';
}

/// Represents a choice/link in a Twine passage.
class Choice {
  /// The display text shown to the player.
  final String text;

  /// The name of the target passage this choice leads to.
  final String targetPassage;

  /// Optional condition that must be true for this choice to appear.
  final String? condition;

  /// State changes that should be applied when selecting this choice.
  final Map<String, dynamic>? stateChanges;

  Choice({
    required this.text,
    required this.targetPassage,
    this.condition,
    this.stateChanges,
  });

  @override
  String toString() => 'Choice($text -> $targetPassage)';
}
