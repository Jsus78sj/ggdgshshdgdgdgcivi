import '../models/slab_enums.dart';
import '../models/slab_geometry_models.dart';
import 'topology_resolver.dart';

/// خطورة مشكلة في المخطط: الخطأ يمنع التصميم، والتحذير لا يمنعه.
enum GridIssueSeverity { error, warning }

enum GridIssueCode {
  emptyId,
  duplicateId,
  duplicateCoordinates,
  cellOutOfBounds,
  missingCell,
  nonPositiveSpan,
  nonPositiveOverride,
  nonPositiveCantilever,
  sharedEdgeLengthMismatch,
  cantileverOnInteriorEdge,
  forcedContinuousWithoutNeighbor,
  asymmetricEdgeOverride,
  noDesignableSlab,
}

/// مشكلة واحدة؛ [row] و[col] (إن وُجدا) يشيران إلى الخانة الرئيسية لتحديدها على المخطط.
class GridValidationIssue {
  final GridIssueSeverity severity;
  final GridIssueCode code;
  final String messageAr;
  final int? row;
  final int? col;

  const GridValidationIssue({
    required this.severity,
    required this.code,
    required this.messageAr,
    this.row,
    this.col,
  });

  bool get isError => severity == GridIssueSeverity.error;
}

class GridValidationReport {
  final List<GridValidationIssue> issues;
  const GridValidationReport(this.issues);

  List<GridValidationIssue> get errors =>
      issues.where((i) => i.isError).toList();
  List<GridValidationIssue> get warnings =>
      issues.where((i) => !i.isError).toList();

  bool get hasErrors => issues.any((i) => i.isError);
  bool get isClean => issues.isEmpty;
}

/// فاحص سلامة المخطط الشبكي قبل التصميم (لا يغيّر المخطط ولا يستدعي المحرك الهندسي).
class GridValidator {
  GridValidator._();

  /// فرق أطوال الحافة المشتركة المسموح به (m) قبل إصدار تحذير
  static const double edgeLengthToleranceM = 0.005;

  static String _pos(int row, int col) => 'الصف ${row + 1}، العمود ${col + 1}';

  /// أول خانة (غير الخانة [row],[col]) تستعمل المعرّف [candidateId] (مقارنة بلا حساسية للحالة).
  static FloorSlabCell? findIdConflict(
    FloorGridPlan plan, {
    required int row,
    required int col,
    required String candidateId,
  }) {
    final key = candidateId.trim().toLowerCase();
    if (key.isEmpty) return null;
    for (final c in plan.cells) {
      if (c.row == row && c.col == col) continue;
      if (c.id.trim().toLowerCase() == key) return c;
    }
    return null;
  }

