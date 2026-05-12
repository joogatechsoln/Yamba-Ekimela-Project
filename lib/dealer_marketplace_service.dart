import 'dart:io';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_services.dart';
import 'dealer_registry.dart';

class DealerThread {
  const DealerThread({
    required this.id,
    required this.farmerId,
    required this.dealerId,
    required this.diseaseName,
    required this.recommendedDrugs,
    required this.lastMessage,
    required this.updatedAt,
    this.diagnosisImagePath,
  });

  final String id;
  final String farmerId;
  final String dealerId;
  final String diseaseName;
  final String recommendedDrugs;
  final String lastMessage;
  final DateTime updatedAt;
  final String? diagnosisImagePath;

  factory DealerThread.fromJson(Map<String, dynamic> json) {
    return DealerThread(
      id: json['id'].toString(),
      farmerId: json['farmer_id'].toString(),
      dealerId: json['dealer_id'].toString(),
      diseaseName: json['disease_name']?.toString() ?? '',
      recommendedDrugs: json['recommended_drugs']?.toString() ?? '',
      lastMessage: json['last_message']?.toString() ?? '',
      diagnosisImagePath: json['diagnosis_image_path']?.toString(),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class DealerMessage {
  const DealerMessage({
    required this.id,
    required this.threadId,
    required this.senderId,
    required this.receiverId,
    required this.message,
    required this.createdAt,
  });

  final String id;
  final String threadId;
  final String senderId;
  final String receiverId;
  final String message;
  final DateTime createdAt;

  factory DealerMessage.fromJson(Map<String, dynamic> json) {
    return DealerMessage(
      id: json['id'].toString(),
      threadId: json['thread_id'].toString(),
      senderId: json['sender_id'].toString(),
      receiverId: json['receiver_id'].toString(),
      message: json['message']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class DealerMarketplaceService {
  DealerMarketplaceService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static String get currentUserId {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      throw Exception('You need to sign in before messaging a dealer.');
    }
    return userId;
  }

  static Future<DealerThread> ensureThread({
    required DrugDealer dealer,
    required String diseaseName,
    required String recommendedDrugs,
    required File imageFile,
  }) async {
    final farmerId = currentUserId;
    final dealerAccountId = dealer.accountId;
    if (dealerAccountId == null || dealerAccountId.isEmpty) {
      throw Exception(
        'This dealer can be called, but messaging needs a registered dealer account.',
      );
    }

    final existing = await _client
        .from('dealer_threads')
        .select()
        .eq('farmer_id', farmerId)
        .eq('dealer_id', dealerAccountId)
        .eq('disease_name', diseaseName)
        .order('updated_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (existing != null) {
      return DealerThread.fromJson(existing);
    }

    final diagnosisImagePath = await _uploadDiagnosisImage(farmerId, imageFile);
    final initialMessage =
        'I analyzed my plant and got $diseaseName. The recommended drug information is: $recommendedDrugs';

    final inserted = await _client
        .from('dealer_threads')
        .insert({
          'farmer_id': farmerId,
          'dealer_id': dealerAccountId,
          'disease_name': diseaseName,
          'recommended_drugs': recommendedDrugs,
          'diagnosis_image_path': diagnosisImagePath,
          'last_message': initialMessage,
        })
        .select()
        .single();

    final thread = DealerThread.fromJson(inserted);
    await sendMessage(
      threadId: thread.id,
      receiverId: dealerAccountId,
      message: initialMessage,
    );
    return thread;
  }

  static Future<void> sendMessage({
    required String threadId,
    required String receiverId,
    required String message,
  }) async {
    final senderId = currentUserId;

    await _client.from('dealer_messages').insert({
      'thread_id': threadId,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'message': message,
    });

    await _client.from('dealer_threads').update({
      'last_message': message,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', threadId);
  }

  static Stream<List<DealerMessage>> messageStream(String threadId) {
    return _client
        .from('dealer_messages')
        .stream(primaryKey: ['id'])
        .eq('thread_id', threadId)
        .order('created_at')
        .map((rows) => rows.map(DealerMessage.fromJson).toList());
  }

  static Stream<List<DealerThread>> threadStream({
    required bool isDealer,
  }) {
    final key = isDealer ? 'dealer_id' : 'farmer_id';
    return _client
        .from('dealer_threads')
        .stream(primaryKey: ['id'])
        .eq(key, currentUserId)
        .order('updated_at', ascending: false)
        .map((rows) => rows.map(DealerThread.fromJson).toList());
  }

  static Future<String?> resolveDiagnosisImageUrl(String? storagePath) async {
    if (storagePath == null || storagePath.isEmpty) return null;
    return _client.storage
        .from(AppServices.diagnosisImageBucket)
        .createSignedUrl(storagePath, 60 * 60);
  }

  static Future<String?> _uploadDiagnosisImage(String userId, File file) async {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;

    final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final path = '$userId/$fileName';

    await _client.storage.from(AppServices.diagnosisImageBucket).uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );

    return path;
  }
}
