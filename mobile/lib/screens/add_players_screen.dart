// add_players_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import '../api_client.dart';
import '../widgets/loading_skeleton.dart';
import 'add_guest_dialog.dart';

class AddPlayersScreen extends StatefulWidget {
  final int leagueId;
  final String sport;
  final String? genderCategory;

  const AddPlayersScreen({
    super.key,
    required this.leagueId,
    required this.sport,
    this.genderCategory,
  });

  @override
  State<AddPlayersScreen> createState() => _AddPlayersScreenState();
}

class _AddPlayersScreenState extends State<AddPlayersScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _results = [];
  bool _searching = false;
  String? _error;
  Timer? _debounce;
  bool _submitting = false;
  // Checked but not yet submitted — this batch's whole point (GAP-05) is
  // letting a host add several players in one action instead of one tap
  // each.
  final Set<int> _selectedIds = {};
  final Set<int> _addedIds = {};
  // Tracks whether the caller's roster needs refreshing on pop — separate
  // from _addedIds since a guest add doesn't put anything in the search
  // results list to check off.
  bool _anyChanges = false;

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(query));
  }

  Future<void> _search(String query) async {
    if (query.trim().length < 2) {
      setState(() {
        _results = [];
        _error = null;
      });
      return;
    }

    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final res = await ApiClient.get(
        '/leagues/${widget.leagueId}/search-players',
        queryParams: {'q': query.trim()},
      );

      if (res.statusCode == 200) {
        setState(() => _results = res.data['users']);
      } else {
        setState(() {
          _results = [];
          _error = res.errorOr('Could not search for players.');
        });
      }
    } catch (err) {
      setState(() {
        _results = [];
        _error = 'Could not reach the server.';
      });
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _toggleSelected(int id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _addSelected() async {
    if (_selectedIds.isEmpty || _submitting) return;
    HapticFeedback.lightImpact();
    setState(() => _submitting = true);

    final toAdd = _selectedIds.toList();
    var succeeded = 0;
    String? lastError;

    for (final playerId in toAdd) {
      try {
        final res = await ApiClient.post(
          '/leagues/${widget.leagueId}/add-player',
          body: {'playerId': playerId},
        );
        if (res.statusCode == 201) {
          succeeded++;
          _addedIds.add(playerId);
          _anyChanges = true;
        } else {
          lastError = res.errorOr('Could not add player.');
        }
      } catch (err) {
        lastError = 'Network error.';
      }
    }

    if (!mounted) return;
    setState(() {
      _selectedIds.clear();
      _submitting = false;
    });

    final failed = toAdd.length - succeeded;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? (succeeded == 1 ? 'Player added!' : '$succeeded players added!')
              : '$succeeded added, $failed skipped${lastError != null ? ': $lastError' : ''}',
        ),
        backgroundColor: failed == 0 ? AppColors.success : AppColors.warning,
      ),
    );
  }

  Future<void> _addGuest() async {
    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => AddGuestDialog(
        leagueId: widget.leagueId,
        sport: widget.sport,
        genderCategory: widget.genderCategory,
      ),
    );
    if (added == true && mounted) {
      setState(() => _anyChanges = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Guest added!'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _handleBack() {
    Navigator.pop(context, _anyChanges);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;
    final borderColor = isDark ? Colors.grey.shade700 : Colors.grey.shade200;
    final titleColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? AppColors.textDark;
    final subtitleColor = isDark ? Colors.grey.shade400 : Colors.grey.shade700;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Add Players'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: _handleBack,
          ),
          actions: [
            TextButton.icon(
              onPressed: _addGuest,
              icon: const Icon(Icons.person_add_alt_1, size: 18),
              label: const Text('Guest'),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: const InputDecoration(
                  labelText: 'Search by username',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            Expanded(
              child: _searching
                  ? const SkeletonList(count: 3)
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!, textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: () =>
                                  _search(_searchController.text),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _results.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _searchController.text.trim().length < 2
                              ? 'Type at least 2 characters to search.'
                              : 'No matching players found.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _results.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final user = _results[index];
                        final isAdded = _addedIds.contains(user['id']);
                        final isSelected = _selectedIds.contains(user['id']);

                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: borderColor),
                            boxShadow: AppShadows.card(isDark),
                          ),
                          child: CheckboxListTile(
                            value: isAdded ? true : isSelected,
                            onChanged: isAdded || _submitting
                                ? null
                                : (_) => _toggleSelected(user['id']),
                            controlAffinity: ListTileControlAffinity.leading,
                            secondary: isAdded
                                ? const Icon(
                                    Icons.check_circle,
                                    color: AppColors.success,
                                  )
                                : null,
                            title: Text(
                              user['username'],
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: titleColor,
                              ),
                            ),
                            subtitle: Text(
                              user['location'] ?? '',
                              style: TextStyle(
                                fontSize: 12,
                                color: subtitleColor,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (_selectedIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _addSelected,
                    child: _submitting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            _selectedIds.length == 1
                                ? 'Add Player'
                                : 'Add ${_selectedIds.length} Players',
                          ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
