import 'package:dio/dio.dart';
import 'package:app/features/admin/models/agent_status.dart';
import 'package:app/features/admin/models/deepseek_balance.dart';
import 'package:app/features/admin/models/brain_model.dart';

class AdminRepository {
  final Dio _dio;

  AdminRepository(this._dio);

  Future<List<AgentStatus>> getAgentStatuses() async {
    final response = await _dio.get('/admin/agents/status');
    return (response.data['agents'] as List)
        .map((e) => AgentStatus.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<DeepseekBalance> getDeepseekBalance() async {
    final response = await _dio.get('/admin/deepseek-balance');
    return DeepseekBalance.fromJson(response.data as Map<String, dynamic>);
  }

  Future<BrainGraph> getBrainGraph() async {
    final response = await _dio.get('/admin/brain/graph');
    return BrainGraph.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> setBrainStatus(String noteId, String newStatus) async {
    await _dio.post('/admin/brain/status', data: {
      'id': noteId,
      'status': newStatus,
    });
  }
}
