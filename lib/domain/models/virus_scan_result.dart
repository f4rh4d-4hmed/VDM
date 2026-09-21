enum VirusScanStatus {
  clean,
  suspicious,
  malicious,
  notFound,
  skippedTooLarge,
  scanning,
  error,
}

class VirusScanResult {
  final VirusScanStatus status;
  final int maliciousCount;
  final int suspiciousCount;
  final int undetectedCount;
  final int harmlessCount;
  final int totalEngines;
  final String? permalink;
  final DateTime? scanDate;
  final Map<String, String> detectedThreats; // Engine -> Threat name
  final String? errorMessage;
  final bool desktopAntivirusHandedOver;
  final String? desktopAntivirusDetails;
  final int? fileSizeBytes;
  final String? fileSha256;

  const VirusScanResult({
    required this.status,
    this.maliciousCount = 0,
    this.suspiciousCount = 0,
    this.undetectedCount = 0,
    this.harmlessCount = 0,
    this.totalEngines = 0,
    this.permalink,
    this.scanDate,
    this.detectedThreats = const {},
    this.errorMessage,
    this.desktopAntivirusHandedOver = false,
    this.desktopAntivirusDetails,
    this.fileSizeBytes,
    this.fileSha256,
  });

  bool get isClean => status == VirusScanStatus.clean;
  bool get isMalicious => status == VirusScanStatus.malicious;
  bool get isSuspicious => status == VirusScanStatus.suspicious;
  bool get isNotFound => status == VirusScanStatus.notFound;
  bool get isSkippedTooLarge => status == VirusScanStatus.skippedTooLarge;
  bool get isError => status == VirusScanStatus.error;
  bool get isScanning => status == VirusScanStatus.scanning;

  factory VirusScanResult.clean({
    int totalEngines = 0,
    int undetectedCount = 0,
    int harmlessCount = 0,
    String? permalink,
    DateTime? scanDate,
    bool desktopAntivirusHandedOver = false,
    String? desktopAntivirusDetails,
    int? fileSizeBytes,
    String? fileSha256,
  }) {
    return VirusScanResult(
      status: VirusScanStatus.clean,
      totalEngines: totalEngines,
      undetectedCount: undetectedCount,
      harmlessCount: harmlessCount,
      permalink: permalink,
      scanDate: scanDate ?? DateTime.now(),
      desktopAntivirusHandedOver: desktopAntivirusHandedOver,
      desktopAntivirusDetails: desktopAntivirusDetails,
      fileSizeBytes: fileSizeBytes,
      fileSha256: fileSha256,
    );
  }

  factory VirusScanResult.malicious({
    required int maliciousCount,
    int suspiciousCount = 0,
    int totalEngines = 0,
    Map<String, String> detectedThreats = const {},
    String? permalink,
    DateTime? scanDate,
    bool desktopAntivirusHandedOver = false,
    String? desktopAntivirusDetails,
    int? fileSizeBytes,
    String? fileSha256,
  }) {
    return VirusScanResult(
      status: VirusScanStatus.malicious,
      maliciousCount: maliciousCount,
      suspiciousCount: suspiciousCount,
      totalEngines: totalEngines,
      detectedThreats: detectedThreats,
      permalink: permalink,
      scanDate: scanDate ?? DateTime.now(),
      desktopAntivirusHandedOver: desktopAntivirusHandedOver,
      desktopAntivirusDetails: desktopAntivirusDetails,
      fileSizeBytes: fileSizeBytes,
      fileSha256: fileSha256,
    );
  }

  factory VirusScanResult.skippedTooLarge({
    required int fileSizeBytes,
    bool desktopAntivirusHandedOver = false,
    String? desktopAntivirusDetails,
  }) {
    return VirusScanResult(
      status: VirusScanStatus.skippedTooLarge,
      fileSizeBytes: fileSizeBytes,
      desktopAntivirusHandedOver: desktopAntivirusHandedOver,
      desktopAntivirusDetails: desktopAntivirusDetails,
      errorMessage: 'File size exceeds 5 GB. Automatic detection was skipped.',
    );
  }

  factory VirusScanResult.notFound({
    String? fileSha256,
    int? fileSizeBytes,
    bool desktopAntivirusHandedOver = false,
    String? desktopAntivirusDetails,
  }) {
    return VirusScanResult(
      status: VirusScanStatus.notFound,
      fileSha256: fileSha256,
      fileSizeBytes: fileSizeBytes,
      desktopAntivirusHandedOver: desktopAntivirusHandedOver,
      desktopAntivirusDetails: desktopAntivirusDetails,
    );
  }

  factory VirusScanResult.error({
    required String message,
    bool desktopAntivirusHandedOver = false,
    String? desktopAntivirusDetails,
  }) {
    return VirusScanResult(
      status: VirusScanStatus.error,
      errorMessage: message,
      desktopAntivirusHandedOver: desktopAntivirusHandedOver,
      desktopAntivirusDetails: desktopAntivirusDetails,
    );
  }

  VirusScanResult copyWith({
    VirusScanStatus? status,
    int? maliciousCount,
    int? suspiciousCount,
    int? undetectedCount,
    int? harmlessCount,
    int? totalEngines,
    String? permalink,
    DateTime? scanDate,
    Map<String, String>? detectedThreats,
    String? errorMessage,
    bool? desktopAntivirusHandedOver,
    String? desktopAntivirusDetails,
    int? fileSizeBytes,
    String? fileSha256,
  }) {
    return VirusScanResult(
      status: status ?? this.status,
      maliciousCount: maliciousCount ?? this.maliciousCount,
      suspiciousCount: suspiciousCount ?? this.suspiciousCount,
      undetectedCount: undetectedCount ?? this.undetectedCount,
      harmlessCount: harmlessCount ?? this.harmlessCount,
      totalEngines: totalEngines ?? this.totalEngines,
      permalink: permalink ?? this.permalink,
      scanDate: scanDate ?? this.scanDate,
      detectedThreats: detectedThreats ?? this.detectedThreats,
      errorMessage: errorMessage ?? this.errorMessage,
      desktopAntivirusHandedOver: desktopAntivirusHandedOver ?? this.desktopAntivirusHandedOver,
      desktopAntivirusDetails: desktopAntivirusDetails ?? this.desktopAntivirusDetails,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      fileSha256: fileSha256 ?? this.fileSha256,
    );
  }
}
