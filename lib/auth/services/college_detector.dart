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

    if (domain.endsWith('pes.edu')) {
      return {
        'collegeId': 'pes',
        'collegeName': 'PES University',
      };
    }

    return null; // ❌ Not supported
  }
}