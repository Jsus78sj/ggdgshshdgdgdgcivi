import 'dart:math' as math;
import '../../data/bs8110/slab_moment_shear_tables.dart';
import '../models/slab_design_report.dart';
import '../models/slab_enums.dart';
import '../models/slab_geometry_models.dart';
import '../models/slab_project_settings.dart';
import 'topology_resolver.dart';

/// معطيات يحتاجها الموازن في الوضع السريع ولا يمكن استنتاجها من المخطط المصغّر نفسه.
class NeighborhoodHints {
  /// عزم سالب مُدخل مباشرة للجار عند الحافة [EdgeSide] (يحل محل الحساب من Table 3.14)
  final Map<EdgeSide, double> givenNeighborMomentKnMBySide;

  /// رقم Case المفترض للجار عند الحافة (للتحذير) عندما لم يحدّده المستخدم
  final Map<EdgeSide, int> assumedCaseBySide;

  const NeighborhoodHints({
    this.givenNeighborMomentKnMBySide = const {},
    this.assumedCaseBySide = const {},
  });
}

/// حواف الجار الأربع بعد الحل: الحافة المشتركة مع البلاطة المدروسة مستمرة دائماً.
class ResolvedNeighborEdges {
  /// الطرف البعيد للجار (المقابل للحافة المشتركة)
  final bool farContinuous;

  /// الحافتان الجانبيتان (الموازيتان للشريحة): البداية = اليسرى (جار علوي/سفلي) أو العلوية
  /// (جار أيسر/أيمن)، والنهاية = المقابلة لها.
  final bool lateralStartContinuous;
  final bool lateralEndContinuous;

  /// true إذا كانت الحافتان الجانبيتان محدّدتين صراحةً من المستخدم
  final bool isExplicit;

  /// تنبيه عند تعارض حالة الجار المدخلة مع حالة طرفه البعيد (إن وُجد)
  final String? conflictNoteAr;

  const ResolvedNeighborEdges({
    required this.farContinuous,
    required this.lateralStartContinuous,
    required this.lateralEndContinuous,
    required this.isExplicit,
    this.conflictNoteAr,
  });
}

/// مخطط الجوار المصغّر الناتج: شبكة 3×3 مركزها البلاطة المدروسة.
class NeighborhoodPlan {
  final FloorGridPlan plan;
  final int centerRow;
  final int centerCol;
  final NeighborhoodHints hints;

  /// ملاحظات تُضاف إلى تحذيرات التقرير (مثل تعارض حالة الجار مع طرفه البعيد)
  final List<String> notesAr;

  const NeighborhoodPlan({
    required this.plan,
    required this.centerRow,
    required this.centerCol,
    required this.hints,
    this.notesAr = const [],
  });
}

/// يحوّل مدخلات الوضع السريع «بلاطة + جيرانها» ([SingleSlabInput]) إلى [FloorGridPlan]
/// مصغّر 3×3 كي يمرّ التصميم عبر المسار نفسه الذي يستعمله المخطط الكامل
/// (`SlabDesignPipeline.designFromFloorGridCell` + `MomentBalancer.balanceInFloorGrid`).
///
/// البنية: البلاطة المدروسة في الخانة (1,1)، وجيرانها الأربعة في (0,1) و(2,1) و(1,0) و(1,2)،
/// والأركان وأي جار غائب خانات `exteriorEmpty`. حالة كل حافة للبلاطة المدروسة ولكل جار تُفرض
/// مباشرة عبر [FloorSlabCell.edgeConditionOverrides]، لأن حافتين متجاورتين على ركن مشترك لا
/// يمكن أن تُستنتجا مستقلتين من الخانات وحدها.
class NeighborhoodBuilder {
  NeighborhoodBuilder._();

  static const int centerRow = 1;
  static const int centerCol = 1;

  static bool _isVertical(EdgeSide side) =>
      side == EdgeSide.top || side == EdgeSide.bottom;

  /// عدد الحواف القصيرة والطويلة غير المستمرة لكل Case في Table 3.14
  static (int, int) _discCounts(TwoWayPanelCase c) {
    switch (c) {
      case TwoWayPanelCase.interiorPanels:
        return (0, 0);
      case TwoWayPanelCase.oneShortEdgeDiscontinuous:
        return (1, 0);
      case TwoWayPanelCase.oneLongEdgeDiscontinuous:
        return (0, 1);
      case TwoWayPanelCase.twoAdjacentEdgesDiscontinuous:
        return (1, 1);
      case TwoWayPanelCase.twoShortEdgesDiscontinuous:
        return (2, 0);
      case TwoWayPanelCase.twoLongEdgesDiscontinuous:
        return (0, 2);
      case TwoWayPanelCase.threeEdgesDiscontinuousOneLongContinuous:
        return (2, 1);
      case TwoWayPanelCase.threeEdgesDiscontinuousOneShortContinuous:
        return (1, 2);
      case TwoWayPanelCase.fourEdgesDiscontinuous:
        return (2, 2);
    }
  }

