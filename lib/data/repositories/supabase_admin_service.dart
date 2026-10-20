import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/admin_models.dart';
import '../../models/app_models.dart';

final supabaseAdminServiceProvider = Provider<SupabaseAdminService>((ref) {
  SupabaseClient? client;
  try {
    client = Supabase.instance.client;
  } catch (_) {
    client = null;
  }
  return SupabaseAdminService(client: client);
});

/// Central Supabase administration client for querying and synchronizing
/// announcements, KYC applications, and sales orders directly with the shared
/// Supabase database used by PalengkeGoAPP.
class SupabaseAdminService {
  const SupabaseAdminService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  SupabaseClient? get client {
    if (_client != null) return _client;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  bool get isConfigured => client != null;

  // ── Announcements ─────────────────────────────────────────────────────────

  /// Fetches all announcements from `system_announcements`.
  Future<List<Announcement>> fetchAnnouncements() async {
    final sb = client;
    if (sb == null) return [];

    try {
      final response = await sb
          .from('system_announcements')
          .select('*')
          .order('created_at', ascending: false);

      final list = response as List<dynamic>? ?? [];
      return list.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        final id = (map['id'] ?? map['announcement_id'] ?? '').toString();
        final rawAudience =
            (map['target_audience'] ?? map['targetAudience']) as String?;
        final audience = targetAudienceToDisplay(rawAudience);
        final createdAt = DateTime.tryParse(
              map['created_at']?.toString() ??
                  map['createdAt']?.toString() ??
                  '',
            ) ??
            DateTime.now();
        final expiresAt = map['expires_at'] != null
            ? DateTime.tryParse(map['expires_at'].toString())
            : (map['expiresAt'] != null
                ? DateTime.tryParse(map['expiresAt'].toString())
                : null);

        return Announcement(
          id: id,
          title: (map['title'] as String?) ?? '',
          summary: (map['body'] as String?) ?? '',
          audience: audience,
          createdAt: createdAt,
          expiresAt: expiresAt,
          isDraft: false,
          state: 'Sent',
          imageUrl: (map['image_url'] ?? map['imageUrl']) as String?,
          createdBy: (map['created_by'] as String?) ?? 'ADM-001',
        );
      }).toList();
    } catch (e) {
      debugPrint('[admin] Supabase fetchAnnouncements failed: $e');
      return [];
    }
  }

  /// Inserts a newly published announcement into `system_announcements`.
  Future<String?> publishAnnouncement({
    required String title,
    required String body,
    required String audience,
    DateTime? expiresAt,
    String? imageUrl,
    Uint8List? imageBytes,
  }) async {
    final sb = client;
    if (sb == null) return 'Supabase client is not configured';

    try {
      String? resolvedImageUrl = imageUrl;
      if (imageBytes != null && imageBytes.isNotEmpty) {
        final uploaded = await _uploadImageBytes(imageBytes);
        if (uploaded != null) resolvedImageUrl = uploaded;
      }

      final payload = <String, dynamic>{
        'title': title,
        'body': body,
        'target_audience': audienceToTargetAudience(audience),
        'created_at': DateTime.now().toUtc().toIso8601String(),
        if (expiresAt != null)
          'expires_at': expiresAt.toUtc().toIso8601String(),
        if (resolvedImageUrl != null && resolvedImageUrl.isNotEmpty)
          'image_url': resolvedImageUrl,
      };

      await sb.from('system_announcements').insert(payload);
      return null;
    } catch (e) {
      debugPrint('[admin] Supabase publishAnnouncement error: $e');
      return e.toString();
    }
  }

  /// Updates an announcement in `system_announcements`.
  Future<String?> updateAnnouncement({
    required String id,
    required String title,
    required String body,
    required String audience,
    DateTime? expiresAt,
    String? imageUrl,
    Uint8List? imageBytes,
    bool clearImage = false,
  }) async {
    final sb = client;
    if (sb == null) return 'Supabase client is not configured';

    try {
      String? resolvedImageUrl = imageUrl;
      if (imageBytes != null && imageBytes.isNotEmpty) {
        final uploaded = await _uploadImageBytes(imageBytes);
        if (uploaded != null) resolvedImageUrl = uploaded;
      }

      final payload = <String, dynamic>{
        'title': title,
        'body': body,
        'target_audience': audienceToTargetAudience(audience),
        if (expiresAt != null)
          'expires_at': expiresAt.toUtc().toIso8601String(),
        if (clearImage)
          'image_url': null
        else if (resolvedImageUrl != null && resolvedImageUrl.isNotEmpty)
          'image_url': resolvedImageUrl,
      };

      try {
        await sb.from('system_announcements').update(payload).eq('id', id);
      } catch (_) {
        await sb
            .from('system_announcements')
            .update(payload)
            .eq('announcement_id', id);
      }
      return null;
    } catch (e) {
      debugPrint('[admin] Supabase updateAnnouncement error: $e');
      return e.toString();
    }
  }

  /// Deletes an announcement in `system_announcements`.
  Future<String?> deleteAnnouncement(String id) async {
    final sb = client;
    if (sb == null) return 'Supabase client is not configured';

    try {
      try {
        await sb.from('system_announcements').delete().eq('id', id);
      } catch (_) {
        await sb.from('system_announcements').delete().eq('announcement_id', id);
      }
      return null;
    } catch (e) {
      debugPrint('[admin] Supabase deleteAnnouncement error: $e');
      return e.toString();
    }
  }

  // ── KYC Applications ──────────────────────────────────────────────────────

  /// Loads vendor KYC submissions from `kyc_submissions` table.
  Future<List<VendorApplication>> fetchApplications() async {
    final sb = client;
    if (sb == null) return [];

    try {
      final kycRows = await sb
          .from('kyc_submissions')
          .select('*')
          .order('submitted_at', ascending: false);

      final stallsRows = await sb.from('stall_holders').select('*');
      final usersRows = await sb.from('users').select('*');

      final stallById = <String, Map<String, dynamic>>{};
      for (final item in (stallsRows as List<dynamic>? ?? [])) {
        final m = Map<String, dynamic>.from(item as Map);
        final id = (m['stall_holder_id'] ?? m['id'] ?? '').toString();
        if (id.isNotEmpty) stallById[id] = m;
      }

      final userById = <String, Map<String, dynamic>>{};
      for (final item in (usersRows as List<dynamic>? ?? [])) {
        final m = Map<String, dynamic>.from(item as Map);
        final id = (m['user_id'] ?? m['id'] ?? '').toString();
        if (id.isNotEmpty) userById[id] = m;
      }

      final results = <VendorApplication>[];
      for (final item in (kycRows as List<dynamic>? ?? [])) {
        final kyc = Map<String, dynamic>.from(item as Map);
        final id = (kyc['kyc_id'] ?? kyc['id'] ?? '').toString();
        final stallId = (kyc['stall_holder_id'] ?? '').toString();
        final stall = stallById[stallId] ?? const <String, dynamic>{};
        final user = userById[stallId] ?? const <String, dynamic>{};

        final submittedAt = DateTime.tryParse(
              kyc['submitted_at']?.toString() ?? '',
            ) ??
            DateTime.now();

        final rawStatus = (kyc['status'] as String? ?? 'pending').toLowerCase();
        final status = switch (rawStatus) {
          'approved' => ApplicationStatus.verified,
          'rejected' => ApplicationStatus.rejected,
          'invaliddocs' || 'invalid_docs' => ApplicationStatus.invalidDocs,
          _ => ApplicationStatus.reviewing,
        };

        final applicantName = (user['full_name'] ??
                user['displayName'] ??
                kyc['owner_name']) as String? ??
            'Vendor ($stallId)';
        final stallName = (stall['stall_name'] ??
                stall['name'] ??
                kyc['stall_name']) as String? ??
            'Stall $stallId';
        final category = (stall['category'] ?? kyc['category']) as String? ??
            'General';
        final location = stall['stall_number'] != null
            ? 'Stall #${stall['stall_number']}, Floor ${stall['floor_number'] ?? '1'}'
            : 'Main Wet Market';

        final documents = <KycDocument>[];
        void addDoc(String name, String? url) {
          if (url != null && url.isNotEmpty) {
            documents.add(
              KycDocument(
                name: name,
                filename: url.split('/').last.split('?').first,
                mimeType: 'image/*',
                uploadedAt: submittedAt,
                fileUrl: url,
                idFrontUrl: url,
              ),
            );
          }
        }

        addDoc("Mayor's Permit", kyc['mayor_permit_url'] as String?);
        addDoc("Sanitary Permit", kyc['sanitary_permit_url'] as String?);
        addDoc(
            "Fire Safety Certificate", kyc['fire_certification_url'] as String?);
        addDoc("Market Clearance", kyc['market_clearance_url'] as String?);
        addDoc("Valid Government ID", kyc['valid_id_photo_url'] as String?);
        addDoc("Selfie Verification", kyc['selfie_url'] as String?);

        results.add(
          VendorApplication(
            id: id,
            userId: stallId,
            applicant: applicantName,
            stallName: stallName,
            category: category,
            submittedAt: submittedAt,
            status: status,
            location: location,
            documents: documents,
            rejectionReason: kyc['rejection_reason'] as String?,
            reviewedAt: kyc['reviewed_at'] != null
                ? DateTime.tryParse(kyc['reviewed_at'].toString())
                : null,
            reviewedBy: kyc['reviewed_by'] as String?,
          ),
        );
      }

      return results;
    } catch (e) {
      debugPrint('[admin] Supabase fetchApplications failed: $e');
      return [];
    }
  }

  /// Updates application status in `kyc_submissions` and `stall_holders`.
  Future<String?> updateApplicationStatus(
    String id,
    ApplicationStatus status, {
    String? rejectionReason,
    String? stallHolderId,
    DateTime? expiryDate,
  }) async {
    final sb = client;
    if (sb == null) return 'Supabase client is not configured';

    try {
      final isApproved = status == ApplicationStatus.verified;
      final dbStatus = isApproved ? 'approved' : 'rejected';

      await sb.from('kyc_submissions').update({
        'status': dbStatus,
        'reviewed_at': DateTime.now().toUtc().toIso8601String(),
        'reviewed_by': 'Admin',
        if (rejectionReason != null) 'rejection_reason': rejectionReason,
      }).or('kyc_id.eq.$id,id.eq.$id');

      var targetStallId = stallHolderId;
      if (targetStallId == null || targetStallId.isEmpty) {
        try {
          final existing = await sb
              .from('kyc_submissions')
              .select('stall_holder_id')
              .or('kyc_id.eq.$id,id.eq.$id')
              .maybeSingle();
          targetStallId = existing?['stall_holder_id']?.toString();
        } catch (_) {}
      }

            if (targetStallId != null && targetStallId.isNotEmpty) {
        List<String> currentTags = [];
        try {
          final stallData = await sb
              .from('stall_holders')
              .select('tags')
              .or('stall_holder_id.eq.$targetStallId,id.eq.$targetStallId,user_id.eq.$targetStallId')
              .maybeSingle();
          if (stallData != null && stallData['tags'] is List) {
            currentTags = (stallData['tags'] as List)
                .cast<String>()
                .where((t) => !t.startsWith('license_expiry:'))
                .toList();
          }
        } catch (_) {}

        if (isApproved && expiryDate != null) {
          final expiryStr = DateFormat('yyyy-MM-dd').format(expiryDate);
          currentTags.add('license_expiry:$expiryStr');
        }

        await sb.from('stall_holders').update({
          'kyc_status': dbStatus,
          'is_kyc_approved': isApproved,
          if (isApproved && expiryDate != null) 'tags': currentTags,
        }).or('stall_holder_id.eq.$targetStallId,id.eq.$targetStallId,user_id.eq.$targetStallId');

        try {
          final expiryFormatted = expiryDate != null
              ? DateFormat('MMMM d, yyyy').format(expiryDate)
              : null;
          final approvalMsg = expiryFormatted != null
              ? 'Congratulations! Your stall holder application has been approved by Market Administration (MEPO). Your permit is valid until $expiryFormatted.'
              : 'Congratulations! Your stall holder application has been approved by Market Administration.';

          await sb.from('notifications').insert({
            'user_id': targetStallId,
            'title': isApproved
                ? 'Application Accepted by MEPO! 🎉'
                : 'Application Update: Review Required',
            'body': isApproved
                ? approvalMsg
                : 'Your application was not approved: ${rejectionReason ?? 'Documents did not pass review.'}',
            'type': 'admin',
            'reference_id': id,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          });
        } catch (notifErr) {
          debugPrint('[admin] Failed to insert KYC notification: $notifErr');
        }
      }
      return null;
    } catch (e) {
      debugPrint('[admin] Supabase updateApplicationStatus failed: $e');
      return e.toString();
    }
  }

  // ── Orders & Sales Reports ────────────────────────────────────────────────

  /// Fetches orders from Supabase `orders` and `order_items` tables.
  Future<List<Order>> fetchOrders() async {
    final sb = client;
    if (sb == null) return [];

    try {
      final orderRows = await sb
          .from('orders')
          .select('*')
          .order('created_at', ascending: false)
          .limit(500);

      final itemsRows = await sb.from('order_items').select('*');
      final stallsRows = await sb.from('stall_holders').select('*');

      final itemsByOrderId = <String, List<OrderItem>>{};
      for (final item in (itemsRows as List<dynamic>? ?? [])) {
        final m = Map<String, dynamic>.from(item as Map);
        final orderId = (m['order_id'] ?? '').toString();
        if (orderId.isEmpty) continue;

        itemsByOrderId.putIfAbsent(orderId, () => []).add(
              OrderItem(
                name: (m['product_name'] ?? 'Product').toString(),
                category: (m['category'] ?? 'Produce').toString(),
                quantity: ((m['quantity'] as num?) ?? 1).round(),
                unitPrice: ((m['unit_price'] ?? m['price_at_order'] as num?) ??
                        0.0)
                    .toDouble(),
              ),
            );
      }

      final stallById = <String, Map<String, dynamic>>{};
      for (final item in (stallsRows as List<dynamic>? ?? [])) {
        final m = Map<String, dynamic>.from(item as Map);
        final id = (m['stall_holder_id'] ?? m['id'] ?? '').toString();
        if (id.isNotEmpty) stallById[id] = m;
      }

      final results = <Order>[];
      for (final item in (orderRows as List<dynamic>? ?? [])) {
        final row = Map<String, dynamic>.from(item as Map);
        final orderId = (row['order_id'] ?? row['id'] ?? '').toString();
        final stallId = (row['stall_holder_id'] ?? '').toString();
        final stall = stallById[stallId] ?? const <String, dynamic>{};

        final stallName = (stall['stall_name'] ??
                stall['name'] ??
                row['vendor_name']) as String? ??
            'Market Stall';
        final vendorName = (stall['owner_name'] ?? stallName) as String;

        final items = itemsByOrderId[orderId] ??
            [
              OrderItem(
                name: 'Market Produce',
                category: 'General',
                quantity: 1,
                unitPrice:
                    ((row['total_amount'] ?? row['total'] as num?) ?? 0.0)
                        .toDouble(),
              ),
            ];

        final pm = (row['payment_method'] as String? ?? 'cod').toLowerCase();
        final paymentMethod = switch (pm) {
          'gcash' => PaymentMethod.gcash,
          'card' => PaymentMethod.card,
          'wallet' => PaymentMethod.wallet,
          _ => PaymentMethod.cashOnDelivery,
        };

        final ps =
            (row['payment_status'] as String? ?? 'pending').toLowerCase();
        final paymentStatus = switch (ps) {
          'paid' => PaymentStatus.paid,
          'refunded' => PaymentStatus.refunded,
          'partially_refunded' => PaymentStatus.partiallyRefunded,
          'failed' => PaymentStatus.failed,
          _ => PaymentStatus.pending,
        };

        final os = (row['order_status'] ??
                row['status'] as String? ??
                'pending')
            .toLowerCase();
        final orderStatus = switch (os) {
          'completed' || 'delivered' => OrderStatus.completed,
          'cancelled' => OrderStatus.cancelled,
          'refunded' => OrderStatus.refunded,
          'preparing' ||
          'ready' ||
          'processing' ||
          'out_for_delivery' ||
          'outfordelivery' =>
            OrderStatus.processing,
          _ => OrderStatus.pending,
        };

        results.add(
          Order(
            id: orderId,
            transactionId: stallId.isNotEmpty ? stallId : orderId,
            placedAt: DateTime.tryParse(
                  row['created_at']?.toString() ??
                      row['placed_at']?.toString() ??
                      '',
                ) ??
                DateTime.now(),
            customerName:
                (row['customer_name'] as String?) ?? 'Market Customer',
            vendorName: vendorName,
            stallName: stallName,
            items: items,
            discounts: ((row['discounts'] as num?) ?? 0.0).toDouble(),
            deliveryFee: ((row['delivery_fee'] as num?) ?? 0.0).toDouble(),
            platformFee: ((row['service_fee'] as num?) ?? 0.0).toDouble(),
            refundAmount: ((row['refunded_amount'] as num?) ?? 0.0).toDouble(),
            paymentMethod: paymentMethod,
            paymentStatus: paymentStatus,
            status: orderStatus,
          ),
        );
      }

      return results;
    } catch (e) {
      debugPrint('[admin] Supabase fetchOrders failed: $e');
      return [];
    }
  }

  // ── Account Blocking & Suspension Sync ─────────────────────────────────────

  /// Syncs an account block/unblock state with Supabase `users` and `stall_holders` tables.
  Future<void> setAccountBlocked(String userId, bool blocked) async {
    final sb = client;
    if (sb == null) return;
    try {
      String resolvedUserId = userId;
      final cust = await sb
          .from('customers')
          .select('user_id')
          .or('customer_id.eq.$userId,user_id.eq.$userId')
          .maybeSingle();
      if (cust != null && cust['user_id'] != null) {
        resolvedUserId = cust['user_id'].toString();
      } else {
        final stall = await sb
            .from('stall_holders')
            .select('user_id')
            .or('stall_holder_id.eq.$userId,user_id.eq.$userId')
            .maybeSingle();
        if (stall != null && stall['user_id'] != null) {
          resolvedUserId = stall['user_id'].toString();
        }
      }

      await sb.from('users').update({
        'is_blocked': blocked,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).or('user_id.eq.$resolvedUserId,user_id.eq.$userId,id.eq.$resolvedUserId,id.eq.$userId');

      await sb.from('stall_holders').update({
        'is_blocked': blocked,
        if (blocked) 'is_open': false,
      }).or('stall_holder_id.eq.$userId,user_id.eq.$userId,user_id.eq.$resolvedUserId');
    } catch (e) {
      debugPrint('[admin] Supabase setAccountBlocked failed: $e');
    }
  }

  /// Syncs an account suspension end date with Supabase `users.banned_until`.
  Future<void> setAccountSuspended(String accountId, DateTime? until) async {
    final sb = client;
    if (sb == null) return;
    try {
      String resolvedUserId = accountId;
      final cust = await sb
          .from('customers')
          .select('user_id')
          .or('customer_id.eq.$accountId,user_id.eq.$accountId')
          .maybeSingle();
      if (cust != null && cust['user_id'] != null) {
        resolvedUserId = cust['user_id'].toString();
      } else {
        final stall = await sb
            .from('stall_holders')
            .select('user_id')
            .or('stall_holder_id.eq.$accountId,user_id.eq.$accountId')
            .maybeSingle();
        if (stall != null && stall['user_id'] != null) {
          resolvedUserId = stall['user_id'].toString();
        }
      }

      await sb.from('users').update({
        'banned_until': until?.toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).or('user_id.eq.$resolvedUserId,user_id.eq.$accountId,id.eq.$resolvedUserId,id.eq.$accountId');
    } catch (e) {
      debugPrint('[admin] Supabase setAccountSuspended failed: $e');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  // ── Vendors & Stalls ────────────────────────────────────────────────────────

  /// Fetches vendor stalls from Supabase `stall_holders` joined with `users` and `orders`.
  Future<List<Vendor>> fetchVendors() async {
    final sb = client;
    if (sb == null) return [];

    try {
      final stallsRows = await sb.from('stall_holders').select('*');
      final usersRows = await sb.from('users').select('*');
      final ordersRows = await sb
          .from('orders')
          .select('stall_holder_id, total_amount, order_status');

      final userById = <String, Map<String, dynamic>>{};
      for (final item in (usersRows as List<dynamic>? ?? [])) {
        final m = Map<String, dynamic>.from(item as Map);
        final id = (m['user_id'] ?? m['id'] ?? '').toString();
        if (id.isNotEmpty) userById[id] = m;
      }

      final orderCounts = <String, int>{};
      final totalRevenues = <String, double>{};
      for (final item in (ordersRows as List<dynamic>? ?? [])) {
        final m = Map<String, dynamic>.from(item as Map);
        final stallId = (m['stall_holder_id'] ?? '').toString();
        if (stallId.isEmpty) continue;
        orderCounts[stallId] = (orderCounts[stallId] ?? 0) + 1;
        final total = (m['total_amount'] as num?)?.toDouble() ?? 0.0;
        totalRevenues[stallId] = (totalRevenues[stallId] ?? 0.0) + total;
      }

      final results = <Vendor>[];
      for (final item in (stallsRows as List<dynamic>? ?? [])) {
        final stall = Map<String, dynamic>.from(item as Map);
        final stallId =
            (stall['stall_holder_id'] ?? stall['id'] ?? '').toString();
        final userId = (stall['user_id'] ?? stallId).toString();
        final user = userById[userId] ??
            userById[stallId] ??
            const <String, dynamic>{};

        final stallName =
            (stall['stall_name'] ?? stall['name'] ?? 'Vendor Stall').toString();
        final category = (stall['category'] ?? 'General').toString();
        final stallNumber = (stall['stall_number'] ?? '1').toString();
        final floorNumber = (stall['floor_number'] ?? '1').toString();

        final bannedUntil =
            DateTime.tryParse(user['banned_until']?.toString() ?? '');
        final isSuspended =
            bannedUntil != null && bannedUntil.isAfter(DateTime.now());
        final isBlocked =
            stall['is_blocked'] == true || user['is_blocked'] == true;
        final status = isBlocked
            ? AccountStatus.blocked
            : isSuspended
                ? AccountStatus.suspended
                : AccountStatus.active;

        final createdAt = DateTime.tryParse(
              stall['created_at']?.toString() ??
                  user['created_at']?.toString() ??
                  '',
            ) ??
            DateTime.now();

        final count = orderCounts[stallId] ?? orderCounts[userId] ?? 0;
        final revenue = totalRevenues[stallId] ?? totalRevenues[userId] ?? 0.0;

        results.add(
          Vendor(
            id: stallId,
            userId: userId,
            name: stallName,
            email: (user['email'] ?? '').toString(),
            stallType: category,
            registeredAt: createdAt,
            status: status,
            location: 'Stall #$stallNumber, Floor $floorNumber',
            orders: count,
            transactions: revenue,
            phone: (user['phone_number'] ?? '').toString(),
            residence: 'Naga City',
          ),
        );
      }

      return results;
    } catch (e) {
      debugPrint('[admin] Supabase fetchVendors failed: $e');
      return [];
    }
  }

  // ── Customers ──────────────────────────────────────────────────────────────

  /// Fetches customers from Supabase `customers` joined with `users` and `orders`.
  Future<List<Customer>> fetchCustomers() async {
    final sb = client;
    if (sb == null) return [];

    try {
      final customersRows = await sb.from('customers').select('*');
      final usersRows = await sb.from('users').select('*');
      final ordersRows =
          await sb.from('orders').select('customer_id, customer_name');

      final userById = <String, Map<String, dynamic>>{};
      for (final item in (usersRows as List<dynamic>? ?? [])) {
        final m = Map<String, dynamic>.from(item as Map);
        final id = (m['user_id'] ?? m['id'] ?? '').toString();
        if (id.isNotEmpty) userById[id] = m;
      }

      final orderCountsById = <String, int>{};
      final orderCountsByName = <String, int>{};
      for (final item in (ordersRows as List<dynamic>? ?? [])) {
        final m = Map<String, dynamic>.from(item as Map);
        final cId = (m['customer_id'] ?? '').toString();
        if (cId.isNotEmpty) {
          orderCountsById[cId] = (orderCountsById[cId] ?? 0) + 1;
        }
        final cName =
            (m['customer_name'] ?? '').toString().trim().toLowerCase();
        if (cName.isNotEmpty) {
          orderCountsByName[cName] = (orderCountsByName[cName] ?? 0) + 1;
        }
      }

      final results = <Customer>[];
      for (final item in (customersRows as List<dynamic>? ?? [])) {
        final customer = Map<String, dynamic>.from(item as Map);
        final customerId =
            (customer['customer_id'] ?? customer['id'] ?? '').toString();
        final userId = (customer['user_id'] ?? customerId).toString();
        final user = userById[userId] ?? const <String, dynamic>{};

        final name = (user['full_name'] ??
                user['displayName'] ??
                'Customer $customerId')
            .toString();
        final email = (user['email'] ?? '').toString();
        final bannedUntil =
            DateTime.tryParse(user['banned_until']?.toString() ?? '');
        final isSuspended =
            bannedUntil != null && bannedUntil.isAfter(DateTime.now());
        final isBlocked = user['is_blocked'] == true;
        final status = isBlocked
            ? AccountStatus.blocked
            : isSuspended
                ? AccountStatus.suspended
                : AccountStatus.active;

        final createdAt = DateTime.tryParse(
              user['created_at']?.toString() ?? '',
            ) ??
            DateTime.now();
        final count = orderCountsById[customerId] ??
            orderCountsById[userId] ??
            orderCountsByName[name.trim().toLowerCase()] ??
            0;

        results.add(
          Customer(
            id: customerId,
            userId: userId,
            name: name,
            email: email,
            registeredAt: createdAt,
            transactions: count,
            status: status,
          ),
        );
      }

      return results;
    } catch (e) {
      debugPrint('[admin] Supabase fetchCustomers failed: $e');
      return [];
    }
  }

  Future<String?> _uploadImageBytes(Uint8List bytes) async {
    final sb = client;
    if (sb == null) return null;
    try {
      final fileName =
          'announcement_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await sb.storage.from('stalls').uploadBinary(
            fileName,
            bytes,
            fileOptions:
                const FileOptions(contentType: 'image/jpeg', upsert: true),
          );
      return sb.storage.from('stalls').getPublicUrl(fileName);
    } catch (e) {
      debugPrint('[admin] Storage upload fallback: $e');
      return null;
    }
  }

  static String audienceToTargetAudience(String audience) {
    switch (audience.trim().toLowerCase()) {
      case 'stall holders':
      case 'stallholders':
      case 'vendors':
      case 'vendor':
        return 'stallholders';
      case 'customers':
      case 'customer':
        return 'customers';
      default:
        return 'all';
    }
  }

  static String targetAudienceToDisplay(String? targetAudience) {
    switch (targetAudience?.trim().toLowerCase()) {
      case 'stallholders':
      case 'vendors':
        return 'Stall Holders';
      case 'customers':
        return 'Customers';
      default:
        return 'All Users';
    }
  }

  // ── Reports ─────────────────────────────────────────────────────────────

  /// Fetches reports and complaints from Supabase `reports` table.
  Future<List<Report>> fetchReports() async {
    final sb = client;
    if (sb == null) return [];

    try {
      final rows = await sb
          .from('reports')
          .select('*')
          .order('created_at', ascending: false)
          .limit(500);

      final results = <Report>[];
      for (final item in (rows as List<dynamic>? ?? [])) {
        final row = Map<String, dynamic>.from(item as Map);
        final id = (row['id'] ?? '').toString();
        if (id.isEmpty) continue;

        final rawStatus =
            (row['status'] as String? ?? 'pending').toLowerCase();
        final status = switch (rawStatus) {
          'resolved' => ReportStatus.resolved,
          'dismissed' => ReportStatus.dismissed,
          'underreview' || 'under_review' => ReportStatus.underReview,
          _ => ReportStatus.pending,
        };

        final rawPriority =
            (row['priority'] as String? ?? 'medium').toLowerCase();
        final priority = switch (rawPriority) {
          'high' => Priority.high,
          'low' => Priority.low,
          _ => Priority.medium,
        };

        final date = DateTime.tryParse(
              row['created_at']?.toString() ??
                  row['date']?.toString() ??
                  '',
            ) ??
            DateTime.now();

        final resolvedAt = row['resolved_at'] != null
            ? DateTime.tryParse(row['resolved_at'].toString())
            : null;

        results.add(
          Report(
            id: id,
            userId: row['user_id']?.toString(),
            type: (row['type'] as String?) ?? 'Customer',
            accountIssue: (row['account_issue'] ?? row['accountIssue'] ?? '')
                .toString(),
            category: (row['category'] as String?) ?? 'General',
            submittedBy:
                (row['submitted_by'] ?? row['submittedBy'] ?? 'User')
                    .toString(),
            reason: (row['reason'] as String?) ?? '',
            date: date,
            status: status,
            priority: priority,
            description: (row['description'] as String?) ?? '',
            evidenceUrls: () {
              final raw = row['evidence_urls'] ?? row['evidenceUrls'];
              if (raw is List) {
                return raw.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
              }
              return const <String>[];
            }(),
            reporterEmail: (row['reporter_email'] ?? row['reporterEmail'] ?? '')
                .toString(),
            phone: (row['phone'] as String?) ?? '',
            vendorName:
                (row['vendor_name'] ?? row['vendorName'] ?? '').toString(),
            owner: (row['owner'] as String?) ?? '',
            stallNumber:
                (row['stall_number'] ?? row['stallNumber'] ?? '').toString(),
            previousViolations:
                (row['previous_violations'] as num?)?.toInt() ?? 0,
            notes: (row['notes'] as String?) ?? '',
            decision: row['decision'] as String?,
            actionTaken:
                (row['action_taken'] ?? row['actionTaken']) as String?,
            resolutionNote:
                (row['resolution_note'] ?? row['resolutionNote']) as String?,
            resolvedAt: resolvedAt,
            resolvedBy: (row['resolved_by'] ?? row['resolvedBy']) as String?,
          ),
        );
      }

      return results;
    } catch (e) {
      debugPrint('[admin] Supabase fetchReports failed: $e');
      return [];
    }
  }

  /// Updates or resolves a report in Supabase `reports` table.
  /// If the report has a valid userId and resolution note, dispatches a notification.
  Future<String?> updateReport(Report report) async {
    final sb = client;
    if (sb == null) return 'Supabase client is not configured';

    try {
      final payload = <String, dynamic>{
        'status': report.status.name,
        'notes': report.notes,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        if (report.decision != null) 'decision': report.decision,
        if (report.actionTaken != null) 'action_taken': report.actionTaken,
        if (report.resolutionNote != null)
          'resolution_note': report.resolutionNote,
        if (report.resolvedAt != null)
          'resolved_at': report.resolvedAt!.toIso8601String(),
        if (report.resolvedBy != null) 'resolved_by': report.resolvedBy,
      };

      await sb.from('reports').update(payload).eq('id', report.id);

      // 1. If this is an Official Warning (status == underReview and notes are present)
      final isWarning = report.status == ReportStatus.underReview && report.notes.trim().isNotEmpty;
      if (isWarning) {
        String? targetUserId;
        if (report.type == 'Stall Holder' || report.type == 'Vendor') {
          try {
            final stallQuery = await sb
                .from('stall_holders')
                .select('user_id, stall_holder_id')
                .or('stall_name.ilike.%${report.vendorName}%,stall_name.ilike.%${report.accountIssue}%,stall_holder_id.eq.${report.accountIssue}')
                .limit(1)
                .maybeSingle();
            if (stallQuery != null) {
              targetUserId = (stallQuery['user_id'] ?? stallQuery['stall_holder_id'])?.toString();
            }
          } catch (e) {
            debugPrint('[admin] Error resolving stall holder for warning: $e');
          }
        } else if (report.type == 'Customer') {
          try {
            final userQuery = await sb
                .from('users')
                .select('id')
                .or('name.ilike.%${report.accountIssue}%,id.eq.${report.accountIssue}')
                .limit(1)
                .maybeSingle();
            if (userQuery != null) {
              targetUserId = userQuery['id']?.toString();
            }
          } catch (e) {
            debugPrint('[admin] Error resolving customer for warning: $e');
          }
        }

        if (targetUserId != null && targetUserId.isNotEmpty) {
          try {
            await sb.from('notifications').insert({
              'user_id': targetUserId,
              'title': 'Official Warning from Market Administration ⚠️',
              'body': report.notes.trim(),
              'type': 'admin_warning',
              'reference_id': report.id,
              'created_at': DateTime.now().toUtc().toIso8601String(),
              'is_read': false,
            });
            debugPrint('[admin] Inserted admin_warning notification to user $targetUserId for report ${report.id}');
          } catch (notifErr) {
            debugPrint('[admin] Failed to insert warning notification: $notifErr');
          }
        }
      }

      // 2. If this is a report update/resolution note to the reporting user
      if (report.userId != null &&
          report.userId!.isNotEmpty &&
          report.resolutionNote != null &&
          report.resolutionNote!.trim().isNotEmpty) {
        try {
          await sb.from('notifications').insert({
            'user_id': report.userId,
            'title': 'Report Update: ${report.decision ?? 'Resolved'}',
            'body': report.resolutionNote!.trim(),
            'type': 'system_announcement',
            'reference_id': report.id,
            'created_at': DateTime.now().toUtc().toIso8601String(),
            'is_read': false,
          });
        } catch (notifErr) {
          debugPrint('[admin] Failed to insert notification for report: $notifErr');
        }
      }

      return null;
    } catch (e) {
      debugPrint('[admin] Supabase updateReport failed: $e');
      return e.toString();
    }
  }
  /// Subscribes to real-time changes on the `reports` table.
  /// Calls [onReportInserted] when a new report is filed from the mobile app,
  /// and [onReportUpdated] when an existing report is updated.
  RealtimeChannel? subscribeToReports({
    required void Function(Report report) onReportInserted,
    required void Function(Report report) onReportUpdated,
  }) {
    final sb = client;
    if (sb == null) return null;

    final channel = sb.channel('admin-reports-realtime');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'reports',
      callback: (payload) {
        try {
          final record = payload.newRecord;
          if (record.isEmpty) return;

          final rawStatus =
              (record['status'] as String? ?? 'pending').toLowerCase();
          final status = switch (rawStatus) {
            'resolved' => ReportStatus.resolved,
            'dismissed' => ReportStatus.dismissed,
            'underreview' || 'under_review' => ReportStatus.underReview,
            _ => ReportStatus.pending,
          };

          final rawPriority =
              (record['priority'] as String? ?? 'medium').toLowerCase();
          final priority = switch (rawPriority) {
            'high' => Priority.high,
            'low' => Priority.low,
            _ => Priority.medium,
          };

          final date = DateTime.tryParse(
                record['created_at']?.toString() ??
                    record['date']?.toString() ??
                    '',
              ) ??
              DateTime.now();

          final resolvedAt = record['resolved_at'] != null
              ? DateTime.tryParse(record['resolved_at'].toString())
              : null;

          final report = Report(
            id: (record['id'] ?? '').toString(),
            userId: record['user_id']?.toString(),
            type: (record['type'] as String?) ?? 'Customer',
            accountIssue:
                (record['account_issue'] ?? record['accountIssue'] ?? '')
                    .toString(),
            category: (record['category'] as String?) ?? 'General',
            submittedBy:
                (record['submitted_by'] ?? record['submittedBy'] ?? 'User')
                    .toString(),
            reason: (record['reason'] as String?) ?? '',
            date: date,
            status: status,
            priority: priority,
            description: (record['description'] as String?) ?? '',
            reporterEmail:
                (record['reporter_email'] ?? record['reporterEmail'] ?? '')
                    .toString(),
            phone: (record['phone'] as String?) ?? '',
            vendorName:
                (record['vendor_name'] ?? record['vendorName'] ?? '').toString(),
            owner: (record['owner'] as String?) ?? '',
            stallNumber:
                (record['stall_number'] ?? record['stallNumber'] ?? '').toString(),
            previousViolations:
                (record['previous_violations'] as num?)?.toInt() ?? 0,
            notes: (record['notes'] as String?) ?? '',
            decision: record['decision'] as String?,
            actionTaken:
                (record['action_taken'] ?? record['actionTaken']) as String?,
            resolutionNote:
                (record['resolution_note'] ?? record['resolutionNote'])
                    as String?,
            resolvedAt: resolvedAt,
            resolvedBy: (record['resolved_by'] ?? record['resolvedBy']) as String?,
          );

          if (payload.eventType == PostgresChangeEvent.insert) {
            onReportInserted(report);
          } else {
            onReportUpdated(report);
          }
        } catch (e) {
          debugPrint('[admin] Realtime report change processing failed: $e');
        }
      },
    );
    channel.subscribe();
    return channel;
  }
}
