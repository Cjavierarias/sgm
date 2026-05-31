import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_service.dart';

class AuthState {
  final String token;
  final String email;
  final bool isLoading;
  final String errorMessage;

  const AuthState({
    this.token = '',
    this.email = '',
    this.isLoading = false,
    this.errorMessage = '',
  });

  bool get isAuthenticated => token.isNotEmpty;

  AuthState copyWith({
    String? token,
    String? email,
    bool? isLoading,
    String? errorMessage,
  }) {
    return AuthState(
      token: token ?? this.token,
      email: email ?? this.email,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState());

  final ApiService _apiService = ApiService();

  Future<void> login(String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: '');

    try {
      final token = await _apiService.login(email, password);
      state = state.copyWith(token: token, email: email, isLoading: false);
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: error.toString().replaceFirst('Exception: ', ''),
      );
      rethrow;
    }
  }

  void logout() {
    state = const AuthState();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