  /// حواف الجار الأربع للجار المتصل بالحافة [side] من البلاطة المدروسة.
  ///
  /// - إذا حُدِّدت الحافتان الجانبيتان صراحةً تُستعملان كما هما.
  /// - وإلا تُحوَّل [NeighborSlabInput.effectivePanelCase] إلى حافتين جانبيتين بحيث يعطي
  ///   التحليل الهندسي للجار نفس Case، مع احترام حالة الطرف البعيد (تؤثر في الجساءة).
  ///   الحافة المشتركة مستمرة دائماً، لذا إن تعارضت الحالة المدخلة مع الطرف البعيد
  ///   (مثل Case 2 مع طرف بعيد مستمر) يُعتمد الطرف البعيد وتُقرَّب الحافتان الجانبيتان.
  static ResolvedNeighborEdges edgesFor(NeighborSlabInput n, EdgeSide side) {
    final bool farCont = n.isFarEndContinuous;

    if (n.hasExplicitLaterals) {
      return ResolvedNeighborEdges(
        farContinuous: farCont,
        lateralStartContinuous: n.lateralStartContinuous!,
        lateralEndContinuous: n.lateralEndContinuous!,
        isExplicit: true,
      );
    }

    final double a = n.spanAlongStripM;
    final double p = n.perpendicularSpanM;
    final double lo = math.min(a, p);
    final double hi = math.max(a, p);

    // اتجاه واحد: الحالة غير مستخدمة، والحافتان الجانبيتان لا تؤثران في العزم
    if (lo > 0 && hi / lo > 2.0) {
      return ResolvedNeighborEdges(
        farContinuous: farCont,
        lateralStartContinuous: true,
        lateralEndContinuous: true,
        isExplicit: false,
      );
    }

    final (int reqShort, int reqLong) = _discCounts(n.effectivePanelCase);
    final int farDisc = farCont ? 0 : 1;

    // الحافة المشتركة والطرف البعيد طولهما = البعد العمودي p.
    // إذا كان p أصغر من a فهما «قصيرتان» والجانبيتان «طويلتان»، والعكس إن كان p أكبر.
    (int, bool) attempt(bool sharedFarAreShort) => sharedFarAreShort
        ? (reqLong, reqShort != farDisc)
        : (reqShort, reqLong != farDisc);

    int lateralDisc;
    bool conflict;
    if ((a - p).abs() < 1e-9) {
      // جار مربع: تسمية «قصيرة/طويلة» اعتباطية. الافتراض «قصيرة» (يوافق
      // NeighborSlabInput.inferredPanelCase ومسار الوضع السريع القديم) في الاتجاهين الأفقي
      // والرأسي، فلا يظهر تعارض وهمي للجار الأيسر/الأيمن؛ وإن تعارضت الحالة المدخلة معه
      // نجرّب العكس. بعدها يطبّق TopologyResolver قاعدة البلاطة المربعة نفسها (الأعلى معاملاً).
      (lateralDisc, conflict) = attempt(true);
      if (conflict) {
        final (int ld2, bool conflict2) = attempt(false);
        if (!conflict2) {
          lateralDisc = ld2;
          conflict = conflict2;
        }
      }
    } else {
      (lateralDisc, conflict) = attempt(p < a);
    }
    lateralDisc = math.min(2, math.max(0, lateralDisc));

    String? note;
    if (conflict) {
      note = 'الجار ${n.label} (${side.titleAr}): حالته المحدّدة Case '
          '${n.effectivePanelCase.caseNumber} لا تتفق مع كون طرفه البعيد '
          '${farCont ? 'مستمراً' : 'غير مستمر'} (الحافة المشتركة مستمرة دائماً)؛ '
          'اعتُمد الطرف البعيد وضُبطت الحافتان الجانبيتان لأقرب حالة ممكنة. '
          'عدّل حواف الجار الأربع لتثبيتها.';
    }

    // نجعل «البداية» غير المستمرة أولاً عند وجود حافة جانبية واحدة غير مستمرة
    return ResolvedNeighborEdges(
      farContinuous: farCont,
      lateralStartContinuous: lateralDisc < 1,
      lateralEndContinuous: lateralDisc < 2,
      isExplicit: false,
      conflictNoteAr: note,
    );
  }

