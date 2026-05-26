import 'package:flutter/material.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_services.dart';
import 'app_language.dart';
import 'dealer_chat_page.dart';
import 'dealer_registry.dart';

class ResultsPage extends StatefulWidget {
  const ResultsPage({super.key});

  @override
  State<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends State<ResultsPage>
    with SingleTickerProviderStateMixin {
  String _disease = 'Analyzing...';
  double _confidence = 0.0;
  String _description = '';
  String _recommendations = '';
  String _drugs = '';
  String _displayDisease = 'Analyzing...';
  String _displayDescription = '';
  String _displayRecommendations = '';
  String _displayDrugs = '';
  bool _isLoading = true;
  String? _error;
  List<DrugDealer> _matchedDealers = const [];
  bool _isDealerRole = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  String _normalizeLabelKey(String value) {
    return value.trim().replaceAll('\r', '');
  }

  Map<String, dynamic>? _findDiseaseInfo(
    Map<String, dynamic> diseases,
    String rawLabel,
  ) {
    final normalizedLabel = _normalizeLabelKey(rawLabel);
    final displayLabel = normalizedLabel.replaceAll('_', ' ').trim();

    final directMatch = diseases[normalizedLabel];
    if (directMatch is Map<String, dynamic>) {
      return directMatch;
    }

    final displayMatch = diseases[displayLabel];
    if (displayMatch is Map<String, dynamic>) {
      return displayMatch;
    }

    return null;
  }

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    // Delay inference to allow animations to start
    Future.delayed(Duration(milliseconds: 300), () {
      _runInference();
    });
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1000),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );

    _animationController.forward();
  }

  Future<void> _runInference() async {
    try {
      final File imageFile = ModalRoute.of(context)!.settings.arguments as File;
      final assetBundle = DefaultAssetBundle.of(context);

      // Load and prepare the image
      final imageBytes = await imageFile.readAsBytes();
      img.Image? image = img.decodeImage(imageBytes);

      if (image == null) {
        throw Exception('Failed to decode image');
      }

      // Resize image to 224x224
      img.Image resizedImage = img.copyResize(image, width: 224, height: 224);

      // Load the model
      final interpreter = await Interpreter.fromAsset(
        'assets/plant_disease_mobilenetv2_quant.tflite',
      );

      // Prepare input
      final Uint8List rgbBytes =
          resizedImage.getBytes(order: img.ChannelOrder.rgb);
      var input = rgbBytes.reshape([1, 224, 224, 3]);

      // Prepare output
      final outputTensor = interpreter.getOutputTensor(0);
      final outputType = outputTensor.type;
      final outputShape = outputTensor.shape;
      final int classCount = outputShape.last;

      // Run inference
      List<List<double>> scores;
      if (outputType == TensorType.uint8) {
        final output = List.generate(1, (_) => List<int>.filled(classCount, 0));
        interpreter.run(input, output);
        scores = [
          output[0].map((v) => v / 255.0).toList(),
        ];
      } else {
        final output =
            List.generate(1, (_) => List<double>.filled(classCount, 0));
        interpreter.run(input, output);
        scores = output;
      }

      // Get prediction
      int predIdx = 0;
      double maxVal = scores[0][0];
      for (int i = 1; i < scores[0].length; i++) {
        if (scores[0][i] > maxVal) {
          maxVal = scores[0][i];
          predIdx = i;
        }
      }

      _confidence = scores[0][predIdx] * 100;

      // Load labels
      String labelsData = await assetBundle.loadString('assets/labels.txt');
      List<String> labels = labelsData
          .split('\n')
          .map(_normalizeLabelKey)
          .where((l) => l.trim().isNotEmpty)
          .toList();

      _disease = labels[predIdx].replaceAll('_', ' ').trim();

      // Load disease information
      String diseasesData = await assetBundle.loadString('assets/diseases.json');
      final Map<String, dynamic> diseases =
          Map<String, dynamic>.from(json.decode(diseasesData));

      final diseaseInfo = _findDiseaseInfo(diseases, labels[predIdx]);
      _description = diseaseInfo?['description'] ?? 'No information available';
      _recommendations =
          diseaseInfo?['recommendations'] ?? 'No recommendations available';
      _drugs = diseaseInfo?['drugs'] ?? 'No treatment information available';
      await _applyTranslations();
      await _loadDealerMatches();

      // Save to history with timestamp
      SharedPreferences prefs = await SharedPreferences.getInstance();
      List<String> history = prefs.getStringList('diagnosis_history') ?? [];
      String timestamp = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
      history
          .add('$timestamp - $_disease - ${_confidence.toStringAsFixed(1)}%');
      prefs.setStringList('diagnosis_history', history);

      interpreter.close();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to analyze image: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _applyTranslations() async {
    final language = AppLanguageScope.of(context);
    _displayDisease = await language.translate(_disease);
    _displayDescription = await language.translate(_description);
    _displayRecommendations = await language.translate(_recommendations);
    _displayDrugs = await language.translate(_drugs);
  }

  Future<void> _loadDealerMatches() async {
    final prefs = await SharedPreferences.getInstance();
    final dealers = await DealerRegistry.loadDealers();
    final matched = DealerRegistry.matchDealers(
      dealers: dealers,
      diseaseName: _disease,
      treatmentText: _drugs,
    );

    _isDealerRole =
        prefs.getString(AppServices.userRoleKey) == AppServices.dealerRole;
    _matchedDealers = matched.take(4).toList();
  }

  Future<void> _callDealer(DrugDealer dealer) async {
    final language = AppLanguageScope.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    if (dealer.phoneNumber.trim().isEmpty) {
      scaffoldMessenger.showSnackBar(
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
      scaffoldMessenger.showSnackBar(
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
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(language.text('Could not start the call.')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _messageDealer(File imageFile, DrugDealer dealer) async {
    final language = AppLanguageScope.of(context);
    if (!AppServices.supabaseReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            language.text(
              'In-app messaging needs Supabase to be configured for this app.',
            ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (dealer.accountId == null || dealer.accountId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            language.text(
              'This Agro Medic can be called now. Add a registered Agro Medic account to enable in-app chat.',
            ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DealerChatPage(
          dealer: dealer,
          diseaseName: _disease,
          recommendedDrugs: _drugs,
          diagnosisImageFile: imageFile,
        ),
      ),
    );
  }

  Color _getConfidenceColor() {
    if (_confidence >= 90) return Color(0xFF4CAF50);
    if (_confidence >= 70) return Color(0xFFFF9800);
    return Color(0xFFF44336);
  }

  String _getConfidenceLabel() {
    if (_confidence >= 90) return 'Very High';
    if (_confidence >= 70) return 'Good';
    return 'Low';
  }

  IconData _getConfidenceIcon() {
    if (_confidence >= 90) return Icons.check_circle;
    if (_confidence >= 70) return Icons.info;
    return Icons.warning;
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final File imageFile = ModalRoute.of(context)!.settings.arguments as File;
    final language = AppLanguageScope.of(context);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF4CAF50),
              Colors.white,
            ],
            stops: [0.0, 0.25],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(
                        language.text('Scan Results'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    SizedBox(width: 48), // Balance the back button
                  ],
                ),
              ),

              // Main Content
              Expanded(
                child: _isLoading
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ScaleTransition(
                              scale: _scaleAnimation,
                              child: Container(
                                padding: EdgeInsets.all(30),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.1),
                                      blurRadius: 20,
                                      offset: Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: CircularProgressIndicator(
                                  strokeWidth: 4,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Color(0xFF4CAF50),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: 30),
                            FadeTransition(
                              opacity: _fadeAnimation,
                              child: Text(
                                language.text('Analyzing your crop...'),
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: EdgeInsets.all(32),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    size: 80,
                                    color: Colors.red,
                                  ),
                                  SizedBox(height: 20),
                                  Text(
                                    language.text('Analysis Failed'),
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red,
                                    ),
                                  ),
                                  SizedBox(height: 12),
                                  Text(
                                    _error!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  SizedBox(height: 30),
                                  ElevatedButton.icon(
                                    onPressed: () => Navigator.pop(context),
                                    icon: Icon(Icons.arrow_back),
                                    label: Text(language.text('Try Again')),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Color(0xFF4CAF50),
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 32,
                                        vertical: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : FadeTransition(
                            opacity: _fadeAnimation,
                            child: SingleChildScrollView(
                              child: Column(
                                children: [
                                  // Image Card
                                  Container(
                                    margin:
                                        EdgeInsets.symmetric(horizontal: 20),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(24),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.2,
                                          ),
                                          blurRadius: 20,
                                          offset: Offset(0, 10),
                                        ),
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(24),
                                      child: Image.file(
                                        imageFile,
                                        height: 250,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),

                                  SizedBox(height: 24),

                                  // Results Container
                                  Container(
                                    padding: EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(30),
                                        topRight: Radius.circular(30),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Disease Name
                                        Center(
                                          child: Column(
                                            children: [
                                              Container(
                                                padding: EdgeInsets.all(16),
                                                decoration: BoxDecoration(
                                                  color: _getConfidenceColor()
                                                      .withValues(alpha: 0.1),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(
                                                  Icons.local_florist,
                                                  size: 50,
                                                  color: _getConfidenceColor(),
                                                ),
                                              ),
                                              SizedBox(height: 16),
                                              Text(
                                                _displayDisease,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: 26,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF2E7D32),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                        SizedBox(height: 20),

                                        // Confidence Card
                                        Container(
                                          padding: EdgeInsets.all(20),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                _getConfidenceColor(),
                                                _getConfidenceColor()
                                                    .withValues(alpha: 0.8),
                                              ],
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            boxShadow: [
                                              BoxShadow(
                                                color: _getConfidenceColor()
                                                    .withValues(alpha: 0.3),
                                                blurRadius: 15,
                                                offset: Offset(0, 8),
                                              ),
                                            ],
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                _getConfidenceIcon(),
                                                color: Colors.white,
                                                size: 40,
                                              ),
                                              SizedBox(width: 16),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      language.text(
                                                          'Confidence Level'),
                                                      style: TextStyle(
                                                        color: Colors.white70,
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                    SizedBox(height: 4),
                                                    Row(
                                                      children: [
                                                        Text(
                                                          '${_confidence.toStringAsFixed(1)}%',
                                                          style: TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 32,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                        SizedBox(width: 12),
                                                        Container(
                                                          padding: EdgeInsets
                                                              .symmetric(
                                                            horizontal: 12,
                                                            vertical: 6,
                                                          ),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: Colors.white
                                                                .withValues(
                                                                  alpha: 0.3,
                                                                ),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        12),
                                                          ),
                                                          child: Text(
                                                            language.text(
                                                              _getConfidenceLabel(),
                                                            ),
                                                            style: TextStyle(
                                                              color:
                                                                  Colors.white,
                                                              fontSize: 12,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                        SizedBox(height: 24),

                                        // Understanding Accuracy
                                        _buildInfoCard(
                                          language
                                              .text('Understanding Accuracy'),
                                          language.text(
                                            'Above 90%: Very reliable result\n'
                                            '70-90%: Good detection, consider retaking in better light\n'
                                            'Below 70%: Low confidence, try a clearer photo',
                                          ),
                                          Icons.help_outline,
                                          Color(0xFF2196F3),
                                        ),

                                        SizedBox(height: 16),

                                        // Description
                                        _buildInfoCard(
                                          language.text('Description'),
                                          _displayDescription,
                                          Icons.description,
                                          Color(0xFF9C27B0),
                                        ),

                                        SizedBox(height: 16),

                                        // Recommendations
                                        _buildInfoCard(
                                          language.text('Recommendations'),
                                          _displayRecommendations,
                                          Icons.lightbulb_outline,
                                          Color(0xFFFF9800),
                                        ),

                                        SizedBox(height: 16),

                                        // Treatments
                                        _buildInfoCard(
                                          language.text('Treatments & Drugs'),
                                          _displayDrugs,
                                          Icons.medical_services_outlined,
                                          Color(0xFFF44336),
                                        ),

                                        SizedBox(height: 24),

                                        _buildDealerSection(imageFile),

                                        SizedBox(height: 24),

                                        // Action Buttons
                                        Row(
                                          children: [
                                            Expanded(
                                              child: OutlinedButton.icon(
                                                onPressed: () =>
                                                    Navigator.pop(context),
                                                icon: Icon(Icons.camera_alt),
                                                label: Text(
                                                  language.text('Scan Again'),
                                                ),
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor:
                                                      Color(0xFF4CAF50),
                                                  side: BorderSide(
                                                    color: Color(0xFF4CAF50),
                                                    width: 2,
                                                  ),
                                                  padding: EdgeInsets.symmetric(
                                                      vertical: 16),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            16),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            SizedBox(width: 12),
                                            Expanded(
                                              child: ElevatedButton.icon(
                                                onPressed: () {
                                                  Navigator.popUntil(
                                                    context,
                                                    (route) => route.isFirst,
                                                  );
                                                },
                                                icon: Icon(Icons.home),
                                                label:
                                                    Text(language.text('Home')),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      Color(0xFF4CAF50),
                                                  padding: EdgeInsets.symmetric(
                                                      vertical: 16),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            16),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),

                                        SizedBox(height: 20),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(
    String title,
    String content,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            content,
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey.shade700,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDealerSection(File imageFile) {
    final language = AppLanguageScope.of(context);
    if (_isDealerRole) {
      return _buildInfoCard(
        language.text('Dealer workflow'),
        language.text(
          'You are signed in as a dealer. Open your inbox from the home page to respond to farmer requests.',
        ),
        Icons.storefront_rounded,
        const Color(0xFF2E7D32),
      );
    }

    if (_matchedDealers.isEmpty) {
      return _buildInfoCard(
        language.text('Agro Medics'),
        language.text(
          'No matching dealer was found from the current treatment list. Open the dealer directory from home or scan again after updating treatment data.',
        ),
        Icons.store_mall_directory_outlined,
        const Color(0xFF2E7D32),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2E7D32).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF2E7D32).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.local_phone_rounded,
                  color: Color(0xFF2E7D32),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  language.text('Call or Message Agro Medics'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2E7D32),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            language.text(
              'These dealers match the treatment information shown above. Farmers can call directly or send the diagnosis image, disease name, and recommended drug details into chat.',
            ),
            style: TextStyle(color: Colors.grey.shade700, height: 1.4),
          ),
          const SizedBox(height: 16),
          ..._matchedDealers.map(
            (dealer) => Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dealer.businessName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: Color(0xFF1F5D2A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('${dealer.ownerName} - ${dealer.district}'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: dealer.availableDrugs
                        .take(3)
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
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _callDealer(dealer),
                          icon: const Icon(Icons.call_outlined),
                          label: Text(language.text('Call')),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF2E7D32),
                            side: const BorderSide(color: Color(0xFF2E7D32)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _messageDealer(imageFile, dealer),
                          icon: const Icon(Icons.chat_bubble_outline_rounded),
                          label: Text(language.text('Message')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2E7D32),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
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
