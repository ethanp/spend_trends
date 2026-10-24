import 'dart:async';
import 'dart:io';

import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'package:spend_trends/agent_api/agent_api_bank_routes.dart';
import 'package:spend_trends/agent_api/agent_api_import_routes.dart';
import 'package:spend_trends/agent_api/agent_api_json.dart';
import 'package:spend_trends/agent_api/agent_api_projection_routes.dart';
import 'package:spend_trends/agent_api/agent_api_read_routes.dart';
import 'package:spend_trends/agent_api/agent_api_write_routes.dart';

const _logger = ELogger('AgentApi');

/// Loopback HTTP API so a local agent can audit and adjust categorization
/// through the same repositories and [Categorizer] the UI uses. Writes land in
/// PowerSync and sync to other devices like any in-app edit.
///
/// Runs only while the macOS app is open. Every route except `/health`
/// requires `Authorization: Bearer $AGENT_API_TOKEN`.
///
/// A hot restart can leave the previous run's listening socket open with no
/// Dart code behind it, so connections to it hang. When [preferredPort] is
/// taken, the server binds any free port. Either way it writes the port it
/// serves on to [portFileName] in Application Support, which
/// `scripts/agent_api` reads.
class AgentApiServer({
  required final ProviderContainer container,
  required final String token,
  required final int preferredPort,
}) {
  static const tokenEnvKey = 'AGENT_API_TOKEN';
  static const portEnvKey = 'AGENT_API_PORT';
  static const defaultPort = 8791;
  static const portFileName = 'agent_api_port';

  HttpServer? _httpServer;

  /// Starts on macOS when [tokenEnvKey] is set; otherwise logs and skips.
  static Future<AgentApiServer?> startFromEnv(
    ProviderContainer container,
  ) async {
    if (!Platform.isMacOS) return null;
    final token = envString(tokenEnvKey);
    if (token == null) {
      _logger.log('Agent API off — set $tokenEnvKey in .env to enable');
      return null;
    }
    final server = AgentApiServer(
      container: container,
      token: token,
      preferredPort: envIntOr(portEnvKey, defaultPort),
    );
    final int boundPort = await server._bindPreferredOrFreePort();
    final supportDirectory = await getApplicationSupportDirectory();
    await File(p.join(supportDirectory.path, portFileName))
        .writeAsString('$boundPort');
    _logger.log('Agent API listening on http://127.0.0.1:$boundPort');
    return server;
  }

  Future<int> _bindPreferredOrFreePort() async {
    try {
      return await _bind(preferredPort);
    } on SocketException catch (error) {
      _logger.log(
        'Agent API port $preferredPort taken ($error); using a free port',
      );
      return _bind(0);
    }
  }

  Future<int> _bind(int port) async {
    final router = Router()
      ..get('/health', (Request request) => jsonOk({'ok': true}));
    AgentApiReadRoutes(container: container).mount(router);
    AgentApiWriteRoutes(container: container).mount(router);
    AgentApiImportRoutes(container: container).mount(router);
    AgentApiProjectionRoutes(container: container).mount(router);
    AgentApiBankRoutes(container: container).mount(router);
    _httpServer = await shelf_io.serve(
      const Pipeline()
          .addMiddleware(_requireBearerToken)
          .addMiddleware(_errorsAsJson)
          .addHandler(router.call),
      InternetAddress.loopbackIPv4,
      port,
    );
    return _httpServer!.port;
  }

  Future<void> stop() async {
    final server = _httpServer;
    _httpServer = null;
    await server?.close(force: true);
  }

  Handler _requireBearerToken(Handler innerHandler) {
    return (Request request) {
      if (request.requestedUri.path == '/health') return innerHandler(request);
      if (request.headers['authorization'] != 'Bearer $token') {
        return jsonError(
          'Unauthorized — send Bearer \$$tokenEnvKey',
          status: 401,
        );
      }
      return innerHandler(request);
    };
  }

  Handler _errorsAsJson(Handler innerHandler) {
    return (Request request) async {
      try {
        return await innerHandler(request);
      } on ArgumentError catch (error) {
        return jsonError('${error.message}', status: 400);
      } on FormatException catch (error) {
        return jsonError(error.message, status: 400);
      } on StateError catch (error) {
        return jsonError(error.message, status: 409);
      } catch (error, stackTrace) {
        _logger.error(
          '${request.method} ${request.url} failed',
          error,
          stackTrace,
        );
        return jsonError('$error', status: 500);
      }
    };
  }
}
