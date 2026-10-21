import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:webview_flutter/webview_flutter.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const _deviceName = 'Remim Android';
const _homeUrl = 'https://www.google.com/';
const _tabLimit = 16;
const _freezeAfter = Duration(seconds: 60);
const _blockedHosts = <String>{
  'doubleclick.net', 'googlesyndication.com', 'googleadservices.com',
  'google-analytics.com', 'googletagmanager.com', 'adservice.google.com',
  'connect.facebook.net', 'pixel.facebook.com', 'scorecardresearch.com',
  'taboola.com', 'outbrain.com', 'adroll.com', 'adnxs.com', 'criteo.com',
  'hotjar.com', 'clarity.ms', 'bat.bing.com', 'amazon-adsystem.com',
  'casalemedia.com', 'rubiconproject.com', 'pubmatic.com', 'openx.net',
  'moatads.com',
};

SupabaseClient? _supabase;

bool get _hasCloudConfig =>
    _supabaseUrl.startsWith('https://') &&
    _supabaseUrl.endsWith('.supabase.co') &&
    _supabaseKey.length > 20 &&
    !_supabaseKey.contains('YOUR_');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_hasCloudConfig) {
    try {
      await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseKey);
      _supabase = Supabase.instance.client;
    } catch (error) {
      debugPrint('Remim Supabase init skipped: $error');
    }
  }
  runApp(const RemimApp());
}

class BrowserTab {
  BrowserTab({required this.id, required this.url, this.title = 'New tab'});

  final String id;
  String url;
  String title;
  String? snapshot;
  bool frozen = false;
  WebViewController? controller;
  Timer? freezeTimer;
  DateTime lastActive = DateTime.now();
}

