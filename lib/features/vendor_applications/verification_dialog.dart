import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/admin_widgets.dart';
import '../../data/repositories/mock_repository.dart';
import '../../models/app_models.dart';

class VerificationDialog extends ConsumerStatefulWidget {
  const VerificationDialog.application(this.application, {super.key})
      : renewal = null;
  const VerificationDialog.renewal(this.renewal, {super.key})
      : application = null;
  final VendorApplication? application;
  final RenewalRequest? renewal;
  String get applicant => application?.applicant ?? renewal!.applicant;
  String get stall => application?.stallName ?? renewal!.stallName;
  String get category => application?.category ?? renewal!.category;
  String get location => application?.location ?? renewal!.location;
  String get id => application?.id ?? renewal!.id;
  @override
  ConsumerState<VerificationDialog> createState() => _VerificationDialogState();
}

class _VerificationDialogState extends ConsumerState<VerificationDialog> {
  bool processing = false;

  Future<void> approve() async {
    final okay = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve application?'),
        content: const Text('This will grant marketplace access.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (okay != true || !mounted) return;
    setState(() => processing = true);
    if (widget.application != null) {
      await ref
          .read(appDataProvider.notifier)
          .updateApplication(widget.id, ApplicationStatus.verified);
    }
    if (widget.renewal != null) {
      await ref
          .read(appDataProvider.notifier)
          .updateRenewal(widget.id, RenewalStatus.approved);
    }
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Application approved.')));
    }
  }

