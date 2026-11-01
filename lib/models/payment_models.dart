// DTO untuk alur pembayaran (monolith-picture: Api\PaymentController).

/// Paket foto yang bisa dibeli (GET /api/packages).
class PackageDto {
  const PackageDto({
    required this.id,
    required this.name,
    required this.takes,
    required this.price,
    this.description,
  });

  final int id;
  final String name;
  final int takes;
  final int price; // rupiah
  final String? description;

  factory PackageDto.fromJson(Map<String, dynamic> json) {
    return PackageDto(
      id: (json['id'] as num).toInt(),
      name: json['name']?.toString() ?? 'Paket',
      takes: (json['takes'] as num?)?.toInt() ?? 1,
      price: _asRupiah(json['price']),
      description: json['description']?.toString(),
    );
  }
}

/// Sesi yang dibuat server untuk pembayaran ini.
class PaymentSessionDto {
  const PaymentSessionDto({
    required this.id,
    required this.sessionCode,
    required this.allowedTakes,
    required this.paymentStatus,
  });

  final int id;
  final String sessionCode;
  final int allowedTakes;
  final String paymentStatus;

  factory PaymentSessionDto.fromJson(Map<String, dynamic> json) {
    return PaymentSessionDto(
      id: (json['id'] as num).toInt(),
      sessionCode: json['session_code']?.toString() ?? '',
      allowedTakes: (json['allowed_takes'] as num?)?.toInt() ?? 0,
      paymentStatus: json['payment_status']?.toString() ?? 'pending',
    );
  }
}

/// Status pembayaran dari server (POST /api/payments, GET /api/payments/{order}).
class PaymentDto {
  const PaymentDto({
    required this.orderId,
    required this.status,
    required this.paid,
    required this.expired,
    required this.amount,
    required this.takes,
    this.expiresAt,
    this.serverTime,
    this.paymentUrl,
    this.session,
  });

  final String orderId;
  final String status;
  final bool paid;
  final bool expired;
  final int amount;
  final int takes;
  final DateTime? expiresAt;
  final DateTime? serverTime;

  /// Isi QR. Pelanggan scan -> halaman bayar Midtrans.
  final String? paymentUrl;
  final PaymentSessionDto? session;

  factory PaymentDto.fromJson(Map<String, dynamic> json) {
    final Object? sessionRaw = json['session'];
    return PaymentDto(
      orderId: json['order_id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      paid: json['paid'] == true,
      expired: json['expired'] == true,
      amount: _asRupiah(json['amount']),
      takes: (json['takes'] as num?)?.toInt() ?? 0,
      expiresAt: _asDate(json['expires_at']),
      serverTime: _asDate(json['server_time']),
      paymentUrl: json['payment_url']?.toString(),
      session: sessionRaw is Map<String, dynamic>
          ? PaymentSessionDto.fromJson(sessionRaw)
          : null,
    );
  }
}

/// Hasil gerbang pembayaran: sesi yang sudah lunas dan boleh dipakai foto.
class PaidSession {
  const PaidSession({
    required this.sessionId,
    required this.sessionCode,
    required this.allowedTakes,
    required this.orderId,
  });

  final int sessionId;
  final String sessionCode;
  final int allowedTakes;
  final String orderId;
}

int _asRupiah(Object? value) {
  if (value is num) return value.round();
  final num? parsed = num.tryParse(value?.toString() ?? '');
  return parsed?.round() ?? 0;
}

DateTime? _asDate(Object? value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}
