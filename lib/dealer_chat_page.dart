import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_language.dart';
import 'dealer_marketplace_service.dart';
import 'dealer_registry.dart';

class DealerChatPage extends StatefulWidget {
  const DealerChatPage({
    super.key,
    this.dealer,
    this.threadId,
    this.diseaseName,
    this.recommendedDrugs,
    this.diagnosisImageFile,
    this.readOnlyTitle,
  });

  final DrugDealer? dealer;
  final String? threadId;
  final String? diseaseName;
  final String? recommendedDrugs;
  final File? diagnosisImageFile;
  final String? readOnlyTitle;

  @override
  State<DealerChatPage> createState() => _DealerChatPageState();
}

class _DealerChatPageState extends State<DealerChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String? _threadId;
  String? _receiverId;
  String? _diagnosisImageUrl;
  bool _creatingThread = false;
  String? _error;

  String _normalizeErrorMessage(Object error) {
    final message = error.toString();
    return message.startsWith('Exception:')
        ? message.substring('Exception:'.length).trim()
        : message;
  }

  @override
  void initState() {
    super.initState();
    _threadId = widget.threadId;
    _receiverId = widget.dealer?.accountId;
    if (_threadId != null) {
      _loadDiagnosisPreview();
    } else {
      _prepareThread();
    }
  }

  Future<void> _prepareThread() async {
    final dealer = widget.dealer;
    final imageFile = widget.diagnosisImageFile;
    if (dealer == null ||
        imageFile == null ||
        widget.diseaseName == null ||
        widget.recommendedDrugs == null) {
      setState(() {
        _error = 'Missing diagnosis details for this chat.';
      });
      return;
    }

    setState(() => _creatingThread = true);
    try {
      final thread = await DealerMarketplaceService.ensureThread(
        dealer: dealer,
        diseaseName: widget.diseaseName!,
        recommendedDrugs: widget.recommendedDrugs!,
        imageFile: imageFile,
      );
      _threadId = thread.id;
      _receiverId = thread.dealerId;
      await _loadDiagnosisPreview(storagePath: thread.diagnosisImagePath);
    } catch (e) {
      setState(() => _error = _normalizeErrorMessage(e));
    } finally {
      if (mounted) {
        setState(() => _creatingThread = false);
      }
    }
  }

  Future<void> _loadDiagnosisPreview({String? storagePath}) async {
    if (storagePath != null) {
      final resolved =
          await DealerMarketplaceService.resolveDiagnosisImageUrl(storagePath);
      if (mounted) {
        setState(() => _diagnosisImageUrl = resolved);
      }
      return;
    }

    if (_threadId == null) return;
    try {
      final thread = await Supabase.instance.client
          .from('dealer_threads')
          .select('diagnosis_image_path,dealer_id,farmer_id')
          .eq('id', _threadId!)
          .single();
      final resolved = await DealerMarketplaceService.resolveDiagnosisImageUrl(
        thread['diagnosis_image_path']?.toString(),
      );
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      final dealerId = thread['dealer_id']?.toString();
      final farmerId = thread['farmer_id']?.toString();
      if (mounted) {
        setState(() {
          _diagnosisImageUrl = resolved;
          _receiverId = currentUserId == dealerId ? farmerId : dealerId;
        });
      }
    } catch (_) {}
  }

  Future<void> _sendMessage() async {
    if (_threadId == null || _receiverId == null) return;
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    try {
      await DealerMarketplaceService.sendMessage(
        threadId: _threadId!,
        receiverId: _receiverId!,
        message: text,
      );
      _messageController.clear();
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      if (!mounted) return;
      final language = AppLanguageScope.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(language.text(_normalizeErrorMessage(e))),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = AppLanguageScope.of(context);
    final title = widget.dealer?.businessName ??
        (widget.readOnlyTitle != null
            ? language.text(widget.readOnlyTitle!)
            : language.text('Dealer Chat'));

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          if (widget.diseaseName != null || _diagnosisImageUrl != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: const Color(0xFFEAF6EC),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.diseaseName != null)
                    Text(
                      '${language.text('Diagnosis')}: ${language.text(widget.diseaseName!)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F5D2A),
                      ),
                    ),
                  if (widget.recommendedDrugs != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${language.text('Recommended drug')}: ${language.text(widget.recommendedDrugs!)}',
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF375A3F)),
                    ),
                  ],
                  if (_diagnosisImageUrl != null) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        _diagnosisImageUrl!,
                        height: 120,
                        width: 120,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          Expanded(
            child: _creatingThread
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            language.text(_error!),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        ),
                      )
                    : _threadId == null
                        ? Center(
                            child: Text(language.text('Unable to open chat.')),
                          )
                        : StreamBuilder<List<DealerMessage>>(
                            stream: DealerMarketplaceService.messageStream(_threadId!),
                            builder: (context, snapshot) {
                              final messages = snapshot.data ?? const <DealerMessage>[];
                              final currentUserId =
                                  Supabase.instance.client.auth.currentUser?.id;

                              return ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.all(16),
                                itemCount: messages.length,
                                itemBuilder: (context, index) {
                                  final message = messages[index];
                                  final isMine = message.senderId == currentUserId;
                                  return Align(
                                    alignment: isMine
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      padding: const EdgeInsets.all(14),
                                      constraints: const BoxConstraints(maxWidth: 290),
                                      decoration: BoxDecoration(
                                        color: isMine
                                            ? const Color(0xFF4CAF50)
                                            : const Color(0xFFF1F3F4),
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      child: Text(
                                        message.message,
                                        style: TextStyle(
                                          color: isMine ? Colors.white : Colors.black87,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: language.text('Type your message'),
                        filled: true,
                        fillColor: const Color(0xFFF6F7F8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: const Color(0xFF2E7D32),
                    child: IconButton(
                      onPressed: _sendMessage,
                      icon: const Icon(Icons.send_rounded, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
