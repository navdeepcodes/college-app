class CollegeEmailValidator {
  static const List<String> allowedDomains = [
    '@nmit.ac.in',
    '@rvce.edu.in',
    '@bmsce.ac.in',
    '.edu', // fallback for global colleges
  ];

  static bool isValid(String email) {
    final lower = email.toLowerCase();
    return allowedDomains.any((d) => lower.endsWith(d));
  }
}