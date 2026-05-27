import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _defaultScheduleUrl =
    'https://kb.chaoxing.com/res/pc/curriculum/schedule.html?curriculumUuid=d46b44d7-88d7-470a-9497-f376dc9ba11d&kd_fidenc=33640C2C01CA94D7&text=%E4%B8%8D%E5%90%AF%E7%94%A8%E5%88%86%E5%8D%95%E4%BD%8D';
const _savedScheduleUrlKey = 'saved_schedule_url';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '课程表',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff2c7be5)),
        useMaterial3: true,
      ),
      home: const SchedulePage(),
    );
  }
}

class CourseLesson {
  const CourseLesson({
    required this.name,
    required this.teacherName,
    required this.location,
    required this.dayOfWeek,
    required this.beginNumber,
    required this.length,
    required this.wholeDay,
    required this.week,
    required this.startTime,
    required this.endTime,
  });

  final String name;
  final String teacherName;
  final String location;
  final int dayOfWeek;
  final int beginNumber;
  final int length;
  final String wholeDay;
  final int week;
  final String startTime;
  final String endTime;

  String get sectionText {
    final end = beginNumber + length - 1;
    return beginNumber == end ? '第$beginNumber节' : '第$beginNumber-$end节';
  }

  DateTime? get startDateTime => _parseDateTime(wholeDay, startTime);

  static DateTime? _parseDateTime(String date, String time) {
    final parts = time.split(':');
    if (parts.length < 2) {
      return null;
    }
    return DateTime.tryParse(
      '$date ${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}:00',
    );
  }
}

class ScheduleData {
  const ScheduleData({
    required this.lessons,
    required this.timeConfig,
    required this.currentWeek,
    required this.selectedWeek,
    required this.maxWeek,
    required this.maxLength,
    required this.weekDates,
    required this.termTitle,
  });

  final List<CourseLesson> lessons;
  final List<String> timeConfig;
  final int currentWeek;
  final int selectedWeek;
  final int maxWeek;
  final int maxLength;
  final List<DateTime> weekDates;
  final String termTitle;
}

class ScheduleConfig {
  const ScheduleConfig({
    required this.url,
    required this.curriculumUuid,
    required this.fidEnc,
    required this.unitText,
  });

  final String url;
  final String curriculumUuid;
  final String fidEnc;
  final String unitText;

  factory ScheduleConfig.fromUrl(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null || !uri.hasAbsolutePath) {
      throw const FormatException('请输入完整的课表链接');
    }

    final curriculumUuid = uri.queryParameters['curriculumUuid'] ?? '';
    final fidEnc = uri.queryParameters['kd_fidenc'] ?? '';
    final unitText = uri.queryParameters['text'] ?? '不启用分单位';
    if (curriculumUuid.isEmpty || fidEnc.isEmpty) {
      throw const FormatException('链接里缺少 curriculumUuid 或 kd_fidenc');
    }

    return ScheduleConfig(
      url: input.trim(),
      curriculumUuid: curriculumUuid,
      fidEnc: fidEnc,
      unitText: unitText,
    );
  }
}

