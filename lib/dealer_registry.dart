import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_services.dart';

class DrugDealer {
  const DrugDealer({
    required this.id,
    this.accountId,
    required this.businessName,
    required this.ownerName,
    required this.district,
    required this.phoneNumber,
    required this.email,
    required this.openHours,
    required this.deliveryOptions,
    required this.availableDrugs,
    required this.expertise,
  });

  final String id;
  final String? accountId;
  final String businessName;
  final String ownerName;
  final String district;
  final String phoneNumber;
  final String email;
  final String openHours;
  final List<String> deliveryOptions;
  final List<String> availableDrugs;
  final List<String> expertise;

  factory DrugDealer.fromJson(Map<String, dynamic> json) {
    return DrugDealer(
      id: json['id']?.toString() ?? '',
      accountId: json['accountId']?.toString(),
      businessName: json['businessName']?.toString() ?? '',
      ownerName:
          json['ownerName']?.toString() ?? json['full_name']?.toString() ?? '',
      district: json['district']?.toString() ?? '',
      phoneNumber: json['phoneNumber']?.toString() ??
          json['phone_number']?.toString() ??
          '',
      email: json['email']?.toString() ?? '',
      openHours:
          json['openHours']?.toString() ?? json['open_hours']?.toString() ?? '',
      deliveryOptions: (json['deliveryOptions'] as List<dynamic>? ??
              json['delivery_options'] as List<dynamic>? ??
              const [])
          .map((item) => item.toString())
          .toList(),
      availableDrugs: (json['availableDrugs'] as List<dynamic>? ??
              json['available_drugs'] as List<dynamic>? ??
              const [])
          .map((item) => item.toString())
          .toList(),
      expertise: (json['expertise'] as List<dynamic>? ??
              json['expertise'] as List<dynamic>? ??
              const [])
          .map((item) => item.toString())
          .toList(),
    );
  }
}

class DealerRegistry {
  static Future<List<DrugDealer>> loadDealers() async {
    final raw = await rootBundle.loadString('assets/drug_dealers.json');
    final decoded = json.decode(raw) as List<dynamic>;
    final fallbackDealers = decoded
        .whereType<Map>()
        .map((item) => DrugDealer.fromJson(Map<String, dynamic>.from(item)))
        .toList();

    if (!AppServices.supabaseReady) {
      return fallbackDealers;
    }

    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select(
            'id,full_name,owner_name,business_name,district,phone_number,email,open_hours,delivery_options,available_drugs,expertise,role',
          )
          .eq('role', AppServices.dealerRole);

      final remoteDealers = (response as List<dynamic>)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .map((item) {
        return DrugDealer.fromJson({
          'id': item['id'],
          'accountId': item['id'],
          'businessName':
              item['business_name'] ?? item['full_name'] ?? 'Registered Agro Medic',
          'ownerName': item['owner_name'] ?? item['full_name'] ?? '',
          'district': item['district'] ?? 'Uganda',
          'phoneNumber': item['phone_number'] ?? '',
          'email': item['email'] ?? '',
          'openHours':
              item['open_hours'] ??
                  'Contact Agro Medic in chat for working hours',
          'deliveryOptions':
              item['delivery_options'] ?? const ['Chat to confirm delivery'],
          'availableDrugs': item['available_drugs'] ?? const [],
          'expertise': item['expertise'] ?? const [],
        });
      }).toList();

      final dealersById = <String, DrugDealer>{};
      for (final dealer in fallbackDealers) {
        dealersById[dealer.id] = dealer;
      }
      for (final dealer in remoteDealers) {
        dealersById[dealer.id] = dealer;
      }
      return dealersById.values.toList();
    } catch (_) {
      return fallbackDealers;
    }
  }

  static List<DrugDealer> matchDealers({
    required List<DrugDealer> dealers,
    required String diseaseName,
    required String treatmentText,
  }) {
    final disease = diseaseName.toLowerCase();
    final treatment = treatmentText.toLowerCase();

    final scored = dealers.map((dealer) {
      var score = 0;

      for (final drug in dealer.availableDrugs) {
        if (treatment.contains(drug.toLowerCase())) {
          score += 4;
        }
      }

      for (final tag in dealer.expertise) {
        final normalizedTag = tag.toLowerCase();
        if (disease.contains(normalizedTag) ||
            treatment.contains(normalizedTag)) {
          score += 2;
        }
      }

      if (score == 0 && treatment.contains('fungicide')) {
        score += 1;
      }

      return MapEntry(dealer, score);
    }).toList();

    scored.sort((a, b) {
      final byScore = b.value.compareTo(a.value);
      if (byScore != 0) return byScore;
      return a.key.businessName.compareTo(b.key.businessName);
    });

    final matched =
        scored.where((entry) => entry.value > 0).map((e) => e.key).toList();
    if (matched.isNotEmpty) {
      return matched;
    }

    return dealers.take(4).toList();
  }
}
