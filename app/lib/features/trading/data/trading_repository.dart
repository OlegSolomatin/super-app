import 'package:dio/dio.dart';
import 'package:app/core/dio_client.dart';
import 'package:app/features/trading/data/models/trading_pair.dart';
import 'package:app/features/trading/data/models/strategy_info.dart';
import 'package:app/features/trading/data/models/exchange_info.dart';
import 'package:app/features/trading/data/models/trading_run.dart';
import 'package:app/features/trading/data/models/trading_trade.dart';
import 'package:app/features/trading/data/models/pair_live_data.dart';
import 'package:app/features/trading/data/models/pair_insight.dart';
import 'package:app/features/trading/data/models/system_load.dart';
import 'package:app/features/trading/data/models/trading_signal.dart';

class TradingRepository {
  final Dio _dio;

  TradingRepository(DioClient dioClient) : _dio = dioClient.dio;

  Future<({List<TradingPair> items, int total})> getPairs({
    String? search,
    String? sort,
    int page = 1,
    int pageSize = 20,
    String? exchange,
  }) async {
    final queryParams = <String, dynamic>{
      if (search != null && search.isNotEmpty) 'search': search,
      if (sort != null && sort.isNotEmpty) 'sort': sort,
      'page': page,
      'page_size': pageSize,
      if (exchange != null && exchange.isNotEmpty) 'exchange': exchange,
    };
    final response = await _dio.get('/trading/pairs', queryParameters: queryParams);
    final data = response.data as Map<String, dynamic>;
    final items = (data['items'] as List)
        .map((e) => TradingPair.fromJson(e as Map<String, dynamic>))
        .toList();
    final total = data['total'] as int;
    return (items: items, total: total);
  }

  Future<Map<String, PairLiveData>> getPairsLive({String? exchange}) async {
    final queryParams = <String, dynamic>{
      if (exchange != null && exchange.isNotEmpty) 'exchange': exchange,
    };
    final response = await _dio.get('/trading/pairs/live', queryParameters: queryParams);
    final data = response.data as Map<String, dynamic>;
    final items = data['items'] as Map<String, dynamic>;
    return items.map((symbol, json) =>
        MapEntry(symbol, PairLiveData.fromJson(json as Map<String, dynamic>)));
  }

  Future<PairInsight> getPairInsight(String symbol, {String? exchange}) async {
    final queryParams = <String, dynamic>{
      if (exchange != null && exchange.isNotEmpty) 'exchange': exchange,
    };
    final response = await _dio.get('/trading/pairs/$symbol/insight', queryParameters: queryParams);
    return PairInsight.fromJson(response.data as Map<String, dynamic>);
  }

  Future<SystemLoad> getSystemLoad() async {
    final response = await _dio.get('/system/load');
    return SystemLoad.fromJson(response.data as Map<String, dynamic>);
  }

  Future<({List<StrategyInfo> items, int total})> getStrategies() async {
    final response = await _dio.get('/trading/strategies');
    final data = response.data as Map<String, dynamic>;
    final items = (data['items'] as List)
        .map((e) => StrategyInfo.fromJson(e as Map<String, dynamic>))
        .toList();
    final total = data['total'] as int;
    return (items: items, total: total);
  }

  Future<({List<ExchangeInfo> items, int total})> getExchanges() async {
    final response = await _dio.get('/trading/exchanges');
    final data = response.data as Map<String, dynamic>;
    final items = (data['items'] as List)
        .map((e) => ExchangeInfo.fromJson(e as Map<String, dynamic>))
        .toList();
    final total = data['total'] as int;
    return (items: items, total: total);
  }

  Future<TradingRun> createRun(Map<String, dynamic> config) async {
    final response = await _dio.post('/trading/runs', data: config);
    return TradingRun.fromJson(response.data as Map<String, dynamic>);
  }

