import 'package:flutter_test/flutter_test.dart';
import 'package:college_app/auth/services/college_detector.dart';

void main() {
  group('CollegeDetector.detect', () {
    test('detects NMIT from nmit.ac.in domain', () {
      final result = CollegeDetector.detect('student@nmit.ac.in');
      expect(result, isNotNull);
      expect(result!['collegeId'], 'nmit');
    });

    test('detects RVCE from rvce.edu.in domain', () {
      final result = CollegeDetector.detect('alice@rvce.edu.in');
      expect(result, isNotNull);
      expect(result!['collegeId'], 'rvce');
    });

    test('detects BMS from bmsce.ac.in domain', () {
      final result = CollegeDetector.detect('bob@bmsce.ac.in');
      expect(result, isNotNull);
      expect(result!['collegeId'], 'bms');
    });

    test('detects PES from pes.edu domain', () {
      final result = CollegeDetector.detect('charlie@pes.edu');
      expect(result, isNotNull);
      expect(result!['collegeId'], 'pes');
    });

    test('returns null for unrecognized domain', () {
      expect(CollegeDetector.detect('user@gmail.com'), isNull);
      expect(CollegeDetector.detect('user@yahoo.com'), isNull);
    });

    test('is case-insensitive on the domain', () {
      final result = CollegeDetector.detect('STUDENT@NMIT.AC.IN');
      expect(result, isNotNull);
      expect(result!['collegeId'], 'nmit');
    });

    test('does not match partial domain suffixes', () {
      // "nmit.example.com" should NOT match "nmit.ac.in"
      expect(CollegeDetector.detect('x@nmit.example.com'), isNull);
    });
  });

  group('canonicalCollegeId', () {
    test('returns collegeId when present', () {
      expect(
        canonicalCollegeId({'collegeId': 'nmit', 'college': 'NMIT'}),
        'nmit',
      );
    });

    test('falls back to legacy college display string when collegeId missing', () {
      expect(
        canonicalCollegeId({'college': 'NMIT'}),
        'NMIT',
      );
    });

    test('returns empty string for null doc', () {
      expect(canonicalCollegeId(null), '');
    });

    test('returns empty string for doc with neither field', () {
      expect(canonicalCollegeId({'name': 'Alice'}), '');
    });

    test('returns collegeId even if college field is also present', () {
      expect(
        canonicalCollegeId({'collegeId': 'rvce', 'college': 'RVCE'}),
        'rvce',
      );
    });
  });

  group('collegeIdForEmail', () {
    test('derives collegeId from recognized email domain', () {
      expect(collegeIdForEmail('alice@nmit.ac.in'), 'nmit');
      expect(collegeIdForEmail('bob@pes.edu'), 'pes');
    });

    test('uses fallbackCollege when email is null', () {
      expect(collegeIdForEmail(null, fallbackCollege: 'NMIT'), 'nmit');
    });

    test('slugs a multi-word fallback', () {
      expect(
        collegeIdForEmail(null, fallbackCollege: 'PES University'),
        'pes_university',
      );
    });

    test('returns unknown when both email and fallback are absent', () {
      expect(collegeIdForEmail(null), 'unknown');
    });

    test('returns unknown when email is empty', () {
      expect(collegeIdForEmail(''), 'unknown');
    });

    test('strips non-alphanumeric chars from fallback slug', () {
      expect(
        collegeIdForEmail(null, fallbackCollege: 'BMS College of Eng!'),
        'bms_college_of_eng',
      );
    });

    test('trims leading/trailing underscores in slug', () {
      expect(
        collegeIdForEmail(null, fallbackCollege: '  !RVCE!  '),
        'rvce',
      );
    });
  });
}
