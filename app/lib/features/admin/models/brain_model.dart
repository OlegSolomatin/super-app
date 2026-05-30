class BrainNode {
  final String id;
  final String title;
  final String folder;
  final List<String> tags;
  final String status;
  final String date;
  final double? lat;
  final double? lon;
  final String address;
  final String time;
  final int weight;
  final double x;
  final double y;

  const BrainNode({
    required this.id,
    required this.title,
    required this.folder,
    this.tags = const [],
    this.status = '',
    this.date = '',
    this.lat,
    this.lon,
    this.address = '',
    this.time = '',
    this.weight = 1,
    this.x = 0,
    this.y = 0,
  });

  factory BrainNode.fromJson(Map<String, dynamic> json) {
    return BrainNode(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      folder: json['folder'] as String? ?? '',
      tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
      status: json['status'] as String? ?? '',
      date: json['date'] as String? ?? '',
      lat: (json['lat'] as num?)?.toDouble(),
      lon: (json['lon'] as num?)?.toDouble(),
      address: json['address'] as String? ?? '',
      time: json['time'] as String? ?? '',
      weight: json['weight'] as int? ?? 1,
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'folder': folder,
        'tags': tags,
        'status': status,
        'date': date,
        'lat': lat,
        'lon': lon,
        'address': address,
        'time': time,
        'weight': weight,
        'x': x,
        'y': y,
      };
}

class BrainEdge {
  final String source;
  final String target;
  final int weight;

  const BrainEdge({
    required this.source,
    required this.target,
    this.weight = 1,
  });

  factory BrainEdge.fromJson(Map<String, dynamic> json) {
    return BrainEdge(
      source: json['source'] as String? ?? '',
      target: json['target'] as String? ?? '',
      weight: json['weight'] as int? ?? 1,
    );
  }
}

class BrainGraph {
  final List<BrainNode> nodes;
  final List<BrainEdge> edges;

  const BrainGraph({
    required this.nodes,
    required this.edges,
  });

  factory BrainGraph.fromJson(Map<String, dynamic> json) {
    return BrainGraph(
      nodes: (json['nodes'] as List?)
              ?.map((e) => BrainNode.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      edges: (json['edges'] as List?)
              ?.map((e) => BrainEdge.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