  Future<({List<TradingRun> items, int total})> getRuns({
    String? status,
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await _dio.get('/trading/runs', queryParameters: {
      if (status != null && status.isNotEmpty) 'status': status,
      'page': page,
      'page_size': pageSize,
    });
    final data = response.data as Map<String, dynamic>;
    final items = (data['items'] as List)
        .map((e) => TradingRun.fromJson(e as Map<String, dynamic>))
        .toList();
    final total = data['total'] as int;
    return (items: items, total: total);
  }

  Future<TradingRun> getRun(String id) async {
    final response = await _dio.get('/trading/runs/$id');
    return TradingRun.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> getRunScanProgress(String id) async {
    try {
      final response = await _dio.get('/trading/runs/$id/scan-progress');
      return response.data as Map<String, dynamic>;
    } catch (_) {
      return {'status': null};
    }
  }

  Future<({List<TradingTrade> items, int total})> getRunTrades(
    String id, {
    int page = 1,
    int pageSize = 50,
  }) async {
    final response = await _dio.get(
      '/trading/runs/$id/trades',
      queryParameters: {
        'page': page,
        'page_size': pageSize,
      },
    );
    final data = response.data as Map<String, dynamic>;
    final items = (data['items'] as List)
        .map((e) => TradingTrade.fromJson(e as Map<String, dynamic>))
        .toList();
    final total = data['total'] as int;
    return (items: items, total: total);
  }

  Future<({String runId, String strategy, String code})> getRunCode(
      String id) async {
    final response = await _dio.get('/trading/runs/$id/code');
    final data = response.data as Map<String, dynamic>;
    return (
      runId: data['run_id'] as String,
      strategy: data['strategy'] as String,
      code: data['code'] as String,
    );
  }

  Future<void> deleteRun(String id) async {
    await _dio.delete('/trading/runs/$id');
  }

  Future<int> cleanupStaleRuns() async {
    final response = await _dio.post('/trading/runs/cleanup');
    final data = response.data as Map<String, dynamic>;
    return data['cleaned'] as int? ?? 0;
  }

  // ── Order Book methods ────────────────────────────────────────────

  Future<Map<String, dynamic>> startOrderBookRun(Map<String, dynamic> config) async {
    final response = await _dio.post('/orderbook/start', data: config);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getOrderBookRun(int runId) async {
    final response = await _dio.get('/orderbook/runs/$runId');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getOrderBookRunStatus(int runId) async {
    final response = await _dio.get('/orderbook/runs/$runId/status');
    return response.data as Map<String, dynamic>;
  }

  Future<({List<Map<String, dynamic>> items, int total})> getOrderBookRuns({
    String? status,
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await _dio.get('/orderbook/runs', queryParameters: {
      if (status != null && status.isNotEmpty) 'status': status,
      'page': page,
      'page_size': pageSize,
    });
    final data = response.data as Map<String, dynamic>;
    final items = (data['items'] as List)
        .map((e) => e as Map<String, dynamic>)
        .toList();
    final total = data['total'] as int;
    return (items: items, total: total);
  }

  Future<void> stopOrderBookRun(int runId) async {
    await _dio.post('/orderbook/stop', queryParameters: {'run_id': runId});
  }

  /// Stop a standard (candle-based) trading run.
  Future<void> stopRun(int runId) async {
    await _dio.delete('/trading/runs/$runId');
  }

  Future<List<Map<String, dynamic>>> getOrderBookRunTrades(int runId) async {
    final response = await _dio.get('/orderbook/runs/$runId/trades');
    final data = response.data as Map<String, dynamic>;
    return (data['trades'] as List).map((e) => e as Map<String, dynamic>).toList();
  }

  // ── Trading Signals ────────────────────────────────────────────────

  /// Fetch the latest N signals from the live Redis cache.
  Future<List<TradingSignal>> getSignalsLive({int limit = 20}) async {
    final response = await _dio.get('/trading/signals/live', queryParameters: {
      'limit': limit,
    });
    final data = response.data as List;
    return data
        .map((e) => TradingSignal.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Fetch signals from PostgreSQL (historical, with full data).
  Future<List<TradingSignal>> getSignals({int limit = 20}) async {
    final response = await _dio.get('/trading/signals', queryParameters: {
      'limit': limit,
    });
    final data = response.data as Map<String, dynamic>;
    final items = data['items'] as List;
    return items
        .map((e) => TradingSignal.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Get signal details by ID.
  Future<TradingSignal> getSignal(int id) async {
    final response = await _dio.get('/trading/signals/$id');
    return TradingSignal.fromJson(response.data as Map<String, dynamic>);
  }

  /// Start a run from a signal.
  Future<Map<String, dynamic>> startSignalRun(int signalId,
      {String mode = 'virtual', String? exchange, String? direction}) async {
    final response = await _dio.post('/trading/signals/$signalId/start',
        data: {'mode': mode, 'exchange': exchange, 'direction': direction});
    return response.data as Map<String, dynamic>;
  }
}
