class ApiEndpoints {
  ApiEndpoints._();

  static const String authRegister = '/auth/register';
  static const String authLogin = '/auth/login';
  static const String authRefresh = '/auth/refresh';
  static const String authOAuth = '/auth/oauth';
  static const String streams = '/streams';
  static const String playlists = '/playlists';
  static const String publicPlaylists = '/playlists/public';
  static const String adminUsers = '/admin/users';
  static const String usersMe = '/users/me';
  static const String favorites = '/favorites';
  static const String music = '/music';
  static const String musicSearch = '/music/search';
  static const String globalSearch = '/search';
  static const String feedback = '/feedback';
  static const String adminFeedback = '/admin/feedback';

  static String adminFeedbackStatus(String id) => '/admin/feedback/$id/status';

  static String stream(String id) => '/streams/$id';
  static String streamStart(String id) => '/streams/$id/start';
  static String streamStop(String id) => '/streams/$id/stop';
  static String streamBroadcast(String id) => '/streams/$id/broadcast';
  static String streamListeners(String id) => '/streams/$id/listeners';
  static String playlist(String id) => '/playlists/$id';
  static String playlistTracks(String id) => '/playlists/$id/tracks';
  static String playlistTrack(String playlistId, String trackId) =>
      '/playlists/$playlistId/tracks/$trackId';
  static String favorite(String streamId) => '/favorites/$streamId';
  static String adminUserRole(String userId) => '/admin/users/$userId/role';
  static String adminUser(String userId) => '/admin/users/$userId';
  static String musicItem(String id) => '/music/$id';
  static const String musicFavorites = '/music/favorites';
  static const String musicFavoriteIds = '/music/favorites/ids';
  static String musicFavorite(String id) => '/music/$id/favorite';
}
