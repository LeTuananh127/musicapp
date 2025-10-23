import 'package:flutter_riverpod/flutter_riverpod.dart';

// Holds the latest audio load error message (dev-friendly). Null = no error.
final audioErrorProvider = StateProvider<String?>((ref) => null);
