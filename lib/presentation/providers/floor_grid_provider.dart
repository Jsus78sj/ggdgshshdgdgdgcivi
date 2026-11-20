import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/design_mode.dart';
import '../../core/utils/natural_compare.dart';
import '../../data/repositories/local_storage_service.dart';
import '../../data/repositories/projects_repository.dart';
import '../../data/templates/exam_floor_plan_template.dart';
import '../../domain/engine/engineering_engine.dart';
import '../../domain/engine/grid_validator.dart';

/// مزوّد قائمة المشاريع المحفوظة محلياً (مرتبط بـ Hive ويتحدّث فورياً في كل الشاشات)
class SavedProjectsNotifier extends Notifier<List<SavedFloorProjectRecord>> {
  @override
  List<SavedFloorProjectRecord> build() {
    return ProjectsRepository.loadAllProjects();
  }

  void refresh() {
    state = ProjectsRepository.loadAllProjects();
  }

  Future<SavedFloorProjectRecord> save(FloorGridPlan plan) async {
    final saved = await ProjectsRepository.saveProject(plan);
    refresh();
    return saved;
  }

  Future<void> delete(String projectId) async {
    await ProjectsRepository.deleteProject(projectId);
    refresh();
  }

  Future<void> rename(String projectId, String newName) async {
    if (newName.trim().isEmpty) return;
    await ProjectsRepository.renameProject(
      projectId: projectId,
      newName: newName.trim(),
    );
    refresh();
  }

  Future<SavedFloorProjectRecord?> duplicate(String projectId) async {
    final copy = await ProjectsRepository.duplicateProject(projectId);
    refresh();
    return copy;
  }
}

final savedProjectsProvider =
    NotifierProvider<SavedProjectsNotifier, List<SavedFloorProjectRecord>>(
  SavedProjectsNotifier.new,
);

/// نتيجة تصميم بلاطة واحدة من المخطط مع خانتها (للفتح لاحقاً بالموضع لا بالمعرّف)
class GridSlabDesign {
  final FloorSlabCell cell;
  final SlabDesignReport report;
  const GridSlabDesign({required this.cell, required this.report});
}

/// نسخة محفوظة من خصائص خانة (دون المعرّف id) للصقها على خانة أو مجموعة خانات
class CellPropertiesClipboard {
  final String sourceId;
  final SlabCellType cellType;
  final double? customDesignLoadN;
  final double fillDepthM;
  final double fillUnitWeightKnM3;
  final List<CantileverAttachment> cantilevers;
  final Map<EdgeSide, EdgeOverride> edgeOverrides;

  const CellPropertiesClipboard({
    required this.sourceId,
    required this.cellType,
    this.customDesignLoadN,
    this.fillDepthM = 0.0,
    this.fillUnitWeightKnM3 = 18.5,
    this.cantilevers = const [],
    this.edgeOverrides = const {},
  });

  factory CellPropertiesClipboard.fromCell(FloorSlabCell cell) {
    return CellPropertiesClipboard(
      sourceId: cell.id,
      cellType: cell.cellType,
      customDesignLoadN: cell.customDesignLoadN,
      fillDepthM: cell.fillDepthM,
      fillUnitWeightKnM3: cell.fillUnitWeightKnM3,
      cantilevers: List<CantileverAttachment>.from(cell.cantilevers),
      edgeOverrides: Map<EdgeSide, EdgeOverride>.from(cell.edgeOverrides),
    );
  }
}

class _HistorySnapshot {
  final FloorGridPlan plan;
  final int revision;
  final Map<(int, int), GridCellResultSummary> resultsByCell;
  const _HistorySnapshot(this.plan, this.revision, this.resultsByCell);
}

/// حالة محرر المخطط الشبكي الكامل للسقف
class FloorGridEditorState {
  final FloorGridPlan plan;
  final int selectedRow;
  final int selectedCol;
  final String? highlightedSlabId;
  final bool hasUnsavedChanges;
  final bool canUndo;
  final bool canRedo;
  final bool isMultiSelectMode;
  final Set<(int, int)> selectedCells;
  final CellPropertiesClipboard? copiedCell;

  /// رقم المراجعة الحالي للمخطط (يتغير مع كل تعديل، ويُقارن بمراجعة آخر تصميم لكشف «النتيجة قديمة»)
  final int planRevision;

  /// خريطة نتائج آخر تصميم للبلاطات المفهرسة بالموضع (صف، عمود)
  final Map<(int, int), GridCellResultSummary> resultsByCell;

  /// وضع الحساب الذي حُسبت به النتائج المخزنة
  final DesignCalculationMode? lastDesignedMode;

  /// هل تُعرض طبقة خريطة النتائج (ألوان الأمان وCase) على المخطط حالياً؟
  final bool showResultsMap;

  const FloorGridEditorState({
    required this.plan,
    this.selectedRow = 1,
    this.selectedCol = 0,
    this.highlightedSlabId,
    this.hasUnsavedChanges = false,
    this.canUndo = false,
    this.canRedo = false,
    this.isMultiSelectMode = false,
    this.selectedCells = const {},
    this.copiedCell,
    this.planRevision = 0,
    this.resultsByCell = const {},
    this.lastDesignedMode,
    this.showResultsMap = true,
  });

  FloorSlabCell? get selectedCell => plan.cellAt(selectedRow, selectedCol);

  ResolvedTopology? get selectedTopology {
    final cell = selectedCell;
    if (cell == null || !cell.cellType.isDesignableSlab) return null;
    return TopologyResolver.resolveFromFloorGrid(plan: plan, cell: cell);
  }

  /// فحص سلامة المخطط الحالي (يُحسب عند الطلب)
  GridValidationReport get validation => GridValidator.validate(plan);

  bool get hasDesignResults => resultsByCell.isNotEmpty;

  /// عدد البلاطات التي أصبحت نتيجتها قديمة بسبب تعديل المخطط بعد تصميمها
  int get staleResultsCount => resultsByCell.values
      .where((r) => r.computedAtRevision != planRevision)
      .length;