  static GridValidationReport validate(FloorGridPlan plan) {
    final issues = <GridValidationIssue>[];

    void add(
      GridIssueSeverity s,
      GridIssueCode code,
      String msg, {
      int? row,
      int? col,
    }) {
      issues.add(GridValidationIssue(
        severity: s,
        code: code,
        messageAr: msg,
        row: row,
        col: col,
      ));
    }

    var structuralOk = true;

    // 1) أطوال المحاور
    for (var i = 0; i < plan.xSpansM.length; i++) {
      final v = plan.xSpansM[i];
      if (!(v > 0) || v.isNaN || v.isInfinite) {
        structuralOk = false;
        add(GridIssueSeverity.error, GridIssueCode.nonPositiveSpan,
            'طول المحور الأفقي رقم ${i + 1} غير صالح ($v).');
      }
    }
    for (var i = 0; i < plan.ySpansM.length; i++) {
      final v = plan.ySpansM[i];
      if (!(v > 0) || v.isNaN || v.isInfinite) {
        structuralOk = false;
        add(GridIssueSeverity.error, GridIssueCode.nonPositiveSpan,
            'طول المحور الرأسي رقم ${i + 1} غير صالح ($v).');
      }
    }

    // 2) إحداثيات الخانات
    final byPos = <String, FloorSlabCell>{};
    for (final c in plan.cells) {
      final inBounds = c.row >= 0 &&
          c.row < plan.rowsCount &&
          c.col >= 0 &&
          c.col < plan.colsCount;
      if (!inBounds) {
        structuralOk = false;
        add(GridIssueSeverity.error, GridIssueCode.cellOutOfBounds,
            'الخانة «${c.id}» خارج حدود الشبكة (${c.row + 1}، ${c.col + 1}).');
        continue;
      }
      final key = '${c.row},${c.col}';
      if (byPos.containsKey(key)) {
        structuralOk = false;
        add(
          GridIssueSeverity.error,
          GridIssueCode.duplicateCoordinates,
          'خانتان في الموضع نفسه (${_pos(c.row, c.col)}): «${byPos[key]!.id}» و«${c.id}».',
          row: c.row,
          col: c.col,
        );
      } else {
        byPos[key] = c;
      }
    }
    for (var r = 0; r < plan.rowsCount; r++) {
      for (var c = 0; c < plan.colsCount; c++) {
        if (!byPos.containsKey('$r,$c')) {
          structuralOk = false;
          add(GridIssueSeverity.error, GridIssueCode.missingCell,
              'لا توجد خانة في ${_pos(r, c)}.',
              row: r, col: c);
        }
      }
    }

    // 3) المعرّفات
    final byId = <String, List<FloorSlabCell>>{};
    for (final c in byPos.values) {
      final trimmed = c.id.trim();
      if (trimmed.isEmpty) {
        add(GridIssueSeverity.error, GridIssueCode.emptyId,
            'معرّف الخانة في ${_pos(c.row, c.col)} فارغ.',
            row: c.row, col: c.col);
        continue;
      }
      byId.putIfAbsent(trimmed.toLowerCase(), () => []).add(c);
    }
    for (final group in byId.values) {
      if (group.length < 2) continue;
      final where = group.map((c) => _pos(c.row, c.col)).join(' • ');
      add(
        GridIssueSeverity.error,
        GridIssueCode.duplicateId,
        'المعرّف «${group.first.id}» مكرر في ${group.length} خانات: $where.',
        row: group.first.row,
        col: group.first.col,
      );
    }

    // 4) قيم الخانات
    for (final c in byPos.values) {
      if (c.overrideWidthXM != null && !(c.overrideWidthXM! > 0)) {
        add(GridIssueSeverity.error, GridIssueCode.nonPositiveOverride,
            'العرض المخصص للخانة «${c.id}» يجب أن يكون أكبر من الصفر.',
            row: c.row, col: c.col);
      }
      if (c.overrideHeightYM != null && !(c.overrideHeightYM! > 0)) {
        add(GridIssueSeverity.error, GridIssueCode.nonPositiveOverride,
            'الطول المخصص للخانة «${c.id}» يجب أن يكون أكبر من الصفر.',
            row: c.row, col: c.col);
      }
      for (final cant in c.cantilevers) {
        if (!(cant.lengthM > 0)) {
          add(GridIssueSeverity.error, GridIssueCode.nonPositiveCantilever,
              'طول الكابولي (${cant.side.titleAr}) في «${c.id}» يجب أن يكون أكبر من الصفر.',
              row: c.row, col: c.col);
        }
      }
    }

    if (!byPos.values.any((c) => c.cellType.isDesignableSlab)) {
      add(GridIssueSeverity.warning, GridIssueCode.noDesignableSlab,
          'لا توجد أي بلاطة قابلة للتصميم في المخطط.');
    }

    // 5) فحوص هندسية (تُتخطى إن كانت البنية نفسها معطوبة لأنها تقرأ المحاور)
    if (structuralOk) {
      FloorSlabCell? at(int r, int c) => byPos['$r,$c'];

      // 5.أ) حافة «مستمرة» بين بلاطتين طول حافتهما المشتركة مختلف
      for (final a in byPos.values) {
        if (!a.cellType.isDesignableSlab) continue;

        final right = at(a.row, a.col + 1);
        if (right != null &&
            right.cellType.isDesignableSlab &&
            a.cantileverOn(EdgeSide.right) == null &&
            right.cantileverOn(EdgeSide.left) == null &&
            TopologyResolver.resolveGridEdge(
              plan: plan,
              cell: a,
              side: EdgeSide.right,
            ).isContinuous &&
            TopologyResolver.resolveGridEdge(
              plan: plan,
              cell: right,
              side: EdgeSide.left,
            ).isContinuous) {
          final ha = plan.heightOf(a);
          final hb = plan.heightOf(right);
          if ((ha - hb).abs() > edgeLengthToleranceM) {
            add(
              GridIssueSeverity.warning,
              GridIssueCode.sharedEdgeLengthMismatch,
              'الحافة المشتركة بين «${a.id}» و«${right.id}» تُعدّ مستمرة لكن طولاها مختلفان '
              '(${ha.toStringAsFixed(2)} م مقابل ${hb.toStringAsFixed(2)} م).',
              row: a.row,
              col: a.col,
            );
          }
        }

        final below = at(a.row + 1, a.col);
        if (below != null &&
            below.cellType.isDesignableSlab &&
            a.cantileverOn(EdgeSide.bottom) == null &&
            below.cantileverOn(EdgeSide.top) == null &&
            TopologyResolver.resolveGridEdge(
              plan: plan,
              cell: a,
              side: EdgeSide.bottom,
            ).isContinuous &&
            TopologyResolver.resolveGridEdge(
              plan: plan,
              cell: below,
              side: EdgeSide.top,
            ).isContinuous) {
          final wa = plan.widthOf(a);
          final wb = plan.widthOf(below);
          if ((wa - wb).abs() > edgeLengthToleranceM) {
            add(
              GridIssueSeverity.warning,
              GridIssueCode.sharedEdgeLengthMismatch,
              'الحافة المشتركة بين «${a.id}» و«${below.id}» تُعدّ مستمرة لكن طولاها مختلفان '
              '(${wa.toStringAsFixed(2)} م مقابل ${wb.toStringAsFixed(2)} م).',
              row: a.row,
              col: a.col,
            );
          }
        }
      }

      // 5.ب) كابولي على حافة داخلية يقابلها جار في الشبكة
      for (final a in byPos.values) {
        if (!a.cellType.isDesignableSlab) continue;
        for (final cant in a.cantilevers) {
          final dr = cant.side == EdgeSide.top
              ? -1
              : cant.side == EdgeSide.bottom
                  ? 1
                  : 0;
          final dc = cant.side == EdgeSide.left
              ? -1
              : cant.side == EdgeSide.right
                  ? 1
                  : 0;
          final n = at(a.row + dr, a.col + dc);
          if (n != null && n.cellType != SlabCellType.exteriorEmpty) {
            add(
              GridIssueSeverity.warning,
              GridIssueCode.cantileverOnInteriorEdge,
              'كابولي (${cant.side.titleAr}) في «${a.id}» يقابله جار «${n.id}» في الشبكة؛ '
              'تُعامل الحافة ككابولي ويُهمل الجار في الموازنة.',
              row: a.row,
              col: a.col,
            );
          }
        }
      }

      // 5.ج) فحص تجاوزات الحواف اليدوية (EdgeOverride)
      for (final a in byPos.values) {
        if (!a.cellType.isDesignableSlab || a.edgeOverrides.isEmpty) continue;
        for (final entry in a.edgeOverrides.entries) {
          final side = entry.key;
          final ov = entry.value;
          final dr = side == EdgeSide.top
              ? -1
              : side == EdgeSide.bottom
                  ? 1
                  : 0;
          final dc = side == EdgeSide.left
              ? -1
              : side == EdgeSide.right
                  ? 1
                  : 0;
          final n = at(a.row + dr, a.col + dc);

          if (ov == EdgeOverride.forcedContinuous &&
              (n == null || !n.cellType.isDesignableSlab)) {
            add(
              GridIssueSeverity.warning,
              GridIssueCode.forcedContinuousWithoutNeighbor,
              'فُرضت استمرارية على ${side.titleAr} في «${a.id}» دون وجود بلاطة مجاورة قابلة للتصميم؛ '
              'سيبقى العزم السالب الأولي بدون موازنة مع جار.',
              row: a.row,
              col: a.col,
            );
          }

          if (n != null && n.cellType.isDesignableSlab) {
            final condA = TopologyResolver.resolveGridEdge(
              plan: plan,
              cell: a,
              side: side,
            );
            final condB = TopologyResolver.resolveGridEdge(
              plan: plan,
              cell: n,
              side: side.opposite,
            );
            if (condA.isContinuous != condB.isContinuous &&
                (side == EdgeSide.right ||
                    side == EdgeSide.bottom ||
                    !n.edgeOverrides.containsKey(side.opposite))) {
              add(
                GridIssueSeverity.warning,
                GridIssueCode.asymmetricEdgeOverride,
                'الحافة المشتركة بين «${a.id}» و«${n.id}» غير متماثلة في التجاوز '
                '(${condA.isContinuous ? "مستمرة" : "غير مستمرة"} مقابل '
                '${condB.isContinuous ? "مستمرة" : "غير مستمرة"}).',
                row: a.row,
                col: a.col,
              );
            }
          }
        }
      }
    }

    // الأخطاء أولاً مع الحفاظ على الترتيب الداخلي
    final errors = issues.where((i) => i.isError).toList();
    final warnings = issues.where((i) => !i.isError).toList();
    return GridValidationReport([...errors, ...warnings]);
  }
}
