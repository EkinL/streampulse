import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/core/network/api_endpoints.dart';

void main() {
  group('ApiEndpoints', () {
    test('admin role update targets the /role sub-resource', () {
      // The API exposes PUT /admin/users/{id}/role - PUT on the bare user
      // resource is a 404.
      expect(ApiEndpoints.adminUserRole('abc'), '/admin/users/abc/role');
    });

    test('stream lifecycle paths', () {
      expect(ApiEndpoints.stream('s1'), '/streams/s1');
      expect(ApiEndpoints.streamStart('s1'), '/streams/s1/start');
      expect(ApiEndpoints.streamStop('s1'), '/streams/s1/stop');
      expect(ApiEndpoints.streamBroadcast('s1'), '/streams/s1/broadcast');
      expect(ApiEndpoints.streamListeners('s1'), '/streams/s1/listeners');
    });

    test('playlist track paths', () {
      expect(ApiEndpoints.playlistTracks('p1'), '/playlists/p1/tracks');
      expect(ApiEndpoints.playlistTrack('p1', 't1'), '/playlists/p1/tracks/t1');
    });
  });
}
