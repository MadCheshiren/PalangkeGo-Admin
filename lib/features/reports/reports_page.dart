import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/theme_controller.dart';
import '../../core/utils/export/admin_export_service.dart';
import '../../core/utils/export/module_export_data_builders.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/admin_shell.dart';
import '../../core/widgets/admin_widgets.dart';
import '../../data/repositories/mock_repository.dart';
import '../../models/app_models.dart';

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});
  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  static const _viewedReportsPreference = 'reports_viewed_new_badges';
  final search = TextEditingController();
  final tableScrollController = ScrollController();
  String status = 'All Statuses';
  String stallCategory = 'All Categories';
  String targetType = 'All Types';
  bool history = false;
  int page = 0;
  late Set<String> _viewedReportIds;

  @override
  void initState() {
    super.initState();
    _viewedReportIds = ref
            .read(sharedPreferencesProvider)
            .getStringList(_viewedReportsPreference)
            ?.toSet() ??
        <String>{};
  }

  void _markReportViewed(String id) {
    if (!_viewedReportIds.add(id)) return;
    setState(() {});
    ref.read(sharedPreferencesProvider).setStringList(
          _viewedReportsPreference,
          _viewedReportIds.toList(),
        );
  }

  String? _newestReportId(List<Report> values) {
    final pending = values
        .where((item) => item.status == ReportStatus.pending)
        .toList();
    if (pending.isEmpty) {
      final active = values
          .where((item) => item.status != ReportStatus.resolved)
          .toList();
      if (active.isEmpty) return null;
      var newest = active.first;
      for (final item in active.skip(1)) {
        if (item.date.isAfter(newest.date)) newest = item;
      }
      return newest.id;
    }
    var newest = pending.first;
    for (final item in pending.skip(1)) {
      if (item.date.isAfter(newest.date)) newest = item;
    }
    return newest.id;
  }

  bool _isStallHolderReport(Report item) =>
      item.type == 'Stall Holder' || item.type == 'Vendor';

  bool _isCustomerReport(Report item) => item.type == 'Customer';

  @override
  void dispose() {
    search.dispose();
    tableScrollController.dispose();
    super.dispose();
  }

  void _resetTable() {
    setState(() => page = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && tableScrollController.hasClients) {
        tableScrollController.jumpTo(0);
      }
    });
  }

  void _goToPage(int value) {
    setState(() => page = value);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && tableScrollController.hasClients) {
        tableScrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final appData = ref.watch(
      appDataProvider.select(
        (s) => (reports: s.reports, vendors: s.vendors, customers: s.customers),
      ),
    );
    final reports = appData.reports;
    final selectedCategory = stallCategory;
    final categories = <String>{
      'All Categories',
      ...reports.map((item) => item.category ?? 'FRESH FISH'),
    }.toList()
      ..sort();
    categories
      ..remove('All Categories')
      ..insert(0, 'All Categories');
    final values = reports
        .where(
          (item) =>
              (history
                  ? item.status == ReportStatus.resolved
                  : item.status != ReportStatus.resolved) &&
              (targetType == 'All Types' ||
                  (targetType == 'Stall Holders' && _isStallHolderReport(item)) ||
                  (targetType == 'Customers' && _isCustomerReport(item))) &&
              (search.text.trim().isEmpty ||
                  '${item.id} ${item.accountIssue} ${item.submittedBy} ${item.reason}'
                      .toLowerCase()
                      .contains(search.text.trim().toLowerCase())) &&
              (status == 'All Statuses' || enumLabel(item.status) == status) &&
              (selectedCategory == 'All Categories' ||
                  (item.category ?? 'FRESH FISH') == selectedCategory),
        )
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final now = DateTime.now();
    final todayReports = reports.where(
      (item) =>
          item.status != ReportStatus.resolved &&
          item.date.year == now.year &&
          item.date.month == now.month &&
          item.date.day == now.day,
    );
    final todayPending = todayReports.where(
      (item) => item.status == ReportStatus.pending,
    );
    final Set<String> newReportIds;
    if (todayPending.isNotEmpty) {
      newReportIds = todayPending
          .map((item) => item.id)
          .where((id) => !_viewedReportIds.contains(id))
          .toSet();
    } else if (todayReports.isNotEmpty) {
      newReportIds = todayReports
          .map((item) => item.id)
          .where((id) => !_viewedReportIds.contains(id))
          .toSet();
    } else {
      final newestId = _newestReportId(reports);
      newReportIds = newestId != null && !_viewedReportIds.contains(newestId)
          ? {newestId}
          : <String>{};
    }
    final int totalPages = (values.length / 10).ceil();
    final int safePage = totalPages == 0 ? 0 : page.clamp(0, totalPages - 1);

    final filteredForMetrics = targetType == 'All Types'
        ? reports
        : targetType == 'Stall Holders'
            ? reports.where(_isStallHolderReport).toList()
            : reports.where(_isCustomerReport).toList();

    final suspendedCount = targetType == 'All Types'
        ? appData.vendors.where((item) => item.status == AccountStatus.suspended).length +
            appData.customers.where((item) => item.status == AccountStatus.suspended).length
        : targetType == 'Stall Holders'
            ? appData.vendors.where((item) => item.status == AccountStatus.suspended).length
            : appData.customers.where((item) => item.status == AccountStatus.suspended).length;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        PageHeader(
          title: 'Reports Management',
          subtitle:
              'Review and manage customer reports, stall holder violations, and application support requests submitted from the PalengkeGo mobile application.',
          tabs: _ReportTabs(
            selected: targetType,
            onChanged: (value) {
              setState(() => targetType = value);
              _resetTable();
            },
          ),
          metrics: [
            MetricCardData(
              value:
                  '${filteredForMetrics.where((item) => item.status == ReportStatus.pending).length}',
              label: 'Pending Reports',
              icon: Icons.folder_copy_outlined,
              accent: const Color(0xFFEF4444),
              onTap: () {
                setState(() {
                  status = 'Pending';
                  history = false;
                });
                _resetTable();
              },
            ),
            MetricCardData(
              value:
                  '${filteredForMetrics.where((item) => item.status == ReportStatus.underReview).length}',
              label: 'Under Review',
              icon: Icons.visibility_outlined,
              accent: const Color(0xFF3B82F6),
              onTap: () {
                setState(() {
                  status = 'Under Review';
                  history = false;
                });
                _resetTable();
              },
            ),
            MetricCardData(
              value:
                  '${filteredForMetrics.where((item) => item.status == ReportStatus.resolved).length}',
              label: 'Resolved',
              icon: Icons.check_circle_outline_rounded,
              accent: const Color(0xFF10B981),
              onTap: () {
                setState(() {
                  status = 'Resolved';
                  history = true;
                });
                _resetTable();
              },
            ),
            MetricCardData(
              value: '$suspendedCount',
              label: targetType == 'Stall Holders'
                  ? 'Suspended Stall Holders'
                  : targetType == 'Customers'
                      ? 'Suspended Customers'
                      : 'Suspended Accounts',
              icon: Icons.pause_circle_outline_rounded,
              accent: const Color(0xFFF59E0B),
              onTap: () => context.go('/accounts'),
            ),
          ],
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            Responsive.horizontalPadding(context),
            26,
            Responsive.horizontalPadding(context),
            36,
          ),
          child: DataPanel(
            title: history ? 'Resolved Report History' : 'Review Reports',
            headerAction: _ReportViewToggle(
              history: history,
              reviewCount: filteredForMetrics
                  .where((item) => item.status != ReportStatus.resolved)
                  .length,
              resolvedCount: filteredForMetrics
                  .where((item) => item.status == ReportStatus.resolved)
                  .length,
              onChanged: (value) {
                setState(() {
                  history = value;
                  status = 'All Statuses';
                });
                _resetTable();
              },
            ),
            child: Column(
              children: [
                Toolbar(
                  controller: search,
                  onChanged: (_) => _resetTable(),
                  onClear: () {
                    search.clear();
                    status = 'All Statuses';
                    stallCategory = 'All Categories';
                    targetType = 'All Types';
                    history = false;
                    _resetTable();
                  },
                  trailing: [
                    _filter(
                      targetType == 'All Types' ? 'Account Type' : targetType,
                      const [
                        'All Types',
                        'Stall Holders',
                        'Customers',
                      ],
                      (value) {
                        setState(() => targetType = value);
                        _resetTable();
                      },
                    ),
                    _filter(status, [
                      'All Statuses',
                      'Pending',
                      'Under Review',
                      'Resolved',
                    ], (value) {
                      status = value;
                      if (value == 'Resolved') history = true;
                      if (value != 'Resolved') history = false;
                      _resetTable();
                    }),
                    _filter(
                        selectedCategory == 'All Categories'
                            ? 'Stall Category'
                            : selectedCategory,
                        categories, (value) {
                      stallCategory = value;
                      _resetTable();
                    }),
                    ExportButton(
                      onExportPdf: () => _exportComplaints(
                        allReports: reports,
                        filteredReports: values,
                        format: ExportFormat.pdf,
                      ),
                      onExportExcel: () => _exportComplaints(
                        allReports: reports,
                        filteredReports: values,
                        format: ExportFormat.excel,
                      ),
                    ),
                  ],
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeInOut,
                  switchOutCurve: Curves.easeInOut,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SizeTransition(
                      sizeFactor: animation,
                      child: child,
                    ),
                  ),
                  child: _ReportTable(
                    key: ValueKey(
                      '$history-$targetType-${values.map((item) => item.id).join(',')}',
                    ),
                    history: history,
                    values: values.skip(safePage * 10).take(10).toList(),
                    newReportIds: newReportIds,
                    verticalController: tableScrollController,
                    onOpen: (item) {
                      _markReportViewed(item.id);
                      showBlurredDialog(
                        context,
                        (context) => ReportReviewDialog(report: item),
                      );
                    },
                  ),
                ),
                if (values.isNotEmpty)
                  PaginationBar(
                    total: values.length,
                    start: safePage * 10 + 1,
                    end: ((safePage + 1) * 10).clamp(0, values.length),
                    page: safePage,
                    pageCount: totalPages,
                    onPageChanged: _goToPage,
                    showSummary: search.text.trim().isNotEmpty,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _filter(
    String label,
    List<String> values,
    ValueChanged<String> onChanged,
  ) =>
      FilterMenuButton(
        label: label,
        values: values,
        onSelected: onChanged,
      );

  Future<void> _exportComplaints({
    required List<Report> allReports,
    required List<Report> filteredReports,
    required ExportFormat format,
  }) async {
    final filterLabels = <String>[];
    if (search.text.trim().isNotEmpty) {
      filterLabels.add('Search: "${search.text.trim()}"');
    }
    filterLabels.add(targetType);
    filterLabels.add(status);
    if (stallCategory != 'All Categories') filterLabels.add(stallCategory);

    final doc = ComplaintExportData.build(
      allReports: allReports,
      filteredReports: filteredReports,
      activeFilters: filterLabels.join(' | '),
    );

    await AdminExportService.export(
      context: context,
      ref: ref,
      doc: doc,
      format: format,
    );
  }
}

class _ReportTable extends StatelessWidget {
  const _ReportTable({
    super.key,
    required this.history,
    required this.values,
    required this.newReportIds,
    required this.verticalController,
    required this.onOpen,
  });
  final bool history;
  final List<Report> values;
  final Set<String> newReportIds;
  final ScrollController verticalController;
  final ValueChanged<Report> onOpen;
  @override
  Widget build(BuildContext context) {
    final colors = semanticColors(context);
    final rows = values
        .map(
          (item) {
            return DataRow(
              onSelectChanged: (_) => onOpen(item),
              cells: history
                  ? [
                      DataCell(Text(item.type == 'Vendor' ? 'Stall Holder' : item.type)),
                      DataCell(Text(item.id)),
                      DataCell(
                        Text(
                          item.accountIssue,
                          style: TextStyle(
                            color: colors.accent,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      DataCell(Text(item.reason)),
                      DataCell(
                        StatusBadge(
                          label: item.decision ?? 'Resolved',
                          kind: item.decision == 'No Violation'
                              ? BadgeKind.neutral
                              : item.decision == 'Account Blocked'
                                  ? BadgeKind.danger
                                  : BadgeKind.warning,
                        ),
                      ),
                      DataCell(Text(item.actionTaken ?? 'Resolved')),
                      DataCell(
                        Text(
                          item.resolvedAt == null
                              ? '—'
                              : longDate.format(item.resolvedAt!),
                        ),
                      ),
                      DataCell(Text(item.resolvedBy ?? 'Administrator')),
                    ]
                  : [
                      DataCell(
                        Text(
                          item.type == 'Vendor' ? 'Stall Holder' : item.type,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DataCell(
                        Text(
                          item.id,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: colors.secondaryText,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          item.accountIssue,
                          style: TextStyle(
                            color: colors.accent,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      DataCell(Text(item.submittedBy)),
                      DataCell(Text(item.reason)),
                      DataCell(
                        CategoryBadge(
                          category: item.category ?? 'FRESH FISH',
                        ),
                      ),
                      DataCell(
                        Text(
                          '${item.date.month.toString().padLeft(2, '0')}/${item.date.day.toString().padLeft(2, '0')}/${item.date.year}',
                        ),
                      ),
                      DataCell(
                        StatusBadge(
                          label: enumLabel(item.status),
                          kind: item.status == ReportStatus.resolved
                              ? BadgeKind.success
                              : item.status == ReportStatus.underReview
                                  ? BadgeKind.info
                                  : BadgeKind.danger,
                        ),
                      ),
                      DataCell(
                        StatusBadge(
                          label: enumLabel(item.priority).toUpperCase(),
                          kind: item.priority == Priority.high
                              ? BadgeKind.danger
                              : item.priority == Priority.medium
                                  ? BadgeKind.warning
                                  : BadgeKind.neutral,
                        ),
                      ),
                    ],
            );
          },
        )
        .toList();
    return ScrollableDataTable(
      verticalController: verticalController,
      minWidth: history ? 1550 : 1550,
      columnSpacing: 18,
      columns: history
          ? const [
              DataColumn(
                columnWidth: FlexColumnWidth(1.15),
                label: Text('TYPE'),
              ),
              DataColumn(
                columnWidth: FlexColumnWidth(1.15),
                label: Text('REPORT ID'),
              ),
              DataColumn(
                columnWidth: FlexColumnWidth(1.4),
                label: Text('REPORTED USER'),
              ),
              DataColumn(
                columnWidth: FlexColumnWidth(1.3),
                label: Text('REASON'),
              ),
              DataColumn(
                columnWidth: FlexColumnWidth(1.3),
                label: Text('DECISION'),
              ),
              DataColumn(
                columnWidth: FlexColumnWidth(1.3),
                label: Text('ACTION TAKEN'),
              ),
              DataColumn(
                columnWidth: FlexColumnWidth(1.4),
                label: Text('RESOLVED DATE'),
              ),
              DataColumn(
                columnWidth: FlexColumnWidth(1.2),
                label: Text('RESOLVED BY'),
              ),
            ]
          : const [
              DataColumn(
                columnWidth: FlexColumnWidth(1.15),
                label: Text('TYPE'),
              ),
              DataColumn(
                columnWidth: FlexColumnWidth(1.1),
                label: Text('REPORT ID'),
              ),
              DataColumn(
                columnWidth: FlexColumnWidth(1.5),
                label: Text('ACCOUNT / ISSUE'),
              ),
              DataColumn(
                columnWidth: FlexColumnWidth(1.3),
                label: Text('SUBMITTED BY'),
              ),
              DataColumn(
                columnWidth: FlexColumnWidth(1.4),
                label: Text('REASON'),
              ),
              DataColumn(
                columnWidth: FlexColumnWidth(1.1),
                label: Text('CATEGORY'),
              ),
              DataColumn(
                columnWidth: FlexColumnWidth(1.0),
                label: Text('DATE'),
              ),
              DataColumn(
                columnWidth: FlexColumnWidth(1.1),
                label: Text('STATUS'),
              ),
              DataColumn(
                columnWidth: FlexColumnWidth(1.1),
                label: Text('PRIORITY'),
              ),
            ],
      rows: rows,
    );
  }
}

class _ReportViewToggle extends StatelessWidget {
  const _ReportViewToggle({
    required this.history,
    required this.reviewCount,
    required this.resolvedCount,
    required this.onChanged,
  });

  final bool history;
  final int reviewCount;
  final int resolvedCount;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = semanticColors(context);
    return SegmentedButton<bool>(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const Color(0xFFD1FAE5);
          }
          if (states.contains(WidgetState.hovered)) {
            return colors.hoverSurface;
          }
          return colors.cardBackground;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const Color(0xFF065F46);
          }
          return colors.secondaryText;
        }),
        textStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          );
        }),
        iconColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const Color(0xFF065F46);
          }
          return colors.secondaryText;
        }),
        side: WidgetStatePropertyAll(
          BorderSide(color: colors.subtleBorder),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        ),
        elevation: const WidgetStatePropertyAll(0),
        mouseCursor: const WidgetStatePropertyAll(SystemMouseCursors.click),
      ),
      segments: [
        ButtonSegment<bool>(
          value: false,
          label: Text('Review ($reviewCount)'),
          icon: const Icon(Icons.inbox_outlined, size: 15),
        ),
        ButtonSegment<bool>(
          value: true,
          label: Text('Resolved ($resolvedCount)'),
          icon: const Icon(Icons.history_rounded, size: 15),
        ),
      ],
      selected: {history},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

class _ReportTabs extends StatelessWidget {
  const _ReportTabs({required this.selected, required this.onChanged});
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _tab(context, 'All Complaints', selected == 'All Types'),
            const SizedBox(width: 8),
            _tab(context, 'Stall Holders', selected == 'Stall Holders'),
            const SizedBox(width: 8),
            _tab(context, 'Customers', selected == 'Customers'),
          ],
        ),
      );

  Widget _tab(BuildContext context, String label, bool active) => Material(
        color: active
            ? semanticColors(context).activeNavigation
            : Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: () {
            if (label == 'All Complaints') {
              onChanged('All Types');
            } else {
              onChanged(label);
            }
          },
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Text(
              label,
              style: TextStyle(
                color: active
                    ? semanticColors(context).heroBackground
                    : semanticColors(context).heroMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
}

class _ReportedAccount {
  const _ReportedAccount({
    required this.id,
    required this.name,
    required this.type,
    required this.status,
  });

  final String id;
  final String name;
  final String type;
  final AccountStatus status;
}

class ReportReviewDialog extends ConsumerStatefulWidget {
  const ReportReviewDialog({super.key, required this.report});
  final Report report;
  @override
  ConsumerState<ReportReviewDialog> createState() => _ReportReviewDialogState();
}

class _ReportReviewDialogState extends ConsumerState<ReportReviewDialog> {
  late final notes = TextEditingController(text: widget.report.notes);
  bool processing = false;
  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  _ReportedAccount? _reportedAccount(AppDataState data) {
    final issue = widget.report.accountIssue.trim().toLowerCase();
    final vendorName = widget.report.vendorName.trim().toLowerCase();

    if (widget.report.type == 'Vendor' || widget.report.type == 'Stall Holder') {
      for (final vendor in data.vendors) {
        final name = vendor.name.trim().toLowerCase();
        if (name == issue || name == vendorName) {
          return _ReportedAccount(
            id: vendor.id,
            name: vendor.name,
            type: 'Stall Holder',
            status: vendor.status,
          );
        }
      }
    }
    if (widget.report.type == 'Customer') {
      for (final customer in data.customers) {
        if (customer.name.trim().toLowerCase() == issue) {
          return _ReportedAccount(
            id: customer.id,
            name: customer.name,
            type: 'Customer',
            status: customer.status,
          );
        }
      }
      for (final vendor in data.vendors) {
        if (vendor.name.trim().toLowerCase() == vendorName) {
          return _ReportedAccount(
            id: vendor.id,
            name: vendor.name,
            type: 'Stall Holder',
            status: vendor.status,
          );
        }
      }
    }
    return null;
  }

  String _reportedAccountTypeLabel() {
    final account = _reportedAccount(ref.watch(appDataProvider));
    if (account == null) {
      return (widget.report.type == 'Vendor' || widget.report.type == 'Stall Holder')
          ? 'STALL HOLDER'
          : widget.report.type.toUpperCase();
    }
    return (account.type.contains('Stall Holder') || account.type.startsWith('Vendor'))
        ? 'STALL HOLDER'
        : 'CUSTOMER';
  }

  String _reportedAccountName() {
    final account = _reportedAccount(ref.watch(appDataProvider));
    if (account != null && account.name.isNotEmpty) return account.name;
    return widget.report.type == 'Customer'
        ? widget.report.accountIssue
        : widget.report.vendorName;
  }

  String _reportedAccountSubtitle() {
    final account = _reportedAccount(ref.watch(appDataProvider));
    final isCustomer = widget.report.type == 'Customer' || account?.type == 'Customer';
    return isCustomer
        ? 'Customer Account'
        : 'Stall Holder: ${widget.report.owner.isNotEmpty ? widget.report.owner : widget.report.vendorName}';
  }

  Future<void> _resolveReport(bool markResolved) async {
    if (processing) return;
    final title =
        markResolved ? 'Resolve Report' : 'Dismiss Report Without Action';
    final confirmation = markResolved
        ? 'Are you sure you want to mark this report as resolved?'
        : 'This will dismiss the report without changing the account status.';
    final noteResult = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _ResolveReportDialog(
        title: title,
        reportId: widget.report.id,
        accountIssue: widget.report.accountIssue,
        confirmation: confirmation,
        markResolved: markResolved,
      ),
    );
    if (noteResult == null || !mounted) return;
    setState(() => processing = true);
    final error = markResolved
        ? await ref.read(appDataProvider.notifier).resolveReport(
              reportId: widget.report.id,
              note: noteResult,
            )
        : await ref.read(appDataProvider.notifier).dismissReport(
              reportId: widget.report.id,
              note: noteResult,
            );
    if (!mounted) return;
    if (error != null) {
      setState(() => processing = false);
      _showError(error);
      return;
    }
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          markResolved
              ? 'Report resolved successfully. Moved to Resolved Reports.'
              : 'Report dismissed successfully. Moved to Resolved Reports.',
        ),
      ),
    );
  }


  Future<void> _suspendAccount(_ReportedAccount? account) async {
    if (account == null || processing) return;
    final result = await showDialog<_ReportSuspensionData>(
      context: context,
      builder: (dialogContext) => _ReportSuspendAccountDialog(
        accountName: account.name,
        accountType: account.type,
        reportId: widget.report.id,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => processing = true);
    final error =
        await ref.read(appDataProvider.notifier).suspendAccountFromReport(
              reportId: widget.report.id,
              reason: result.reason,
              startDate: result.startDate,
              endDate: result.endDate,
            );
    if (!mounted) return;
    if (error != null) {
      setState(() => processing = false);
      _showError(error);
      return;
    }
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content:
            Text('Account suspended successfully. Report moved to Resolved.'),
      ),
    );
    if (mounted) {
      context.go(
        '/accounts?accountId=${Uri.encodeComponent(account.id)}&open=1',
      );
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> action(String title, ReportStatus value) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _ReportActionInputDialog(title: title),
    );
    if (result == null || result.isEmpty || !mounted) return;
    setState(() => processing = true);
    await ref
        .read(appDataProvider.notifier)
        .updateReport(widget.report.id, value, result);
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$title completed.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final resolved = widget.report.status == ReportStatus.resolved;
    final account = _reportedAccount(ref.watch(appDataProvider));
    final screenHeight = MediaQuery.sizeOf(context).height;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: MediaQuery.sizeOf(context).width < 500 ? 12 : 24,
        vertical: 20,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 780,
          maxHeight: screenHeight * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context),
            const Divider(height: 1),
            Expanded(
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _info(context),
                      const SizedBox(height: 16),
                      Text(
                        'REASON: ${widget.report.reason.toUpperCase()}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: semanticColors(context)
                              .infoContainer
                              .withValues(alpha: .6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          widget.report.description,
                          style: const TextStyle(fontSize: 11, height: 1.45),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'EVIDENCE ATTACHED (2 IMAGES)',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          _evidence(
                            'assets/images/spoiled_produce.png',
                            'Spoiled produce',
                          ),
                          const SizedBox(width: 10),
                          _evidence(
                            'assets/images/mobile_conversation.png',
                            'Mobile conversation',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'ACCOUNT HISTORY HIGHLIGHTS',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _history(context),
                      const SizedBox(height: 16),
                      const Text(
                        'INVESTIGATION FINDINGS & NOTES',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 7),
                      TextField(
                        controller: notes,
                        minLines: 3,
                        maxLines: 5,
                        readOnly: resolved,
                        decoration: const InputDecoration(
                          hintText: 'Add investigation findings...',
                        ),
                      ),
                      if (widget.report.decision != null) ...[
                        const SizedBox(height: 14),
                        _decisionSummary(context),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (!resolved) ...[
              const Divider(height: 1),
              _footer(context, account),
            ] else ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: semanticColors(context).heroBackground,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final cleanId = widget.report.id.startsWith('#')
        ? widget.report.id
        : '#${widget.report.id}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 14, 16),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Text(
                  'Report Review: $cleanId',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(width: 9),
                StatusBadge(
                  label: enumLabel(widget.report.status),
                  kind: widget.report.status == ReportStatus.resolved
                      ? BadgeKind.success
                      : widget.report.status == ReportStatus.underReview
                          ? BadgeKind.info
                          : BadgeKind.danger,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context, _ReportedAccount? account) {
    final outlineStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
    );
    final warningStyle = outlineStyle.copyWith(
      foregroundColor: WidgetStatePropertyAll(
        semanticColors(context).warning,
      ),
      side: WidgetStatePropertyAll(
        BorderSide(color: semanticColors(context).warning),
      ),
    );
    final resolvedStyle = FilledButton.styleFrom(
      backgroundColor: semanticColors(context).heroBackground,
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
    );
    final suspendStyle = FilledButton.styleFrom(
      backgroundColor: semanticColors(context).danger,
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
    );

    final warningBtn = OutlinedButton.icon(
      onPressed: processing
          ? null
          : () => action(
                'Send warning',
                ReportStatus.underReview,
              ),
      style: warningStyle,
      icon: const Icon(Icons.warning_amber_outlined, size: 16),
      label: const Text('Send Warning', style: TextStyle(fontSize: 11.5)),
    );

    final dismissBtn = OutlinedButton(
      onPressed: processing ? null : () => _resolveReport(false),
      style: outlineStyle,
      child: const Text('Dismiss Report', style: TextStyle(fontSize: 11.5)),
    );

    final resolveBtn = FilledButton.icon(
      onPressed: processing
          ? null
          : () => _resolveReport(true),
      style: resolvedStyle,
      icon: const Icon(Icons.check_circle_outline, size: 16),
      label: const Text('Mark as Resolved', style: TextStyle(fontSize: 11.5)),
    );

    final suspendBtn = FilledButton.icon(
      onPressed: processing ||
              account == null ||
              account.status == AccountStatus.blocked ||
              account.status == AccountStatus.suspended
          ? null
          : () => _suspendAccount(account),
      style: suspendStyle,
      icon: const Icon(Icons.pause_circle_outline, size: 16),
      label: const Text('Suspend Account', style: TextStyle(fontSize: 11.5)),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).dialogTheme.backgroundColor ??
            Theme.of(context).cardColor,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 600) {
            return Row(
              children: [
                Expanded(child: warningBtn),
                const SizedBox(width: 8),
                Expanded(child: dismissBtn),
                const SizedBox(width: 8),
                Expanded(child: resolveBtn),
                const SizedBox(width: 8),
                Expanded(child: suspendBtn),
              ],
            );
          } else if (constraints.maxWidth > 420) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(child: warningBtn),
                    const SizedBox(width: 8),
                    Expanded(child: dismissBtn),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: resolveBtn),
                    const SizedBox(width: 8),
                    Expanded(child: suspendBtn),
                  ],
                ),
              ],
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              warningBtn,
              const SizedBox(height: 8),
              dismissBtn,
              const SizedBox(height: 8),
              resolveBtn,
              const SizedBox(height: 8),
              suspendBtn,
            ],
          );
        },
      ),
    );
  }

  Widget _decisionSummary(BuildContext context) {
    final isDismissed = widget.report.decision == 'No Violation';
    final color = isDismissed
        ? semanticColors(context).mutedText
        : widget.report.decision == 'Account Blocked'
            ? semanticColors(context).danger
            : semanticColors(context).warning;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FINAL DECISION',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(widget.report.decision ?? 'Resolved'),
          if (widget.report.actionTaken != null)
            Text('Action taken: ${widget.report.actionTaken}'),
          if (widget.report.resolutionNote != null &&
              widget.report.resolutionNote!.isNotEmpty)
            Text('Note: ${widget.report.resolutionNote}'),
          if (widget.report.resolvedBy != null)
            Text('Resolved by: ${widget.report.resolvedBy}'),
          if (widget.report.resolvedAt != null)
            Text('Resolved on: ${longDate.format(widget.report.resolvedAt!)}'),
        ],
      ),
    );
  }

  Widget _info(BuildContext context) {
    final account = _reportedAccount(ref.watch(appDataProvider));
    final isCustomer = widget.report.type == 'Customer' || account?.type == 'Customer';
    final reporterName = widget.report.submittedBy.trim().isNotEmpty
        ? widget.report.submittedBy
        : 'Unknown Reporter';
    final reportedName = _reportedAccountName();
    final reportedSubtitle = _reportedAccountSubtitle();
    final reportedDetail = isCustomer
        ? (account != null ? 'Customer ID: ${account.id}' : 'Customer Account')
        : 'Stall No: ${widget.report.stallNumber.isNotEmpty ? widget.report.stallNumber : '—'}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _infoHeading(context, 'REPORTER INFORMATION')),
            const SizedBox(width: 24),
            Expanded(
              child: _infoHeading(
                context,
                'REPORTED ACCOUNT (${_reportedAccountTypeLabel()})',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AvatarCircle(name: reporterName, size: 34),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          reporterName,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (widget.report.reporterEmail.isNotEmpty)
                          Text(
                            widget.report.reporterEmail,
                            style: const TextStyle(fontSize: 9),
                          ),
                        const SizedBox(height: 11),
                        if (widget.report.phone.isNotEmpty)
                          Row(
                            children: [
                              const Icon(Icons.phone_outlined, size: 15),
                              const SizedBox(width: 6),
                              Text(
                                widget.report.phone,
                                style: const TextStyle(fontSize: 10),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: semanticColors(context).infoContainer,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(
                      isCustomer
                          ? Icons.person_rounded
                          : Icons.storefront_outlined,
                      color: semanticColors(context).info,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          reportedName,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          reportedSubtitle,
                          style: const TextStyle(fontSize: 9),
                        ),
                        const SizedBox(height: 11),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    reportedDetail,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                  if (account != null) ...[
                                    const SizedBox(height: 3),
                                    InkWell(
                                      onTap: () {
                                        Navigator.pop(context);
                                        context.go(
                                          '/accounts?accountId=${Uri.encodeComponent(account.id)}&open=1',
                                        );
                                      },
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'View Account Profile',
                                            style: TextStyle(
                                              fontSize: 9.5,
                                              color: semanticColors(context).accent,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(width: 3),
                                          Icon(
                                            Icons.arrow_forward_rounded,
                                            size: 10,
                                            color: semanticColors(context).accent,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            StatusBadge(
                              label: widget.report.previousViolations > 0
                                  ? '${widget.report.previousViolations} PREVIOUS VIOLATION${widget.report.previousViolations == 1 ? '' : 'S'}'
                                  : 'NO PREVIOUS VIOLATIONS',
                              kind: widget.report.previousViolations > 0
                                  ? BadgeKind.danger
                                  : BadgeKind.neutral,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _infoHeading(BuildContext context, String label) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: .7,
            ),
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: Theme.of(context).dividerColor),
        ],
      );

  Widget _evidence(String asset, String label) => Expanded(
        child: InkWell(
          onTap: () => showDialog<void>(
            context: context,
            builder: (context) => Dialog(
              child: InteractiveViewer(
                child: Image.asset(
                  asset,
                  errorBuilder: (context, error, stackTrace) =>
                      _missingEvidence(context),
                ),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: 2.1,
                  child: Image.asset(
                    asset,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        _missingEvidence(context),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                style:
                    const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );

  Widget _missingEvidence(BuildContext context) {
    final colors = semanticColors(context);
    return Container(
      color: colors.inputSurface,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_not_supported_outlined, color: colors.mutedText),
          const SizedBox(height: 7),
          Text(
            'Evidence unavailable',
            style: TextStyle(
              color: colors.secondaryText,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'The attached image could not be loaded.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.mutedText, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _history(BuildContext context) {
    if (widget.report.previousViolations == 0) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: semanticColors(context).inputSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: semanticColors(context).subtleBorder),
        ),
        child: Center(
          child: Text(
            'No previous violations recorded for this account.',
            style: TextStyle(
              fontSize: 11,
              color: semanticColors(context).mutedText,
            ),
          ),
        ),
      );
    }

    final account = _reportedAccount(ref.watch(appDataProvider));
    final isCustomer = widget.report.type == 'Customer' || account?.type == 'Customer';

    final rows = <TableRow>[
      TableRow(
        decoration: BoxDecoration(
          color: semanticColors(context).inputSurface.withValues(alpha: .5),
        ),
        children: [
          _cell('Date', isHeader: true),
          _cell('Violation Type', isHeader: true),
          _cell('Action Taken', isHeader: true),
          _cell('Status', isHeader: true),
        ],
      ),
      TableRow(children: [
        _cell('Sep 15, 2023'),
        _cell(isCustomer ? 'Dispute with Stall Holder' : 'Late Delivery'),
        _cell('Warning Issued'),
        _cell('Closed'),
      ]),
    ];

    if (widget.report.previousViolations >= 2) {
      rows.add(
        TableRow(children: [
          _cell('Aug 02, 2023'),
          _cell(isCustomer ? 'Abusive Messaging' : 'Incorrect Pricing'),
          _cell('System Flag'),
          _cell('Closed'),
        ]),
      );
    }

    return Table(
      border: TableBorder.all(color: semanticColors(context).subtleBorder),
      children: rows,
    );
  }

  Widget _cell(String value, {bool isHeader = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(
          value,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: isHeader ? FontWeight.w800 : FontWeight.normal,
          ),
        ),
      );
}

class _ResolveReportDialog extends StatefulWidget {
  const _ResolveReportDialog({
    required this.title,
    required this.reportId,
    required this.accountIssue,
    required this.confirmation,
    required this.markResolved,
  });

  final String title;
  final String reportId;
  final String accountIssue;
  final String confirmation;
  final bool markResolved;

  @override
  State<_ResolveReportDialog> createState() => _ResolveReportDialogState();
}

class _ResolveReportDialogState extends State<_ResolveReportDialog> {
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Report: #${widget.reportId}'),
            const SizedBox(height: 7),
            Text('Reported User: ${widget.accountIssue}'),
            const SizedBox(height: 14),
            Text(widget.confirmation),
            const SizedBox(height: 14),
            TextField(
              controller: _noteController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Optional Resolution Note',
                hintText: 'Enter a note for the resolved report',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _noteController.text.trim()),
          child: Text(
            widget.markResolved ? 'Mark as Resolved' : 'Confirm Dismiss',
          ),
        ),
      ],
    );
  }
}


class _ReportSuspensionData {
  const _ReportSuspensionData({
    required this.reason,
    required this.startDate,
    required this.endDate,
  });

  final String reason;
  final DateTime startDate;
  final DateTime endDate;
}

class _ReportSuspendAccountDialog extends StatefulWidget {
  const _ReportSuspendAccountDialog({
    required this.accountName,
    required this.accountType,
    required this.reportId,
  });

  final String accountName;
  final String accountType;
  final String reportId;

  @override
  State<_ReportSuspendAccountDialog> createState() =>
      _ReportSuspendAccountDialogState();
}

class _ReportSuspendAccountDialogState
    extends State<_ReportSuspendAccountDialog> {
  late final TextEditingController _reasonController;
  late DateTime _startDate;
  late DateTime _endDate;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _reasonController = TextEditingController();
    _startDate = DateTime.now();
    _endDate = DateTime.now().add(const Duration(days: 7));
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool start) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: start ? _startDate : _endDate,
      firstDate: start ? DateUtils.dateOnly(_startDate) : _startDate,
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (selected == null) return;
    setState(() {
      if (start) {
        _startDate = selected;
        if (!_endDate.isAfter(_startDate)) {
          _endDate = _startDate.add(const Duration(days: 1));
        }
      } else {
        _endDate = selected;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Suspend Account?'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Reported User: ${widget.accountName}'),
              const SizedBox(height: 6),
              Text('Account Type: ${widget.accountType}'),
              const SizedBox(height: 6),
              Text('Related Report: #${widget.reportId}'),
              const SizedBox(height: 14),
              TextField(
                controller: _reasonController,
                minLines: 2,
                maxLines: 4,
                onChanged: (_) {
                  if (_validationError != null) {
                    setState(() => _validationError = null);
                  }
                },
                decoration: InputDecoration(
                  labelText: 'Suspension Reason *',
                  hintText: 'Enter the reason for temporary suspension',
                  errorText: _validationError,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickDate(true),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 12,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Starts', style: TextStyle(fontSize: 11)),
                          const SizedBox(height: 2),
                          Text(
                            shortDate.format(_startDate),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickDate(false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 12,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Ends', style: TextStyle(fontSize: 11)),
                          const SizedBox(height: 2),
                          Text(
                            shortDate.format(_endDate),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: semanticColors(context).danger,
          ),
          onPressed: () {
            final reason = _reasonController.text.trim();
            if (reason.isEmpty) {
              setState(
                () => _validationError = 'A suspension reason is required.',
              );
              return;
            }
            if (!_endDate.isAfter(_startDate)) {
              setState(
                () => _validationError =
                    'The end date must be after the start date.',
              );
              return;
            }
            Navigator.pop(
              context,
              _ReportSuspensionData(
                reason: reason,
                startDate: _startDate,
                endDate: _endDate,
              ),
            );
          },
          icon: const Icon(Icons.pause_circle_outline, size: 17),
          label: const Text('Suspend Account'),
        ),
      ],
    );
  }
}

class _ReportActionInputDialog extends StatefulWidget {
  const _ReportActionInputDialog({required this.title});
  final String title;

  @override
  State<_ReportActionInputDialog> createState() =>
      _ReportActionInputDialogState();
}

class _ReportActionInputDialogState extends State<_ReportActionInputDialog> {
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
        maxLines: 3,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Add a reason or message...',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
