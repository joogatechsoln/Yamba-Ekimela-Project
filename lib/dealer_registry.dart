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
      ownerName: json['ownerName']?.toString() ?? '',
      district: json['district']?.toString() ?? '',
      phoneNumber: json['phoneNumber']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      openHours: json['openHours']?.toString() ?? '',
      deliveryOptions: (json['deliveryOptions'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      availableDrugs: (json['availableDrugs'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      expertise: (json['expertise'] as List<dynamic>? ?? const [])
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
          .select('id,full_name,district,phone_number,available_drugs,role')
          .eq('role', AppServices.dealerRole);

      final remoteDealers = (response as List<dynamic>)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .map((item) {
            final fullName = item['full_name']?.toString() ?? '';
            final availableDrugs =
                (item['available_drugs'] as List<dynamic>? ?? const [])
                    .map((entry) => entry.toString())
                    .toList();

            return DrugDealer(
              id: item['id']?.toString() ?? '',
              accountId: item['id']?.toString(),
              businessName: fullName.isNotEmpty
                  ? '$fullName Agro Support'
                  : 'Registered Dealer',
              ownerName: fullName.isNotEmpty ? fullName : 'Registered Dealer',
              district: item['district']?.toString() ?? 'Uganda',
              phoneNumber: item['phone_number']?.toString() ?? '',
              email: '',
              openHours: 'Contact dealer in chat for working hours',
              deliveryOptions: const ['Chat to confirm delivery'],
              availableDrugs: availableDrugs,
              expertise: availableDrugs,
            );
          })
          .toList();

      return [...remoteDealers, ...fallbackDealers];
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
        if (disease.contains(normalizedTag) || treatment.contains(normalizedTag)) {
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

    final matched = scored.where((entry) => entry.value > 0).map((e) => e.key).toList();
    if (matched.isNotEmpty) {
      return matched;
    }

    return dealers.take(4).toList();
  }
}
