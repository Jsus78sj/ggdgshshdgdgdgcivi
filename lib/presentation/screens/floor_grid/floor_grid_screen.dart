import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/design_mode.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../data/bs8110/flexure_tables.dart';
import '../../../domain/engine/engineering_engine.dart';
import '../../../domain/engine/grid_validator.dart';
import '../../painters/floor_plan_painter.dart';
import '../../providers/floor_grid_provider.dart';
import '../../providers/single_slab_provider.dart';

/// شاشة محرر المخطط الشبكي الكامل للسقف (Full Floor Grid Editor — المرحلة 5)
class FloorGridScreen extends ConsumerWidget {
  const FloorGridScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editorState = ref.watch(floorGridEditorProvider);
    final notifier = ref.read(floorGridEditorProvider.notifier);
    final activeMode = ref.watch(designModeProvider);
    final theme = Theme.of(context);

    final plan = editorState.plan;
    final selectedCell = editorState.selectedCell;
    final selectedTopo = editorState.selectedTopology;
    final validation = editorState.validation;

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: () => _showRenameDialog(context, plan.projectName, notifier),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      plan.projectName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (editorState.hasUnsavedChanges) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.accentAmber,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                '${plan.colsCount}×${plan.rowsCount} محاور • ${plan.designableSlabsCount} بلاطة • ${activeMode.shortLabelAr}',
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'حاسبة الرقم السحري (S_No.)',
            icon: const Icon(Icons.auto_awesome_rounded),
            onPressed: () => _showMagicNumberDialog(context, notifier),
          ),
          IconButton(
            tooltip: 'جدول تسليح السقف كاملاً',
            icon: const Icon(Icons.table_rows_rounded),
            onPressed: () =>
                _showFullBuildingScheduleSheet(context, ref, activeMode),
          ),
          IconButton(
            tooltip: 'إعدادات المشروع (n, h, c, Ø, fcu, fy)',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => _showProjectSettingsSheet(context, plan, notifier),
          ),
          IconButton(
            tooltip: 'حفظ المشروع محلياً',
            icon: const Icon(Icons.save_rounded),
            onPressed: () async {
              await notifier.saveCurrentPlan();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('تم حفظ المشروع "${plan.projectName}" محلياً.'),
                    backgroundColor: AppColors.safeGreen,
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. شريط أدوات الشبكة والمحاور السريع
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.undo_rounded, size: 17),
                    label: const Text('تراجع'),
                    onPressed: editorState.canUndo ? notifier.undo : null,
                  ),
                  const SizedBox(width: 6),
                  ActionChip(
                    avatar: const Icon(Icons.redo_rounded, size: 17),
                    label: const Text('إعادة'),
                    onPressed: editorState.canRedo ? notifier.redo : null,
                  ),
                  const SizedBox(width: 6),
                  ActionChip(
                    avatar: Icon(
                      validation.hasErrors
                          ? Icons.error_rounded
                          : validation.isClean
                              ? Icons.verified_rounded
                              : Icons.warning_amber_rounded,
                      size: 17,
                      color: validation.hasErrors
                          ? AppColors.dangerRed
                          : validation.isClean
                              ? AppColors.safeGreen
                              : AppColors.accentAmber,
                    ),
                    label: Text(
                      validation.isClean
                          ? 'المخطط سليم'
                          : '${validation.errors.length} أخطاء • ${validation.warnings.length} تحذيرات',
                    ),
                    onPressed: () => _showValidationSheet(context, ref),
                  ),
                  const SizedBox(width: 6),
                  FilterChip(
                    avatar: Icon(
                      Icons.map_rounded,
                      size: 17,
                      color: editorState.hasDesignResults &&
                              editorState.showResultsMap
                          ? AppColors.safeGreen
                          : null,
                    ),
                    label: const Text('خريطة النتائج'),
                    selected: editorState.hasDesignResults &&
                        editorState.showResultsMap,
                    onSelected: (_) {
                      if (!editorState.hasDesignResults) {
                        if (validation.hasErrors) {
                          _showValidationSheet(context, ref);
                          return;
                        }
                        notifier.designAllSlabs(activeMode);
                      } else {
                        notifier.toggleResultsMap();
                      }
                    },
                  ),
                  const SizedBox(width: 6),
                  ActionChip(
                    avatar: const Icon(Icons.straighten_rounded, size: 17),
                    label: const Text('تعديل المحاور'),
                    onPressed: () => _showAxesEditorDialog(context),
                  ),
                  const SizedBox(width: 6),
                  ActionChip(
                    avatar: const Icon(Icons.add_box_outlined, size: 17),
                    label: const Text('+ عمود X'),
                    onPressed: plan.colsCount < FloorGridEditorNotifier.maxGridSize
                        ? () => notifier.addColumn()
                        : null,
                  ),
                  const SizedBox(width: 6),
                  ActionChip(
                    avatar: const Icon(Icons.add_box_outlined, size: 17),
                    label: const Text('+ صف Y'),
                    onPressed: plan.rowsCount < FloorGridEditorNotifier.maxGridSize
                        ? () => notifier.addRow()
                        : null,
                  ),
                  const SizedBox(width: 6),
                  FilterChip(
                    avatar: const Icon(Icons.checklist_rounded, size: 17),
                    label: Text(
                      editorState.isMultiSelectMode
                          ? 'تحديد متعدد (${editorState.selectedCells.length})'
                          : 'تحديد متعدد',
                    ),
                    selected: editorState.isMultiSelectMode,
                    onSelected: (_) => notifier.toggleMultiSelectMode(),
                  ),
                  const SizedBox(width: 6),
                  ActionChip(
                    avatar: const Icon(Icons.copy_rounded, size: 17),
                    label: const Text('نسخ خصائص'),
                    onPressed: selectedCell != null
                        ? () {
                            notifier.copyCellProperties(
                              selectedCell.row,
                              selectedCell.col,
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'تم نسخ خصائص الخانة (${selectedCell.id}).',
                                ),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        : null,
                  ),
                  if (editorState.copiedCell != null) ...[
                    const SizedBox(width: 6),
                    ActionChip(
                      avatar: const Icon(Icons.paste_rounded, size: 17),
                      label: Text('لصق (${editorState.copiedCell!.sourceId})'),
                      onPressed: () {
                        final targets = editorState.isMultiSelectMode
                            ? editorState.selectedCells
                            : {
                                if (selectedCell != null)
                                  (selectedCell.row, selectedCell.col),
                              };
                        final count = notifier.pasteCellPropertiesTo(targets);
                        if (count > 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'تم لصق الخصائص على $count خانة.',
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                  const SizedBox(width: 6),
                  ActionChip(
                    avatar: const Icon(Icons.format_list_numbered_rounded,
                        size: 17),
                    label: const Text('ترقيم تلقائي'),
                    onPressed: notifier.autoRenumberNormalSlabs,
                  ),
                  const SizedBox(width: 6),
                  ActionChip(
                    avatar: const Icon(Icons.quiz_rounded, size: 17),
                    label: const Text('قالب الاختبار'),
                    onPressed: notifier.loadUniversityExamTemplate,
                  ),
                  const SizedBox(width: 6),
                  ActionChip(
                    avatar: const Icon(Icons.note_add_outlined, size: 17),
                    label: const Text('مخطط جديد'),
                    onPressed: () => notifier.createNewBlankPlan(),
                  ),
                ],
              ),
            ),
          ),

          // 1.ب شريط تنبيه «النتيجة قديمة» عند تعديل المخطط أو تغيير وضع الحساب بعد آخر تصميم
          if (editorState.isResultsStaleForMode(activeMode))
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.warningAmber.withAlpha(28),
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.warningAmber.withAlpha(120),
                  ),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.history_rounded,
                    size: 18,
                    color: AppColors.warningAmber,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      editorState.areResultsStale
                          ? 'النتيجة قديمة — تم تعديل المخطط بعد آخر تصميم.'
                          : 'النتيجة قديمة — تغيّر وضع الحساب إلى ${activeMode.shortLabelAr}.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.warningAmber,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: AppColors.warningAmber,
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('تحديث النتائج'),
                    onPressed: () {
                      if (validation.hasErrors) {
                        _showValidationSheet(context, ref);
                        return;
                      }
                      notifier.designAllSlabs(activeMode);
                    },
                  ),
                ],
              ),
            ),

          // 1.ج شريط دليل ألوان خريطة النتائج عند تفعيلها
          if (editorState.hasDesignResults && editorState.showResultsMap)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(bottom: BorderSide(color: theme.dividerColor)),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _LegendDot(
                      color: AppColors.safeGreen,
                      label: 'آمن (${editorState.safeResultsCount})',
                    ),
                    const SizedBox(width: 12),
                    _LegendDot(
                      color: AppColors.dangerRed,
                      label: 'هطول/قص ✗ (${editorState.unsafeResultsCount})',
                    ),
                    if (editorState.warningResultsCount > 0) ...[
                      const SizedBox(width: 12),
                      _LegendDot(
                        color: AppColors.accentAmber,
                        label: 'تنبيه (${editorState.warningResultsCount})',
                      ),
                    ],
                  ],
                ),
              ),
            ),

          // 2. لوحة رسم المخطط التفاعلية (Pinch, Zoom & Tap)
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: FloorPlanCanvasWidget(
                    plan: plan,
                    selectedRow: editorState.selectedRow,
                    selectedCol: editorState.selectedCol,
                    selectedCells: editorState.selectedCells,
                    highlightedSlabId: editorState.highlightedSlabId,
                    resultsByCell: editorState.resultsByCell,
                    showResultsMap: editorState.showResultsMap,
                    currentPlanRevision: editorState.planRevision,
                    activeMode: activeMode,
                    onCellTapped: (row, col) {
                      if (editorState.isMultiSelectMode) {
                        notifier.toggleCellSelection(row, col);
                      } else {
                        notifier.selectCell(row, col);
                      }
                    },
                  ),
                ),
                // تلميح علوي صغير للتحكم
                Positioned(
                  top: 8,
                  right: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withAlpha(225),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Text(
                      editorState.isMultiSelectMode
                          ? 'وضع التحديد المتعدد: انقر على الخانات لتحديدها أو إلغائها'
                          : 'انقر على أي بلاطة لتحديدها • اسحب أو كبّر بإصبعين',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ),
                if (editorState.highlightedSlabId != null)
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: InputChip(
                      avatar: const Icon(
                        Icons.star_rounded,
                        color: AppColors.accentAmber,
                        size: 18,
                      ),
                      label: Text(
                        'الرقم السحري: ${editorState.highlightedSlabId}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onDeleted: notifier.clearHighlight,
                    ),
                  ),
              ],
            ),
          ),

          // 3. لوحة التعديل الجماعي أو لوحة خصائص الخانة المحددة
          if (editorState.isMultiSelectMode)
            _MultiSelectBulkPanel(
              selectedCount: editorState.selectedCells.length,
              copiedSourceId: editorState.copiedCell?.sourceId,
              onSelectAll: notifier.selectAllCells,
              onExitMultiSelect: notifier.clearMultiSelection,
              onQuickChangeType: (t) => notifier.bulkUpdateCells(
                targets: editorState.selectedCells,
                cellType: t,
              ),
              onPasteCopied: editorState.copiedCell != null &&
                      editorState.selectedCells.isNotEmpty
                  ? () {
                      final count = notifier
                          .pasteCellPropertiesTo(editorState.selectedCells);
                      if (count > 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('تم لصق الخصائص على $count خانة.'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    }
                  : null,
              onOpenBulkDialog: editorState.selectedCells.isNotEmpty
                  ? () => _showBulkEditDialog(
                        context,
                        editorState.selectedCells,
                        notifier,
                      )
                  : null,
            )
          else if (selectedCell != null)
            _SelectedCellInspectorPanel(
              plan: plan,
              cell: selectedCell,
              topology: selectedTopo,
              copiedSourceId: editorState.copiedCell?.sourceId,
              onChangeType: (t) => notifier.updateCellType(
                selectedCell.row,
                selectedCell.col,
                t,
              ),
              onEditDetails: () =>
                  _showCellDetailsDialog(context, plan, selectedCell, notifier),
              onCopyProperties: () {
                notifier.copyCellProperties(selectedCell.row, selectedCell.col);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('تم نسخ خصائص الخانة (${selectedCell.id}).'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              onPasteProperties: editorState.copiedCell != null
                  ? () {
                      notifier.pasteCellPropertiesTo(
                        {(selectedCell.row, selectedCell.col)},
                      );
                    }
                  : null,
              onPickEdgeOverride: (side) => _showEdgeOverridePicker(
                context,
                selectedCell,
                side,
                notifier,
              ),
              onToggleCantilever: (side) => notifier.toggleCantilever(
                row: selectedCell.row,
                col: selectedCell.col,
                side: side,
              ),
              cellResult: editorState.resultsByCell[(
                selectedCell.row,
                selectedCell.col,
              )],
              isCellResultStale: editorState.isCellResultStale(
                selectedCell.row,
                selectedCell.col,
                mode: activeMode,
              ),
              onDesignWithNeighborsPressed:
                  selectedCell.cellType.isDesignableSlab
                      ? () => _openInQuickMode(
                            context,
                            ref,
                            selectedCell.row,
                            selectedCell.col,
                          )
                      : null,
              onDesignPressed: selectedCell.cellType.isDesignableSlab
                  ? () => _openSlabDesignReport(
                        context,
                        ref,
                        selectedCell.row,
                        selectedCell.col,
                        activeMode,
                      )
                  : null,
            ),
        ],
      ),
    );
  }

  void _openInQuickMode(
    BuildContext context,
    WidgetRef ref,
    int row,
    int col,
  ) {
    final editorState = ref.read(floorGridEditorProvider);
    if (editorState.validation.hasErrors) {
      _showValidationSheet(context, ref);
      return;
    }
    try {
      ref.read(singleSlabFormProvider.notifier).loadFromFloorGridCell(
            plan: editorState.plan,
            row: row,
            col: col,
          );
      context.push(AppRoutes.singleSlab);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذّر نقل البلاطة إلى الوضع السريع: $e'),
          backgroundColor: AppColors.dangerRed,
        ),
      );
    }
  }

  void _openSlabDesignReport(
    BuildContext context,
    WidgetRef ref,
    int row,
    int col,
    DesignCalculationMode mode,
  ) {
    // لا نصمّم مخططاً فيه أخطاء بنيوية (معرّف مكرر، محور غير صالح ...): نعرض المشاكل أولاً
    if (ref.read(floorGridEditorProvider).validation.hasErrors) {
      _showValidationSheet(context, ref);
      return;
    }

    final notifier = ref.read(floorGridEditorProvider.notifier);
    final label = ref.read(floorGridEditorProvider).plan.cellAt(row, col)?.id ??
        '(${row + 1}،${col + 1})';
    try {
      final report = notifier.designCell(row, col, mode);
      ref.read(activeReportProvider.notifier).setReport(
            ActiveReportContext(
              report: report,
              sourceLabelAr:
                  'محرر المخطط الكامل (${ref.read(floorGridEditorProvider).plan.projectName})',
              recompute: (newMode, {bool autoAdjustDepth = false}) {
                return ref.read(floorGridEditorProvider.notifier).designCell(
                      row,
                      col,
                      newMode,
                      autoAdjustDepthInStrictMode: autoAdjustDepth,
                    );
              },
            ),
          );
      context.push(AppRoutes.slabReport);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذّر تصميم البلاطة $label: $e'),
          backgroundColor: AppColors.dangerRed,
        ),
      );
    }
  }

  /// قائمة مشاكل المخطط؛ النقر على مشكلة يحدّد خانتها على المخطط
  Future<void> _showValidationSheet(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(floorGridEditorProvider.notifier);
    final report = ref.read(floorGridEditorProvider).validation;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.9,
        builder: (ctx, scrollCtrl) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Text(
                report.isClean
                    ? 'فحص المخطط: لا توجد مشاكل'
                    : 'فحص المخطط (${report.errors.length} أخطاء • ${report.warnings.length} تحذيرات)',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            if (report.hasErrors)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'أصلح الأخطاء أولاً: التصميم متوقف حتى تزول.',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: AppColors.dangerRed,
                      ),
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: report.isClean
                  ? const Center(child: Text('المخطط سليم ✓'))
                  : ListView.separated(
                      controller: scrollCtrl,
                      itemCount: report.issues.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final issue = report.issues[i];
                        return ListTile(
                          leading: Icon(
                            issue.isError
                                ? Icons.error_rounded
                                : Icons.warning_amber_rounded,
                            color: issue.isError
                                ? AppColors.dangerRed
                                : AppColors.accentAmber,
                          ),
                          title: Text(issue.messageAr),
                          onTap: (issue.row != null && issue.col != null)
                              ? () {
                                  notifier.selectCell(issue.row!, issue.col!);
                                  Navigator.pop(ctx);
                                }
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    String currentName,
    FloorGridEditorNotifier notifier,
  ) async {
    final ctrl = TextEditingController(text: currentName);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل اسم المشروع'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'اسم المخطط'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (confirmed == true && ctrl.text.trim().isNotEmpty) {
      notifier.updateProjectName(ctrl.text.trim());
    }
    ctrl.dispose();
  }

  Future<void> _showMagicNumberDialog(
    BuildContext context,
    FloorGridEditorNotifier notifier,
  ) async {
    final d1Ctrl = TextEditingController(text: '4');
    final d2Ctrl = TextEditingController(text: '2');
    String preview = 'S7';

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          void recalc() {
            final d1 = int.tryParse(d1Ctrl.text.trim());
            final d2 = int.tryParse(d2Ctrl.text.trim());
            if (d1 != null &&
                d2 != null &&
                d1 >= 0 &&
                d1 <= 9 &&
                d2 >= 0 &&
                d2 <= 9) {
              setState(() => preview = FloorGridPlan.magicSlabId(d1, d2));
            } else {
              setState(() => preview = '—');
            }
          }

          return AlertDialog(
            title: const Text('حاسبة الرقم السحري (S_No.)'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'أدخل آخر رقمين من رقم القيد الجامعي لحساب بلاطة الاختبار وتظليلها تلقائياً:\nS_No. = 9 − |d₁ − d₂|',
                  style: TextStyle(fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: d1Ctrl,
                        keyboardType: TextInputType.number,
                        maxLength: 1,
                        decoration: const InputDecoration(
                          labelText: 'الرقم الأول d1',
                          counterText: '',
                        ),
                        onChanged: (_) => recalc(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: d2Ctrl,
                        keyboardType: TextInputType.number,
                        maxLength: 1,
                        decoration: const InputDecoration(
                          labelText: 'الرقم الثاني d2',
                          counterText: '',
                        ),
                        onChanged: (_) => recalc(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.accentAmber.withAlpha(30),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'البلاطة المطلوبة: $preview',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.warningAmber,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () {
                  final d1 = int.tryParse(d1Ctrl.text.trim());
                  final d2 = int.tryParse(d2Ctrl.text.trim());
                  if (d1 != null &&
                      d2 != null &&
                      d1 >= 0 &&
                      d1 <= 9 &&
                      d2 >= 0 &&
                      d2 <= 9) {
                    notifier.applyMagicRegistrationDigits(d1, d2);
                    Navigator.pop(ctx);
                  }
                },
                child: const Text('تحديد على المخطط'),
              ),
            ],
          );
        },
      ),
    );
    d1Ctrl.dispose();
    d2Ctrl.dispose();
  }

  Future<void> _showAxesEditorDialog(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => const _AxesEditorSheet(),
    );
  }

  Future<void> _showEdgeOverridePicker(
    BuildContext context,
    FloorSlabCell cell,
    EdgeSide side,
    FloorGridEditorNotifier notifier,
  ) async {
    final current = cell.edgeOverrides[side];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'تجاوز ${side.titleAr} للخانة (${cell.id})',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.auto_mode_rounded),
              title: const Text('تلقائي (يُستنتج من المخطط والجار)'),
              trailing: current == null
                  ? const Icon(Icons.check_rounded, color: AppColors.safeGreen)
                  : null,
              onTap: () {
                notifier.setEdgeOverride(
                  row: cell.row,
                  col: cell.col,
                  side: side,
                  override: null,
                );
                Navigator.pop(ctx);
              },
            ),
            const Divider(height: 1),
            ...EdgeOverride.values.map(
              (ov) => ListTile(
                leading: Icon(
                  _iconForEdgeOverride(ov),
                  color: _colorForEdgeOverride(ov),
                ),
                title: Text(ov.titleAr),
                trailing: current == ov
                    ? const Icon(Icons.check_rounded,
                        color: AppColors.safeGreen)
                    : null,
                onTap: () {
                  notifier.setEdgeOverride(
                    row: cell.row,
                    col: cell.col,
                    side: side,
                    override: ov,
                  );
                  Navigator.pop(ctx);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showBulkEditDialog(
    BuildContext context,
    Set<(int, int)> targets,
    FloorGridEditorNotifier notifier,
  ) async {
    SlabCellType? chosenType;
    final loadCtrl = TextEditingController();
    bool clearLoad = false;
    EdgeSide? chosenSide;
    EdgeOverride? chosenOverride;
    bool clearEdgeOverride = false;
    bool clearAllOverrides = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            4,
            16,
            MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'تعديل جماعي (${targets.length} خانة محددة)',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'تغيير نوع الخانات (اختياري):',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: const Text('بدون تغيير'),
                      selected: chosenType == null,
                      onSelected: (_) => setState(() => chosenType = null),
                    ),
                    ...SlabCellType.values.map(
                      (t) => ChoiceChip(
                        label: Text(t.titleAr),
                        selected: chosenType == t,
                        onSelected: (_) => setState(() => chosenType = t),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: loadCtrl,
                  enabled: !clearLoad,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'حمل تصميمي مخصص n (kN/m² — اتركه فارغاً لعدم التغيير)',
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: clearLoad,
                  onChanged: (v) => setState(() => clearLoad = v ?? false),
                  title: const Text('إلغاء الحمل المخصص والعودة لحمل المشروع'),
                ),
                const Divider(),
                const Text(
                  'تجاوز حافة (EdgeOverride) للخانات المحددة:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: const Text('بدون تعديل حافة'),
                      selected: chosenSide == null,
                      onSelected: (_) => setState(() {
                        chosenSide = null;
                        chosenOverride = null;
                        clearEdgeOverride = false;
                      }),
                    ),
                    ...EdgeSide.values.map(
                      (s) => ChoiceChip(
                        label: Text(s.titleAr),
                        selected: chosenSide == s,
                        onSelected: (_) => setState(() => chosenSide = s),
                      ),
                    ),
                  ],
                ),
                if (chosenSide != null) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ChoiceChip(
                        label: const Text('تلقائي (مسح التجاوز)'),
                        selected: clearEdgeOverride,
                        onSelected: (_) => setState(() {
                          clearEdgeOverride = true;
                          chosenOverride = null;
                        }),
                      ),
                      ...EdgeOverride.values.map(
                        (ov) => ChoiceChip(
                          label: Text(ov.shortAr),
                          selected: !clearEdgeOverride && chosenOverride == ov,
                          onSelected: (_) => setState(() {
                            clearEdgeOverride = false;
                            chosenOverride = ov;
                          }),
                        ),
                      ),
                    ],
                  ),
                ],
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: clearAllOverrides,
                  onChanged: (v) =>
                      setState(() => clearAllOverrides = v ?? false),
                  title: const Text('مسح جميع تجاوزات الحواف في الخانات المحددة'),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () {
                    final parsedLoad = double.tryParse(loadCtrl.text.trim());
                    notifier.bulkUpdateCells(
                      targets: targets,
                      cellType: chosenType,
                      customDesignLoadN:
                          (!clearLoad && parsedLoad != null && parsedLoad > 0)
                              ? parsedLoad
                              : null,
                      clearCustomDesignLoad: clearLoad,
                      edgeOverrideSide: chosenSide,
                      edgeOverrideValue: chosenOverride,
                      clearEdgeOverrideOnSide: clearEdgeOverride,
                      clearAllEdgeOverrides: clearAllOverrides,
                    );
                    Navigator.pop(ctx);
                  },
                  child: const Text('تطبيق التعديل الجماعي'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    loadCtrl.dispose();
  }

  static IconData _iconForEdgeOverride(EdgeOverride ov) {
    switch (ov) {
      case EdgeOverride.wall:
        return Icons.view_week_rounded;
      case EdgeOverride.beam:
        return Icons.horizontal_rule_rounded;
      case EdgeOverride.forcedDiscontinuous:
        return Icons.link_off_rounded;
      case EdgeOverride.forcedContinuous:
        return Icons.link_rounded;
    }
  }

  static Color _colorForEdgeOverride(EdgeOverride ov) {
    switch (ov) {
      case EdgeOverride.wall:
        return const Color(0xFF334155);
      case EdgeOverride.beam:
        return AppColors.accentAmber;
      case EdgeOverride.forcedDiscontinuous:
        return AppColors.dangerRed;
      case EdgeOverride.forcedContinuous:
        return AppColors.safeGreen;
    }
  }

  Future<void> _showProjectSettingsSheet(
    BuildContext context,
    FloorGridPlan plan,
    FloorGridEditorNotifier notifier,
  ) async {
    final s = plan.settings;
    final loadCtrl = TextEditingController(text: s.designLoadN.toStringAsFixed(2));
    final hCtrl = TextEditingController(text: s.overallDepthH.toStringAsFixed(0));
    final cCtrl = TextEditingController(text: s.clearCoverC.toStringAsFixed(0));
    final addMomCtrl = TextEditingController(
      text: plan.additionalSupportMomentKnM.toStringAsFixed(2),
    );

    int dia = s.barDiameterPhi.round();
    int fcu = s.fcu.round();
    double fy = s.fy;
    CantileverMomentSource cantSource = plan.cantileverMomentSource;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            4,
            16,
            MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'معطيات التصميم العامة للمخطط',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: loadCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'الحمل n (kN/m²)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: hCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'السماكة h (mm)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: cCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'الغطاء c (mm)',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        // value يتحكم به الـ state؛ initialValue لا يتحدّث بعد أول بناء.
                        // ignore: deprecated_member_use
                        value: dia,
                        decoration: const InputDecoration(labelText: 'القطر Ø'),
                        items: const [8, 10, 12, 14, 16]
                            .map((d) => DropdownMenuItem(
                                value: d, child: Text('Ø$d')))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => dia = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        // value يتحكم به الـ state؛ initialValue لا يتحدّث بعد أول بناء.
                        // ignore: deprecated_member_use
                        value: fcu,
                        decoration: const InputDecoration(labelText: 'fcu'),
                        items: FlexureTables.supportedFcuGrades
                            .map((g) =>
                                DropdownMenuItem(value: g, child: Text('$g')))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => fcu = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<double>(
                        // value يتحكم به الـ state؛ initialValue لا يتحدّث بعد أول بناء.
                        // ignore: deprecated_member_use
                        value: fy,
                        decoration: const InputDecoration(labelText: 'fy'),
                        items: const [250.0, 460.0]
                            .map((y) => DropdownMenuItem(
                                value: y, child: Text(y.toStringAsFixed(0))))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => fy = v);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: addMomCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'عزم مسند أدنى إضافي لجميع البلاطات (kN.m/m)',
                    hintText: '0.00 أو 1.00 حسب ملاحظة الاختبار',
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'عزم مسند الكابولي',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                SegmentedButton<CantileverMomentSource>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: CantileverMomentSource.givenSupportMoment,
                      label: Text('المعطى في السؤال'),
                    ),
                    ButtonSegment(
                      value: CantileverMomentSource.statics,
                      label: Text('ستاتيكي n·l²/2'),
                    ),
                  ],
                  selected: {cantSource},
                  onSelectionChanged: (v) =>
                      setState(() => cantSource = v.first),
                ),
                const SizedBox(height: 4),
                Text(
                  cantSource == CantileverMomentSource.givenSupportMoment
                      ? 'يُعتمد عزم المسند أعلاه كعزم الكابولي (ملاحظة المخطط: 1 kN.m/m). إن كان صفراً يُستخدم العزم الستاتيكي.'
                      : 'يُحسب عزم الكابولي من الحمل والطول: M = n·lc²/2.',
                  style: const TextStyle(fontSize: 11),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    final nVal = double.tryParse(loadCtrl.text.trim()) ??
                        s.designLoadN;
                    final hVal =
                        double.tryParse(hCtrl.text.trim()) ?? s.overallDepthH;
                    final cVal =
                        double.tryParse(cCtrl.text.trim()) ?? s.clearCoverC;
                    final addM =
                        double.tryParse(addMomCtrl.text.trim()) ?? 0.0;

                    notifier.updateSettings(
                      s.copyWith(
                        designLoadN: nVal > 0 ? nVal : s.designLoadN,
                        overallDepthH: hVal >= 60 ? hVal : s.overallDepthH,
                        clearCoverC: cVal >= 10 ? cVal : s.clearCoverC,
                        barDiameterPhi: dia.toDouble(),
                        fcu: fcu.toDouble(),
                        fy: fy,
                      ),
                      additionalSupportMomentKnM: addM >= 0 ? addM : 0.0,
                      cantileverMomentSource: cantSource,
                    );
                    Navigator.pop(ctx);
                  },
                  child: const Text('حفظ المعطيات'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    loadCtrl.dispose();
    hCtrl.dispose();
    cCtrl.dispose();
    addMomCtrl.dispose();
  }

  Future<void> _showCellDetailsDialog(
    BuildContext context,
    FloorGridPlan plan,
    FloorSlabCell cell,
    FloorGridEditorNotifier notifier,
  ) async {
    final idCtrl = TextEditingController(text: cell.id);
    final labelCtrl = TextEditingController(text: cell.label);
    final owCtrl = TextEditingController(
      text: cell.overrideWidthXM?.toStringAsFixed(2) ?? '',
    );
    final ohCtrl = TextEditingController(
      text: cell.overrideHeightYM?.toStringAsFixed(2) ?? '',
    );
    final loadCtrl = TextEditingController(
      text: cell.customDesignLoadN?.toStringAsFixed(2) ?? '',
    );
    final fillCtrl =
        TextEditingController(text: cell.fillDepthM.toStringAsFixed(2));
    final fillWeightCtrl = TextEditingController(
        text: cell.fillUnitWeightKnM3.toStringAsFixed(1));

    final cantCtrls = <EdgeSide, TextEditingController>{
      for (final c in cell.cantilevers)
        c.side: TextEditingController(text: c.lengthM.toStringAsFixed(2)),
    };

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          4,
          16,
          MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'خصائص الخانة (${cell.id})',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: idCtrl,
                      decoration: const InputDecoration(labelText: 'رمز البلاطة'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: labelCtrl,
                      decoration: const InputDecoration(labelText: 'التسمية'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: owCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'تجاوز العرض X (m)',
                        hintText: plan.xSpansM[cell.col].toStringAsFixed(2),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: ohCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'تجاوز الطول Y (m)',
                        hintText: plan.ySpansM[cell.row].toStringAsFixed(2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: loadCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'حمل تصميمي مخصص لهذه البلاطة (اختياري — kN/m²)',
                  hintText:
                      'افتراضي المشروع: ${plan.settings.designLoadN.toStringAsFixed(2)}',
                ),
              ),
              if (cell.cellType == SlabCellType.droppedSolid) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: fillCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                            labelText: 'سماكة الردم (m)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: fillWeightCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                            labelText: 'كثافة الردم (kN/m³)'),
                      ),
                    ),
                  ],
                ),
              ],
              if (cantCtrls.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'أطوال الكوابيل المتصلة بهذه البلاطة:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                ...cantCtrls.entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      controller: e.value,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'طول الكابولي (${e.key.titleAr}) — m',
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: () async {
                  final ow = double.tryParse(owCtrl.text.trim());
                  final oh = double.tryParse(ohCtrl.text.trim());
                  final cl = double.tryParse(loadCtrl.text.trim());
                  final fd = double.tryParse(fillCtrl.text.trim());
                  final fw = double.tryParse(fillWeightCtrl.text.trim());

                  final err = notifier.updateCellProperties(
                    row: cell.row,
                    col: cell.col,
                    id: idCtrl.text,
                    label: labelCtrl.text,
                    overrideWidthXM: (ow != null && ow > 0) ? ow : null,
                    clearOverrideWidthX: owCtrl.text.trim().isEmpty,
                    overrideHeightYM: (oh != null && oh > 0) ? oh : null,
                    clearOverrideHeightY: ohCtrl.text.trim().isEmpty,
                    customDesignLoadN: (cl != null && cl > 0) ? cl : null,
                    clearCustomDesignLoad: loadCtrl.text.trim().isEmpty,
                    fillDepthM: (fd != null && fd >= 0) ? fd : null,
                    fillUnitWeightKnM3: (fw != null && fw > 0) ? fw : null,
                  );

                  if (err != null) {
                    // لم يُحفظ شيء: نُبقي النافذة مفتوحة ليصحّح المستخدم المعرّف
                    await showDialog<void>(
                      context: ctx,
                      builder: (d) => AlertDialog(
                        title: const Text('تعذّر حفظ التعديلات'),
                        content: Text(err),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(d),
                            child: const Text('حسناً'),
                          ),
                        ],
                      ),
                    );
                    return;
                  }

                  for (final entry in cantCtrls.entries) {
                    final len = double.tryParse(entry.value.text.trim());
                    if (len != null && len > 0) {
                      notifier.updateCantileverLength(
                        row: cell.row,
                        col: cell.col,
                        side: entry.key,
                        lengthM: len,
                      );
                    }
                  }
                  Navigator.pop(ctx);
                },
                child: const Text('حفظ التعديلات'),
              ),
            ],
          ),
        ),
      ),
    );

    idCtrl.dispose();
    labelCtrl.dispose();
    owCtrl.dispose();
    ohCtrl.dispose();
    loadCtrl.dispose();
    fillCtrl.dispose();
    fillWeightCtrl.dispose();
    for (final c in cantCtrls.values) {
      c.dispose();
    }
  }

  Future<void> _showFullBuildingScheduleSheet(
    BuildContext context,
    WidgetRef ref,
    DesignCalculationMode mode,
  ) async {
    if (ref.read(floorGridEditorProvider).validation.hasErrors) {
      await _showValidationSheet(context, ref);
      return;
    }
    final designs =
        ref.read(floorGridEditorProvider.notifier).designAllSlabs(mode);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.92,
        builder: (ctx, scrollCtrl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'جدول تسليح جميع بلاطات السقف (${designs.length})',
                          style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        Text(
                          'انقر على أي صف لفتح التقرير الكامل للبلاطة • ${mode.shortLabelAr}',
                          style: Theme.of(ctx).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollCtrl,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Slab')),
                      DataColumn(label: Text('Case')),
                      DataColumn(label: Text('Short Mid')),
                      DataColumn(label: Text('Short Sup')),
                      DataColumn(label: Text('Long Mid')),
                      DataColumn(label: Text('Long Sup')),
                      DataColumn(label: Text('الحالة')),
                    ],
                    rows: designs
                        .map(
                          (d) => DataRow(
                            onSelectChanged: (_) {
                              Navigator.pop(ctx);
                              _openSlabDesignReport(
                                  context, ref, d.cell.row, d.cell.col, mode);
                            },
                            cells: [
                              DataCell(
                                Text(
                                  d.report.slabId,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  d.report.topology.twoWayCase != null
                                      ? 'C${d.report.topology.twoWayCase!.caseNumber}'
                                      : '1-Way',
                                ),
                              ),
                              DataCell(Text(d.report.summaryRow.shortMidLecture)),
                              DataCell(Text(d.report.summaryRow.shortSupportAllLecture())),
                              DataCell(Text(d.report.summaryRow.longMidLecture)),
                              DataCell(Text(d.report.summaryRow.longSupportAllLecture())),
                              DataCell(
                                Icon(
                                  d.report.overallIsSafe
                                      ? Icons.check_circle_rounded
                                      : Icons.warning_amber_rounded,
                                  size: 18,
                                  color: d.report.overallIsSafe
                                      ? AppColors.safeGreen
                                      : AppColors.dangerRed,
                                ),
                              ),
                            ],
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// لوحة المفتش السفلية للخانة المحددة على المخطط
class _SelectedCellInspectorPanel extends StatelessWidget {
  final FloorGridPlan plan;
  final FloorSlabCell cell;
  final ResolvedTopology? topology;
  final String? copiedSourceId;
  final GridCellResultSummary? cellResult;
  final bool isCellResultStale;
  final ValueChanged<SlabCellType> onChangeType;
  final VoidCallback onEditDetails;
  final VoidCallback onCopyProperties;
  final VoidCallback? onPasteProperties;
  final ValueChanged<EdgeSide> onPickEdgeOverride;
  final ValueChanged<EdgeSide> onToggleCantilever;
  final VoidCallback? onDesignWithNeighborsPressed;
  final VoidCallback? onDesignPressed;

  const _SelectedCellInspectorPanel({
    required this.plan,
    required this.cell,
    required this.topology,
    this.copiedSourceId,
    this.cellResult,
    this.isCellResultStale = false,
    required this.onChangeType,
    required this.onEditDetails,
    required this.onCopyProperties,
    this.onPasteProperties,
    required this.onPickEdgeOverride,
    required this.onToggleCantilever,
    this.onDesignWithNeighborsPressed,
    required this.onDesignPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wM = plan.widthOf(cell);
    final hM = plan.heightOf(cell);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor, width: 1.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(18),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // الصف الأول: عنوان الخانة + التصنيف + أزرار النسخ/اللصق/الخصائص
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: theme.colorScheme.primary.withAlpha(25),
                  child: Text(
                    cell.id.length <= 3 ? cell.id : cell.id.substring(0, 2),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${cell.id} (${wM.toStringAsFixed(2)} × ${hM.toStringAsFixed(2)} m)',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        topology != null
                            ? (topology!.twoWayCase != null
                                ? 'Case ${topology!.twoWayCase!.caseNumber}: ${topology!.twoWayCase!.titleAr}'
                                : topology!.spanningType.titleAr)
                            : cell.cellType.titleAr,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.secondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'نسخ خصائص الخانة',
                  icon: const Icon(Icons.copy_rounded, size: 19),
                  onPressed: onCopyProperties,
                ),
                if (onPasteProperties != null)
                  IconButton(
                    tooltip: 'لصق خصائص (${copiedSourceId ?? ""})',
                    icon: const Icon(Icons.paste_rounded, size: 19),
                    onPressed: onPasteProperties,
                  ),
                IconButton(
                  tooltip: 'تعديل خصائص الخانة',
                  icon: const Icon(Icons.edit_rounded, size: 20),
                  onPressed: onEditDetails,
                ),
              ],
            ),
            const SizedBox(height: 8),

            // الصف الثاني: تبديل سريع لنوع الخانة والكوابيل
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ...SlabCellType.values.map(
                    (t) => Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: ChoiceChip(
                        label: Text(
                          _shortTypeLabel(t),
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        selected: cell.cellType == t,
                        onSelected: (_) => onChangeType(t),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                  if (cell.cellType.isDesignableSlab) ...[
                    const SizedBox(width: 4),
                    ...EdgeSide.values.map((side) {
                      final hasCant = cell.cantileverOn(side) != null;
                      return Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: FilterChip(
                          label: Text(
                            'كابولي ${_shortSideLabel(side)}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          selected: hasCant,
                          selectedColor: AppColors.safeGreen.withAlpha(40),
                          onSelected: (_) => onToggleCantilever(side),
                          visualDensity: VisualDensity.compact,
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),

            // الصف الثالث (للبلاطات القابلة للتصميم): تجاوزات الحواف اليدوية (EdgeOverride)
            if (cell.cellType.isDesignableSlab) ...[
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Text(
                      'الحواف:',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 6),
                    ...EdgeSide.values.map((side) {
                      final ov = cell.edgeOverrides[side];
                      return Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: ActionChip(
                          avatar: Icon(
                            ov != null
                                ? Icons.border_style_rounded
                                : Icons.auto_mode_rounded,
                            size: 14,
                            color: ov != null
                                ? AppColors.accentAmber
                                : theme.colorScheme.secondary,
                          ),
                          label: Text(
                            ov != null
                                ? '${_shortSideLabel(side)}: ${ov.shortAr}'
                                : '${_shortSideLabel(side)}: تلقائي',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: ov != null
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => onPickEdgeOverride(side),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],

            if (cellResult != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    cellResult!.safetyStatus == SlabSafetyStatus.safe
                        ? Icons.check_circle_rounded
                        : Icons.warning_amber_rounded,
                    size: 16,
                    color: cellResult!.safetyStatus == SlabSafetyStatus.safe
                        ? AppColors.safeGreen
                        : (cellResult!.safetyStatus == SlabSafetyStatus.unsafe
                            ? AppColors.dangerRed
                            : AppColors.accentAmber),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'آخر نتيجة: ${cellResult!.shortStatusBadgeAr}'
                      '${isCellResultStale ? " (النتيجة قديمة)" : ""}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            if (onDesignPressed != null) ...[
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: onDesignPressed,
                icon: const Icon(Icons.calculate_rounded),
                label: Text(
                  'صمّم البلاطة (${cell.id}) واعرض الحل الكامل',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              if (onDesignWithNeighborsPressed != null) ...[
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: onDesignWithNeighborsPressed,
                  icon: const Icon(Icons.hub_outlined, size: 18),
                  label: const Text('صمّم هذه + جيرانها'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  static String _shortTypeLabel(SlabCellType t) {
    switch (t) {
      case SlabCellType.normalSolid:
        return 'بلاطة عادية';
      case SlabCellType.droppedSolid:
        return 'مهبطة (Dropped)';
      case SlabCellType.stairwellOrVoid:
        return 'درج / فتحة';
      case SlabCellType.exteriorEmpty:
        return 'فراغ';
    }
  }

  static String _shortSideLabel(EdgeSide s) {
    switch (s) {
      case EdgeSide.top:
        return 'أعلى';
      case EdgeSide.bottom:
        return 'أسفل';
      case EdgeSide.left:
        return 'يسار';
      case EdgeSide.right:
        return 'يمين';
    }
  }
}

/// لوحة التعديل الجماعي عند تفعيل التحديد المتعدد
class _MultiSelectBulkPanel extends StatelessWidget {
  final int selectedCount;
  final String? copiedSourceId;
  final VoidCallback onSelectAll;
  final VoidCallback onExitMultiSelect;
  final ValueChanged<SlabCellType> onQuickChangeType;
  final VoidCallback? onPasteCopied;
  final VoidCallback? onOpenBulkDialog;

  const _MultiSelectBulkPanel({
    required this.selectedCount,
    this.copiedSourceId,
    required this.onSelectAll,
    required this.onExitMultiSelect,
    required this.onQuickChangeType,
    this.onPasteCopied,
    this.onOpenBulkDialog,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: const Border(top: BorderSide(color: AppColors.secondary, width: 1.6)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.checklist_rounded,
                    color: AppColors.secondary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'التحديد المتعدد: $selectedCount خانة محددة',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onSelectAll,
                  child: const Text('تحديد الكل'),
                ),
                TextButton(
                  onPressed: onExitMultiSelect,
                  child: const Text('إنهاء'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ...SlabCellType.values.map(
                    (t) => Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: ActionChip(
                        label: Text(
                          _SelectedCellInspectorPanel._shortTypeLabel(t),
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        visualDensity: VisualDensity.compact,
                        onPressed:
                            selectedCount > 0 ? () => onQuickChangeType(t) : null,
                      ),
                    ),
                  ),
                  if (onPasteCopied != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: ActionChip(
                        avatar: const Icon(Icons.paste_rounded, size: 15),
                        label: Text('لصق (${copiedSourceId ?? ""})'),
                        visualDensity: VisualDensity.compact,
                        onPressed: onPasteCopied,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: onOpenBulkDialog,
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('تعديل جماعي للخصائص والحواف'),
            ),
          ],
        ),
      ),
    );
  }
}

/// نافذة إدارة المحاور (تعديل الأطوال، وإدراج/حذف صف أو عمود في أي موضع حتى 12)
class _AxesEditorSheet extends ConsumerStatefulWidget {
  const _AxesEditorSheet();

  @override
  ConsumerState<_AxesEditorSheet> createState() => _AxesEditorSheetState();
}

class _AxesEditorSheetState extends ConsumerState<_AxesEditorSheet> {
  List<TextEditingController> _xCtrls = [];
  List<TextEditingController> _yCtrls = [];

  @override
  void initState() {
    super.initState();
    final plan = ref.read(floorGridEditorProvider).plan;
    _rebuildControllers(plan);
  }

  void _rebuildControllers(FloorGridPlan plan) {
    for (final c in _xCtrls) {
      c.dispose();
    }
    for (final c in _yCtrls) {
      c.dispose();
    }
    _xCtrls = plan.xSpansM
        .map((v) => TextEditingController(text: v.toStringAsFixed(2)))
        .toList();
    _yCtrls = plan.ySpansM
        .map((v) => TextEditingController(text: v.toStringAsFixed(2)))
        .toList();
  }

  @override
  void dispose() {
    for (final c in _xCtrls) {
      c.dispose();
    }
    for (final c in _yCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _applyTypedSpans(FloorGridEditorNotifier notifier) {
    final plan = ref.read(floorGridEditorProvider).plan;
    for (int i = 0; i < _xCtrls.length && i < plan.colsCount; i++) {
      final v = double.tryParse(_xCtrls[i].text.trim());
      if (v != null && v > 0 && (v - plan.xSpansM[i]).abs() > 1e-9) {
        notifier.updateColumnSpan(i, v);
      }
    }
    for (int i = 0; i < _yCtrls.length && i < plan.rowsCount; i++) {
      final v = double.tryParse(_yCtrls[i].text.trim());
      if (v != null && v > 0 && (v - plan.ySpansM[i]).abs() > 1e-9) {
        notifier.updateRowSpan(i, v);
      }
    }
  }

  void _mutateAxes(VoidCallback action) {
    final notifier = ref.read(floorGridEditorProvider.notifier);
    _applyTypedSpans(notifier);
    action();
    setState(() {
      _rebuildControllers(ref.read(floorGridEditorProvider).plan);
    });
  }

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(floorGridEditorProvider).plan;
    final notifier = ref.read(floorGridEditorProvider.notifier);
    if (_xCtrls.length != plan.colsCount || _yCtrls.length != plan.rowsCount) {
      _rebuildControllers(plan);
    }

    final canAddCol = plan.colsCount < FloorGridEditorNotifier.maxGridSize;
    final canAddRow = plan.rowsCount < FloorGridEditorNotifier.maxGridSize;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        4,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'إدارة المحاور (إدراج / حذف / تعديل حتى ${FloorGridEditorNotifier.maxGridSize})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'المحاور الأفقية X (${plan.colsCount}/${FloorGridEditorNotifier.maxGridSize})',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('إدراج في البداية'),
                  onPressed: canAddCol
                      ? () => _mutateAxes(() => notifier.insertColumnAt(0))
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 4),
            ...List.generate(
              _xCtrls.length,
              (i) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _xCtrls[i],
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: 'العمود X${i + 1} (m)',
                          isDense: true,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'إدراج عمود بعد X${i + 1}',
                      icon: const Icon(Icons.add_circle_outline_rounded,
                          size: 20),
                      onPressed: canAddCol
                          ? () => _mutateAxes(
                                () => notifier.insertColumnAt(i + 1),
                              )
                          : null,
                    ),
                    IconButton(
                      tooltip: 'حذف العمود X${i + 1}',
                      icon: const Icon(Icons.delete_outline_rounded,
                          size: 20, color: AppColors.dangerRed),
                      onPressed: plan.colsCount > 1
                          ? () => _mutateAxes(() => notifier.deleteColumnAt(i))
                          : null,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'المحاور الرأسية Y (${plan.rowsCount}/${FloorGridEditorNotifier.maxGridSize})',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('إدراج في البداية'),
                  onPressed: canAddRow
                      ? () => _mutateAxes(() => notifier.insertRowAt(0))
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 4),
            ...List.generate(
              _yCtrls.length,
              (i) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _yCtrls[i],
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: 'الصف Y${i + 1} (m)',
                          isDense: true,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'إدراج صف بعد Y${i + 1}',
                      icon: const Icon(Icons.add_circle_outline_rounded,
                          size: 20),
                      onPressed: canAddRow
                          ? () => _mutateAxes(
                                () => notifier.insertRowAt(i + 1),
                              )
                          : null,
                    ),
                    IconButton(
                      tooltip: 'حذف الصف Y${i + 1}',
                      icon: const Icon(Icons.delete_outline_rounded,
                          size: 20, color: AppColors.dangerRed),
                      onPressed: plan.rowsCount > 1
                          ? () => _mutateAxes(() => notifier.deleteRowAt(i))
                          : null,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: () {
                _applyTypedSpans(notifier);
                Navigator.pop(context);
              },
              child: const Text('تطبيق الأبعاد'),
            ),
          ],
        ),
      ),
    );
  }
}


class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }
}
