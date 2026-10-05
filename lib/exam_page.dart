import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'grade_service.dart';

const gradeCacheKey = 'exam_grades_v1';

class ExamPage extends StatefulWidget {
  const ExamPage({super.key, this.service});
  final GradeService? service;
  @override
  State<ExamPage> createState() => ExamPageState();
}

class ExamPageState extends State<ExamPage> {
  late final GradeService _service = widget.service ?? GradeService();
  Map<String, dynamic>? _cache;
  bool _busy = true;
  bool _expanded = false;
  String? _error;
  final _vertical = ScrollController();
  final _horizontal = ScrollController();

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(gradeCacheKey);
      if (raw != null) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        if (decoded['data'] is! List) throw const FormatException();
        _cache = decoded;
      }
    } catch (_) {
      _error = '本地成绩无法读取，请刷新重新获取';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (_cache == null) await refresh();
  }

  Future<void> refresh() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      Map<String, dynamic>? data;
      if (_service.hasSession) {
        try {
          data = await _service.fetchGrades();
        } on LoginRequired {
          /* Prompt below. */
        }
      }
      if (data == null) {
        if (!mounted) return;
        data = await showDialog<Map<String, dynamic>>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _GradeLoginDialog(service: _service),
        );
      }
      if (data != null) {
        if (!mounted) return;
        setState(() => _cache = data);
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(gradeCacheKey, jsonEncode(data));
        } catch (_) {
          _error = '成绩已获取，但本地保存失败，请稍后刷新重试';
        }
      }
    } catch (error) {
      _error = _friendlyError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          if (!_expanded) ...[
            Expanded(child: _panel('考试时间', const SizedBox.expand())),
            const SizedBox(height: 12),
          ],
          Expanded(
            key: const ValueKey('exam-grades-panel'),
            child: _panel(
              '考试成绩',
              _grades(),
              action: IconButton(
                tooltip: _expanded ? '缩小' : '放大',
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                  _expanded ? Icons.fullscreen_exit : Icons.fullscreen,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _panel(String title, Widget content, {Widget? action}) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xffe3e8ef)),
    ),
    child: Column(
      children: [
        SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ?action,
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(child: content),
      ],
    ),
  );

  Widget _grades() {
    final rows = (_cache?['data'] as List? ?? []).whereType<Map>().toList();
    final groups = <String, List<Map>>{};
    for (final row in rows) {
      final term =
          ['xnxqid', 'xqmc', 'xqstr']
              .map((key) => '${row[key] ?? ''}'.trim())
              .where((value) => value.isNotEmpty)
              .firstOrNull ??
          '未知学期';
      groups.putIfAbsent(term, () => []).add(row);
    }
    final terms = groups.keys.toList()..sort(_compareTerms);
    final entries = <({String term, Map? row, bool header})>[
      for (final term in terms) ...[
        (term: term, row: null, header: false),
        (term: term, row: const {}, header: true),
        for (final row in groups[term]!) (term: term, row: row, header: false),
      ],
    ];
    return Column(
      children: [
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              _error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_cache != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '共 ${rows.length} 门 · 更新于 ${_savedTime()}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Color(0xff5f6b7a)),
              ),
            ),
          ),
        Expanded(
          child: _cache == null
              ? Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('登录教务系统后查看成绩'),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _busy ? null : refresh,
                          child: const Text('登录'),
                        ),
                      ],
                    ),
                  ),
                )
              : rows.isEmpty
              ? const Center(child: Text('暂无考试成绩'))
              : LayoutBuilder(
                  builder: (context, constraints) => Scrollbar(
                    controller: _horizontal,
                    thumbVisibility: true,
                    notificationPredicate: (n) =>
                        n.metrics.axis == Axis.horizontal,
                    child: SingleChildScrollView(
                      controller: _horizontal,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: constraints.maxWidth < 1350
                            ? 1350
                            : constraints.maxWidth,
                        child: Scrollbar(
                          controller: _vertical,
                          thumbVisibility: true,
                          child: ListView.builder(
                            controller: _vertical,
                            itemExtent: 72,
                            cacheExtent: 216,
                            padding: const EdgeInsets.only(bottom: 16),
                            itemCount: entries.length,
                            itemBuilder: (context, index) {
                              final entry = entries[index];
                              if (entry.row == null) {
                                return ColoredBox(
                                  color: const Color(0xffe8f0fe),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        '${entry.term} · ${groups[entry.term]!.length} 门',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xff2c7be5),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }
                              return _gradeRow(
                                entry.row!,
                                header: entry.header,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  static const _columns = <({String label, String key, double width})>[
    (label: '课程名称', key: 'kc_mc', width: 260),
    (label: '成绩', key: 'zcjstr', width: 80),
    (label: '学分', key: 'xf', width: 70),
    (label: '绩点', key: 'jd', width: 70),
    (label: '学期', key: 'xqmc', width: 150),
    (label: '课程属性', key: 'kcsx', width: 100),
    (label: '课程性质', key: 'kcxzmc', width: 150),
    (label: '考核方式', key: 'ksfs', width: 100),
    (label: '考试性质', key: 'ksxz', width: 110),
    (label: '学时', key: 'zxs', width: 80),
    (label: '课程编号', key: 'kch', width: 180),
  ];

  Widget _gradeRow(Map row, {required bool header}) => DecoratedBox(
    decoration: BoxDecoration(
      color: header ? const Color(0xffeef4fd) : Colors.white,
      border: const Border(bottom: BorderSide(color: Color(0xffe3e8ef))),
    ),
    child: Row(
      children: [
        for (final column in _columns)
          SizedBox(
            width: column.width,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Semantics(
                header: header,
                child: Text(
                  header
                      ? column.label
                      : _value(
                          row,
                          column.key,
                          fallback: column.key == 'zcjstr'
                              ? 'zcj'
                              : column.key == 'xqmc'
                              ? 'xnxqid'
                              : null,
                        ),
                  maxLines: column.key == 'kc_mc' ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: header || column.key == 'zcjstr'
                        ? FontWeight.w700
                        : FontWeight.normal,
                    color: !header && column.key == 'zcjstr'
                        ? const Color(0xff2c7be5)
                        : null,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
  String _savedTime() => '${_cache?['savedAt'] ?? _cache?['tjsj'] ?? '—'}'
      .replaceFirst('T', ' ')
      .split('.')
      .first;

  static int _compareTerms(String a, String b) {
    if (a == b) return 0;
    if (a == '未知学期') return 1;
    if (b == '未知学期') return -1;
    final aParts = RegExp(
      r'\d+',
    ).allMatches(a).map((m) => int.parse(m[0]!)).toList();
    final bParts = RegExp(
      r'\d+',
    ).allMatches(b).map((m) => int.parse(m[0]!)).toList();
    for (var i = 0; i < aParts.length && i < bParts.length; i++) {
      final comparison = bParts[i].compareTo(aParts[i]);
      if (comparison != 0) return comparison;
    }
    return b.compareTo(a);
  }

  String _value(Map row, String key, {String? fallback}) {
    final value = row[key];
    return '${value == null || value == '' ? row[fallback] ?? '—' : value}';
  }
}

String _friendlyError(Object error) {
  if (error is LoginRequired) return '账号或密码错误，或登录已失效，请重新登录';
  if (error is DioException) return '连接教务系统失败，请检查网络后重试';
  if (error is FormatException) return error.message;
  return '获取成绩失败，请稍后重试';
}

class _GradeLoginDialog extends StatefulWidget {
  const _GradeLoginDialog({required this.service});
  final GradeService service;
  @override
  State<_GradeLoginDialog> createState() => _GradeLoginDialogState();
}

class _GradeLoginDialogState extends State<_GradeLoginDialog> {
  final _account = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _account.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_account.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = '请输入账号和密码');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.login(_account.text.trim(), _password.text);
      final data = await widget.service.fetchGrades();
      if (mounted) Navigator.pop(context, data);
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('登录教务系统'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '首次获取成绩或登录失效时，需要登录。成绩将保存在本机。',
                style: TextStyle(color: Color(0xff5f6b7a)),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _account,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: '账号 / 学号',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _password,
                enabled: !_busy,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: '密码',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? '正在获取…' : '登录并获取成绩'),
        ),
      ],
    ),
  );
}
