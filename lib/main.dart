import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Scripts présents au premier lancement. Ensuite la liste est sauvegardée
/// sur le téléphone et peut être modifiée depuis l'application.
const List<ScriptEntry> defaultScripts = [
  ScriptEntry(
    name: 'Script 1 (admin)',
    url:
        'https://script.google.com/macros/s/AKfycbyN_k134kkvoqfq4h-oooFuz3zensDZtCIbkPrVNLDIJ73xvZghfLnu_X1jAYb985HkEg/exec?admin=1',
  ),
  ScriptEntry(
    name: 'Script 2',
    url:
        'https://script.google.com/macros/s/AKfycbyKs2NrDJjS2IW3y99RuerF5OeMwv2g8JzPQrYXnGCmkHKs4C8hKXGG5y60Z_i8KkoR9g/exec',
  ),
  ScriptEntry(
    name: 'Script 3',
    url:
        'https://script.google.com/macros/s/AKfycbzG_ja3mKzQR9H61xCWvX3Nt03eg3aF5tUqIMEBT2I5xQlaCUKNAh4-ikqJ-XhPDDBA/exec',
  ),
];

const String _storageKey = 'scripts';

void main() {
  runApp(const AdminApp());
}

class ScriptEntry {
  const ScriptEntry({required this.name, required this.url, this.owner = ''});

  final String name;
  final String url;

  /// Compte Gmail propriétaire du script (affiché sous le nom).
  final String owner;

  Map<String, String> toJson() => {'name': name, 'url': url, 'owner': owner};

  factory ScriptEntry.fromJson(Map<String, dynamic> json) => ScriptEntry(
        name: json['name'] as String? ?? '',
        url: json['url'] as String? ?? '',
        owner: json['owner'] as String? ?? '',
      );
}

class ScriptStore {
  static Future<List<ScriptEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) return List.of(defaultScripts);
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => ScriptEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> save(List<ScriptEntry> scripts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(scripts.map((s) => s.toJson()).toList()),
    );
  }
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
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
  List<ScriptEntry>? _scripts;

  @override
  void initState() {
    super.initState();
    ScriptStore.load().then((s) => setState(() => _scripts = s));
  }

  Future<void> _update(List<ScriptEntry> scripts) async {
    setState(() => _scripts = scripts);
    await ScriptStore.save(scripts);
  }

  Future<void> _addOrEdit({int? index}) async {
    final scripts = _scripts!;
    final result = await showDialog<ScriptEntry>(
      context: context,
      builder: (_) =>
          ScriptDialog(initial: index == null ? null : scripts[index]),
    );
    if (result == null) return;
    final updated = List.of(scripts);
    if (index == null) {
      updated.add(result);
    } else {
      updated[index] = result;
    }
    await _update(updated);
  }

  Future<void> _delete(int index) async {
    final entry = _scripts![index];
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ?'),
        content: Text('Supprimer « ${entry.name} » de la liste ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok == true) await _update(List.of(_scripts!)..removeAt(index));
  }

  void _open(ScriptEntry entry) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WebPage(entry: entry)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scripts = _scripts;
    return Scaffold(
      appBar: AppBar(title: const Text('Mes scripts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: scripts == null ? null : () => _addOrEdit(),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter'),
      ),
      body: scripts == null
          ? const Center(child: CircularProgressIndicator())
          : scripts.isEmpty
              ? const Center(child: Text('Aucun script. Appuie sur « Ajouter ».'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                  itemCount: scripts.length,
                  itemBuilder: (context, i) {
                    final s = scripts[i];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: Text(s.name),
                        subtitle: Text(
                          s.owner.isEmpty ? s.url : s.owner,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _open(s),
                        trailing: PopupMenuButton<String>(
                          onSelected: (action) => action == 'edit'
                              ? _addOrEdit(index: i)
                              : _delete(i),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Modifier')),
                            PopupMenuItem(
                                value: 'delete', child: Text('Supprimer')),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class ScriptDialog extends StatefulWidget {
  const ScriptDialog({super.key, this.initial});

  final ScriptEntry? initial;

  @override
  State<ScriptDialog> createState() => _ScriptDialogState();
}

class _ScriptDialogState extends State<ScriptDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _owner = TextEditingController(text: widget.initial?.owner);
  late final _url = TextEditingController(text: widget.initial?.url);

  @override
  void dispose() {
    _name.dispose();
    _owner.dispose();
    _url.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      ScriptEntry(
        name: _name.text.trim(),
        owner: _owner.text.trim(),
        url: _url.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Ajouter un script' : 'Modifier'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nom'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Nom obligatoire' : null,
              ),
              TextFormField(
                controller: _owner,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Compte Gmail propriétaire (optionnel)',
                ),
              ),
              TextFormField(
                controller: _url,
                keyboardType: TextInputType.url,
                maxLines: 3,
                minLines: 1,
                decoration: const InputDecoration(
                  labelText: 'URL',
                  hintText: 'https://script.google.com/macros/s/.../exec',
                ),
                validator: (v) {
                  final uri = Uri.tryParse(v?.trim() ?? '');
                  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
                    return 'URL invalide (doit commencer par https://)';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Enregistrer')),
      ],
    );
  }
}

class WebPage extends StatefulWidget {
  const WebPage({super.key, required this.entry});

  final ScriptEntry entry;

  @override
  State<WebPage> createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  late final WebViewController _controller;
  int _progress = 0;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) => setState(() => _progress = p),
          onPageStarted: (_) => setState(() => _hasError = false),
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? true) {
              setState(() => _hasError = true);
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.entry.url));
  }

  Future<void> _reload() async {
    setState(() => _hasError = false);
    await _controller.loadRequest(Uri.parse(widget.entry.url));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _controller.canGoBack()) {
          await _controller.goBack();
        } else if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.entry.name),
          actions: [
            IconButton(
              tooltip: 'Recharger',
              icon: const Icon(Icons.refresh),
              onPressed: _reload,
            ),
          ],
        ),
        body: Stack(
          children: [
            if (_hasError)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off, size: 64),
                    const SizedBox(height: 16),
                    const Text('Impossible de charger la page.'),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Réessayer'),
                    ),
                  ],
                ),
              )
            else
              WebViewWidget(controller: _controller),
            if (_progress < 100 && !_hasError)
              LinearProgressIndicator(value: _progress / 100),
          ],
        ),
      ),
    );
  }
}
