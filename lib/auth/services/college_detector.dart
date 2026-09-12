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

/// Canonical college identity for a user document, with backward compatibility:
/// reads `collegeId` when present, otherwise falls back to the legacy `college`
/// display string. Never returns null for a fetched document that has either.
String canonicalCollegeId(Map<String, dynamic>? doc) {
  if (doc == null) return '';
  final id = doc['collegeId'];
  if (id is String && id.isNotEmpty) return id;
  final legacy = doc['college'];
  if (legacy is String && legacy.isNotEmpty) return legacy;
  return '';
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