import 'dart:math';

/// College identity contract.
///
/// Canonical field on a user document: **`collegeId`** — a stable, lower-case
/// slug derived from the student's email domain (e.g. `nmit`, `rvce`, `bms`).
/// `college` remains the human-readable display label.
class CollegeDetector {
  static Map<String, String>? detect(String email) {
    final domain = email.split('@').last.toLowerCase();

    if (domain.endsWith('nmit.ac.in')) {
      return {
        'collegeId': 'nmit',
        'collegeName': 'NMIT',
      };
    }

    if (domain.endsWith('rvce.edu.in')) {
      return {
        'collegeId': 'rvce',
        'collegeName': 'RVCE',
      };
    }

    if (domain.endsWith('bmsce.ac.in')) {
      return {
        'collegeId': 'bms',
        'collegeName': 'BMSCE',
      };
    }

    if (domain.endsWith('pes.edu')) {
      return {
        'collegeId': 'pes',
        'collegeName': 'PES University',
      };
    }

    return null; // ❌ Not supported
  }
}

/// Canonical college identity for a user row. `profiles.college_id` (the
/// column this app's Postgres schema actually uses) is checked first; the
/// legacy `collegeId` key is kept only for any leftover Firestore-shaped
/// map that still reaches this function, and `college` (the human-readable
/// display name typed into profile setup) is the last resort, not the
/// canonical id -- it must never silently stand in for one, since it's
/// arbitrary free text, not the slug college_id_from_email() derives and
/// every RLS policy and Realtime filter compares against.
String canonicalCollegeId(Map<String, dynamic>? doc) {
  if (doc == null) return '';
  final snakeCase = doc['college_id'];
  if (snakeCase is String && snakeCase.isNotEmpty) return snakeCase;
  final camelCase = doc['collegeId'];
  if (camelCase is String && camelCase.isNotEmpty) return camelCase;
  final legacy = doc['college'];
  if (legacy is String && legacy.isNotEmpty) return legacy;
  return '';
}

/// Anonymous handle minted ONCE per user at document creation. The anon chat
/// seeds every message with this value and its rule ties it back to the users
/// doc (`messages.anonId == users/{uid}.anonId`), so it must be unguessable and
/// set before first use — anything that creates a user doc stamps it.
String anonDisplayId() {
  const alphabet = 'abcdefghjkmnpqrstuvwxyz23456789'; // no 0/O/1/l ambiguity
  final r = Random.secure();
  return List.generate(8, (_) => alphabet[r.nextInt(alphabet.length)]).join();
}

/// College id to persist when writing a user document: derived from the email
/// domain when recognised, else stable-slugified from the chosen display name,
/// else `unknown`. Deterministic so writers and readers always agree.
String collegeIdForEmail(String? email, {String? fallbackCollege}) {
  if (email != null && email.isNotEmpty) {
    final detected = CollegeDetector.detect(email);
    if (detected != null) return detected['collegeId']!;
  }

  final fallback = fallbackCollege;
  if (fallback != null && fallback.trim().isNotEmpty) {
    final slug = fallback
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (slug.isNotEmpty) return slug;
  }

  return 'unknown';
}