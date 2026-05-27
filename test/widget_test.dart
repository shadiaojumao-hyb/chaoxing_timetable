import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/main.dart';

void main() {
  test('formats section range', () {
    const lesson = CourseLesson(
      name: '数字图像处理',
      teacherName: '韩轶龙',
      location: 'J1-228室',
      dayOfWeek: 5,
      beginNumber: 1,
      length: 2,
      wholeDay: '2026-04-24',
      week: 7,
      startTime: '8:00',
      endTime: '10:00',
    );

    expect(lesson.sectionText, '第1-2节');
  });
}