class ScheduleService {
  ScheduleService()
    : _dio = Dio(
        BaseOptions(
          baseUrl: kIsWeb ? 'http://localhost:8787' : 'https://kb.chaoxing.com',
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 12),
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Flutter Dio',
            'Referer':
                'https://kb.chaoxing.com/res/pc/curriculum/schedule.html',
          },
          responseType: ResponseType.bytes,
        ),
      );

  final Dio _dio;

  Future<ScheduleData> fetchLessons({
    required ScheduleConfig config,
    int? week,
  }) async {
    final response = await _dio.get<dynamic>(
      '/curriculum/getOtherLessons',
      queryParameters: {
        'curriculumUuid': config.curriculumUuid,
        'kd_fidenc': config.fidEnc,
        'text': config.unitText,
        'curTime': DateTime.now().millisecondsSinceEpoch,
        'week': ?week,
      },
    );

    final body = switch (response.data) {
      final List<int> bytes => utf8.decode(bytes),
      final String text => text,
      final Object value => jsonEncode(value),
      null => '',
    };
    final json = jsonDecode(body) as Map<String, dynamic>;
    if (json['result'] != 1) {
      throw Exception(json['msg'] ?? '课程表接口返回异常');
    }

    final data = json['data'] as Map<String, dynamic>;
    final curriculum = data['curriculum'] as Map<String, dynamic>;
    final timeConfig = (curriculum['lessonTimeConfigArray'] as List? ?? [])
        .map((item) => item.toString())
        .toList();
    final currentWeek = _asInt(curriculum['currentWeek'], fallback: 1);
    final maxWeek = _asInt(curriculum['maxWeek'], fallback: 25);
    final maxLength = _asInt(
      curriculum['maxLength'],
      fallback: timeConfig.length,
    );
    final selectedWeek = week ?? currentWeek;
    final schoolYear = _asInt(curriculum['schoolYear'], fallback: 2025);
    final semester = _asInt(curriculum['semester'], fallback: 1);
    final firstWeekDate = _asDate(curriculum['firstWeekDate']);

    final lessons =
        (data['lessonArray'] as List? ?? [])
            .whereType<Map>()
            .map(
              (raw) => _toLesson(
                raw.cast<String, dynamic>(),
                selectedWeek,
                timeConfig,
              ),
            )
            .toList()
          ..sort((a, b) {
            final dateCompare = (a.startDateTime ?? DateTime(2099)).compareTo(
              b.startDateTime ?? DateTime(2099),
            );
            if (dateCompare != 0) {
              return dateCompare;
            }
            return a.beginNumber.compareTo(b.beginNumber);
          });

    return ScheduleData(
      lessons: lessons,
      timeConfig: timeConfig,
      currentWeek: currentWeek,
      selectedWeek: selectedWeek,
      maxWeek: maxWeek,
      maxLength: maxLength == 0 ? timeConfig.length : maxLength,
      weekDates: _weekDates(firstWeekDate, selectedWeek),
      termTitle: '$schoolYear-${schoolYear + 1} 第$semester学期',
    );
  }

  CourseLesson _toLesson(
    Map<String, dynamic> raw,
    int week,
    List<String> timeConfig,
  ) {
    final beginNumber = _asInt(raw['beginNumber'], fallback: 1);
    final length = _asInt(raw['length'], fallback: 1);
    final startEnd = timeConfig.isEmpty
        ? ['', '']
        : timeConfig[(beginNumber - 1).clamp(0, timeConfig.length - 1)].split(
            '-',
          );
    final startTime = startEnd.isNotEmpty ? startEnd.first : '';

    return CourseLesson(
      name: _clean(raw['name']),
      teacherName: _clean(raw['teacherName']),
      location: _clean(raw['location']),
      dayOfWeek: _asInt(raw['dayOfWeek'], fallback: 1),
      beginNumber: beginNumber,
      length: length,
      wholeDay: _clean(raw['wholeDay']),
      week: week,
      startTime: startTime,
      endTime: _addHours(startTime, 2),
    );
  }

  static int _asInt(Object? value, {required int fallback}) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static String _clean(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty || text == 'null' ? '未填写' : text;
  }

  static DateTime _asDate(Object? value) {
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    final millis = int.tryParse(value?.toString() ?? '');
    if (millis != null) {
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }
    final now = DateTime.now();
    return DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
  }

  static List<DateTime> _weekDates(DateTime firstWeekDate, int selectedWeek) {
    final firstMonday = DateTime(
      firstWeekDate.year,
      firstWeekDate.month,
      firstWeekDate.day,
    );
    final monday = firstMonday.add(Duration(days: (selectedWeek - 1) * 7));
    return List.generate(7, (index) => monday.add(Duration(days: index)));
  }

  static String _addHours(String time, int hours) {
    final parts = time.split(':');
    if (parts.length < 2) {
      return '';
    }
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      return '';
    }

    final totalMinutes = hour * 60 + minute + hours * 60;
    final endHour = (totalMinutes ~/ 60) % 24;
    final endMinute = totalMinutes % 60;
    return '${endHour.toString().padLeft(2, '0')}:${endMinute.toString().padLeft(2, '0')}';
  }
}

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  final _service = ScheduleService();
  ScheduleConfig _config = ScheduleConfig.fromUrl(_defaultScheduleUrl);
  ScheduleData? _schedule;
  CourseLesson? _nextLesson;
  int _selectedWeek = 1;
  bool _loading = true;
  bool _showFocus = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSavedConfigAndSchedule();
  }

  Future<void> _loadSavedConfigAndSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString(_savedScheduleUrlKey);
    if (savedUrl != null && savedUrl.trim().isNotEmpty) {
      try {
        _config = ScheduleConfig.fromUrl(savedUrl);
      } catch (_) {
        await prefs.remove(_savedScheduleUrlKey);
      }
    }
    await _loadInitial();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final first = await _service.fetchLessons(config: _config);
      var data = first;
      var week = first.currentWeek;
      var next = _findNext(first.lessons);

      while (next == null && week < first.maxWeek) {
        week += 1;
        data = await _service.fetchLessons(config: _config, week: week);
        next = _findNext(data.lessons);
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _schedule = data;
        _selectedWeek = week;
        _nextLesson = next ?? data.lessons.firstOrNull;
        _loading = false;
        _showFocus = _nextLesson != null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadWeek(int week) async {
    final schedule = _schedule;
    if (schedule == null || week < 1 || week > schedule.maxWeek) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _showFocus = false;
    });

    try {
      final data = await _service.fetchLessons(config: _config, week: week);
      if (!mounted) {
        return;
      }
      setState(() {
        _schedule = data;
        _selectedWeek = week;
        _nextLesson = _findNext(data.lessons) ?? data.lessons.firstOrNull;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _changeScheduleUrl() async {
    final controller = TextEditingController(text: _config.url);
    final newConfig = await showDialog<ScheduleConfig>(
      context: context,
      builder: (context) {
        String? errorText;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('切换课表'),
            content: TextField(
              controller: controller,
              minLines: 4,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: '超星课表链接',
                hintText: _defaultScheduleUrl,
                errorText: errorText,
                border: const OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  try {
                    Navigator.pop(
                      context,
                      ScheduleConfig.fromUrl(controller.text),
                    );
                  } catch (error) {
                    setDialogState(() => errorText = error.toString());
                  }
                },
                child: const Text('保存并查看'),
              ),
            ],
          ),
        );
      },
    );
    controller.dispose();

    if (newConfig == null) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedScheduleUrlKey, newConfig.url);
    if (!mounted) {
      return;
    }
    setState(() {
      _config = newConfig;
      _schedule = null;
      _nextLesson = null;
      _selectedWeek = 1;
      _showFocus = true;
    });
    await _loadInitial();
  }

  CourseLesson? _findNext(List<CourseLesson> lessons) {
    final now = DateTime.now();
    for (final lesson in lessons) {
      final start = lesson.startDateTime;
      if (start != null && start.isAfter(now)) {
        return lesson;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final schedule = _schedule;

    return Scaffold(
      backgroundColor: const Color(0xfff5f7fb),
      appBar: AppBar(
        title: const Text('课程表'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        actions: [
          IconButton(
            tooltip: '切换课表',
            onPressed: _changeScheduleUrl,
            icon: const Icon(Icons.link),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: _loadInitial,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading && schedule == null
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _ErrorView(message: _error!, onRetry: _loadInitial)
            : Stack(
                children: [
                  _ScheduleBoard(
                    schedule: schedule!,
                    selectedWeek: _selectedWeek,
                    loading: _loading,
                    onPreviousWeek: () => _loadWeek(_selectedWeek - 1),
                    onNextWeek: () => _loadWeek(_selectedWeek + 1),
                    onShowFocus: _nextLesson == null
                        ? null
                        : () => setState(() => _showFocus = true),
                  ),
                  if (_showFocus && _nextLesson != null)
                    _NextLessonOverlay(
                      lesson: _nextLesson!,
                      onClose: () => setState(() => _showFocus = false),
                    ),
                ],
              ),
      ),
    );
  }
}

class _ScheduleBoard extends StatelessWidget {
  const _ScheduleBoard({
    required this.schedule,
    required this.selectedWeek,
    required this.loading,
    required this.onPreviousWeek,
    required this.onNextWeek,
    required this.onShowFocus,
  });

  final ScheduleData schedule;
  final int selectedWeek;
  final bool loading;
  final VoidCallback onPreviousWeek;
  final VoidCallback onNextWeek;
  final VoidCallback? onShowFocus;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      schedule.termTitle,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '第$selectedWeek周 · ${schedule.lessons.length}节课',
                      style: const TextStyle(color: Color(0xff5f6b7a)),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                onPressed: selectedWeek <= 1 || loading ? null : onPreviousWeek,
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_left),
              ),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                onPressed: selectedWeek >= schedule.maxWeek || loading
                    ? null
                    : onNextWeek,
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_right),
              ),
              const SizedBox(width: 4),
              IconButton.filled(
                onPressed: onShowFocus,
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.center_focus_strong),
              ),
            ],
          ),
        ),
        if (loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: _ScheduleGrid(schedule: schedule)),
      ],
    );
  }
}