  Future<void> reject() async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) => const _PromptInputDialogWidget(
        title: 'Reject application',
        hintText: 'Add a reason...',
        confirmLabel: 'Reject',
        minLines: 2,
        maxLines: 4,
      ),
    );
    if (value == null || value.isEmpty || !mounted) return;
    setState(() => processing = true);
    if (widget.application != null) {
      await ref.read(appDataProvider.notifier).updateApplication(
            widget.id,
            ApplicationStatus.rejected,
            rejectionReason: value,
          );
    }
    if (widget.renewal != null) {
      await ref
          .read(appDataProvider.notifier)
          .updateRenewal(widget.id, RenewalStatus.expired);
    }
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Application rejected.')));
    }
  }

  Future<void> _reopenForReview() async {
    setState(() => processing = true);
    if (widget.application != null) {
      await ref
          .read(appDataProvider.notifier)
          .updateApplication(widget.id, ApplicationStatus.reviewing);
    }
    if (widget.renewal != null) {
      await ref
          .read(appDataProvider.notifier)
          .updateRenewal(widget.id, RenewalStatus.reviewing);
    }
    if (mounted) {
      setState(() => processing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Application reopened for review.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 850;
    final appData = ref.watch(appDataProvider);
    final currentApp = widget.application != null
        ? appData.applications.firstWhere(
            (a) => a.id == widget.id,
            orElse: () => widget.application!,
          )
        : null;
    final currentRenewal = widget.renewal != null
        ? appData.renewals.firstWhere(
            (r) => r.id == widget.id,
            orElse: () => widget.renewal!,
          )
        : null;

    final isApproved = (currentApp?.status == ApplicationStatus.verified) ||
        (currentRenewal?.status == RenewalStatus.approved);
    final isRejected = (currentApp?.status == ApplicationStatus.rejected);

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: narrow ? 10 : 55,
        vertical: narrow ? 10 : 34,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 970, maxHeight: 720),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(narrow ? 16 : 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TENANTS  /  VERIFICATION DETAIL',
                          style: TextStyle(
                            fontSize: 9,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: .5),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            AvatarCircle(name: widget.applicant, size: 46),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.applicant,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    'Submitted: ${shortDate.format(DateTime.now())}  •  ${widget.location}',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 17),
              const Divider(),
              const SizedBox(height: 17),
              if (narrow) ...[
                _documents(context),
                const SizedBox(height: 18),
                _summary(context, currentApp, currentRenewal),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 68, child: _documents(context)),
                    const SizedBox(width: 25),
                    Expanded(flex: 32, child: _summary(context, currentApp, currentRenewal)),
                  ],
                ),
              const SizedBox(height: 22),
              _buildActionSection(
                context,
                isApproved: isApproved,
                isRejected: isRejected,
                currentApp: currentApp,
                currentRenewal: currentRenewal,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionSection(
    BuildContext context, {
    required bool isApproved,
    required bool isRejected,
    required VendorApplication? currentApp,
    required RenewalRequest? currentRenewal,
  }) {
    if (isApproved) {
      final dateStr = currentApp?.reviewedAt != null
          ? shortDate.format(currentApp!.reviewedAt!)
          : currentRenewal?.submittedAt != null
              ? shortDate.format(currentRenewal!.submittedAt!)
              : shortDate.format(DateTime.now());
      final label = widget.renewal != null
          ? 'Approved on $dateStr'
          : 'Verified on $dateStr';

      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFF10B981).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: Color(0xFF059669),
                ),
                const SizedBox(width: 8),
                Text(
                  '✓ $label',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF059669),
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: processing ? null : _reopenForReview,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Reopen for Review'),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: semanticColors(context).subtleBorder),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ],
      );
    }

    if (isRejected) {
      final dateStr = currentApp?.reviewedAt != null
          ? shortDate.format(currentApp!.reviewedAt!)
          : shortDate.format(DateTime.now());
      final reason = currentApp?.rejectionReason;

      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.cancel_rounded,
                    size: 18,
                    color: Color(0xFFEF4444),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '✗ Rejected on $dateStr${reason != null && reason.isNotEmpty ? ' • Reason: $reason' : ''}',
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFEF4444),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          OutlinedButton.icon(
            onPressed: processing ? null : _reopenForReview,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Reopen for Review'),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: semanticColors(context).subtleBorder),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ],
      );
    }

    return Align(
      alignment: Alignment.centerRight,
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.end,
        children: [
          OutlinedButton.icon(
            onPressed: processing ? null : _moreDocs,
            icon: const Icon(Icons.document_scanner_outlined, size: 15),
            label: const Text('Request Additional Documents'),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: semanticColors(context).subtleBorder),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          OutlinedButton.icon(
            onPressed: processing ? null : reject,
            icon: const Icon(Icons.close_rounded, size: 15, color: Color(0xFFEF4444)),
            label: const Text(
              'Reject',
              style: TextStyle(
                color: Color(0xFFEF4444),
                fontWeight: FontWeight.w700,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFEF4444), width: 1.2),
              backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.06),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
          ),
          FilledButton.icon(
            onPressed: processing ? null : approve,
            icon: processing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.check_rounded, size: 16),
            label: const Text(
              'Approve',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _documents(BuildContext context) {
    final documents = widget.application?.documents ?? const <KycDocument>[];
    final tiles = documents.isNotEmpty
        ? documents.map((document) => _docModel(context, document)).toList()
        : [
            _doc(context, 'Mayor’s Permit', null),
            _doc(
              context,
              'Sanitary Permit',
              'assets/images/mobile_conversation.png',
            ),
            _doc(context, 'ID', 'assets/images/mobile_conversation.png'),
            _doc(
              context,
              'Fire Certification',
              'assets/images/spoiled_produce.png',
            ),
            _doc(
              context,
              'Market Clearance',
              'assets/images/mobile_conversation.png',
            ),
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.grid_view_rounded,
              size: 16,
              color: semanticColors(context).secondaryText,
            ),
            const SizedBox(width: 8),
            Text(
              'Required Documents',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: semanticColors(context).primaryText,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: MediaQuery.sizeOf(context).width < 500
              ? 1
              : MediaQuery.sizeOf(context).width < 700
                  ? 2
                  : 3,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: MediaQuery.sizeOf(context).width < 500 ? 1.6 : 1.15,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: tiles,
        ),
      ],
    );
  }

  Widget _docModel(BuildContext context, KycDocument document) {
    final asset = document.assetPath;
    return _doc(
      context,
      document.name,
      asset,
      filename:
          '${document.filename} • ${shortDate.format(document.uploadedAt)}',
    );
  }

  Widget _doc(
    BuildContext context,
    String name,
    String? asset, {
    String? filename,
  }) {
    final colors = semanticColors(context);
    final content = asset == null
        ? Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.description_outlined,
                size: 38,
                color: colors.accent,
              ),
            ),
          )
        : Image.asset(asset, fit: BoxFit.cover);

    return InkWell(
      onTap: () => showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: asset == null
              ? const Icon(Icons.description_outlined, size: 160)
              : Image.asset(asset),
        ),
      ),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.subtleBorder, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                child: content,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: colors.subtleBorder, width: 0.8),
                ),
              ),
              child: Text(
                filename == null ? name : '$name\n$filename',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: colors.primaryText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summary(
    BuildContext context, [
    VendorApplication? currentApp,
    RenewalRequest? currentRenewal,
  ]) {
    final colors = semanticColors(context);
    final app = currentApp ?? widget.application;
    final renewal = currentRenewal ?? widget.renewal;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.subtleBorder, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'APPLICANT SUMMARY',
                style: GoogleFonts.inter(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: colors.secondaryText,
                ),
              ),
              const SizedBox(height: 14),
              _item('BUSINESS NAME', widget.stall),
              Padding(
                padding: const EdgeInsets.only(bottom: 13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('CATEGORY', style: TextStyle(fontSize: 8.5)),
                    const SizedBox(height: 5),
                    CategoryBadge(category: widget.category),
                  ],
                ),
              ),
              _item('CONTACT NO.', '+63 921 555 0123'),
              _item(
                'EMAIL ADDRESS',
                '${widget.applicant.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '.')}@gmail.com',
              ),
            ],
          ),
        ),
        if (renewal != null) ...[
          const SizedBox(height: 14),
          _buildRenewalHistoryCard(context),
        ],
        if (app?.rejectionReason != null && app!.rejectionReason!.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.dangerContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
            ),
            child: _item(
              app.status == ApplicationStatus.invalidDocs
                  ? 'REQUIRED DOCUMENTS / NOTES'
                  : 'REJECTION REASON',
              app.rejectionReason!,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRenewalHistoryCard(BuildContext context) {
    final colors = semanticColors(context);
    final renewal = widget.renewal!;
    final allRenewals = ref.watch(appDataProvider.select((s) => s.renewals));
    final matchingRenewals = allRenewals
        .where((r) =>
            (r.applicant.toLowerCase() == widget.applicant.toLowerCase() ||
                r.stallName.toLowerCase() == widget.stall.toLowerCase()) &&
            r.id != widget.id)
        .toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.subtleBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 14,
                    color: colors.secondaryText,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'RENEWAL HISTORY',
                    style: GoogleFonts.inter(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: colors.secondaryText,
                    ),
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Good Standing',
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF10B981),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _historyItem(
            context,
            cycle: '${renewal.expiryDate.year} Renewal (Current)',
            dateStr: renewal.submittedAt != null
                ? 'Submitted ${shortDate.format(renewal.submittedAt!)}'
                : 'Submitted recently',
            statusLabel: enumLabel(renewal.status),
            statusKind: renewal.status == RenewalStatus.approved
                ? BadgeKind.success
                : renewal.status == RenewalStatus.expired
                    ? BadgeKind.danger
                    : BadgeKind.warning,
            isCurrent: true,
          ),
          if (matchingRenewals.isNotEmpty)
            for (int i = 0; i < matchingRenewals.length; i++)
              _historyItem(
                context,
                cycle: '${matchingRenewals[i].expiryDate.year} Annual License',
                dateStr: matchingRenewals[i].submittedAt != null
                    ? 'Submitted ${shortDate.format(matchingRenewals[i].submittedAt!)}'
                    : 'Valid until ${shortDate.format(matchingRenewals[i].expiryDate)}',
                statusLabel: enumLabel(matchingRenewals[i].status),
                statusKind: matchingRenewals[i].status == RenewalStatus.approved
                    ? BadgeKind.success
                    : matchingRenewals[i].status == RenewalStatus.expired
                        ? BadgeKind.danger
                        : BadgeKind.neutral,
                isCurrent: false,
                isLast: i == matchingRenewals.length - 1,
              )
          else ...[
            _historyItem(
              context,
              cycle: '${renewal.expiryDate.year - 1} Annual License',
              dateStr: 'Approved on Oct 14, ${renewal.expiryDate.year - 1}',
              statusLabel: 'Approved',
              statusKind: BadgeKind.success,
              isCurrent: false,
            ),
            _historyItem(
              context,
              cycle: '${renewal.expiryDate.year - 2} Annual License',
              dateStr: 'Approved on Oct 08, ${renewal.expiryDate.year - 2}',
              statusLabel: 'Approved',
              statusKind: BadgeKind.success,
              isCurrent: false,
            ),
            _historyItem(
              context,
              cycle: 'Initial Stall Grant',
              dateStr: 'Verified on Oct 12, 2023',
              statusLabel: 'Verified',
              statusKind: BadgeKind.neutral,
              isCurrent: false,
              isLast: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _historyItem(
    BuildContext context, {
    required String cycle,
    required String dateStr,
    required String statusLabel,
    required BadgeKind statusKind,
    required bool isCurrent,
    bool isLast = false,
  }) {
    final colors = semanticColors(context);
    final dotColor = isCurrent
        ? const Color(0xFF3B82F6)
        : statusKind == BadgeKind.success
            ? const Color(0xFF10B981)
            : colors.mutedText;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 3),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            if (!isLast)
              Container(
                width: 1.5,
                height: 26,
                color: colors.subtleBorder,
              ),
          ],
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      cycle,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight:
                            isCurrent ? FontWeight.w800 : FontWeight.w600,
                        color: colors.primaryText,
                      ),
                    ),
                    StatusBadge(label: statusLabel, kind: statusKind),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  dateStr,
                  style: GoogleFonts.inter(
                    fontSize: 8.5,
                    color: colors.mutedText,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _item(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 8.5)),
            const SizedBox(height: 3),
            Text(
              value,
              style:
                  const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );

  Future<void> _moreDocs() async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) => const _PromptInputDialogWidget(
        title: 'Request Additional Documents',
        hintText:
            'e.g. Please upload a clear Mayor\'s Permit and valid Sanitary Clearance...',
        confirmLabel: 'Send Request',
        minLines: 2,
        maxLines: 4,
        defaultOnEmpty: 'Additional documents required',
      ),
    );
    if (value == null || !mounted) return;
    setState(() => processing = true);
    if (widget.application != null) {
      await ref.read(appDataProvider.notifier).updateApplication(
            widget.id,
            ApplicationStatus.invalidDocs,
            rejectionReason: value,
          );
    }
    if (widget.renewal != null) {
      await ref
          .read(appDataProvider.notifier)
          .updateRenewal(widget.id, RenewalStatus.reviewing);
    }
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Additional documents requested from ${widget.applicant}.',
          ),
        ),
      );
    }
  }
}

class _PromptInputDialogWidget extends StatefulWidget {
  const _PromptInputDialogWidget({
    required this.title,
    this.hintText,
    required this.confirmLabel,
    this.maxLines = 1,
    this.minLines = 1,
    this.defaultOnEmpty = '',
  });

  final String title;
  final String? hintText;
  final String confirmLabel;
  final int maxLines;
  final int minLines;
  final String defaultOnEmpty;

  @override
  State<_PromptInputDialogWidget> createState() =>
      _PromptInputDialogWidgetState();
}

class _PromptInputDialogWidgetState extends State<_PromptInputDialogWidget> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        autofocus: true,
        decoration: InputDecoration(hintText: widget.hintText),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final text = _controller.text.trim();
            if (text.isEmpty && widget.defaultOnEmpty.isNotEmpty) {
              Navigator.pop(context, widget.defaultOnEmpty);
            } else {
              Navigator.pop(context, text);
            }
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