  /// هل توجد نتائج قديمة بعد تعديل المخطط؟
  bool get areResultsStale => staleResultsCount > 0;

  /// هل النتائج قديمة مقارنة بالمخطط الحالي أو بوضع الحساب النشط؟
  bool isResultsStaleForMode(DesignCalculationMode mode) =>
      areResultsStale ||
      (hasDesignResults &&
          lastDesignedMode != null &&
          lastDesignedMode != mode);

  bool isCellResultStale(
    int row,
    int col, {
    DesignCalculationMode? mode,
  }) {
    final res = resultsByCell[(row, col)];
    if (res == null) return false;
    if (res.computedAtRevision != planRevision) return true;
    if (mode != null && res.mode != mode) return true;
    return false;
  }

  int get safeResultsCount => resultsByCell.values
      .where((r) => r.safetyStatus == SlabSafetyStatus.safe)
      .length;

  int get warningResultsCount => resultsByCell.values
      .where((r) => r.safetyStatus == SlabSafetyStatus.warning)
      .length;

  int get unsafeResultsCount => resultsByCell.values
      .where((r) => r.safetyStatus == SlabSafetyStatus.unsafe)
      .length;

  FloorGridEditorState copyWith({
    FloorGridPlan? plan,
    int? selectedRow,
    int? selectedCol,
    String? highlightedSlabId,
    bool clearHighlight = false,
    bool? hasUnsavedChanges,
    bool? canUndo,
    bool? canRedo,
    bool? isMultiSelectMode,
    Set<(int, int)>? selectedCells,
    CellPropertiesClipboard? copiedCell,
    bool clearCopiedCell = false,
    int? planRevision,
    Map<(int, int), GridCellResultSummary>? resultsByCell,
    DesignCalculationMode? lastDesignedMode,
    bool clearLastDesignedMode = false,
    bool? showResultsMap,
  }) {
    return FloorGridEditorState(
      plan: plan ?? this.plan,
      selectedRow: selectedRow ?? this.selectedRow,
      selectedCol: selectedCol ?? this.selectedCol,
      highlightedSlabId: clearHighlight
          ? null
          : (highlightedSlabId ?? this.highlightedSlabId),
      hasUnsavedChanges: hasUnsavedChanges ?? this.hasUnsavedChanges,
      canUndo: canUndo ?? this.canUndo,
      canRedo: canRedo ?? this.canRedo,
      isMultiSelectMode: isMultiSelectMode ?? this.isMultiSelectMode,
      selectedCells: selectedCells ?? this.selectedCells,
      copiedCell: clearCopiedCell ? null : (copiedCell ?? this.copiedCell),
      planRevision: planRevision ?? this.planRevision,
      resultsByCell: resultsByCell ?? this.resultsByCell,
      lastDesignedMode: clearLastDesignedMode
          ? null
          : (lastDesignedMode ?? this.lastDesignedMode),
      showResultsMap: showResultsMap ?? this.showResultsMap,
    );
  }
}

/// متحكم محرر المخطط الشبكي الكامل للسقف
///
/// - كل تعديل يمرّ عبر [_commit] فيُسجَّل في سجل التراجع (حتى [_maxHistory] خطوة).
/// - يُكتب «مسوّدة» تلقائياً عند كل تعديل غير محفوظ (مفتاح مستقل عن المشاريع المحفوظة
///   حتى لا تُستبدل نسخة حفظها المستخدم صراحةً)، وتُستعاد عند فتح التطبيق.
class FloorGridEditorNotifier extends Notifier<FloorGridEditorState> {
  static const String _draftKey = 'floor_grid_draft_v1';
  static const int _maxHistory = 50;

  /// الحد الأقصى لعدد الصفوف أو الأعمدة في محرر المخطط (المرحلة 3: رُفع من 8 إلى 12)
  static const int maxGridSize = 12;

  final List<_HistorySnapshot> _undoStack = [];
  final List<_HistorySnapshot> _redoStack = [];
  int _revisionCounter = 0;

  /// آخر مخطط حُفظ صراحةً (أو حُمّل كما هو)؛ للمقارنة بالهوية عند التراجع إليه
  FloorGridPlan? _savedPlan;

  @override
  FloorGridEditorState build() {
    final draft = _readDraft();
    if (draft != null) {
      _savedPlan = null;
      final sel = _firstDesignable(draft);
      return FloorGridEditorState(
        plan: draft,
        selectedRow: sel.$1,
        selectedCol: sel.$2,
        hasUnsavedChanges: true,
      );
    }

    // يفتح افتراضياً على مخطط اختبار جامعة عدن (S0 إلى S9) مع تحديد البلاطة S7
    final examPlan = ExamFloorPlanTemplate.buildUniversityOfAdenExamPlan();
    _savedPlan = examPlan;
    return FloorGridEditorState(
      plan: examPlan,
      selectedRow: 1,
      selectedCol: 0,
      hasUnsavedChanges: false,
    );
  }

  // ───────────────────────── المسوّدة (حفظ تلقائي) ─────────────────────────

