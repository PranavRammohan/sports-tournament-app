// playoffs_screen.dart
// Thin Scaffold wrapper around BracketView for the whole-tournament
// "Playoffs" entry point (a knockout stage a round-robin/matches-per-player
// league can optionally start after its regular season). This is the only
// place that still needs its own generate/cancel actions and its own
// navigation destination — a knockout-format GROUP renders BracketView
// directly inline in its own tab instead (see groups_overview_screen.dart).
import 'package:flutter/material.dart';
import '../widgets/bracket_view.dart';

class PlayoffsScreen extends StatefulWidget {
  final int leagueId;
  final bool isHost;
  final String format;

  const PlayoffsScreen({
    super.key,
    required this.leagueId,
    required this.isHost,
    this.format = 'singles',
  });

  @override
  State<PlayoffsScreen> createState() => _PlayoffsScreenState();
}

class _PlayoffsScreenState extends State<PlayoffsScreen> {
  final GlobalKey<BracketViewState> _bracketKey = GlobalKey<BracketViewState>();
  bool _hasBracket = false;
  bool _cancelling = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Playoffs'),
        actions: [
          if (widget.isHost && _hasBracket)
            IconButton(
              icon: _cancelling
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.delete_outline),
              tooltip: 'Cancel playoffs',
              onPressed: _cancelling
                  ? null
                  : () => _bracketKey.currentState?.confirmCancelPlayoffs(),
            ),
        ],
      ),
      body: BracketView(
        key: _bracketKey,
        leagueId: widget.leagueId,
        isHost: widget.isHost,
        format: widget.format,
        onBracketChanged: (hasBracket) => setState(() => _hasBracket = hasBracket),
        onCancellingChanged: (cancelling) => setState(() => _cancelling = cancelling),
      ),
    );
  }
}
