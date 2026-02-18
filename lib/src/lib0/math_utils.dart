/// Native Dart implementation of lib0/math utilities.
///
/// Mirrors: lib0/math.js
library;

import 'dart:math' as dart_math;

const int maxSafeInteger = 9007199254740991; // Number.MAX_SAFE_INTEGER
const int minSafeInteger = -9007199254740991; // Number.MIN_SAFE_INTEGER

int min(int a, int b) => dart_math.min(a, b);
int max(int a, int b) => dart_math.max(a, b);
int abs(int n) => n.abs();
int floor(double n) => n.floor();
int ceil(double n) => n.ceil();
int round(double n) => n.round();
double log(double n) => dart_math.log(n);
double log2(double n) => dart_math.log(n) / dart_math.log(2);
double pow(double base, double exp) => dart_math.pow(base, exp).toDouble();

/// Integer division (floor division).
int idiv(int a, int b) => (a / b).floor();