  /// حالات حواف الجار الأربع بالنسبة للمخطط (الحافة المشتركة مستمرة).
  static Map<EdgeSide, EdgeCondition> neighborEdgeConditions(
    NeighborSlabInput n,
    EdgeSide side,
  ) {
    final e = edgesFor(n, side);
    EdgeCondition c(bool continuous) =>
        continuous ? EdgeCondition.continuous : EdgeCondition.discontinuousFree;

    switch (side) {
      case EdgeSide.top:
        // الجار فوق البلاطة: حافته السفلية مشتركة وعلويته هي الطرف البعيد
        return {
          EdgeSide.bottom: EdgeCondition.continuous,
          EdgeSide.top: c(e.farContinuous),
          EdgeSide.left: c(e.lateralStartContinuous),
          EdgeSide.right: c(e.lateralEndContinuous),
        };
      case EdgeSide.bottom:
        return {
          EdgeSide.top: EdgeCondition.continuous,
          EdgeSide.bottom: c(e.farContinuous),
          EdgeSide.left: c(e.lateralStartContinuous),
          EdgeSide.right: c(e.lateralEndContinuous),
        };
      case EdgeSide.left:
        return {
          EdgeSide.right: EdgeCondition.continuous,
          EdgeSide.left: c(e.farContinuous),
          EdgeSide.top: c(e.lateralStartContinuous),
          EdgeSide.bottom: c(e.lateralEndContinuous),
        };
      case EdgeSide.right:
        return {
          EdgeSide.left: EdgeCondition.continuous,
          EdgeSide.right: c(e.farContinuous),
          EdgeSide.top: c(e.lateralStartContinuous),
          EdgeSide.bottom: c(e.lateralEndContinuous),
        };
    }
  }

  /// تحليل طوبولوجية الجار منفرداً (لعرض Case المشتق من حوافه في بطاقة الجار).
  /// يرمي [ArgumentError] إذا كان أحد بعديه غير موجب.
  static ResolvedTopology resolveNeighborTopology(
    NeighborSlabInput n,
    EdgeSide side,
  ) {
    final edges = neighborEdgeConditions(n, side);
    final bool vertical = _isVertical(side);
    return TopologyResolver.resolveFromEdges(
      slabId: n.label,
      cellType: SlabCellType.normalSolid,
      widthXM: vertical ? n.perpendicularSpanM : n.spanAlongStripM,
      heightYM: vertical ? n.spanAlongStripM : n.perpendicularSpanM,
      topEdge: edges[EdgeSide.top]!,
      bottomEdge: edges[EdgeSide.bottom]!,
      leftEdge: edges[EdgeSide.left]!,
      rightEdge: edges[EdgeSide.right]!,
    );
  }

  /// هل يلزم وضع خانة جار عند الحافة [side]؟ (مطابق لشرط المسار القديم: حافة مستمرة
  /// وبيانات جار موجودة، والحافة ليست كابولياً له تصميم خاص).
  static bool _needsNeighbor(SingleSlabInput input, EdgeSide side) {
    final edge = input.edgeFor(side);
    if (!edge.isContinuous) return false;
    if (input.neighborFor(side) == null) return false;
    if (edge == EdgeCondition.cantilever && input.cantileverFor(side) != null) {
      return false;
    }
    return true;
  }

  /// رقم Case المفترض للجار (للتحذير)، أو null إذا حدّده المستخدم أو أُدخل عزمه مباشرة
  /// أو كان يعمل باتجاه واحد.
  static int? _assumedCaseNumber(NeighborSlabInput n) {
    if (!n.isPanelCaseAssumed || n.overrideNegativeMomentKnM != null) {
      return null;
    }
    final lo = math.min(n.spanAlongStripM, n.perpendicularSpanM);
    final hi = math.max(n.spanAlongStripM, n.perpendicularSpanM);
    if (hi / lo > 2.0) return null;
    return n.effectivePanelCase.caseNumber;
  }

