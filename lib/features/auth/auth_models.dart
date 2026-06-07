enum UserRole {
  manager,
  accounting,
  branchUser,
}

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.userId,
    required this.displayName,
    required this.role,
    this.branchId,
  });

  final String accessToken;
  final String userId;
  final String displayName;
  final UserRole role;
  final String? branchId;
}

