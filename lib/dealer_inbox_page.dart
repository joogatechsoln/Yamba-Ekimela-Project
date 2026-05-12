import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_language.dart';
import 'app_services.dart';
import 'dealer_chat_page.dart';
import 'dealer_marketplace_service.dart';

class DealerInboxPage extends StatefulWidget {
  const DealerInboxPage({super.key});

  @override
  State<DealerInboxPage> createState() => _DealerInboxPageState();
}

class _DealerInboxPageState extends State<DealerInboxPage> {
  bool _isDealerRole = false;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _isDealerRole =
          prefs.getString(AppServices.userRoleKey) == AppServices.dealerRole;
    });
  }

  @override
  Widget build(BuildContext context) {
    final language = AppLanguageScope.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isDealerRole
              ? language.text('Dealer Inbox')
              : language.text('Dealer Messages'),
        ),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
      ),
      body: !AppServices.supabaseReady ||
              Supabase.instance.client.auth.currentUser == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  language.text(
                    'Dealer messaging needs a signed-in Supabase account.',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : StreamBuilder<List<DealerThread>>(
        stream: DealerMarketplaceService.threadStream(isDealer: _isDealerRole),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '${language.text('Unable to load inbox.')}\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final threads = snapshot.data!;
          if (threads.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  language.text(
                    'No diagnosis conversations yet. Farmers can start a chat from the results page.',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: threads.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final thread = threads[index];
              return InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DealerChatPage(
                        threadId: thread.id,
                        diseaseName: thread.diseaseName,
                        recommendedDrugs: thread.recommendedDrugs,
                        readOnlyTitle: thread.diseaseName,
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        thread.diseaseName,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1F5D2A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        thread.lastMessage,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        thread.updatedAt.toLocal().toString(),
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