class _ScheduleGrid extends StatelessWidget {
  const _ScheduleGrid({required this.schedule});

  final ScheduleData schedule;

  @override
  Widget build(BuildContext context) {
    final groupedLessons = <String, List<CourseLesson>>{};
    for (final lesson in schedule.lessons) {
      groupedLessons
          .putIfAbsent('${lesson.beginNumber}-${lesson.dayOfWeek}', () => [])
          .add(lesson);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth - 12;
        final timeColumnWidth = viewportWidth < 480 ? 48.0 : 64.0;
        final dayColumnWidth = viewportWidth < 480 ? 62.0 : 96.0;
        final width = timeColumnWidth + dayColumnWidth * 7;
        final rowHeight = viewportWidth < 480 ? 66.0 : 82.0;
        const headerHeight = 42.0;
        final displayMaxLength = _displayMaxLength();
        final bodyHeight = rowHeight * displayMaxLength;

        return Scrollbar(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 0),
            child: SizedBox(
              width: width,
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  children: [
                    _header(timeColumnWidth, dayColumnWidth, headerHeight),
                    SizedBox(
                      width: width,
                      height: bodyHeight,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ..._backgroundCells(
                            timeColumnWidth,
                            dayColumnWidth,
                            rowHeight,
                            displayMaxLength,
                          ),
                          for (final entry in groupedLessons.entries)
                            ..._lessonCards(
                              context,
                              entry.value,
                              timeColumnWidth,
                              dayColumnWidth,
                              rowHeight,
                              displayMaxLength,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _header(
    double timeColumnWidth,
    double dayColumnWidth,
    double headerHeight,
  ) {
    const days = ['节次', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final today = DateTime.now();
    return Row(
      children: [
        for (var index = 0; index < days.length; index++)
          _GridCell(
            width: index == 0 ? timeColumnWidth : dayColumnWidth,
            height: headerHeight,
            color: index > 0 && _isSameDay(schedule.weekDates[index - 1], today)
                ? const Color(0xfffff0d6)
                : const Color(0xffeaf2ff),
            child: index == 0
                ? Text(
                    days[index],
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  )
                : _DayHeader(
                    dayText: days[index],
                    date: schedule.weekDates[index - 1],
                    compact: dayColumnWidth < 47,
                    isToday: _isSameDay(schedule.weekDates[index - 1], today),
                  ),
          ),
      ],
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  List<Widget> _backgroundCells(
    double timeColumnWidth,
    double dayColumnWidth,
    double rowHeight,
    int displayMaxLength,
  ) {
    final cells = <Widget>[];
    for (var section = 1; section <= displayMaxLength; section++) {
      final top = (section - 1) * rowHeight;
      final time = section <= schedule.timeConfig.length
          ? _normalizeTimeRange(schedule.timeConfig[section - 1])
          : '';
      cells.add(
        Positioned(
          left: 0,
          top: top,
          child: _TimeCell(
            width: timeColumnWidth,
            height: rowHeight,
            section: section,
            time: time,
          ),
        ),
      );

      for (var day = 1; day <= 7; day++) {
        cells.add(
          Positioned(
            left: timeColumnWidth + (day - 1) * dayColumnWidth,
            top: top,
            child: _GridCell(
              width: dayColumnWidth,
              height: rowHeight,
              color: Colors.white,
            ),
          ),
        );
      }
    }
    return cells;
  }

  List<Widget> _lessonCards(
    BuildContext context,
    List<CourseLesson> lessons,
    double timeColumnWidth,
    double dayColumnWidth,
    double rowHeight,
    int displayMaxLength,
  ) {
    final cards = <Widget>[];
    for (var index = 0; index < lessons.length; index++) {
      final lesson = lessons[index];
      if (lesson.beginNumber > displayMaxLength) {
        continue;
      }
      final visibleRows = displayMaxLength - lesson.beginNumber + 1;
      final spanRows = visibleRows >= 2 ? 2 : 1;
      final cardGap = dayColumnWidth < 50 ? 2.0 : 4.0;
      final totalGap = cardGap * (lessons.length - 1);
      final cardWidth = (dayColumnWidth - 6 - totalGap) / lessons.length;
      cards.add(
        Positioned(
          left:
              timeColumnWidth +
              (lesson.dayOfWeek - 1) * dayColumnWidth +
              3 +
              index * (cardWidth + cardGap),
          top: (lesson.beginNumber - 1) * rowHeight + 3,
          width: cardWidth,
          height: spanRows * rowHeight - 6,
          child: _CourseBlock(
            lesson: lesson,
            color: _colorForCourse(lesson.name),
            compact: dayColumnWidth < 58,
            onTap: () => _showCourseDetail(context, lesson),
          ),
        ),
      );
    }
    return cards;
  }

  Color _colorForCourse(String courseName) {
    final index = courseName.hashCode.abs() % _courseColors.length;
    return _courseColors[index];
  }

  String _normalizeTimeRange(String rawRange) {
    return rawRange;
  }

  int _displayMaxLength() {
    final firstLateIndex = schedule.timeConfig.indexWhere((time) {
      final start = time.split('-').first.trim();
      final hour = int.tryParse(start.split(':').first);
      return hour != null && hour >= 21;
    });
    if (firstLateIndex < 0) {
      return schedule.maxLength;
    }
    return firstLateIndex.clamp(1, schedule.maxLength);
  }

  void _showCourseDetail(BuildContext context, CourseLesson lesson) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _CourseDetailSheet(lesson: lesson),
    );
  }
}

class _GridCell extends StatelessWidget {
  const _GridCell({
    required this.width,
    required this.height,
    required this.color,
    this.child,
  });

  final double width;
  final double height;
  final Color color;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: const Color(0xffd9e1ec)),
      ),
      child: child,
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.dayText,
    required this.date,
    required this.compact,
    required this.isToday,
  });

  final String dayText;
  final DateTime date;
  final bool compact;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              dayText,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: compact ? 11 : 13,
              ),
            ),
            if (isToday && !compact) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xffd68b00),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '今',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}',
          style: TextStyle(
            color: isToday ? const Color(0xff9a6500) : const Color(0xff5f6b7a),
            fontSize: compact ? 10 : 11,
            fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _TimeCell extends StatelessWidget {
  const _TimeCell({
    required this.width,
    required this.height,
    required this.section,
    required this.time,
  });

  final double width;
  final double height;
  final int section;
  final String time;

  @override
  Widget build(BuildContext context) {
    return _GridCell(
      width: width,
      height: height,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$section',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                time,
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10, color: Color(0xff687789)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CourseBlock extends StatelessWidget {
  const _CourseBlock({
    required this.lesson,
    required this.color,
    required this.compact,
    required this.onTap,
  });

  final CourseLesson lesson;
  final Color color;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Ink(
          padding: EdgeInsets.all(compact ? 4 : 7),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(7),
            boxShadow: const [
              BoxShadow(
                blurRadius: 6,
                color: Color(0x1f000000),
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: DefaultTextStyle(
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 8.5 : 10.5,
              height: 1.08,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lesson.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: compact ? 8.5 : 10.5,
                  ),
                  maxLines: compact ? 4 : 3,
                  overflow: TextOverflow.visible,
                ),
                const SizedBox(height: 3),
                Text(
                  lesson.teacherName,
                  maxLines: 2,
                  overflow: TextOverflow.visible,
                ),
                const Spacer(),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 3 : 5,
                    vertical: compact ? 2 : 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                  child: Text(
                    lesson.location,
                    maxLines: compact ? 3 : 2,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      fontSize: compact ? 8.5 : 10.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CourseDetailSheet extends StatelessWidget {
  const _CourseDetailSheet({required this.lesson});

  final CourseLesson lesson;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              lesson.name,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 18),
            _InfoLine(icon: Icons.person, text: lesson.teacherName),
            _InfoLine(icon: Icons.location_on, text: lesson.location),
            _InfoLine(
              icon: Icons.schedule,
              text:
                  '${lesson.wholeDay} ${lesson.startTime}-${lesson.endTime} · ${lesson.sectionText}',
            ),
            _InfoLine(
              icon: Icons.calendar_month,
              text: '第${lesson.week}周 · ${_weekdayName(lesson.dayOfWeek)}',
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.check),
                label: const Text('知道了'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _weekdayName(int dayOfWeek) {
    const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    if (dayOfWeek < 1 || dayOfWeek > names.length) {
      return '周$dayOfWeek';
    }
    return names[dayOfWeek - 1];
  }
}

class _NextLessonOverlay extends StatelessWidget {
  const _NextLessonOverlay({required this.lesson, required this.onClose});

  final CourseLesson lesson;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onClose,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.48),
          ),
          child: Center(
            child: GestureDetector(
              onTap: () {},
              child: Container(
                margin: const EdgeInsets.all(22),
                constraints: const BoxConstraints(maxWidth: 520),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 28,
                      color: Color(0x33000000),
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '下一节课',
                      style: TextStyle(
                        color: Color(0xff2c7be5),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      lesson.name,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 20),
                    _InfoLine(icon: Icons.person, text: lesson.teacherName),
                    _InfoLine(icon: Icons.location_on, text: lesson.location),
                    _InfoLine(
                      icon: Icons.schedule,
                      text:
                          '${lesson.wholeDay} ${lesson.startTime}-${lesson.endTime} · ${lesson.sectionText}',
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: onClose,
                        icon: const Icon(Icons.table_chart),
                        label: const Text('查看完整课程表'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xff2c7be5)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 52, color: Color(0xffd9534f)),
            const SizedBox(height: 12),
            const Text(
              '课程表加载失败',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xff5f6b7a)),
            ),
            const SizedBox(height: 18),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

const _courseColors = [
  Color(0xff0052cc),
  Color(0xff00a676),
  Color(0xffd7263d),
  Color(0xff6f2dbd),
  Color(0xfff18f01),
  Color(0xff0081a7),
  Color(0xff8f2d56),
  Color(0xff2d6a4f),
  Color(0xffc44536),
  Color(0xff3a0ca3),
];
