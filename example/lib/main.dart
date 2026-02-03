import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:twine_parser/twine_parser.dart';

void main() {
  runApp(const TwineParserExampleApp());
}

class TwineParserExampleApp extends StatelessWidget {
  const TwineParserExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Twine Parser Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const StorySelectionScreen(),
    );
  }
}

/// Example Twine stories from rheteric.org
class ExampleStory {
  final String title;
  final String description;
  final String url;
  final List<String> features;

  const ExampleStory({
    required this.title,
    required this.description,
    required this.url,
    required this.features,
  });
}

const exampleStories = [
  ExampleStory(
    title: 'Sandwich Distribution Simulator',
    description:
        'Collect and give away sandwiches using numerical variables and if/else macros.',
    url: 'https://rheteric.org/games/sandwich.html',
    features: ['(set:)', '(if:)', '(else:)'],
  ),
  ExampleStory(
    title: "What's Your Name?",
    description:
        'A game that lets the player name a character using string variables.',
    url: 'https://rheteric.org/games/names.html',
    features: ['(prompt:)', '(set:)'],
  ),
  ExampleStory(
    title: 'Traveler',
    description:
        'Go in four cardinal directions while the game tracks where you\'ve been.',
    url: 'https://rheteric.org/games/traveler.html',
    features: ['(set:)', '(visited:)', 'passage tags'],
  ),
  ExampleStory(
    title: 'Bus Stop',
    description:
        'Experience a haunting encounter at a bus stop with random text generation.',
    url: 'https://rheteric.org/games/busstop.html',
    features: ['(a:)', '(print:)', '(random:)', '(set:)'],
  ),
  ExampleStory(
    title: 'Epic Journey',
    description:
        'A fantasy quest using true/false and numerical variables for combat and inventory.',
    url: 'https://rheteric.org/games/journey.html',
    features: ['(if:)', '(else:)', '(set:)'],
  ),
];

class StorySelectionScreen extends StatefulWidget {
  const StorySelectionScreen({super.key});

  @override
  State<StorySelectionScreen> createState() => _StorySelectionScreenState();
}

class _StorySelectionScreenState extends State<StorySelectionScreen> {
  final _urlController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _loadStory(String url) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('Failed to load story: HTTP ${response.statusCode}');
      }

      final parser = TwineParser();
      await parser.parseStory(response.body);

      if (parser.passages.isEmpty) {
        throw Exception(
            'No passages found in the story. Make sure the URL points to a Twine HTML file.');
      }

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => StoryPlayerScreen(
              parser: parser,
              storyUrl: url,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showCustomUrlDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Story URL'),
        content: TextField(
          controller: _urlController,
          decoration: const InputDecoration(
            hintText: 'https://example.com/story.html',
            labelText: 'Twine Story URL',
          ),
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              if (_urlController.text.isNotEmpty) {
                _loadStory(_urlController.text);
              }
            },
            child: const Text('Load'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Twine Parser Example'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading story...'),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Error',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.link),
                    title: const Text('Load Custom URL'),
                    subtitle: const Text('Enter the URL of any Twine story'),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: _showCustomUrlDialog,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Example Stories',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'From rheteric.org/twine - Tiny Twine Examples by Eric Detweiler',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                ...exampleStories.map((story) => Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        onTap: () => _loadStory(story.url),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                story.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                story.description,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: story.features
                                    .map((f) => Chip(
                                          label: Text(f),
                                          visualDensity: VisualDensity.compact,
                                        ))
                                    .toList(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )),
              ],
            ),
    );
  }
}

class StoryPlayerScreen extends StatefulWidget {
  final TwineParser parser;
  final String storyUrl;

  const StoryPlayerScreen({
    super.key,
    required this.parser,
    required this.storyUrl,
  });

  @override
  State<StoryPlayerScreen> createState() => _StoryPlayerScreenState();
}

class _StoryPlayerScreenState extends State<StoryPlayerScreen> {
  late Passage _currentPassage;
  final Map<String, dynamic> _gameState = {};
  final List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _currentPassage = widget.parser.getStartPassage();
    _history.add(_currentPassage.name);
  }

  void _navigateToPassage(String passageName) {
    // Always re-parse the passage to get fresh random values
    final passage =
        widget.parser.getPassage(passageName, gameState: _gameState);
    if (passage != null) {
      // Apply state changes
      if (passage.stateChanges != null) {
        _gameState.addAll(passage.stateChanges!);
      }
      setState(() {
        // Force a rebuild even if navigating to the same passage name
        _currentPassage = passage;
        _history.add(passageName);
      });
    }
  }

  void _restart() {
    setState(() {
      _gameState.clear();
      _history.clear();
      _currentPassage = widget.parser.getStartPassage();
      _history.add(_currentPassage.name);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentPassage.name),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt),
            tooltip: 'Restart',
            onPressed: _restart,
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Story Info',
            onPressed: () => _showStoryInfo(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Story content - use key to force rebuild on navigation
            Card(
              key: ValueKey('passage_${_history.length}'),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  _currentPassage.content,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        height: 1.6,
                      ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Choices
            if (_currentPassage.choices.isNotEmpty) ...[
              Text(
                'What do you do?',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              ..._currentPassage.choices.map((choice) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: FilledButton.tonal(
                      onPressed: () => _navigateToPassage(choice.targetPassage),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(choice.text),
                      ),
                    ),
                  )),
            ] else ...[
              const Center(
                child: Text(
                  '— The End —',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: FilledButton(
                  onPressed: _restart,
                  child: const Text('Play Again'),
                ),
              ),
            ],
            // Debug: Show game state
            if (_gameState.isNotEmpty) ...[
              const SizedBox(height: 32),
              ExpansionTile(
                title: const Text('Game State (Debug)'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _gameState.entries
                          .map((e) => '${e.key}: ${e.value}')
                          .join('\n'),
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showStoryInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Story Info'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('URL: ${widget.storyUrl}'),
            const SizedBox(height: 8),
            Text('Passages: ${widget.parser.passages.length}'),
            const SizedBox(height: 8),
            Text('Visited: ${_history.length}'),
            const SizedBox(height: 16),
            const Text('Passage List:'),
            const SizedBox(height: 8),
            ...widget.parser.passages.keys.map((name) => Text('• $name')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
