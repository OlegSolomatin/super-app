import 'package:dio/dio.dart';
import 'package:app/features/admin/models/agent_status.dart';

class AdminRepository {
  final Dio _dio;

  AdminRepository(this._dio);

  Future<List<AgentStatus>> getAgentStatuses() async {
    final response = await _dio.get('/admin/agents/status');
    return (response.data['agents'] as List)
        .map((e) => AgentStatus.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
