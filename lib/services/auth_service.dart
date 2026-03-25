import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  static SupabaseClient get _client => Supabase.instance.client;

  /// 현재 로그인된 사용자의 store_id (로그인 후 loadStoreId()로 설정됨)
  static String? storeId;

  /// 이메일/비밀번호로 로그인 후 storeId 로드
  static Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (res.user == null) return '로그인에 실패했습니다.';
      final error = await loadStoreId();
      return error;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return '로그인 오류: $e';
    }
  }

  /// store_members 에서 store_id 조회 및 저장
  static Future<String?> loadStoreId() async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) return '로그인 상태가 아닙니다.';

      final rows = await _client
          .from('store_members')
          .select('store_id')
          .eq('user_id', user.id)
          .limit(1);

      if ((rows as List).isEmpty) {
        return '소속 매장이 없습니다. 관리자에게 문의하세요.';
      }

      storeId = rows.first['store_id'] as String;
      return null; // 성공
    } catch (e) {
      return '매장 정보 로드 오류: $e';
    }
  }

  static Future<void> signOut() async {
    storeId = null;
    await _client.auth.signOut();
  }

  static bool get isLoggedIn => _client.auth.currentSession != null;

  static String? get currentUserEmail => _client.auth.currentUser?.email;
}