  /// بناء المخطط المصغّر. يرمي [ArgumentError] لأبعاد غير موجبة (كالمسار القديم).
  static NeighborhoodPlan build({
    required SingleSlabInput input,
    required SlabProjectSettings settings,
  }) {
    final double w = input.widthXM;
    final double h = input.heightYM;

    // الحمل الأساسي للجار الذي لم يُحدَّد له حمل مخصص: لا ردم هذه البلاطة ولا وزنها الإضافي
    final double neighborBaseLoadN =
        input.customDesignLoadN ?? settings.designLoadN;

    final Map<EdgeSide, bool> hasNeighbor = {
      for (final s in EdgeSide.values) s: _needsNeighbor(input, s),
    };

    // أبعاد الصفوف والأعمدة: الجار يأخذ بحره بالشريحة، والغائب يأخذ بُعد البلاطة المدروسة
    double along(EdgeSide s, double fallback) =>
        hasNeighbor[s]! ? input.neighborFor(s)!.spanAlongStripM : fallback;

    final List<double> xSpans = [
      along(EdgeSide.left, w),
      w,
      along(EdgeSide.right, w),
    ];
    final List<double> ySpans = [
      along(EdgeSide.top, h),
      h,
      along(EdgeSide.bottom, h),
    ];

    final List<String> notes = [];
    final Map<EdgeSide, double> givenMoments = {};
    final Map<EdgeSide, int> assumedCases = {};

    FloorSlabCell empty(int row, int col) => FloorSlabCell(
          row: row,
          col: col,
          id: '_ext_${row}_$col',
          label: '',
          cellType: SlabCellType.exteriorEmpty,
        );

    final cells = <FloorSlabCell>[];

    // البلاطة المدروسة: حواف الإدخال تُفرض كما هي، والكوابيل تُربط بحافتها
    final List<CantileverAttachment> cants = [];
    for (final side in EdgeSide.values) {
      final c = input.cantileverFor(side);
      if (c == null) continue;
      cants.add(
        c.side == side
            ? c
            : CantileverAttachment(
                side: side,
                lengthM: c.lengthM,
                customDesignLoadN: c.customDesignLoadN,
                label: c.label,
              ),
      );
    }

    final center = FloorSlabCell(
      row: centerRow,
      col: centerCol,
      id: input.slabId,
      label: input.slabId,
      cellType: input.cellType,
      customDesignLoadN: input.customDesignLoadN,
      fillDepthM: input.fillDepthM,
      fillUnitWeightKnM3: input.fillUnitWeightKnM3,
      cantilevers: cants,
      edgeConditionOverrides: {
        for (final s in EdgeSide.values) s: input.edgeFor(s),
      },
    );

    // موضع خانة كل جار حول المركز
    (int, int) posOf(EdgeSide s) {
      switch (s) {
        case EdgeSide.top:
          return (0, 1);
        case EdgeSide.bottom:
          return (2, 1);
        case EdgeSide.left:
          return (1, 0);
        case EdgeSide.right:
          return (1, 2);
      }
    }

    final Map<(int, int), FloorSlabCell> placed = {
      (centerRow, centerCol): center,
    };

    for (final side in EdgeSide.values) {
      if (!hasNeighbor[side]!) continue;
      final n = input.neighborFor(side)!;
      final (r, c) = posOf(side);
      final edges = edgesFor(n, side);
      if (edges.conflictNoteAr != null) notes.add(edges.conflictNoteAr!);

      if (n.overrideNegativeMomentKnM != null) {
        givenMoments[side] = n.overrideNegativeMomentKnM!;
      }
      final assumed = _assumedCaseNumber(n);
      if (assumed != null) assumedCases[side] = assumed;

      final bool vertical = _isVertical(side);
      placed[(r, c)] = FloorSlabCell(
        row: r,
        col: c,
        id: n.label,
        label: n.label,
        cellType: SlabCellType.normalSolid,
        // البعد العمودي على الشريحة يُفرض على الخانة لأن عمود/صف الجار مشترك مع المركز
        overrideWidthXM: vertical ? n.perpendicularSpanM : null,
        overrideHeightYM: vertical ? null : n.perpendicularSpanM,
        customDesignLoadN: n.customDesignLoadN ?? neighborBaseLoadN,
        edgeConditionOverrides: neighborEdgeConditions(n, side),
      );
    }

    for (var r = 0; r < 3; r++) {
      for (var c = 0; c < 3; c++) {
        cells.add(placed[(r, c)] ?? empty(r, c));
      }
    }

    final plan = FloorGridPlan(
      projectId: 'quick_neighborhood_${input.slabId}',
      projectName: 'جوار ${input.slabId}',
      xSpansM: xSpans,
      ySpansM: ySpans,
      cells: cells,
      settings: settings,
      additionalSupportMomentKnM: input.additionalSupportMomentKnM,
      cantileverMomentSource: input.cantileverMomentSource,
    );

    return NeighborhoodPlan(
      plan: plan,
      centerRow: centerRow,
      centerCol: centerCol,
      hints: NeighborhoodHints(
        givenNeighborMomentKnMBySide: givenMoments,
        assumedCaseBySide: assumedCases,
      ),
      notesAr: notes,
    );
  }
}