class RemimApp extends StatelessWidget {
  const RemimApp({super.key});

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF101514);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Remim Browser',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF88DFA6),
          brightness: Brightness.dark,
          surface: const Color(0xFF18201C),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: background,
          foregroundColor: Color(0xFFEAF4ED),
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1C2621),
          contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: Color(0xFF314137)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: Color(0xFF314137)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: Color(0xFF84D99F)),
          ),
        ),
        useMaterial3: true,
      ),
      home: const BrowserScreen(),
    );
  }
}

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> with WidgetsBindingObserver {
  final _addressController = TextEditingController();
  final _uuid = const Uuid();
  final List<BrowserTab> _tabs = [];
  final List<Map<String, dynamic>> _bookmarks = [];
  final List<Map<String, dynamic>> _history = [];
  int _activeIndex = 0;
  bool _lowMemory = true;
  bool _loading = false;
  String _syncStatus = 'Local only';
  String? _deviceId;
  RealtimeChannel? _transferChannel;
  StreamSubscription<AuthState>? _authSubscription;
  Timer? _heartbeat;

  BrowserTab? get _activeTab => _tabs.isEmpty ? null : _tabs[_activeIndex];
  User? get _user => _supabase?.auth.currentUser;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeLocalState();
    if (_supabase != null) {
      _authSubscription = _supabase!.auth.onAuthStateChange.listen((state) {
        if (!mounted) return;
        if (state.session != null) {
          unawaited(_startCloudSession());
        } else {
          _stopCloudSession();
          setState(() => _syncStatus = 'Sign in to sync');
        }
      });
      if (_user != null) unawaited(_startCloudSession());
    }
  }

  Future<void> _initializeLocalState() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('remim.device-id') ?? _uuid.v4();
    await prefs.setString('remim.device-id', _deviceId!);
    _lowMemory = prefs.getBool('remim.low-memory') ?? true;
    _bookmarks
      ..clear()
      ..addAll(_decodeList(prefs.getString('remim.bookmarks')));
    _history
      ..clear()
      ..addAll(_decodeList(prefs.getString('remim.history')));
    final savedTabs = _decodeList(prefs.getString('remim.tabs'));
    if (_tabs.isEmpty) {
      final restored = savedTabs.take(_tabLimit).toList();
      if (restored.isNotEmpty) {
        for (final item in restored) {
          final url = _normalizeAddress((item['url'] ?? _homeUrl).toString());
          if (url == null) continue;
          final tab = BrowserTab(
            id: (item['id'] ?? _uuid.v4()).toString(),
            url: url,
            title: (item['title'] ?? 'Saved tab').toString(),
          );
          tab.frozen = true;
          tab.snapshot = (item['snapshot'] ?? '').toString();
          _tabs.add(tab);
        }
      }
      if (_tabs.isEmpty) _tabs.add(BrowserTab(id: _uuid.v4(), url: _homeUrl));
      _activeIndex = 0;
      _addressController.text = _activeTab?.url ?? _homeUrl;
      if (mounted) setState(() {});
      unawaited(_ensureLive(_activeTab!));
      if (_user != null && _supabase != null) unawaited(_startCloudSession());
    }
    if (mounted) setState(() {});
  }

  List<Map<String, dynamic>> _decodeList(String? source) {
    if (source == null || source.isEmpty) return [];
    try {
      final value = jsonDecode(source);
      if (value is List) {
        return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {
      // Ignore corrupted local metadata and keep the browser usable.
    }
    return [];
  }

  Future<void> _persistLocalState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('remim.low-memory', _lowMemory);
    await prefs.setString('remim.bookmarks', jsonEncode(_bookmarks));
    await prefs.setString('remim.history', jsonEncode(_history.take(300).toList()));
    await prefs.setString('remim.tabs', jsonEncode(_tabs.map((t) => {
      'id': t.id,
      'url': t.url,
      'title': t.title,
      'snapshot': (t.snapshot ?? '').length > 12000 ? t.snapshot!.substring(0, 12000) : t.snapshot,
    }).toList()));
  }

  String? _normalizeAddress(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return _homeUrl;
    if (RegExp(r'^(javascript|file|data|vbscript):', caseSensitive: false).hasMatch(raw)) return null;
    final direct = Uri.tryParse(raw);
    if (direct != null && (direct.scheme == 'https' || direct.scheme == 'http') && direct.host.isNotEmpty) {
      return direct.toString();
    }
    if (RegExp(r'^(localhost|127(?:\.\d{1,3}){3})(:\d+)?(?:/|$)', caseSensitive: false).hasMatch(raw)) {
      return 'http://$raw';
    }
    if (RegExp(r'^[\w-]+(?:\.[\w-]+)+(?:\:\d+)?(?:/[^\s]*)?$', caseSensitive: false).hasMatch(raw)) {
      return 'https://$raw';
    }
    return 'https://www.google.com/search?q=${Uri.encodeQueryComponent(raw)}';
  }

  bool _isBlocked(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    return _blockedHosts.any((domain) => host == domain || host.endsWith('.$domain')) ||
        (host == 'facebook.com' && uri.path == '/tr');
  }

  Future<WebViewController> _makeController(BrowserTab tab) async {
    final controller = WebViewController();
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(NavigationDelegate(
      onNavigationRequest: (request) {
        final uri = Uri.tryParse(request.url);
        if (_isBlocked(request.url)) return NavigationDecision.prevent;
        if (uri == null || !{'http', 'https', 'about'}.contains(uri.scheme)) {
          return NavigationDecision.prevent;
        }
        return NavigationDecision.navigate;
      },
      onPageStarted: (url) {
        if (url.startsWith('http://') || url.startsWith('https://')) {
          tab.url = url;
          if (tab.id == _activeTab?.id && mounted) {
            _addressController.text = url;
            setState(() => _loading = true);
          }
        }
      },
      onPageFinished: (url) async {
        if (!url.startsWith('http://') && !url.startsWith('https://')) return;
        tab.url = url;
        tab.frozen = false;
        tab.lastActive = DateTime.now();
        try {
          await controller.runJavaScript('''(() => {
            const style = document.createElement('style');
            style.id = '__remim_lite__';
            style.textContent = '*,*::before,*::after{scroll-behavior:auto!important;animation-duration:.001ms!important;animation-iteration-count:1!important;transition-duration:.001ms!important} iframe[src*="doubleclick" i],iframe[src*="googlesyndication" i],iframe[id*="ad" i],[aria-label*="advertisement" i],[data-ad-slot],[data-ad-unit],.adsbygoogle,.advertisement,.ad-banner{display:none!important}';
            if (!document.getElementById(style.id)) (document.head || document.documentElement).appendChild(style);
          })()''');
          final pageTitle = await controller.getTitle();
          if (pageTitle != null && pageTitle.trim().isNotEmpty) {
          final cleanTitle = pageTitle.trim();
          tab.title = cleanTitle.substring(0, cleanTitle.length > 300 ? 300 : cleanTitle.length);
        }
        } catch (_) {
          // Pages can forbid script execution; navigation still works.
        }
        if (mounted && tab.id == _activeTab?.id) {
          _addressController.text = tab.url;
          setState(() => _loading = false);
        }
        await _recordVisit(tab);
        await _persistLocalState();
      },
      onWebResourceError: (error) {
        if (error.isForMainFrame == true && mounted && tab.id == _activeTab?.id) {
          setState(() => _loading = false);
          _showMessage('Could not load this page. Check the address or connection.');
        }
      },
    ));
    tab.controller = controller;
    tab.frozen = false;
    await controller.loadRequest(Uri.parse(tab.url));
    return controller;
  }

  Future<void> _ensureLive(BrowserTab tab) async {
    if (tab.controller != null) return;
    if (!mounted) return;
    setState(() {
      _loading = true;
      if (tab.id == _activeTab?.id) _addressController.text = tab.url;
    });
    try {
      await _makeController(tab);
    } catch (error) {
      tab.controller = null;
      if (mounted) {
        setState(() => _loading = false);
        _showMessage('Browser view could not start: $error');
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _captureSnapshot(BrowserTab tab) async {
    final controller = tab.controller;
    if (controller == null) return;
    try {
      final result = await controller.runJavaScriptReturningResult(
        "JSON.stringify({title:document.title||'',text:(document.body?.innerText||'').slice(0,8000)})",
      );
      var raw = result.toString();
      dynamic decoded;
      try {
        decoded = jsonDecode(raw);
        if (decoded is String) decoded = jsonDecode(decoded);
      } catch (_) {
        decoded = null;
      }
      if (decoded is Map) {
        final title = decoded['title']?.toString();
        final text = decoded['text']?.toString();
        if (title != null && title.isNotEmpty) tab.title = title.substring(0, title.length > 300 ? 300 : title.length);
        final cleanText = text ?? '';
        tab.snapshot = cleanText.substring(0, cleanText.length > 8000 ? 8000 : cleanText.length);
      }
    } catch (_) {
      tab.snapshot ??= '${tab.title}\n${tab.url}';
    }
  }

  Future<void> _switchTab(int index) async {
    if (index < 0 || index >= _tabs.length || index == _activeIndex) return;
    final outgoing = _activeTab;
    if (outgoing != null) {
      outgoing.lastActive = DateTime.now();
      await _captureSnapshot(outgoing);
      outgoing.freezeTimer?.cancel();
      if (_lowMemory) {
        outgoing.freezeTimer = Timer(_freezeAfter, () {
          if (!mounted || outgoing.id == _activeTab?.id) return;
          outgoing.controller = null;
          outgoing.frozen = true;
          outgoing.freezeTimer = null;
          unawaited(_persistLocalState());
          setState(() {});
        });
      }
    }
    _tabs[index].freezeTimer?.cancel();
    _tabs[index].freezeTimer = null;
    _tabs[index].lastActive = DateTime.now();
    setState(() {
      _activeIndex = index;
      _addressController.text = _tabs[index].url;
      _loading = _tabs[index].controller == null;
    });
    await _ensureLive(_tabs[index]);
    unawaited(_persistLocalState());
  }

  Future<void> _newTab([String? address]) async {
    if (_tabs.length >= _tabLimit) {
      _showMessage('Tab limit reached ($_tabLimit). Close a tab first.');
      return;
    }
    final outgoing = _activeTab;
    if (outgoing != null) {
      await _captureSnapshot(outgoing);
      outgoing.freezeTimer?.cancel();
      if (_lowMemory) {
        outgoing.freezeTimer = Timer(_freezeAfter, () {
          if (!mounted || outgoing.id == _activeTab?.id) return;
          outgoing.controller = null;
          outgoing.frozen = true;
          outgoing.freezeTimer = null;
          unawaited(_persistLocalState());
          setState(() {});
        });
      }
    }
    final target = _normalizeAddress(address ?? _homeUrl);
    if (target == null) return _showMessage('Only HTTP/HTTPS web addresses are allowed.');
    final tab = BrowserTab(id: _uuid.v4(), url: target);
    setState(() {
      _tabs.add(tab);
      _activeIndex = _tabs.length - 1;
      _addressController.text = target;
      _loading = true;
    });
    await _ensureLive(tab);
    await _persistLocalState();
  }

  Future<void> _closeTab(int index) async {
    if (index < 0 || index >= _tabs.length) return;
    final tab = _tabs[index];
    tab.freezeTimer?.cancel();
    if (tab.controller != null) {
      try { await tab.controller!.clearCache(); } catch (_) {}
    }
    setState(() {
      _tabs.removeAt(index);
      if (_tabs.isEmpty) _tabs.add(BrowserTab(id: _uuid.v4(), url: _homeUrl));
      if (index < _activeIndex) _activeIndex--;
      if (_activeIndex >= _tabs.length) _activeIndex = _tabs.length - 1;
      _addressController.text = _activeTab?.url ?? _homeUrl;
      _loading = _activeTab?.controller == null;
    });
    await _ensureLive(_activeTab!);
    await _persistLocalState();
  }

  Future<void> _navigate(String input) async {
    final url = _normalizeAddress(input);
    if (url == null) return _showMessage('Only HTTP/HTTPS web addresses are allowed.');
    final tab = _activeTab;
    if (tab == null) return;
    tab.freezeTimer?.cancel();
    tab.freezeTimer = null;
    tab.url = url;
    tab.snapshot = null;
    tab.frozen = false;
    _addressController.text = url;
    setState(() => _loading = true);
    if (tab.controller == null) {
      await _ensureLive(tab); // Controller creation loads the new URL.
    } else {
      try {
        await tab.controller!.loadRequest(Uri.parse(url));
      } catch (_) {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  Future<void> _goBack() async {
    final controller = _activeTab?.controller;
    if (controller == null) return;
    if (await controller.canGoBack()) await controller.goBack();
  }

  Future<void> _goForward() async {
    final controller = _activeTab?.controller;
    if (controller == null) return;
    if (await controller.canGoForward()) await controller.goForward();
  }

  Future<void> _toggleLowMemory(bool value) async {
    setState(() => _lowMemory = value);
    if (!value) {
      for (final tab in _tabs) {
        tab.freezeTimer?.cancel();
        tab.freezeTimer = null;
      }
    } else {
      for (final tab in _tabs) {
        if (tab.id == _activeTab?.id || tab.controller == null) continue;
        tab.freezeTimer?.cancel();
        tab.freezeTimer = Timer(_freezeAfter, () {
          if (!mounted || tab.id == _activeTab?.id) return;
          tab.controller = null;
          tab.frozen = true;
          tab.freezeTimer = null;
          unawaited(_persistLocalState());
          setState(() {});
        });
      }
    }
    await _persistLocalState();
  }

  bool _isBookmarked(String url) => _bookmarks.any((item) => item['url'] == url);

  Future<void> _toggleBookmark() async {
    final tab = _activeTab;
    if (tab == null || !tab.url.startsWith(RegExp(r'https?://'))) {
      return _showMessage('Open a web page before bookmarking it.');
    }
    final existing = _bookmarks.indexWhere((item) => item['url'] == tab.url);
    if (existing >= 0) {
      _bookmarks.removeAt(existing);
      if (_supabase != null && _user != null) {
        await _supabase!.from('bookmarks').delete().eq('user_id', _user!.id).eq('url', tab.url);
      }
      _showMessage('Bookmark removed.');
    } else {
      final item = {'url': tab.url, 'title': tab.title, 'created_at': DateTime.now().toIso8601String()};
      _bookmarks.insert(0, item);
      if (_supabase != null && _user != null) {
        try {
        await _supabase!.from('bookmarks').upsert({
          'user_id': _user!.id, 'url': tab.url, 'title': tab.title,
        }, onConflict: 'user_id,url');
      } catch (_) {
        _showMessage('Bookmark saved locally; cloud sync may retry later.');
      }
      }
      _showMessage('Bookmark saved.');
    }
    await _persistLocalState();
    if (mounted) setState(() {});
  }

  Future<void> _recordVisit(BrowserTab tab) async {
    if (!tab.url.startsWith(RegExp(r'https?://'))) return;
    final row = {'url': tab.url, 'title': tab.title, 'visitedAt': DateTime.now().toIso8601String()};
    _history.removeWhere((item) => item['url'] == tab.url);
    _history.insert(0, row);
    if (_history.length > 300) _history.removeRange(300, _history.length);
    if (_supabase != null && _user != null) {
      try {
        await _supabase!.from('browsing_history').insert({
          'user_id': _user!.id,
          'url': tab.url,
          'title': tab.title,
          'visited_at': row['visitedAt'],
        });
      } catch (error) {
        debugPrint('History cloud sync failed: $error');
      }
      unawaited(_updateDeviceSession());
    }
    await _persistLocalState();
  }

  Future<void> _loadCloudBookmarks() async {
    if (_supabase == null || _user == null) return;
    try {
      final rows = await _supabase!.from('bookmarks').select('url,title,created_at')
          .eq('user_id', _user!.id).order('created_at', ascending: false).limit(500);
      final merged = <String, Map<String, dynamic>>{};
      for (final item in (rows as List).whereType<Map>()) {
        final row = Map<String, dynamic>.from(item);
        merged[row['url'].toString()] = row;
      }
      for (final item in _bookmarks) {
        if (item['url'] != null) merged[item['url'].toString()] = item;
      }
      _bookmarks
        ..clear()
        ..addAll(merged.values.take(500));
      // Merge and upload local-only bookmarks in a single request.
      if (_bookmarks.isNotEmpty) {
        await _supabase!.from('bookmarks').upsert(
          _bookmarks.where((item) => item['url'] != null).map((item) => {
            'user_id': _user!.id,
            'url': item['url'],
            'title': item['title']?.toString() ?? '',
          }).toList(),
          onConflict: 'user_id,url',
        );
      }
      await _persistLocalState();
      if (mounted) setState(() {});
    } catch (error) {
      debugPrint('Could not load cloud bookmarks: $error');
    }
  }

  Future<void> _startCloudSession() async {
    if (_supabase == null || _user == null || _deviceId == null) {
      if (mounted) setState(() => _syncStatus = _hasCloudConfig ? 'Sign in to sync' : 'Set up Supabase');
      return;
    }
    await _updateDeviceSession();
    await _loadCloudBookmarks();
    await _transferChannel?.unsubscribe();
    final user = _user!;
    _transferChannel = _supabase!.channel('remim-transfers:${user.id}:$_deviceId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'session_transfers',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: user.id,
        ),
        callback: (payload) {
          final row = payload.newRecord;
          final sender = row['sender_device_id']?.toString();
          final target = row['target_device_id']?.toString();
          final url = row['url']?.toString() ?? '';
          final expiry = DateTime.tryParse(row['expires_at']?.toString() ?? '');
          if (sender == _deviceId || (target != null && target != _deviceId) ||
              (expiry != null && expiry.isBefore(DateTime.now())) ||
              !(url.startsWith('https://') || url.startsWith('http://'))) return;
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Tab received: ${row['title'] ?? url}', maxLines: 2, overflow: TextOverflow.ellipsis),
            action: SnackBarAction(label: 'OPEN', onPressed: () => unawaited(_newTab(url))),
            duration: const Duration(seconds: 10),
          ));
        },
      )
      ..subscribe((status, error) {
        if (!mounted) return;
        setState(() => _syncStatus = status == RealtimeSubscribeStatus.subscribed ? 'Synced' : 'Connecting…');
      });
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 60), (_) => unawaited(_updateDeviceSession()));
    if (mounted) setState(() => _syncStatus = 'Synced');
  }

  Future<void> _updateDeviceSession() async {
    if (_supabase == null || _user == null || _deviceId == null) return;
    final tab = _activeTab;
    try {
      await _supabase!.from('device_sessions').upsert({
        'user_id': _user!.id,
        'device_id': _deviceId,
        'device_name': _deviceName,
        'platform': 'android',
        'current_url': tab?.url,
        'current_title': tab?.title ?? 'Remim',
        'last_seen': DateTime.now().toIso8601String(),
        'is_active': true,
      }, onConflict: 'user_id,device_id');
    } catch (error) {
      debugPrint('Device session sync failed: $error');
      if (mounted) setState(() => _syncStatus = 'Sync offline');
    }
  }

  Future<void> _stopCloudSession() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    final channel = _transferChannel;
    _transferChannel = null;
    if (channel != null) await _supabase?.removeChannel(channel);
  }

  Future<void> _teleport() async {
    final tab = _activeTab;
    if (_supabase == null || _user == null || _deviceId == null) {
      return _showMessage('Sign in and configure Supabase on both devices to use Teleport.');
    }
    if (tab == null || !(tab.url.startsWith('https://') || tab.url.startsWith('http://'))) {
      return _showMessage('Open a web page to teleport it.');
    }
    try {
      await _supabase!.from('session_transfers').insert({
        'user_id': _user!.id,
        'sender_device_id': _deviceId,
        'target_device_id': null,
        'url': tab.url,
        'title': tab.title,
        'status': 'pending',
        'expires_at': DateTime.now().add(const Duration(minutes: 10)).toIso8601String(),
      });
      _showMessage('Tab sent to your other Remim devices.');
    } catch (error) {
      _showMessage('Could not transfer tab: $error');
    }
  }

  Future<void> _showAuthDialog() async {
    if (_supabase == null) {
      return _showMessage('Cloud sync is optional. Set SUPABASE_URL and SUPABASE_ANON_KEY at build time.');
    }
    if (_user != null) {
      final shouldSignOut = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: const Text('Remim account'),
        content: Text('Signed in as ${_user!.email ?? 'Remim user'}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign out')),
        ],
      ));
      if (shouldSignOut == true) {
        await _supabase!.auth.signOut();
        await _stopCloudSession();
        if (mounted) setState(() => _syncStatus = 'Sign in to sync');
      }
      return;
    }
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    bool createAccount = false;
    final formKey = GlobalKey<FormState>();
    String? errorText;
    await showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(createAccount ? 'Create Remim account' : 'Sign in to Remim'),
        content: SizedBox(
          width: 380,
          child: Form(
            key: formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Email address'),
                validator: (value) => (value == null || !value.contains('@')) ? 'Enter a valid email.' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: passwordController,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: const InputDecoration(labelText: 'Password (6+ characters)'),
                validator: (value) => (value == null || value.length < 6) ? 'Use at least 6 characters.' : null,
              ),
              if (errorText != null) Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(errorText!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setDialogState(() { createAccount = !createAccount; errorText = null; }),
                  child: Text(createAccount ? 'Already have an account? Sign in' : 'New here? Create account'),
                ),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (!(formKey.currentState?.validate() ?? false)) return;
              try {
                if (createAccount) {
                  final result = await _supabase!.auth.signUp(
                    email: emailController.text.trim(), password: passwordController.text,
                  );
                  if (result.session == null) {
                    setDialogState(() => errorText = 'Check your email for the confirmation link, then sign in.');
                    return;
                  }
                } else {
                  await _supabase!.auth.signInWithPassword(
                    email: emailController.text.trim(), password: passwordController.text,
                  );
                }
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                await _startCloudSession();
              } catch (error) {
                setDialogState(() => errorText = error.toString());
              }
            },
            child: Text(createAccount ? 'Create account' : 'Sign in'),
          ),
        ],
      ),
    ));
    emailController.dispose();
    passwordController.dispose();
  }

  Future<void> _showTabsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF18201C),
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * .66,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 16, 10),
              child: Row(children: [
                const Expanded(child: Text('Open tabs', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
                Text('${_tabs.length}/$_tabLimit', style: const TextStyle(color: Color(0xFF8CA296))),
                const SizedBox(width: 8),
                IconButton(onPressed: () { Navigator.pop(context); unawaited(_newTab()); }, icon: const Icon(Icons.add)),
              ]),
            ),
            Expanded(child: ListView.builder(
              itemCount: _tabs.length,
              itemBuilder: (context, index) {
                final tab = _tabs[index];
                return ListTile(
                  selected: index == _activeIndex,
                  leading: Icon(tab.frozen ? Icons.bolt : Icons.language, color: tab.frozen ? const Color(0xFFE0BD77) : const Color(0xFF91DCA7)),
                  title: Text(tab.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(tab.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(icon: const Icon(Icons.close), onPressed: () { Navigator.pop(context); unawaited(_closeTab(index)); }),
                  onTap: () { Navigator.pop(context); unawaited(_switchTab(index)); },
                );
              },
            )),
          ]),
        ),
      ),
    );
  }

  Future<void> _showSavedList({required bool bookmarks}) async {
    final rows = bookmarks ? _bookmarks : _history;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF18201C),
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * .72,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(children: [
                Expanded(child: Text(bookmarks ? 'Bookmarks' : 'Recent history', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
                if (!bookmarks) Text('${_history.length} pages', style: const TextStyle(color: Color(0xFF8CA296))),
              ]),
            ),
            Expanded(child: rows.isEmpty
              ? Center(child: Text(bookmarks ? 'No bookmarks saved yet.' : 'No browsing history yet.', style: const TextStyle(color: Color(0xFF91A39A))))
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final item = rows[index];
                    final url = item['url']?.toString() ?? '';
                    return ListTile(
                      leading: Icon(bookmarks ? Icons.bookmark_outline : Icons.history, color: const Color(0xFF91DCA7)),
                      title: Text(item['title']?.toString().isNotEmpty == true ? item['title'].toString() : url, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: bookmarks ? IconButton(
                        tooltip: 'Remove bookmark', icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          Navigator.pop(context);
                          _bookmarks.removeWhere((entry) => entry['url'] == url);
                          if (_supabase != null && _user != null) {
                            await _supabase!.from('bookmarks').delete().eq('user_id', _user!.id).eq('url', url);
                          }
                          await _persistLocalState();
                          if (mounted) setState(() {});
                        },
                      ) : null,
                      onTap: () { Navigator.pop(context); unawaited(_newTab(url)); },
                    );
                  },
                )),
          ]),
        ),
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
  }

  Widget _buildWebViews() {
    final children = <Widget>[];
    for (var i = 0; i < _tabs.length; i++) {
      final tab = _tabs[i];
      if (tab.controller == null) continue;
      children.add(Offstage(
        offstage: i != _activeIndex,
        child: TickerMode(enabled: i == _activeIndex, child: WebViewWidget(controller: tab.controller!)),
      ));
    }
    if (_activeTab?.controller == null) {
      children.add(Container(
        color: const Color(0xFF101514),
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.bolt, size: 34, color: Color(0xFF91DCA7)),
          const SizedBox(height: 12),
          Text(_activeTab?.frozen == true ? 'Tab frozen to save memory' : 'Opening page…', style: const TextStyle(color: Color(0xFFE5F1E8))),
          const SizedBox(height: 6),
          Text(_activeTab?.snapshot?.split('\n').take(3).join('\n') ?? '', textAlign: TextAlign.center, maxLines: 4, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF8EA296), fontSize: 12)),
          if (_activeTab?.frozen == true) TextButton.icon(
            onPressed: () => _ensureLive(_activeTab!), icon: const Icon(Icons.refresh), label: const Text('Restore live page'),
          ),
        ]),
      ));
    }
    return Stack(fit: StackFit.expand, children: children);
  }

  @override
  Widget build(BuildContext context) {
    final tab = _activeTab;
    final signedIn = _user != null;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 54,
        titleSpacing: 16,
        title: Row(children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), gradient: const LinearGradient(colors: [Color(0xFFB8F2C7), Color(0xFF49B978)])),
            alignment: Alignment.center,
            child: const Text('R', style: TextStyle(color: Color(0xFF102017), fontWeight: FontWeight.w900, fontSize: 17)),
          ),
          const SizedBox(width: 9),
          const Text('Remim', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        ]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Center(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: signedIn ? const Color(0xFF1D3A29) : const Color(0xFF252D29),
                borderRadius: BorderRadius.circular(99), border: Border.all(color: signedIn ? const Color(0xFF3E6B4C) : const Color(0xFF36443B)),
              ),
              child: Row(children: [
                Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: signedIn ? const Color(0xFF81E29A) : const Color(0xFFE1B96F))),
                const SizedBox(width: 6),
                Text(signedIn ? _syncStatus : 'Local', style: const TextStyle(fontSize: 10)),
              ]),
            )),
          ),
          IconButton(tooltip: 'Session Teleport', onPressed: _teleport, icon: const Icon(Icons.near_me_outlined)),
          PopupMenuButton<String>(
            tooltip: 'Browser menu',
            onSelected: (choice) {
              switch (choice) {
                case 'tabs': unawaited(_showTabsSheet()); break;
                case 'bookmarks': unawaited(_showSavedList(bookmarks: true)); break;
                case 'history': unawaited(_showSavedList(bookmarks: false)); break;
                case 'account': unawaited(_showAuthDialog()); break;
                case 'memory': unawaited(_toggleLowMemory(!_lowMemory)); break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'tabs', child: Text('Open tabs (${_tabs.length})')),
              const PopupMenuItem(value: 'bookmarks', child: Text('Bookmarks')),
              const PopupMenuItem(value: 'history', child: Text('History')),
              PopupMenuItem(value: 'memory', child: Text(_lowMemory ? '✓ Low-memory mode' : 'Enable low-memory mode')),
              PopupMenuItem(value: 'account', child: Text(signedIn ? 'Account / sign out' : 'Sign in to sync')),
            ],
          ),
          const SizedBox(width: 5),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
            child: Row(children: [
              Expanded(child: TextField(
                controller: _addressController,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search or enter website',
                  prefixIcon: const Icon(Icons.search, size: 21, color: Color(0xFF91DCA7)),
                  suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward, size: 20), onPressed: () => _navigate(_addressController.text)),
                ),
                onSubmitted: _navigate,
              )),
              const SizedBox(width: 7),
              IconButton.filledTonal(
                tooltip: 'New tab', onPressed: () => unawaited(_newTab()),
                icon: const Icon(Icons.add),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 7),
            child: Row(children: [
              IconButton(tooltip: 'Back', visualDensity: VisualDensity.compact, onPressed: _goBack, icon: const Icon(Icons.arrow_back, size: 20)),
              IconButton(tooltip: 'Forward', visualDensity: VisualDensity.compact, onPressed: _goForward, icon: const Icon(Icons.arrow_forward, size: 20)),
              IconButton(tooltip: 'Reload', visualDensity: VisualDensity.compact,
                onPressed: () { if (tab?.controller != null) unawaited(tab!.controller!.reload()); else if (tab != null) unawaited(_ensureLive(tab)); },
                icon: Icon(_loading ? Icons.hourglass_top : Icons.refresh, size: 21)),
              IconButton(tooltip: _isBookmarked(tab?.url ?? '') ? 'Remove bookmark' : 'Bookmark', visualDensity: VisualDensity.compact,
                onPressed: _toggleBookmark, icon: Icon(_isBookmarked(tab?.url ?? '') ? Icons.bookmark : Icons.bookmark_add_outlined,
                  color: _isBookmarked(tab?.url ?? '') ? const Color(0xFF91DCA7) : null, size: 21)),
              const Spacer(),
              Text('${_tabs.length} tab${_tabs.length == 1 ? '' : 's'}', style: const TextStyle(color: Color(0xFF8EA296), fontSize: 11)),
              const SizedBox(width: 7),
              IconButton(tooltip: _lowMemory ? 'Low-memory mode on' : 'Low-memory mode off', visualDensity: VisualDensity.compact,
                onPressed: () => unawaited(_toggleLowMemory(!_lowMemory)),
                icon: Icon(Icons.memory, size: 21, color: _lowMemory ? const Color(0xFF91DCA7) : const Color(0xFF87978E))),
            ]),
          ),
          Expanded(child: ClipRect(child: _buildWebViews())),
          Container(
            height: 27,
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF27332C))), color: Color(0xFF131A16)),
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: Row(children: [
              const Icon(Icons.shield_outlined, size: 13, color: Color(0xFF86D79B)),
              const SizedBox(width: 6),
              const Text('Tracker filter active', style: TextStyle(fontSize: 10, color: Color(0xFF8FA398))),
              const Spacer(),
              Text(_lowMemory ? 'Auto-freeze · 60s' : 'Memory saver off', style: const TextStyle(fontSize: 10, color: Color(0xFF8FA398))),
            ]),
          ),
        ]),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _user != null) unawaited(_updateDeviceSession());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _addressController.dispose();
    _heartbeat?.cancel();
    for (final tab in _tabs) {
      tab.freezeTimer?.cancel();
    }
    unawaited(_transferChannel?.unsubscribe());
    unawaited(_authSubscription?.cancel());
    super.dispose();
  }
}
