import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_language.dart';
import 'dealer_registry.dart';

class DealerDirectoryPage extends StatefulWidget {
  const DealerDirectoryPage({super.key});

  @override
  State<DealerDirectoryPage> createState() => _DealerDirectoryPageState();
}

class _DealerDirectoryPageState extends State<DealerDirectoryPage> {
  late Future<List<DrugDealer>> _dealersFuture;

  @override
  void initState() {
    super.initState();
    _dealersFuture = DealerRegistry.loadDealers();
  }

  Future<void> _callDealer(DrugDealer dealer) async {
    final language = AppLanguageScope.of(context);
    if (dealer.phoneNumber.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            language.text('This dealer has not added a phone number yet.'),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final status = await Permission.phone.request();
    if (!status.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            language.text('Phone permission is required to contact dealers.'),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final uri = Uri(scheme: 'tel', path: dealer.phoneNumber);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(language.text('Could not open the phone dialer.')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = AppLanguageScope.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(language.text('Agro Medics')),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<DrugDealer>>(
        future: _dealersFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final dealers = snapshot.data!;
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: dealers.length,
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (context, index) {
              final dealer = dealers[index];
              return Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dealer.businessName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: Color(0xFF1F5D2A),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('${dealer.ownerName} - ${dealer.district}'),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: dealer.availableDrugs
                          .take(4)
                          .map(
                            (drug) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEAF6EC),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                language.text(drug),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF2E7D32),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${language.text('Delivery')}: ${dealer.deliveryOptions.map(language.text).join(', ')}',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${language.text('Hours')}: ${language.text(dealer.openHours)}',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _callDealer(dealer),
                        icon: const Icon(Icons.call_rounded),
                        label: Text(language.text('Call Agro Medic')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4CAF50),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
