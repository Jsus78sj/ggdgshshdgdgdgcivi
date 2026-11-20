import 'dart:math' as math;

import '../models/slab_enums.dart';
import '../models/slab_geometry_models.dart';
import '../models/slab_project_settings.dart';
import 'load_calculator.dart';
import 'neighborhood_builder.dart';
import 'topology_resolver.dart';

/// نتيجة استخراج بلاطة وجيرانها من المخطط الكامل للفتح في الوضع السريع
class ExtractedQuickSlab {
  final SingleSlabInput input;
  final SlabProjectSettings settings;

  const ExtractedQuickSlab({
    required this.input,
    required this.settings,
  });
}

/// نتيجة تحويل إدخال الوضع السريع («بلاطة + جيرانها») إلى مخطط كامل قابل للتحرير
class ConvertedGridPlan {
  final FloorGridPlan plan;
  final int centerRow;
  final int centerCol;

  const ConvertedGridPlan({
    required this.plan,
    required this.centerRow,
    required this.centerCol,
  });
}

/// جسر الربط الثنائي بين محرر المخطط الكامل (`FloorGridPlan`) والوضع السريع (`SingleSlabInput`)
class GridQuickBridge {
  GridQuickBridge._();

  /// استخراج بلاطة محددة بالموضع ([row], [col]) مع حوافها وجيرانها وكوابيلها
  /// من [plan] لتصميمها أو تعديلها في الوضع السريع («صمّم هذه + جيرانها»).
  static ExtractedQuickSlab extractFromFloorGrid({
    required FloorGridPlan plan,
    required int row,
    required int col,
  }) {
    final cell = plan.cellAt(row, col);
    if (cell == null) {
      throw ArgumentError('لا توجد خانة في الموضع ($row, $col).');
    }
    if (!cell.cellType.isDesignableSlab) {
      throw ArgumentError(
        'الخانة «${cell.id}» ليست بلاطة قابلة للتصميم (${cell.cellType.titleAr}).',
      );
    }

    final topEdge = TopologyResolver.resolveGridEdge(
        plan: plan, cell: cell, side: EdgeSide.top);
    final bottomEdge = TopologyResolver.resolveGridEdge(
        plan: plan, cell: cell, side: EdgeSide.bottom);
    final leftEdge = TopologyResolver.resolveGridEdge(
        plan: plan, cell: cell, side: EdgeSide.left);
    final rightEdge = TopologyResolver.resolveGridEdge(
        plan: plan, cell: cell, side: EdgeSide.right);

    final double baseLoadN = cell.customDesignLoadN ?? plan.settings.designLoadN;

    NeighborSlabInput? buildNeighbor(EdgeSide side, EdgeCondition resolvedEdge) {
      if (resolvedEdge != EdgeCondition.continuous) return null;
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
      final n = plan.cellAt(row + dr, col + dc);
      if (n == null || !n.cellType.isDesignableSlab) return null;

      final bool isVertical = side == EdgeSide.top || side == EdgeSide.bottom;
      final double spanAlong = isVertical ? plan.heightOf(n) : plan.widthOf(n);
      final double perpSpan = isVertical ? plan.widthOf(n) : plan.heightOf(n);

      final bool farCont = TopologyResolver.resolveGridEdge(
        plan: plan,
        cell: n,
        side: side,
      ).isContinuous;

      final EdgeSide latStartSide = isVertical ? EdgeSide.left : EdgeSide.top;
      final EdgeSide latEndSide = isVertical ? EdgeSide.right : EdgeSide.bottom;
      final bool latStartCont = TopologyResolver.resolveGridEdge(
        plan: plan,
        cell: n,
        side: latStartSide,
      ).isContinuous;
      final bool latEndCont = TopologyResolver.resolveGridEdge(
        plan: plan,
        cell: n,
        side: latEndSide,
      ).isContinuous;

      final nTopo = TopologyResolver.resolveFromFloorGrid(plan: plan, cell: n);
      final double nEffectiveLoad = LoadCalculator.compute(
        settings: plan.settings,
        cellType: n.cellType,
        customDesignLoadN: n.customDesignLoadN,
        fillDepthM: n.fillDepthM,
        fillUnitWeightKnM3: n.fillUnitWeightKnM3,
      ).finalDesignLoadN;

      final double? customNeighborLoad =
          (nEffectiveLoad - baseLoadN).abs() > 1e-9 ? nEffectiveLoad : null;

      return NeighborSlabInput(
        label: n.id,
        spanAlongStripM: spanAlong,
        perpendicularSpanM: perpSpan,
        isFarEndContinuous: farCont,
        panelCase: nTopo.twoWayCase,
        customDesignLoadN: customNeighborLoad,
        lateralStartContinuous: latStartCont,
        lateralEndContinuous: latEndCont,
      );
    }

    CantileverAttachment? buildCantilever(
      EdgeSide side,
      EdgeCondition resolvedEdge,
    ) {
      if (resolvedEdge != EdgeCondition.cantilever) return null;
      return cell.cantileverOn(side);
    }

    final input = SingleSlabInput(
      slabId: cell.id,
      widthXM: plan.widthOf(cell),
      heightYM: plan.heightOf(cell),
      cellType: cell.cellType,
      topEdge: topEdge,
      bottomEdge: bottomEdge,
      leftEdge: leftEdge,
      rightEdge: rightEdge,
      topNeighbor: buildNeighbor(EdgeSide.top, topEdge),
      bottomNeighbor: buildNeighbor(EdgeSide.bottom, bottomEdge),
      leftNeighbor: buildNeighbor(EdgeSide.left, leftEdge),
      rightNeighbor: buildNeighbor(EdgeSide.right, rightEdge),
      topCantilever: buildCantilever(EdgeSide.top, topEdge),
      bottomCantilever: buildCantilever(EdgeSide.bottom, bottomEdge),
      leftCantilever: buildCantilever(EdgeSide.left, leftEdge),
      rightCantilever: buildCantilever(EdgeSide.right, rightEdge),
      fillDepthM: cell.fillDepthM,
      fillUnitWeightKnM3: cell.fillUnitWeightKnM3,
      customDesignLoadN: baseLoadN,
      additionalSupportMomentKnM: plan.additionalSupportMomentKnM,
      cantileverMomentSource: plan.cantileverMomentSource,
    );

    final settings = plan.settings.copyWith(designLoadN: baseLoadN);
    return ExtractedQuickSlab(input: input, settings: settings);
  }