  FloorGridPlan? _readDraft() {
    try {
      final raw = LocalStorageService.readSetting(_draftKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final plan = FloorGridPlan.fromJson(Map<String, dynamic>.from(decoded));
      if (plan.cells.isEmpty ||
          plan.xSpansM.isEmpty ||
          plan.ySpansM.isEmpty) {
        return null;
      }
      return plan;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeDraft(String value) async {
    try {
      await LocalStorageService.writeSetting(_draftKey, value);
    } catch (_) {
      // الحفظ التلقائي «أفضل جهد»: فشله لا يعطّل التحرير
    }
  }

  void _syncDraft() {
    try {
      if (state.hasUnsavedChanges) {
        unawaited(_writeDraft(jsonEncode(state.plan.toJson())));
      } else {
        unawaited(_writeDraft(''));
      }
    } catch (_) {}
  }

  // ───────────────────────── السجل (Undo / Redo) ─────────────────────────

  void _resetHistory() {
    _undoStack.clear();
    _redoStack.clear();
    _revisionCounter = 0;
  }

  (int, int) _firstDesignable(FloorGridPlan plan) {
    for (final c in plan.cells) {
      if (c.cellType.isDesignableSlab) return (c.row, c.col);
    }
    return (0, 0);
  }

  void _commit(
    FloorGridPlan next, {
    int? selectedRow,
    int? selectedCol,
    Set<(int, int)>? selectedCells,
    Map<(int, int), GridCellResultSummary>? resultsByCell,
  }) {
    _undoStack.add(
      _HistorySnapshot(
        state.plan,
        state.planRevision,
        Map<(int, int), GridCellResultSummary>.from(state.resultsByCell),
      ),
    );
    if (_undoStack.length > _maxHistory) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
    _revisionCounter++;
    state = state.copyWith(
      plan: next,
      selectedRow: selectedRow,
      selectedCol: selectedCol,
      selectedCells: selectedCells,
      resultsByCell: resultsByCell,
      planRevision: _revisionCounter,
      hasUnsavedChanges: true,
      canUndo: true,
      canRedo: false,
    );
    _syncDraft();
  }

  void _restore(_HistorySnapshot snap) {
    final plan = snap.plan;
    final row = state.selectedRow.clamp(0, plan.rowsCount - 1).toInt();
    final col = state.selectedCol.clamp(0, plan.colsCount - 1).toInt();
    final validMulti = <(int, int)>{
      for (final p in state.selectedCells)
        if (p.$1 >= 0 &&
            p.$1 < plan.rowsCount &&
            p.$2 >= 0 &&
            p.$2 < plan.colsCount)
          p,
    };
    final sourceResults =
        snap.resultsByCell.isNotEmpty ? snap.resultsByCell : state.resultsByCell;
    final validResults = <(int, int), GridCellResultSummary>{
      for (final entry in sourceResults.entries)
        if (entry.key.$1 >= 0 &&
            entry.key.$1 < plan.rowsCount &&
            entry.key.$2 >= 0 &&
            entry.key.$2 < plan.colsCount)
          entry.key: entry.value,
    };
    state = FloorGridEditorState(
      plan: plan,
      selectedRow: row,
      selectedCol: col,
      highlightedSlabId: state.highlightedSlabId,
      hasUnsavedChanges: !identical(plan, _savedPlan),
      canUndo: _undoStack.isNotEmpty,
      canRedo: _redoStack.isNotEmpty,
      isMultiSelectMode: state.isMultiSelectMode && validMulti.isNotEmpty,
      selectedCells: validMulti,
      copiedCell: state.copiedCell,
      planRevision: snap.revision,
      resultsByCell: validResults,
      lastDesignedMode:
          validResults.isEmpty ? null : state.lastDesignedMode,
      showResultsMap: state.showResultsMap,
    );
    _syncDraft();
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    final previous = _undoStack.removeLast();
    _redoStack.add(
      _HistorySnapshot(
        state.plan,
        state.planRevision,
        Map<(int, int), GridCellResultSummary>.from(state.resultsByCell),
      ),
    );
    _restore(previous);
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    final next = _redoStack.removeLast();
    _undoStack.add(
      _HistorySnapshot(
        state.plan,
        state.planRevision,
        Map<(int, int), GridCellResultSummary>.from(state.resultsByCell),
      ),
    );
    _restore(next);
  }

  // ───────────────────────── تحميل مخططات ─────────────────────────

  void loadPlan(
    FloorGridPlan plan, {
    bool markUnsaved = false,
    int? initialSelectedRow,
    int? initialSelectedCol,
  }) {
    final fallback = _firstDesignable(plan);
    final selRow = (initialSelectedRow != null &&
            initialSelectedRow >= 0 &&
            initialSelectedRow < plan.rowsCount)
        ? initialSelectedRow
        : fallback.$1;
    final selCol = (initialSelectedCol != null &&
            initialSelectedCol >= 0 &&
            initialSelectedCol < plan.colsCount)
        ? initialSelectedCol
        : fallback.$2;

    _resetHistory();
    _savedPlan = markUnsaved ? null : plan;
    state = FloorGridEditorState(
      plan: plan,
      selectedRow: selRow,
      selectedCol: selCol,
      highlightedSlabId: null,
      hasUnsavedChanges: markUnsaved,
    );
    _syncDraft();
  }

  void loadUniversityExamTemplate() {
    final examPlan = ExamFloorPlanTemplate.buildUniversityOfAdenExamPlan();
    _resetHistory();
    _savedPlan = examPlan;
    state = FloorGridEditorState(
      plan: examPlan,
      selectedRow: 1,
      selectedCol: 0,
      highlightedSlabId: null,
      hasUnsavedChanges: false,
    );
    _syncDraft();
  }

  void createNewBlankPlan({
    int rows = 3,
    int cols = 3,
    double defaultSpanX = 4.00,
    double defaultSpanY = 4.20,
    String projectName = 'مخطط سقف جديد',
  }) {
    final xSpans = List<double>.filled(cols, defaultSpanX);
    final ySpans = List<double>.filled(rows, defaultSpanY);
    final cells = <FloorSlabCell>[];
    int idx = 1;
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final id = 'S$idx';
        cells.add(
          FloorSlabCell(
            row: r,
            col: c,
            id: id,
            label: id,
            cellType: SlabCellType.normalSolid,
          ),
        );
        idx++;
      }
    }

    final newPlan = FloorGridPlan(
      projectId: 'proj_${DateTime.now().microsecondsSinceEpoch}',
      projectName: projectName,
      xSpansM: xSpans,
      ySpansM: ySpans,
      cells: cells,
      settings: state.plan.settings,
    );

    _resetHistory();
    _savedPlan = null;
    state = FloorGridEditorState(
      plan: newPlan,
      selectedRow: 0,
      selectedCol: 0,
      highlightedSlabId: null,
      hasUnsavedChanges: true,
    );
    _syncDraft();
  }

  void selectCell(int row, int col) {
    if (row < 0 ||
        row >= state.plan.rowsCount ||
        col < 0 ||
        col >= state.plan.colsCount) {
      return;
    }
    state = state.copyWith(selectedRow: row, selectedCol: col);
  }

  // ───────────────────────── تعديلات المخطط ─────────────────────────

  void updateProjectName(String name) {
    if (name.trim().isEmpty) return;
    _commit(state.plan.copyWith(projectName: name.trim()));
  }

  void updateSettings(
    SlabProjectSettings newSettings, {
    double? additionalSupportMomentKnM,
    CantileverMomentSource? cantileverMomentSource,
  }) {
    _commit(
      state.plan.copyWith(
        settings: newSettings,
        additionalSupportMomentKnM: additionalSupportMomentKnM ??
            state.plan.additionalSupportMomentKnM,
        cantileverMomentSource:
            cantileverMomentSource ?? state.plan.cantileverMomentSource,
      ),
    );
  }

  void updateColumnSpan(int col, double spanM) {
    if (col < 0 || col >= state.plan.colsCount || !(spanM > 0)) return;
    final nextX = List<double>.from(state.plan.xSpansM);
    nextX[col] = spanM;
    _commit(state.plan.copyWith(xSpansM: nextX));
  }

  void updateRowSpan(int row, double spanM) {
    if (row < 0 || row >= state.plan.rowsCount || !(spanM > 0)) return;
    final nextY = List<double>.from(state.plan.ySpansM);
    nextY[row] = spanM;
    _commit(state.plan.copyWith(ySpansM: nextY));
  }

  /// معرّف 'S<n>' غير مستعمل في أي خانة أخرى (يتفادى التكرار بعد حذف/إضافة صفوف وأعمدة).
  /// المقارنة بلا حساسية لحالة الأحرف، مطابقةً لـ [FloorGridPlan.findById].
  static String _uniqueSlabId(Iterable<FloorSlabCell> cells, int preferred) {
    final used = cells.map((c) => c.id.trim().toLowerCase()).toSet();
    int n = preferred < 1 ? 1 : preferred;
    while (used.contains('s$n')) {
      n++;
    }
    return 'S$n';
  }

  /// اسم غير مستعمل مبنيّ على [base] (يضيف _2، _3 ... عند الحاجة)
  static String _uniqueName(Iterable<FloorSlabCell> others, String base) {
    final used = others.map((c) => c.id.trim().toLowerCase()).toSet();
    if (!used.contains(base.toLowerCase())) return base;
    int n = 2;
    while (used.contains('${base}_$n'.toLowerCase())) {
      n++;
    }
    return '${base}_$n';
  }

  void addColumn({double spanM = 4.00}) {
    insertColumnAt(state.plan.colsCount, spanM: spanM);
  }

  /// إدراج عمود جديد في الموضع [index] (من 0 إلى colsCount) حتى الحد [maxGridSize]
  void insertColumnAt(int index, {double spanM = 4.00}) {
    if (state.plan.colsCount >= maxGridSize || !(spanM > 0)) return;
    final insertIdx = index.clamp(0, state.plan.colsCount).toInt();

    final nextX = List<double>.from(state.plan.xSpansM)
      ..insert(insertIdx, spanM);
    final nextCells = state.plan.cells
        .map((c) => c.col >= insertIdx ? c.copyWith(col: c.col + 1) : c)
        .toList();

    for (int r = 0; r < state.plan.rowsCount; r++) {
      final id = _uniqueSlabId(nextCells, nextCells.length + 1);
      nextCells.add(
        FloorSlabCell(
          row: r,
          col: insertIdx,
          id: id,
          label: id,
          cellType: SlabCellType.normalSolid,
        ),
      );
    }

    final nextSelectedCol =
        state.selectedCol >= insertIdx ? state.selectedCol + 1 : state.selectedCol;
    final nextMulti = state.selectedCells
        .map((p) => p.$2 >= insertIdx ? (p.$1, p.$2 + 1) : p)
        .toSet();
    final nextResults = <(int, int), GridCellResultSummary>{
      for (final e in state.resultsByCell.entries)
        (e.key.$1, e.key.$2 >= insertIdx ? e.key.$2 + 1 : e.key.$2):
            e.value.copyWithPosition(
          e.key.$1,
          e.key.$2 >= insertIdx ? e.key.$2 + 1 : e.key.$2,
        ),
    };

    _commit(
      state.plan.copyWith(xSpansM: nextX, cells: nextCells),
      selectedCol: nextSelectedCol,
      selectedCells: nextMulti,
      resultsByCell: nextResults,
    );
  }

  void removeLastColumn() {
    deleteColumnAt(state.plan.colsCount - 1);
  }

  /// حذف العمود في الموضع [index] مع إعادة فهرسة الأعمدة اللاحقة
  void deleteColumnAt(int index) {
    if (state.plan.colsCount <= 1) return;
    if (index < 0 || index >= state.plan.colsCount) return;

    final nextX = List<double>.from(state.plan.xSpansM)..removeAt(index);
    final nextCells = <FloorSlabCell>[];
    for (final c in state.plan.cells) {
      if (c.col == index) continue;
      nextCells.add(c.col > index ? c.copyWith(col: c.col - 1) : c);
    }

    final safeCol = (state.selectedCol > index
            ? state.selectedCol - 1
            : state.selectedCol)
        .clamp(0, nextX.length - 1)
        .toInt();

    final nextMulti = <(int, int)>{};
    for (final p in state.selectedCells) {
      if (p.$2 == index) continue;
      nextMulti.add(p.$2 > index ? (p.$1, p.$2 - 1) : p);
    }
    final nextResults = <(int, int), GridCellResultSummary>{};
    for (final e in state.resultsByCell.entries) {
      if (e.key.$2 == index) continue;
      final nc = e.key.$2 > index ? e.key.$2 - 1 : e.key.$2;
      nextResults[(e.key.$1, nc)] = e.value.copyWithPosition(e.key.$1, nc);
    }

    _commit(
      state.plan.copyWith(xSpansM: nextX, cells: nextCells),
      selectedCol: safeCol,
      selectedCells: nextMulti,
      resultsByCell: nextResults,
    );
  }

  void addRow({double spanM = 4.20}) {
    insertRowAt(state.plan.rowsCount, spanM: spanM);
  }

  /// إدراج صف جديد في الموضع [index] (من 0 إلى rowsCount) حتى الحد [maxGridSize]
  void insertRowAt(int index, {double spanM = 4.20}) {
    if (state.plan.rowsCount >= maxGridSize || !(spanM > 0)) return;
    final insertIdx = index.clamp(0, state.plan.rowsCount).toInt();

    final nextY = List<double>.from(state.plan.ySpansM)
      ..insert(insertIdx, spanM);
    final nextCells = state.plan.cells
        .map((c) => c.row >= insertIdx ? c.copyWith(row: c.row + 1) : c)
        .toList();

    for (int c = 0; c < state.plan.colsCount; c++) {
      final id = _uniqueSlabId(nextCells, nextCells.length + 1);
      nextCells.add(
        FloorSlabCell(
          row: insertIdx,
          col: c,
          id: id,
          label: id,
          cellType: SlabCellType.normalSolid,
        ),
      );
    }

    final nextSelectedRow =
        state.selectedRow >= insertIdx ? state.selectedRow + 1 : state.selectedRow;
    final nextMulti = state.selectedCells
        .map((p) => p.$1 >= insertIdx ? (p.$1 + 1, p.$2) : p)
        .toSet();
    final nextResults = <(int, int), GridCellResultSummary>{
      for (final e in state.resultsByCell.entries)
        (e.key.$1 >= insertIdx ? e.key.$1 + 1 : e.key.$1, e.key.$2):
            e.value.copyWithPosition(
          e.key.$1 >= insertIdx ? e.key.$1 + 1 : e.key.$1,
          e.key.$2,
        ),
    };

    _commit(
      state.plan.copyWith(ySpansM: nextY, cells: nextCells),
      selectedRow: nextSelectedRow,
      selectedCells: nextMulti,
      resultsByCell: nextResults,
    );
  }

  void removeLastRow() {
    deleteRowAt(state.plan.rowsCount - 1);
  }

  /// حذف الصف في الموضع [index] مع إعادة فهرسة الصفوف اللاحقة
  void deleteRowAt(int index) {
    if (state.plan.rowsCount <= 1) return;
    if (index < 0 || index >= state.plan.rowsCount) return;

    final nextY = List<double>.from(state.plan.ySpansM)..removeAt(index);
    final nextCells = <FloorSlabCell>[];
    for (final c in state.plan.cells) {
      if (c.row == index) continue;
      nextCells.add(c.row > index ? c.copyWith(row: c.row - 1) : c);
    }

    final safeRow = (state.selectedRow > index
            ? state.selectedRow - 1
            : state.selectedRow)
        .clamp(0, nextY.length - 1)
        .toInt();

    final nextMulti = <(int, int)>{};
    for (final p in state.selectedCells) {
      if (p.$1 == index) continue;
      nextMulti.add(p.$1 > index ? (p.$1 - 1, p.$2) : p);
    }
    final nextResults = <(int, int), GridCellResultSummary>{};
    for (final e in state.resultsByCell.entries) {
      if (e.key.$1 == index) continue;
      final nr = e.key.$1 > index ? e.key.$1 - 1 : e.key.$1;
      nextResults[(nr, e.key.$2)] = e.value.copyWithPosition(nr, e.key.$2);
    }

    _commit(
      state.plan.copyWith(ySpansM: nextY, cells: nextCells),
      selectedRow: safeRow,
      selectedCells: nextMulti,
      resultsByCell: nextResults,
    );
  }

  void updateCellType(int row, int col, SlabCellType newType) {
    final target = state.plan.cellAt(row, col);
    if (target == null) return;

    final others =
        state.plan.cells.where((c) => !(c.row == row && c.col == col));

    String newId = target.id;
    String newLabel = target.label;
    double fillDepth = target.fillDepthM;

    if (newType == SlabCellType.droppedSolid) {
      if (target.cellType != SlabCellType.droppedSolid) {
        newLabel = 'Dropped Solid Slab';
        // لا نفترض ردماً: الردم يُدخله المستخدم من خصائص الخانة إن كان في السؤال
        fillDepth = target.fillDepthM;
      }
    } else if (newType == SlabCellType.stairwellOrVoid) {
      newId = _uniqueName(others, 'Stair_${row}_$col');
      newLabel = 'Staircase';
    } else if (newType == SlabCellType.exteriorEmpty) {
      newId = _uniqueName(others, 'Void_${row}_$col');
      newLabel = 'فراغ';
    } else if (newType == SlabCellType.normalSolid &&
        !target.cellType.isDesignableSlab) {
      newId = _uniqueSlabId(others, row * state.plan.colsCount + col + 1);
      newLabel = newId;
    }

    final updated = target.copyWith(
      id: newId,
      label: newLabel,
      cellType: newType,
      fillDepthM: fillDepth,
      cantilevers:
          newType.isDesignableSlab ? target.cantilevers : const [],
      edgeOverrides:
          newType.isDesignableSlab ? target.edgeOverrides : const {},
    );

    _replaceCell(updated);
  }

  // ─────────────────── تجاوزات الحواف (EdgeOverride) ───────────────────

  /// تعيين أو إزالة (بتمرير null) تجاوز حافة يدوي على خانة قابلة للتصميم
  void setEdgeOverride({
    required int row,
    required int col,
    required EdgeSide side,
    EdgeOverride? override,
  }) {
    final target = state.plan.cellAt(row, col);
    if (target == null || !target.cellType.isDesignableSlab) return;

    final nextOverrides =
        Map<EdgeSide, EdgeOverride>.from(target.edgeOverrides);
    if (override == null) {
      nextOverrides.remove(side);
    } else {
      nextOverrides[side] = override;
    }

    _replaceCell(target.copyWith(edgeOverrides: nextOverrides));
  }

  void clearEdgeOverrides(int row, int col) {
    final target = state.plan.cellAt(row, col);
    if (target == null || target.edgeOverrides.isEmpty) return;
    _replaceCell(target.copyWith(edgeOverrides: const {}));
  }

  // ───────── التحديد المتعدد والتعديل الجماعي ونسخ خصائص الخانة ─────────

  void toggleMultiSelectMode({bool? enabled}) {
    final next = enabled ?? !state.isMultiSelectMode;
    state = state.copyWith(
      isMultiSelectMode: next,
      selectedCells: next
          ? {(state.selectedRow, state.selectedCol)}
          : const <(int, int)>{},
    );
  }

  void toggleCellSelection(int row, int col) {
    if (row < 0 ||
        row >= state.plan.rowsCount ||
        col < 0 ||
        col >= state.plan.colsCount) {
      return;
    }
    final next = Set<(int, int)>.from(state.selectedCells);
    final key = (row, col);
    if (next.contains(key)) {
      next.remove(key);
    } else {
      next.add(key);
    }
    state = state.copyWith(
      isMultiSelectMode: true,
      selectedRow: row,
      selectedCol: col,
      selectedCells: next,
    );
  }

  void selectAllCells() {
    final all = <(int, int)>{
      for (final c in state.plan.cells) (c.row, c.col),
    };
    state = state.copyWith(isMultiSelectMode: true, selectedCells: all);
  }

  void clearMultiSelection() {
    state = state.copyWith(
      isMultiSelectMode: false,
      selectedCells: const <(int, int)>{},
    );
  }

  /// تعديل جماعي لمجموعة خانات دفعة واحدة (يُسجّل كخطوة Undo واحدة)
  int bulkUpdateCells({
    required Set<(int, int)> targets,
    SlabCellType? cellType,
    double? customDesignLoadN,
    bool clearCustomDesignLoad = false,
    double? fillDepthM,
    double? fillUnitWeightKnM3,
    EdgeSide? edgeOverrideSide,
    EdgeOverride? edgeOverrideValue,
    bool clearEdgeOverrideOnSide = false,
    bool clearAllEdgeOverrides = false,
  }) {
    if (targets.isEmpty) return 0;

    final workingCells = List<FloorSlabCell>.from(state.plan.cells);
    int modified = 0;

    for (int i = 0; i < workingCells.length; i++) {
      final c = workingCells[i];
      if (!targets.contains((c.row, c.col))) continue;

      final others = [
        for (int j = 0; j < workingCells.length; j++)
          if (j != i) workingCells[j],
      ];

      final nextType = cellType ?? c.cellType;
      String nextId = c.id;
      String nextLabel = c.label;
      if (cellType != null && cellType != c.cellType) {
        if (nextType == SlabCellType.droppedSolid) {
          nextLabel = 'Dropped Solid Slab';
        } else if (nextType == SlabCellType.stairwellOrVoid) {
          nextId = _uniqueName(others, 'Stair_${c.row}_${c.col}');
          nextLabel = 'Staircase';
        } else if (nextType == SlabCellType.exteriorEmpty) {
          nextId = _uniqueName(others, 'Void_${c.row}_${c.col}');
          nextLabel = 'فراغ';
        } else if (nextType == SlabCellType.normalSolid &&
            !c.cellType.isDesignableSlab) {
          nextId = _uniqueSlabId(
              others, c.row * state.plan.colsCount + c.col + 1);
          nextLabel = nextId;
        }
      }

      Map<EdgeSide, EdgeOverride> nextOverrides;
      if (!nextType.isDesignableSlab || clearAllEdgeOverrides) {
        nextOverrides = const {};
      } else {
        nextOverrides = Map<EdgeSide, EdgeOverride>.from(c.edgeOverrides);
        if (edgeOverrideSide != null) {
          if (clearEdgeOverrideOnSide) {
            nextOverrides.remove(edgeOverrideSide);
          } else if (edgeOverrideValue != null) {
            nextOverrides[edgeOverrideSide] = edgeOverrideValue;
          }
        }
      }

      workingCells[i] = c.copyWith(
        id: nextId,
        label: nextLabel,
        cellType: nextType,
        customDesignLoadN: customDesignLoadN,
        clearCustomDesignLoad: clearCustomDesignLoad,
        fillDepthM: fillDepthM ?? c.fillDepthM,
        fillUnitWeightKnM3: fillUnitWeightKnM3 ?? c.fillUnitWeightKnM3,
        cantilevers: nextType.isDesignableSlab ? c.cantilevers : const [],
        edgeOverrides: nextOverrides,
      );
      modified++;
    }

    if (modified > 0) {
      _commit(state.plan.copyWith(cells: workingCells));
    }
    return modified;
  }

  /// نسخ خصائص خانة إلى الحافظة الداخلية (دون المعرّف id)
  bool copyCellProperties(int row, int col) {
    final cell = state.plan.cellAt(row, col);
    if (cell == null) return false;
    state = state.copyWith(
      copiedCell: CellPropertiesClipboard.fromCell(cell),
    );
    return true;
  }

  /// لصق الخصائص المنسوخة على خانة أو عدة خانات مع الحفاظ على فرادة المعرّفات
  int pasteCellPropertiesTo(Set<(int, int)> targets) {
    final clip = state.copiedCell;
    if (clip == null || targets.isEmpty) return 0;

    final workingCells = List<FloorSlabCell>.from(state.plan.cells);
    int pasted = 0;

    for (int i = 0; i < workingCells.length; i++) {
      final c = workingCells[i];
      if (!targets.contains((c.row, c.col))) continue;

      final others = [
        for (int j = 0; j < workingCells.length; j++)
          if (j != i) workingCells[j],
      ];

      String nextId = c.id;
      String nextLabel = c.label;
      if (clip.cellType != c.cellType) {
        if (clip.cellType == SlabCellType.droppedSolid) {
          nextLabel = 'Dropped Solid Slab';
        } else if (clip.cellType == SlabCellType.stairwellOrVoid) {
          nextId = _uniqueName(others, 'Stair_${c.row}_${c.col}');
          nextLabel = 'Staircase';
        } else if (clip.cellType == SlabCellType.exteriorEmpty) {
          nextId = _uniqueName(others, 'Void_${c.row}_${c.col}');
          nextLabel = 'فراغ';
        } else if (clip.cellType == SlabCellType.normalSolid &&
            !c.cellType.isDesignableSlab) {
          nextId = _uniqueSlabId(
              others, c.row * state.plan.colsCount + c.col + 1);
          nextLabel = nextId;
        }
      }

      workingCells[i] = c.copyWith(
        id: nextId,
        label: nextLabel,
        cellType: clip.cellType,
        customDesignLoadN: clip.customDesignLoadN,
        clearCustomDesignLoad: clip.customDesignLoadN == null,
        fillDepthM: clip.fillDepthM,
        fillUnitWeightKnM3: clip.fillUnitWeightKnM3,
        cantilevers: clip.cellType.isDesignableSlab
            ? List<CantileverAttachment>.from(clip.cantilevers)
            : const [],
        edgeOverrides: clip.cellType.isDesignableSlab
            ? Map<EdgeSide, EdgeOverride>.from(clip.edgeOverrides)
            : const {},
      );
      pasted++;
    }

    if (pasted > 0) {
      _commit(state.plan.copyWith(cells: workingCells));
    }
    return pasted;
  }

  /// يعدّل خصائص خانة. يرجع `null` عند النجاح، أو رسالة خطأ عربية عند الرفض
  /// (حالياً: معرّف مستعمل في خانة أخرى؛ لا يُغيَّر شيء عند الرفض).
  String? updateCellProperties({
    required int row,
    required int col,
    required String id,
    required String label,
    double? overrideWidthXM,
    bool clearOverrideWidthX = false,
    double? overrideHeightYM,
    bool clearOverrideHeightY = false,
    double? customDesignLoadN,
    bool clearCustomDesignLoad = false,
    double? fillDepthM,
    double? fillUnitWeightKnM3,
  }) {
    final target = state.plan.cellAt(row, col);
    if (target == null) return 'الخانة غير موجودة في المخطط.';

    final newId = id.trim().isEmpty ? target.id : id.trim();
    final conflict = GridValidator.findIdConflict(
      state.plan,
      row: row,
      col: col,
      candidateId: newId,
    );
    if (conflict != null) {
      return 'المعرّف «$newId» مستعمل في خانة أخرى '
          '(الصف ${conflict.row + 1}، العمود ${conflict.col + 1}). اختر معرّفاً مختلفاً.';
    }

    final updated = target.copyWith(
      id: newId,
      label: label.trim().isEmpty ? target.label : label.trim(),
      overrideWidthXM: overrideWidthXM,
      clearOverrideWidthX: clearOverrideWidthX,
      overrideHeightYM: overrideHeightYM,
      clearOverrideHeightY: clearOverrideHeightY,
      customDesignLoadN: customDesignLoadN,
      clearCustomDesignLoad: clearCustomDesignLoad,
      fillDepthM: fillDepthM,
      fillUnitWeightKnM3: fillUnitWeightKnM3,
    );
    _replaceCell(updated);
    return null;
  }

  void toggleCantilever({
    required int row,
    required int col,
    required EdgeSide side,
    double defaultLengthM = 1.60,
  }) {
    final target = state.plan.cellAt(row, col);
    if (target == null || !target.cellType.isDesignableSlab) return;

    final existing = target.cantileverOn(side);
    final nextCantilevers = List<CantileverAttachment>.from(target.cantilevers);
    if (existing != null) {
      nextCantilevers.removeWhere((c) => c.side == side);
    } else {
      nextCantilevers.add(
        CantileverAttachment(
          side: side,
          lengthM: defaultLengthM,
          label: 'Solid Slab (${side.titleEn})',
        ),
      );
    }
    _replaceCell(target.copyWith(cantilevers: nextCantilevers));
  }

  void updateCantileverLength({
    required int row,
    required int col,
    required EdgeSide side,
    required double lengthM,
  }) {
    final target = state.plan.cellAt(row, col);
    if (target == null || !(lengthM > 0)) return;

    final nextCantilevers = target.cantilevers.map((c) {
      if (c.side == side) {
        return CantileverAttachment(
          side: c.side,
          lengthM: lengthM,
          customDesignLoadN: c.customDesignLoadN,
          label: c.label,
        );
      }
      return c;
    }).toList();

    _replaceCell(target.copyWith(cantilevers: nextCantilevers));
  }

  /// ترقيم تلقائي للبلاطات المصمتة العادية (S0, S1, S2...)
  void autoRenumberNormalSlabs({bool startFromZero = true}) {
    int counter = startFromZero ? 0 : 1;
    final sorted = List<FloorSlabCell>.from(state.plan.cells)
      ..sort((a, b) =>
          a.row != b.row ? a.row.compareTo(b.row) : a.col.compareTo(b.col));

    final renumbered = <FloorSlabCell>[];
    for (final c in sorted) {
      if (c.cellType == SlabCellType.normalSolid) {
        final newId = 'S$counter';
        counter++;
        renumbered.add(c.copyWith(id: newId, label: newId));
      } else {
        renumbered.add(c);
      }
    }

    // الخانات غير العادية (مهبطة/درج/فراغ) قد تحمل معرّفاً مثل «S3»؛ نعيد تسميتها
    // إن تعارضت مع الترقيم الجديد حتى لا ينشأ تكرار.
    final normalIds = renumbered
        .where((c) => c.cellType == SlabCellType.normalSolid)
        .map((c) => c.id.toLowerCase())
        .toSet();
    final fixed = <FloorSlabCell>[];
    final usedAll = <String>{...normalIds};
    for (final c in renumbered) {
      if (c.cellType != SlabCellType.normalSolid &&
          usedAll.contains(c.id.trim().toLowerCase())) {
        var n = 2;
        var candidate = '${c.id}_$n';
        while (usedAll.contains(candidate.toLowerCase())) {
          n++;
          candidate = '${c.id}_$n';
        }
        usedAll.add(candidate.toLowerCase());
        fixed.add(c.copyWith(id: candidate));
      } else {
        usedAll.add(c.id.trim().toLowerCase());
        fixed.add(c);
      }
    }

    _commit(state.plan.copyWith(cells: fixed));
  }

  /// تطبيق معادلة الرقم السحري لرقم القيد: S_No. = 9 - |d1 - d2|
  /// يرجع معرّف البلاطة المطلوبة ويحددها على المخطط تلقائياً إن وُجدت.
  String applyMagicRegistrationDigits(int digit1, int digit2) {
    final targetId = FloorGridPlan.magicSlabId(digit1, digit2);
    final found = state.plan.findById(targetId);

    if (found != null) {
      state = state.copyWith(
        selectedRow: found.row,
        selectedCol: found.col,
        highlightedSlabId: found.id,
      );
    } else {
      state = state.copyWith(highlightedSlabId: targetId);
    }
    return targetId;
  }

  void clearHighlight() {
    state = state.copyWith(clearHighlight: true);
  }

  /// حفظ المخطط الحالي في التخزين المحلي (Hive)
  Future<SavedFloorProjectRecord> saveCurrentPlan() async {
    final planToSave = state.plan;
    final saved =
        await ref.read(savedProjectsProvider.notifier).save(planToSave);
    _savedPlan = planToSave;
    // لو عُدّل المخطط أثناء الحفظ فيبقى «غير محفوظ» بدل إخفاء التعديل
    state = state.copyWith(
      hasUnsavedChanges: !identical(state.plan, _savedPlan),
    );
    _syncDraft();
    return saved;
  }

  // ───────────────────────── التصميم ─────────────────────────

  FloorGridPlan _planWithMode(DesignCalculationMode mode) {
    return state.plan.copyWith(
      settings: state.plan.settings.copyWith(calculationMode: mode),
    );
  }

  void toggleResultsMap({bool? visible}) {
    state = state.copyWith(showResultsMap: visible ?? !state.showResultsMap);
  }

  void clearDesignResults() {
    state = state.copyWith(
      resultsByCell: const {},
      clearLastDesignedMode: true,
    );
  }

  /// تصميم البلاطة الموجودة في (صف، عمود) من داخل المخطط.
  /// التصميم بالموضع لا بالمعرّف، فلا يتأثر بتكرار المعرّفات، ويُحدّث ملخصها على خريطة النتائج.
  SlabDesignReport designCell(
    int row,
    int col,
    DesignCalculationMode mode, {
    bool autoAdjustDepthInStrictMode = false,
  }) {
    final report = SlabDesignPipeline.designFromFloorGridCell(
      plan: _planWithMode(mode),
      row: row,
      col: col,
      autoAdjustDepthIfUnsafeInStrictMode: autoAdjustDepthInStrictMode,
    );

    final sameMode = state.lastDesignedMode == null ||
        state.lastDesignedMode == mode;
    final nextResults = sameMode
        ? Map<(int, int), GridCellResultSummary>.from(state.resultsByCell)
        : <(int, int), GridCellResultSummary>{};
    nextResults[(row, col)] = GridCellResultSummary.fromReport(
      row: row,
      col: col,
      report: report,
      computedAtRevision: state.planRevision,
    );
    state = state.copyWith(
      resultsByCell: nextResults,
      lastDesignedMode: mode,
    );

    return report;
  }

  /// تصميم جميع البلاطات القابلة للتصميم في السقف (جدول التسليح الكامل وخريطة النتائج)،
  /// مرتبة ترتيباً طبيعياً (S2 قبل S10) مع خانة كل بلاطة.
  List<GridSlabDesign> designAllSlabs(DesignCalculationMode mode) {
    final planWithMode = _planWithMode(mode);
    final sorted = planWithMode.cells
        .where((c) => c.cellType.isDesignableSlab)
        .toList()
      ..sort((a, b) {
        final byId = naturalCompare(a.id, b.id);
        if (byId != 0) return byId;
        return a.row != b.row ? a.row.compareTo(b.row) : a.col.compareTo(b.col);
      });

    final designs = <GridSlabDesign>[
      for (final c in sorted)
        GridSlabDesign(
          cell: c,
          report: SlabDesignPipeline.designFromFloorGridCell(
            plan: planWithMode,
            row: c.row,
            col: c.col,
          ),
        ),
    ];

    final nextResults = <(int, int), GridCellResultSummary>{
      for (final d in designs)
        (d.cell.row, d.cell.col): GridCellResultSummary.fromReport(
          row: d.cell.row,
          col: d.cell.col,
          report: d.report,
          computedAtRevision: state.planRevision,
        ),
    };

    state = state.copyWith(
      resultsByCell: nextResults,
      lastDesignedMode: mode,
      showResultsMap: true,
    );

    return designs;
  }

  void _replaceCell(FloorSlabCell updated) {
    final nextCells = state.plan.cells
        .map((c) => (c.row == updated.row && c.col == updated.col) ? updated : c)
        .toList();
    _commit(state.plan.copyWith(cells: nextCells));
  }
}

final floorGridEditorProvider =
    NotifierProvider<FloorGridEditorNotifier, FloorGridEditorState>(
  FloorGridEditorNotifier.new,
);
