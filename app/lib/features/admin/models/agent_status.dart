class AgentStatus {
  final String name;
  final String role;
  final String position;
  final String pipelineStage;
  final String model;
  final String provider;
  final String status; // idle/working/error
  final String currentTask;
  final int tokensIn;
  final int tokensOut;
  final double costUsd;

  const AgentStatus({
    required this.name,
    required this.role,
    required this.position,
    required this.pipelineStage,
    required this.model,
    required this.provider,
    required this.status,
    required this.currentTask,
    required this.tokensIn,
    required this.tokensOut,
    required this.costUsd,
  });

  bool get isWorking => status == 'working';
  bool get isError => status == 'error';
  bool get isIdle => status == 'idle';

  factory AgentStatus.fromJson(Map<String, dynamic> json) {
    return AgentStatus(
      name: json['name'] as String? ?? '',
      role: json['role'] as String? ?? '',
      position: json['position'] as String? ?? '',
      pipelineStage: json['pipeline_stage'] as String? ?? '',
      model: json['model'] as String? ?? '',
      provider: json['provider'] as String? ?? '',
      status: json['status'] as String? ?? 'idle',
      currentTask: json['current_task'] as String? ?? '',
      tokensIn: (json['tokens_in'] as num?)?.toInt() ?? 0,
      tokensOut: (json['tokens_out'] as num?)?.toInt() ?? 0,
      costUsd: (json['cost_usd'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