  /// تحويل مدخلات الوضع السريع («بلاطة + جيرانها») إلى مخطط كامل قابل للتحرير
  /// («حوّل إلى مخطط كامل») مع خانات حقيقية للمهبّط والدرج والجيران وتجاوزات حواف مرئية.
  static ConvertedGridPlan convertSingleSlabToGrid({
    required SingleSlabInput input,
    required SlabProjectSettings settings,
    String? projectId,
    String? projectName,
  }) {
    if (input.widthXM <= 0 || input.heightYM <= 0) {
      throw ArgumentError('يجب أن تكون أبعاد البلاطة أكبر من الصفر.');
    }

    final double baseLoadN = input.customDesignLoadN ?? settings.designLoadN;
    final effectiveSettings = settings.copyWith(designLoadN: baseLoadN);

    final String centerId =
        input.slabId.trim().isEmpty ? 'S1' : input.slabId.trim();
    final usedIds = <String>{centerId.toLowerCase()};

    String claimUniqueId(String rawBase) {
      final base = rawBase.trim().isEmpty ? 'S' : rawBase.trim();
      if (usedIds.add(base.toLowerCase())) return base;
      int n = 2;
      while (!usedIds.add('${base}_$n'.toLowerCase())) {
        n++;
      }
      return '${base}_$n';
    }

    // أبعاد مبدئية للمصفوفة 3×3 (تُقتطع لاحقاً الصفوف/الأعمدة الخارجية الفارغة بالكامل)
    double sideSpan(EdgeSide side, double centerSpan) {
      final edge = input.edgeFor(side);
      final n = input.neighborFor(side);
      if (edge == EdgeCondition.continuous && n != null && n.spanAlongStripM > 0) {
        return n.spanAlongStripM;
      }
      if (edge == EdgeCondition.discontinuousDropped ||
          edge == EdgeCondition.discontinuousStairwell) {
        return math.min(centerSpan, 2.50);
      }
      return centerSpan;
    }

    final xSpans3 = <double>[
      sideSpan(EdgeSide.left, input.widthXM),
      input.widthXM,
      sideSpan(EdgeSide.right, input.widthXM),
    ];
    final ySpans3 = <double>[
      sideSpan(EdgeSide.top, input.heightYM),
      input.heightYM,
      sideSpan(EdgeSide.bottom, input.heightYM),
    ];

    final centerCantilevers = <CantileverAttachment>[];
    final centerOverrides = <EdgeSide, EdgeOverride>{};
    final placed = <(int, int), FloorSlabCell>{};

    (int, int) posOf(EdgeSide side) {
      switch (side) {
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

    for (final side in EdgeSide.values) {
      final edge = input.edgeFor(side);
      final (r, c) = posOf(side);

      if (edge == EdgeCondition.cantilever) {
        final cant = input.cantileverFor(side);
        if (cant != null) {
          centerCantilevers.add(
            cant.side == side
                ? cant
                : CantileverAttachment(
                    side: side,
                    lengthM: cant.lengthM,
                    customDesignLoadN: cant.customDesignLoadN,
                    label: cant.label,
                  ),
          );
        } else {
          centerOverrides[side] = EdgeOverride.forcedContinuous;
        }
        continue;
      }

      if (edge == EdgeCondition.continuous) {
        final n = input.neighborFor(side);
        if (n == null) {
          centerOverrides[side] = EdgeOverride.forcedContinuous;
          continue;
        }

        final bool isVertical = side == EdgeSide.top || side == EdgeSide.bottom;
        final desiredEdges = NeighborhoodBuilder.neighborEdgeConditions(n, side);
        final nOverrides = <EdgeSide, EdgeOverride>{};

        // في مخطط 3×3، الحافة المشتركة (side.opposite) مستمرة طبيعياً، بينما الحواف الثلاث
        // الأخرى تقابل فراغاً خارجياً، لذا نفرض forcedContinuous لكل حافة خارجية مستمرة للجار.
        for (final s in EdgeSide.values) {
          if (s == side.opposite) continue;
          if (desiredEdges[s] == EdgeCondition.continuous) {
            nOverrides[s] = EdgeOverride.forcedContinuous;
          }
        }

        final nId = claimUniqueId(
          n.label.trim().isEmpty ? 'N_${side.name}' : n.label,
        );
        final double? overrideW = isVertical &&
                (n.perpendicularSpanM - input.widthXM).abs() > 1e-6
            ? n.perpendicularSpanM
            : null;
        final double? overrideH = !isVertical &&
                (n.perpendicularSpanM - input.heightYM).abs() > 1e-6
            ? n.perpendicularSpanM
            : null;
        final double? nCustomLoad = n.customDesignLoadN != null &&
                (n.customDesignLoadN! - baseLoadN).abs() > 1e-9
            ? n.customDesignLoadN
            : null;

        placed[(r, c)] = FloorSlabCell(
          row: r,
          col: c,
          id: nId,
          label: nId,
          cellType: input.cellType.isDesignableSlab
              ? input.cellType
              : SlabCellType.normalSolid,
          overrideWidthXM: overrideW,
          overrideHeightYM: overrideH,
          customDesignLoadN: nCustomLoad,
          edgeOverrides: nOverrides,
        );
        continue;
      }

      if (edge == EdgeCondition.discontinuousDropped) {
        final droppedType = input.cellType == SlabCellType.droppedSolid
            ? SlabCellType.normalSolid
            : SlabCellType.droppedSolid;
        final id = claimUniqueId(
          droppedType == SlabCellType.droppedSolid ? 'Dropped' : 'Normal',
        );
        placed[(r, c)] = FloorSlabCell(
          row: r,
          col: c,
          id: id,
          label: droppedType == SlabCellType.droppedSolid
              ? 'Dropped Solid Slab'
              : id,
          cellType: droppedType,
        );
        continue;
      }

      if (edge == EdgeCondition.discontinuousStairwell) {
        final id = claimUniqueId('Stair');
        placed[(r, c)] = FloorSlabCell(
          row: r,
          col: c,
          id: id,
          label: 'Staircase',
          cellType: SlabCellType.stairwellOrVoid,
        );
      }
    }

    placed[(1, 1)] = FloorSlabCell(
      row: 1,
      col: 1,
      id: centerId,
      label: centerId,
      cellType: input.cellType,
      fillDepthM: input.fillDepthM,
      fillUnitWeightKnM3: input.fillUnitWeightKnM3,
      cantilevers: centerCantilevers,
      edgeOverrides: centerOverrides,
    );

    // اقتطاع الصفوف والأعمدة الخارجية الفارغة بالكامل لجعل المخطط نظيفاً ومركزاً
    final activeRows = <int>[
      for (int r = 0; r < 3; r++)
        if (placed.keys.any((k) => k.$1 == r)) r,
    ];
    final activeCols = <int>[
      for (int c = 0; c < 3; c++)
        if (placed.keys.any((k) => k.$2 == c)) c,
    ];

    final finalXSpans = [for (final c in activeCols) xSpans3[c]];
    final finalYSpans = [for (final r in activeRows) ySpans3[r]];
    final finalCells = <FloorSlabCell>[];

    for (int nr = 0; nr < activeRows.length; nr++) {
      final origR = activeRows[nr];
      for (int nc = 0; nc < activeCols.length; nc++) {
        final origC = activeCols[nc];
        final existing = placed[(origR, origC)];
        if (existing != null) {
          finalCells.add(existing.copyWith(row: nr, col: nc));
        } else {
          final voidId = claimUniqueId('Void_${nr}_$nc');
          finalCells.add(
            FloorSlabCell(
              row: nr,
              col: nc,
              id: voidId,
              label: 'فراغ',
              cellType: SlabCellType.exteriorEmpty,
            ),
          );
        }
      }
    }

    final plan = FloorGridPlan(
      projectId: projectId ?? 'proj_${DateTime.now().microsecondsSinceEpoch}',
      projectName: projectName ?? 'مخطط $centerId',
      xSpansM: finalXSpans,
      ySpansM: finalYSpans,
      cells: finalCells,
      settings: effectiveSettings,
      additionalSupportMomentKnM: input.additionalSupportMomentKnM,
      cantileverMomentSource: input.cantileverMomentSource,
    );

    return ConvertedGridPlan(
      plan: plan,
      centerRow: activeRows.indexOf(1),
      centerCol: activeCols.indexOf(1),
    );
  }
}
