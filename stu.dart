import 'package:flutter/cupertino.dart';

void main(List<String> args) {
  test();
}

void test() async {
  try {
    await Future.delayed(Duration(microseconds: 100000), () {
      throw Exception("An error occurred");
    });
    // await Future.delayed( Duration(seconds: 3));
  } catch (e) {
    debugPrint("catch error: $e");
  }
}
