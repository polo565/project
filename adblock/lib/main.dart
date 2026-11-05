import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('adblock');

void main() {
  runApp(const AdBlockApp());
}

class AdBlockApp extends StatelessWidget {
  const AdBlockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AdBlock',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.green,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Map<String, dynamic> _status = const {};
  Timer? _timer;
  bool _busy = false;
  bool _updating = false;
  bool _checkedList = false;

  bool get _running => _status['running'] == true;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final s = await _channel.invokeMapMethod<String, dynamic>('status');
    if (!mounted || s == null) return;
    setState(() => _status = s);
    // Premier lancement : télécharge la liste complète automatiquement.
    if (!_checkedList) {
      _checkedList = true;
      if ((s['listDate'] as int? ?? 0) == 0) _updateList(silent: true);
    }
  }

  Future<void> _toggle(bool on) async {
    setState(() => _busy = true);
    try {
      if (on) {
        final ok = await _channel.invokeMethod<bool>('start') ?? false;
        if (!ok) _snack('Autorisation VPN refusée.');
      } else {
        await _channel.invokeMethod('stop');
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updateList({bool silent = false}) async {
    setState(() => _updating = true);
    try {
      final n = await _channel.invokeMethod<int>('updateList');
      if (!silent) _snack('Liste mise à jour : $n domaines.');
    } on PlatformException catch (e) {
      if (!silent) _snack('Échec du téléchargement : ${e.message}');
    } finally {
      if (mounted) setState(() => _updating = false);
      await _refresh();
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final recent = (_status['recent'] as List?)?.cast<String>() ?? const [];
    final listDate = _status['listDate'] as int? ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('AdBlock')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: _running ? scheme.primaryContainer : null,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(
                    _running ? Icons.shield : Icons.shield_outlined,
                    size: 48,
                    color: _running ? scheme.primary : scheme.outline,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      _running ? 'Protection activée' : 'Protection désactivée',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Switch(
                    value: _running,
                    onChanged: _busy ? null : _toggle,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _StatCard(label: 'Pubs bloquées', value: '${_status['blocked'] ?? 0}'),
              const SizedBox(width: 8),
              _StatCard(label: 'Requêtes', value: '${_status['total'] ?? 0}'),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.apps),
              title: const Text('Applications autorisées'),
              subtitle: const Text('Choisir les apps qui peuvent afficher des pubs'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AllowedAppsPage()),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.list_alt),
              title: Text('${_status['listSize'] ?? 0} domaines bloqués'),
              subtitle: Text(listDate == 0
                  ? 'Liste de base (pas encore téléchargée)'
                  : 'Mise à jour le ${_formatDate(listDate)}'),
              trailing: _updating
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      tooltip: 'Mettre à jour',
                      icon: const Icon(Icons.refresh),
                      onPressed: () => _updateList(),
                    ),
            ),
          ),
          if (recent.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
              child: Text('Derniers blocages',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            Card(
              child: Column(
                children: [
                  for (final d in recent.take(20))
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.block, size: 18),
                      title: Text(d, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: Theme.of(context).textTheme.headlineMedium),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}

class InstalledApp {
  InstalledApp(this.package, this.name, this.icon);

  final String package;
  final String name;
  final Uint8List icon;
}

class AllowedAppsPage extends StatefulWidget {
  const AllowedAppsPage({super.key});

  @override
  State<AllowedAppsPage> createState() => _AllowedAppsPageState();
}

class _AllowedAppsPageState extends State<AllowedAppsPage> {
  List<InstalledApp>? _apps;
  Set<String> _allowed = {};
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final allowed = await _channel.invokeListMethod<String>('getAllowed') ?? [];
    final raw = await _channel.invokeListMethod<Map>('getApps') ?? [];
    if (!mounted) return;
    setState(() {
      _allowed = allowed.toSet();
      _apps = [
        for (final a in raw)
          InstalledApp(a['package'] as String, a['name'] as String, a['icon'] as Uint8List),
      ];
    });
  }

  Future<void> _set(String package, bool allow) async {
    setState(() => allow ? _allowed.add(package) : _allowed.remove(package));
    await _channel.invokeMethod('setAllowed', _allowed.toList());
  }

  @override
  Widget build(BuildContext context) {
    final apps = _apps;
    final q = _query.toLowerCase();
    final visible = apps
        ?.where((a) => q.isEmpty || a.name.toLowerCase().contains(q) || a.package.contains(q))
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Applications autorisées')),
      body: apps == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    'Active une application pour autoriser ses publicités. '
                    'Les autres sont bloquées.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Rechercher une application',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: visible!.length,
                    itemBuilder: (context, i) {
                      final app = visible[i];
                      final allowed = _allowed.contains(app.package);
                      return SwitchListTile(
                        secondary: Image.memory(app.icon, width: 40, height: 40),
                        title: Text(app.name),
                        subtitle: Text(
                          allowed ? 'Pubs autorisées' : 'Pubs bloquées',
                          style: TextStyle(
                            color: allowed
                                ? Theme.of(context).colorScheme.tertiary
                                : Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        value: allowed,
                        onChanged: (v) => _set(app.package, v),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
