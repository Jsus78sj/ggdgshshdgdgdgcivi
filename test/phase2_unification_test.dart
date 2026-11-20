import 'package:bs8110_slab_designer/core/constants/design_mode.dart';
import 'package:bs8110_slab_designer/data/bs8110/slab_moment_shear_tables.dart';
import 'package:bs8110_slab_designer/domain/engine/engineering_engine.dart';
import 'package:bs8110_slab_designer/presentation/providers/single_slab_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// المرحلة 2 — توحيد مساري التصميم.
///
/// **شرط القبول:** نتائج قالبَي S7 وS6 في الوضع السريع متطابقة قبل التوحيد
/// (`designSingleSlabLegacy` + `MomentBalancer.balanceForSingleSlab`) وبعده
/// (`designSingleSlab` = `NeighborhoodBuilder` + `designFromFloorGridCell`) في العزوم والحديد
/// والهطول (وكذلك القص والملخص والتحذيرات).
///
/// الأعداد الحقيقية تُقارن بتسامح 1e-9 لأن ترتيب عمليات الضرب يختلف بين المسارين
/// (β·n·lx·lx مقابل β·(n·lx·lx)) فقد يختلف آخر بت عشري؛ أما النصوص (تسليح، ملخص، تحذيرات)
/// والمنطقيات (آمن/غير آمن) والأعداد الصحيحة فتُقارن بالتساوي التام.
void main() {
  const double tol = 1e-9;

  // ---------------------------------------------------------------------------
  // أدوات
  // ---------------------------------------------------------------------------
  SingleSlabFormState presetS7() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(singleSlabFormProvider.notifier).loadExamPresetS7();
    return c.read(singleSlabFormProvider);
  }

  SingleSlabFormState presetS6() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(singleSlabFormProvider.notifier).loadExamPresetS6WithCantilever();
    return c.read(singleSlabFormProvider);
  }

  /// نسخة من المدخلات بحمل مخصص مختلف (يحاكي ما يفعله `runDesign` عند تغيير السماكة).
  SingleSlabInput withLoad(SingleSlabInput i, double loadN) => SingleSlabInput(
        slabId: i.slabId,
        widthXM: i.widthXM,
        heightYM: i.heightYM,
        cellType: i.cellType,
        topEdge: i.topEdge,
        bottomEdge: i.bottomEdge,
        leftEdge: i.leftEdge,
        rightEdge: i.rightEdge,
        topNeighbor: i.topNeighbor,
        bottomNeighbor: i.bottomNeighbor,
        leftNeighbor: i.leftNeighbor,
        rightNeighbor: i.rightNeighbor,
        topCantilever: i.topCantilever,
        bottomCantilever: i.bottomCantilever,
        leftCantilever: i.leftCantilever,
        rightCantilever: i.rightCantilever,
        fillDepthM: i.fillDepthM,
        fillUnitWeightKnM3: i.fillUnitWeightKnM3,
        customDesignLoadN: loadN,
        additionalSupportMomentKnM: i.additionalSupportMomentKnM,
        cantileverMomentSource: i.cantileverMomentSource,
      );

  void near(double? a, double? b, String reason) {
    if (a == null || b == null) {
      expect(a, b, reason: reason);
    } else {
      expect(a, closeTo(b, tol), reason: reason);
    }
  }

  void sameSteel(
    SectionReinforcementDesign a,
    SectionReinforcementDesign b,
    String where,
  ) {
    expect(a.zoneId, b.zoneId, reason: where);
    near(a.designMomentKnM, b.designMomentKnM, '$where moment');
    near(a.asRequiredMm2, b.asRequiredMm2, '$where As,req');
    near(a.asGoverningMm2, b.asGoverningMm2, '$where As,gov');
    near(a.compressionSteelMm2, b.compressionSteelMm2, '$where A\'sc');
    expect(a.requiresDoublyReinforced, b.requiresDoublyReinforced,
        reason: '$where doubly');
    expect(a.barCountSelection.lectureNotation, b.barCountSelection.lectureNotation,
        reason: '$where bars');
    near(a.barCountSelection.areaProvidedMm2, b.barCountSelection.areaProvidedMm2,
        '$where area');
    expect(a.barSpacingSelection?.standardNotation,
        b.barSpacingSelection?.standardNotation,
        reason: '$where spacing');
    expect(a.isAreaSufficient, b.isAreaSufficient, reason: '$where sufficient');
    expect(a.isSpacingSafe, b.isSpacingSafe, reason: '$where spacing safe');
  }

  void sameDeflection(DeflectionCheckResult a, DeflectionCheckResult b, String w) {
    expect(a.isSafe, b.isSafe, reason: '$w isSafe');
    near(a.basicRatioBR, b.basicRatioBR, '$w B.R');
    near(a.serviceStressFs, b.serviceStressFs, '$w fs');
    near(a.rawModificationFactor, b.rawModificationFactor, '$w M.F raw');
    near(a.tensionModificationFactor, b.tensionModificationFactor, '$w M.Ft');
    near(a.compressionModificationFactor, b.compressionModificationFactor, '$w M.Fc');
    near(a.allowableSpanDepthRatio, b.allowableSpanDepthRatio, '$w allowable');
    near(a.actualSpanDepthRatio, b.actualSpanDepthRatio, '$w actual');
    near(a.dMinRequiredMm, b.dMinRequiredMm, '$w d,min');
    near(a.suggestedOverallDepthHMm, b.suggestedOverallDepthHMm, '$w h suggested');
    near(a.suggestedCompressionSteelPercent, b.suggestedCompressionSteelPercent,
        '$w A\'sc suggested');
  }

  /// يقارن تقريرين كاملين: التصنيف، العزوم والموازنة، الحديد، الهطول، القص، الملخص، التحذيرات.
  void expectEquivalent(SlabDesignReport old, SlabDesignReport neu, String tag) {
    // التصنيف والهندسة
    expect(neu.slabId, old.slabId, reason: tag);
    expect(neu.topology.twoWayCase, old.topology.twoWayCase, reason: '$tag case');
    expect(neu.topology.spanningType, old.topology.spanningType, reason: tag);
    expect(neu.topology.isShortSpanHorizontal, old.topology.isShortSpanHorizontal,
        reason: tag);
    for (final s in EdgeSide.values) {
      expect(neu.topology.edgeFor(s), old.topology.edgeFor(s),
          reason: '$tag edge ${s.name}');
    }
    near(neu.topology.widthXM, old.topology.widthXM, '$tag width');
    near(neu.topology.heightYM, old.topology.heightYM, '$tag height');

    // الأحمال
    near(neu.loadResult.finalDesignLoadN, old.loadResult.finalDesignLoadN, '$tag n');
    near(neu.loadResult.overallDepthHMm, old.loadResult.overallDepthHMm, '$tag h');

    // العزوم الأولية والنهائية
    near(neu.initialMoments.msxPos, old.initialMoments.msxPos, '$tag Msx+');
    near(neu.initialMoments.msxNeg, old.initialMoments.msxNeg, '$tag Msx-');
    near(neu.initialMoments.msyPos, old.initialMoments.msyPos, '$tag Msy+');
    near(neu.initialMoments.msyNeg, old.initialMoments.msyNeg, '$tag Msy-');
    final mo = old.balancedMoments;
    final mn = neu.balancedMoments;
    near(mn.shortMidMomentFinal, mo.shortMidMomentFinal, '$tag short mid');
    near(mn.shortSupportMomentFinal, mo.shortSupportMomentFinal, '$tag short sup');
    near(mn.longMidMomentFinal, mo.longMidMomentFinal, '$tag long mid');
    near(mn.longSupportMomentFinal, mo.longSupportMomentFinal, '$tag long sup');
    for (final s in EdgeSide.values) {
      near(mn.supportMomentBySide[s], mo.supportMomentBySide[s],
          '$tag support ${s.name}');
    }

    // تفاصيل الموازنة عند كل مسند
    expect(mn.supportBalances.length, mo.supportBalances.length,
        reason: '$tag balances count');
    for (var i = 0; i < mo.supportBalances.length; i++) {
      final a = mo.supportBalances[i];
      final b = mn.supportBalances[i];
      final w = '$tag balance[${a.side.name}]';
      expect(b.side, a.side, reason: w);
      expect(b.axisDirection, a.axisDirection, reason: w);
      expect(b.neighborLabel, a.neighborLabel, reason: w);
      expect(b.isCantileverSupport, a.isCantileverSupport, reason: w);
      expect(b.assumedNeighborCaseNumber, a.assumedNeighborCaseNumber, reason: w);
      near(b.mSlabInitial, a.mSlabInitial, '$w M slab');
      near(b.mNeighborInitial, a.mNeighborInitial, '$w M neighbor');
      near(b.kSlab, a.kSlab, '$w k slab');
      near(b.kNeighbor, a.kNeighbor, '$w k neighbor');
      near(b.mUnbalanced, a.mUnbalanced, '$w M unbalanced');
      near(b.mBalancedSupport, a.mBalancedSupport, '$w M balanced');
      near(b.slabNegativeReduction, a.slabNegativeReduction, '$w reduction');
      near(b.midSpanMomentIncrease, a.midSpanMomentIncrease, '$w mid increase');
    }

    // الحديد
    final sa = old.allSteelDesigns;
    final sb = neu.allSteelDesigns;
    expect(sb.length, sa.length, reason: '$tag steel zones');
    for (var i = 0; i < sa.length; i++) {
      sameSteel(sa[i], sb[i], '$tag ${sa[i].zoneId}');
    }

    // الهطول والقص
    sameDeflection(old.deflectionCheck, neu.deflectionCheck, '$tag deflection');
    near(neu.shearCheck.designShearStressV, old.shearCheck.designShearStressV,
        '$tag v');
    near(neu.shearCheck.concreteShearStressVc, old.shearCheck.concreteShearStressVc,
        '$tag vc');
    near(neu.shearCheck.governingBetaV, old.shearCheck.governingBetaV, '$tag betaV');
    expect(neu.shearCheck.isSafe, old.shearCheck.isSafe, reason: '$tag shear safe');

    // الملخص
    final ra = old.summaryRow;
    final rb = neu.summaryRow;
    expect(rb.shortMidLecture, ra.shortMidLecture, reason: tag);
    expect(rb.shortSupportLecture, ra.shortSupportLecture, reason: tag);
    expect(rb.longMidLecture, ra.longMidLecture, reason: tag);
    expect(rb.longSupportLecture, ra.longSupportLecture, reason: tag);
    expect(rb.shortSupportDiscLecture, ra.shortSupportDiscLecture, reason: tag);
    expect(rb.longSupportDiscLecture, ra.longSupportDiscLecture, reason: tag);
    expect(rb.shortMidSpacing, ra.shortMidSpacing, reason: tag);
    expect(rb.longMidSpacing, ra.longMidSpacing, reason: tag);

    // الكوابيل
    expect(neu.cantileverReports.keys.toSet(), old.cantileverReports.keys.toSet(),
        reason: '$tag cantilevers');
    for (final side in old.cantileverReports.keys) {
      final ca = old.cantileverReports[side]!;
      final cb = neu.cantileverReports[side]!;
      near(cb.supportMomentKnM, ca.supportMomentKnM, '$tag cant M');
      near(cb.staticMomentKnM, ca.staticMomentKnM, '$tag cant M static');
      expect(cb.overallIsSafe, ca.overallIsSafe, reason: '$tag cant safe');
      expect(cb.topSteel.barCountSelection.lectureNotation,
          ca.topSteel.barCountSelection.lectureNotation,
          reason: '$tag cant top');
      expect(cb.warningsAr, ca.warningsAr, reason: '$tag cant warnings');
    }

    // الخلاصة والتحذيرات والخطوات
    expect(neu.overallIsSafe, old.overallIsSafe, reason: '$tag overallIsSafe');
    expect(neu.warningsAr, old.warningsAr, reason: '$tag warnings');
    expect(neu.steps.length, old.steps.length, reason: '$tag steps count');
    for (var i = 0; i < old.steps.length; i++) {
      expect(neu.steps[i].titleAr, old.steps[i].titleAr, reason: '$tag step $i');
    }
  }

  // ---------------------------------------------------------------------------
  // شرط القبول: S7 وS6 قبل التوحيد وبعده
  // ---------------------------------------------------------------------------
  group('شرط القبول — نتائج S7 وS6 متطابقة قبل التوحيد وبعده', () {
    final modes = <String, DesignCalculationMode>{
      'شرح المحاضرة': DesignCalculationMode.lectureMode,
      'الكود الصارم': DesignCalculationMode.strictBs8110,
    };

    for (final m in modes.entries) {
      test('S7 (${m.key})', () {
        final f = presetS7();
        final input = f.toSingleSlabInput();
        final settings = f.toSettings(m.value);
        final old = SlabDesignPipeline.designSingleSlabLegacy(
          input: input,
          settings: settings,
        );
        final neu = SlabDesignPipeline.designSingleSlab(
          input: input,
          settings: settings,
        );
        expectEquivalent(old, neu, 'S7/${m.key}');
      });

      test('S6 + كابولي، العزم المعطى 1 kN.m/m (${m.key})', () {
        final f = presetS6();
        final input = f.toSingleSlabInput();
        final settings = f.toSettings(m.value);
        final old = SlabDesignPipeline.designSingleSlabLegacy(
          input: input,
          settings: settings,
        );
        final neu = SlabDesignPipeline.designSingleSlab(
          input: input,
          settings: settings,
        );
        expectEquivalent(old, neu, 'S6-given/${m.key}');
        expect(neu.cantileverReports, isNotEmpty);
      });

      test('S6 + كابولي، العزم الستاتيكي n·l²/2 (${m.key})', () {
        final f = presetS6().copyWith(
          cantileverMomentSource: CantileverMomentSource.statics,
        );
        final input = f.toSingleSlabInput();
        final settings = f.toSettings(m.value);
        final old = SlabDesignPipeline.designSingleSlabLegacy(
          input: input,
          settings: settings,
        );
        final neu = SlabDesignPipeline.designSingleSlab(
          input: input,
          settings: settings,
        );
        expectEquivalent(old, neu, 'S6-statics/${m.key}');
        near(neu.balancedMoments.shortSupportMomentFinal, 14.72, 'n·l²/2');
      });
    }

    test('الكود الصارم مع الزيادة التلقائية للسماكة (S7: 120 → 140 mm)', () {
      final f = presetS7();
      final input = f.toSingleSlabInput();
      final settings = f.toSettings(DesignCalculationMode.strictBs8110);
      final old = SlabDesignPipeline.designSingleSlabLegacy(
        input: input,
        settings: settings,
        autoAdjustDepthIfUnsafeInStrictMode: true,
      );
      final neu = SlabDesignPipeline.designSingleSlab(
        input: input,
        settings: settings,
        autoAdjustDepthIfUnsafeInStrictMode: true,
      );
      expectEquivalent(old, neu, 'S7/auto-depth');
      expect(neu.loadResult.overallDepthHMm, greaterThan(120.0));
    });

    test('إعادة التصميم بسماكة مقترحة 140 mm (مسار runDesign): الجار يأخذ الحمل المعدَّل',
        () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(singleSlabFormProvider.notifier);
      n.loadExamPresetS7();
      final f = c.read(singleSlabFormProvider);

      final unified = n.runDesign(
        DesignCalculationMode.strictBs8110,
        overrideDepthHMm: 140.0,
      );

      // المرجع: المسار القديم بالمدخلات المعدّلة نفسها التي يبنيها runDesign
      final base = f.toSettings(DesignCalculationMode.strictBs8110);
      final delta = LoadCalculator.calculateSelfWeightDeltaFactored(
        originalDepthHMm: base.overallDepthH,
        newDepthHMm: 140.0,
      );
      final old = SlabDesignPipeline.designSingleSlabLegacy(
        input: withLoad(f.toSingleSlabInput(), f.effectiveDesignLoadN + delta),
        settings: base.copyWith(overallDepthH: 140.0),
      );
      expectEquivalent(old, unified, 'S7/140mm');
    });
  });

  // ---------------------------------------------------------------------------
  // القيم المرجعية لورقة الدكتور ما زالت كما هي بعد التوحيد
  // ---------------------------------------------------------------------------
  group('القيم المرجعية بعد التوحيد', () {
    test('S7 (شرح المحاضرة): Msx+ = 7.15 وMsy+ = 7.41 وحديد 5/4/6/6 No 10', () {
      final f = presetS7();
      final r = SlabDesignPipeline.designSingleSlab(
        input: f.toSingleSlabInput(),
        settings: f.toSettings(DesignCalculationMode.lectureMode),
      );
      expect(r.topology.twoWayCase, TwoWayPanelCase.twoLongEdgesDiscontinuous);
      expect(r.balancedMoments.shortMidMomentFinal, closeTo(7.15, 0.01));
      expect(r.balancedMoments.longMidMomentFinal, closeTo(7.41, 0.01));
      expect(r.summaryRow.shortMidLecture, '5 No 10');
      expect(r.summaryRow.longMidLecture, '6 No 10');
      expect(r.summaryRow.longSupportLecture, '6 No 10');
      expect(r.overallIsSafe, isTrue);
    });

    // قيم مجمّدة للعزوم النهائية (kN.m/m) على قالبَي S7 وS6. حُسبت بمحاكاة مستقلة للصيغ نفسها
    // (Table 3.14 + الموازنة) وتطابق ورقة الدكتور لـ S7 (7.15 / 7.41)؛ وتبقى حارساً للنتائج
    // حتى بعد حذف المسار القديم من المقارنة أعلاه.
    test('عزوم نهائية مجمّدة: S7 وS6 (شرح المحاضرة والصارم)', () {
      // تسامح 1e-4 (أربع خانات) لأن القيم المرجعية مطبوعة بست خانات من المحاكاة
      void check5(
        SingleSlabFormState f,
        DesignCalculationMode mode,
        List<double> expected,
        String tag,
      ) {
        final m = SlabDesignPipeline.designSingleSlab(
          input: f.toSingleSlabInput(),
          settings: f.toSettings(mode),
        ).balancedMoments;
        final actual = [
          m.shortMidMomentFinal,
          m.shortSupportMomentFinal,
          m.longMidMomentFinal,
          m.longSupportMomentFinal,
        ];
        for (var i = 0; i < 4; i++) {
          expect(actual[i], closeTo(expected[i], 1e-4), reason: '$tag [$i]');
        }
      }

      check5(presetS7(), DesignCalculationMode.lectureMode,
          [7.152655, 0.0, 7.410194, 7.907932], 'S7 lecture');
      check5(presetS7(), DesignCalculationMode.strictBs8110,
          [7.138510, 0.0, 7.410194, 7.907932], 'S7 strict');
      check5(presetS6(), DesignCalculationMode.lectureMode,
          [5.799450, 7.873288, 5.412820, 7.815449], 'S6 lecture');
      check5(presetS6(), DesignCalculationMode.strictBs8110,
          [5.794735, 7.925869, 5.412820, 7.815449], 'S6 strict');
    });

    test('S7 في الصارم يكتشف فشل الهطول ويقترح 140 mm كما قبل التوحيد', () {
      final f = presetS7();
      final r = SlabDesignPipeline.designSingleSlab(
        input: f.toSingleSlabInput(),
        settings: f.toSettings(DesignCalculationMode.strictBs8110),
      );
      expect(r.deflectionCheck.isSafe, isFalse);
      expect(r.deflectionCheck.suggestedOverallDepthHMm, 140.0);
    });
  });

  // ---------------------------------------------------------------------------
  // NeighborhoodBuilder
  // ---------------------------------------------------------------------------
  group('NeighborhoodBuilder — المخطط المصغّر 3×3', () {
    test('S7: البلاطة في (1,1) وS6 فوقها وS8 تحتها، والبقية فراغ خارجي', () {
      final f = presetS7();
      final hood = NeighborhoodBuilder.build(
        input: f.toSingleSlabInput(),
        settings: f.toSettings(DesignCalculationMode.lectureMode),
      );
      final p = hood.plan;
      expect(p.rowsCount, 3);
      expect(p.colsCount, 3);
      expect(p.cells.length, 9);
      expect(hood.centerRow, 1);
      expect(hood.centerCol, 1);

      expect(p.cellAt(1, 1)!.id, 'S7');
      expect(p.cellAt(0, 1)!.id, 'S6');
      expect(p.cellAt(2, 1)!.id, 'S8');
      for (final rc in [(0, 0), (0, 2), (1, 0), (1, 2), (2, 0), (2, 2)]) {
        expect(p.cellAt(rc.$1, rc.$2)!.cellType, SlabCellType.exteriorEmpty,
            reason: '$rc');
      }

      // أبعاد الصفوف والأعمدة من بحر الجار بالشريحة
      expect(p.ySpansM, [4.20, 4.20, 4.40]);
      expect(p.xSpansM[1], 4.10);
      expect(hood.notesAr, isEmpty);
    });

    test('حواف البلاطة المدروسة تُفرض كما أُدخلت (حتى على خانة بلا جار)', () {
      final f = presetS7();
      final hood = NeighborhoodBuilder.build(
        input: f.toSingleSlabInput(),
        settings: f.toSettings(DesignCalculationMode.lectureMode),
      );
      final center = hood.plan.cellAt(1, 1)!;
      expect(center.edgeConditionOverrides[EdgeSide.left],
          EdgeCondition.discontinuousFree);
      expect(center.edgeConditionOverrides[EdgeSide.right],
          EdgeCondition.discontinuousDropped);
      expect(center.edgeConditionOverrides[EdgeSide.top], EdgeCondition.continuous);
      expect(center.edgeConditionOverrides[EdgeSide.bottom],
          EdgeCondition.continuous);
    });

    test('حالات الجيران المشتقة من الحواف تعيد Case المدخلة: S6=2، S8=3، S7=6، S4=5', () {
      final s7 = presetS7().toSingleSlabInput();
      expect(
        NeighborhoodBuilder.resolveNeighborTopology(s7.topNeighbor!, EdgeSide.top)
            .twoWayCase,
        TwoWayPanelCase.oneShortEdgeDiscontinuous,
      );
      expect(
        NeighborhoodBuilder.resolveNeighborTopology(
                s7.bottomNeighbor!, EdgeSide.bottom)
            .twoWayCase,
        TwoWayPanelCase.oneLongEdgeDiscontinuous,
      );

      final s6 = presetS6().toSingleSlabInput();
      expect(
        NeighborhoodBuilder.resolveNeighborTopology(
                s6.bottomNeighbor!, EdgeSide.bottom)
            .twoWayCase,
        TwoWayPanelCase.twoLongEdgesDiscontinuous,
      );
      expect(
        NeighborhoodBuilder.resolveNeighborTopology(s6.rightNeighbor!, EdgeSide.right)
            .twoWayCase,
        TwoWayPanelCase.twoShortEdgesDiscontinuous,
      );
    });

    test('الحافة المشتركة مستمرة دائماً في كل جار', () {
      for (final side in EdgeSide.values) {
        final n = NeighborSlabInput(
          label: 'N',
          spanAlongStripM: 4.2,
          perpendicularSpanM: 4.1,
        );
        final e = NeighborhoodBuilder.neighborEdgeConditions(n, side);
        expect(e[side.opposite], EdgeCondition.continuous, reason: side.name);
      }
    });

    test('كل Case صالحة يعيدها المحوّل بلا تعارض (جار غير مربع، طرف بعيد متّسق)', () {
      // لكل حالة نبني حواف الجار الحقيقية، نحسب Case منها بالمحلل، ثم نعطيها للمحوّل
      // كحالة مثبّتة: يجب أن تعود الحالة نفسها دون تنبيه تعارض.
      const sides = EdgeSide.values;
      for (final side in sides) {
        for (final far in [true, false]) {
          for (final ls in [true, false]) {
            for (final le in [true, false]) {
              final probe = NeighborSlabInput(
                label: 'N',
                spanAlongStripM: 4.4,
                perpendicularSpanM: 4.0,
                isFarEndContinuous: far,
                lateralStartContinuous: ls,
                lateralEndContinuous: le,
              );
              final truth =
                  NeighborhoodBuilder.resolveNeighborTopology(probe, side)
                      .twoWayCase!;
              final pinned = NeighborSlabInput(
                label: 'N',
                spanAlongStripM: 4.4,
                perpendicularSpanM: 4.0,
                isFarEndContinuous: far,
                panelCase: truth,
              );
              final edges = NeighborhoodBuilder.edgesFor(pinned, side);
              expect(edges.conflictNoteAr, isNull,
                  reason: '${side.name} far=$far ls=$ls le=$le Case ${truth.caseNumber}');
              expect(
                NeighborhoodBuilder.resolveNeighborTopology(pinned, side).twoWayCase,
                truth,
                reason: '${side.name} far=$far ls=$ls le=$le',
              );
            }
          }
        }
      }
    });

    test('حالة متعارضة مع الطرف البعيد: يُعتمد الطرف البعيد ويظهر تنبيه في التقرير', () {
      // Case 1 (كل الحواف مستمرة) مع طرف بعيد غير مستمر: متناقضان
      final input = SingleSlabInput(
        slabId: 'Q',
        widthXM: 4.1,
        heightYM: 4.2,
        topEdge: EdgeCondition.continuous,
        bottomEdge: EdgeCondition.discontinuousFree,
        leftEdge: EdgeCondition.discontinuousFree,
        rightEdge: EdgeCondition.discontinuousFree,
        topNeighbor: const NeighborSlabInput(
          label: 'N1',
          spanAlongStripM: 4.2,
          perpendicularSpanM: 4.1,
          isFarEndContinuous: false,
          panelCase: TwoWayPanelCase.interiorPanels,
        ),
      );
      final edges =
          NeighborhoodBuilder.edgesFor(input.topNeighbor!, EdgeSide.top);
      expect(edges.farContinuous, isFalse);
      expect(edges.conflictNoteAr, isNotNull);

      final r = SlabDesignPipeline.designSingleSlab(
        input: input,
        settings: const SlabProjectSettings(
          designLoadN: 11.50,
          overallDepthH: 120.0,
          clearCoverC: 25.0,
          barDiameterPhi: 10.0,
          fcu: 25.0,
          fy: 250.0,
        ),
      );
      expect(r.warningsAr.any((w) => w.contains('N1') && w.contains('Case 1')),
          isTrue);
    });

    test('جار مربع أيسر/أيمن: لا تعارض وهمي بين الحالة المستنتجة وتسمية الحواف', () {
      for (final side in [EdgeSide.left, EdgeSide.right, EdgeSide.top, EdgeSide.bottom]) {
        final sq = NeighborSlabInput(
          label: 'SQ',
          spanAlongStripM: 4.0,
          perpendicularSpanM: 4.0,
          isFarEndContinuous: false,
        );
        final e = NeighborhoodBuilder.edgesFor(sq, side);
        expect(e.conflictNoteAr, isNull, reason: side.name);
        // الطرف البعيد غير مستمر والحافتان الجانبيتان مستمرتان (Case 2 المستنتجة)
        expect(e.lateralStartContinuous, isTrue, reason: side.name);
        expect(e.lateralEndContinuous, isTrue, reason: side.name);
      }
    });

    test('الحواف الأربع الصريحة تُستعمل كما هي وتُحدّد حالة الجار', () {
      // حافة جانبية واحدة غير مستمرة + طرف بعيد غير مستمر = حافتان متجاورتان: Case 4
      const n = NeighborSlabInput(
        label: 'N',
        spanAlongStripM: 4.2,
        perpendicularSpanM: 4.1,
        isFarEndContinuous: false,
        lateralStartContinuous: false,
        lateralEndContinuous: true,
      );
      final e = NeighborhoodBuilder.edgesFor(n, EdgeSide.top);
      expect(e.isExplicit, isTrue);
      expect(e.lateralStartContinuous, isFalse);
      expect(e.lateralEndContinuous, isTrue);
      expect(NeighborhoodBuilder.resolveNeighborTopology(n, EdgeSide.top).twoWayCase,
          TwoWayPanelCase.twoAdjacentEdgesDiscontinuous);
      expect(n.isPanelCaseAssumed, isFalse);
    });

    test('جار بحافتين جانبيتين صريحتين يغيّر نتيجة التصميم (لم تعد الحواف تُهمل)', () {
      SlabDesignReport run(NeighborSlabInput n) => SlabDesignPipeline.designSingleSlab(
            input: SingleSlabInput(
              slabId: 'Q',
              widthXM: 4.1,
              heightYM: 4.2,
              topEdge: EdgeCondition.continuous,
              bottomEdge: EdgeCondition.discontinuousFree,
              leftEdge: EdgeCondition.discontinuousFree,
              rightEdge: EdgeCondition.discontinuousFree,
              topNeighbor: n,
            ),
            settings: const SlabProjectSettings(
              designLoadN: 11.50,
              overallDepthH: 120.0,
              clearCoverC: 25.0,
              barDiameterPhi: 10.0,
              fcu: 25.0,
              fy: 250.0,
            ),
          );

      const allCont = NeighborSlabInput(
        label: 'N',
        spanAlongStripM: 4.2,
        perpendicularSpanM: 4.1,
        isFarEndContinuous: false,
        lateralStartContinuous: true,
        lateralEndContinuous: true,
      );
      const oneFree = NeighborSlabInput(
        label: 'N',
        spanAlongStripM: 4.2,
        perpendicularSpanM: 4.1,
        isFarEndContinuous: false,
        lateralStartContinuous: false,
        lateralEndContinuous: true,
      );
      final a = run(allCont).balancedMoments.supportBalances.single;
      final b = run(oneFree).balancedMoments.supportBalances.single;
      expect(b.mNeighborInitial, isNot(closeTo(a.mNeighborInitial, 1e-6)));
    });

    test('جار بلا بيانات على حافة مستمرة: لا موازنة ويبقى العزم الأولي', () {
      final f = presetS7();
      final base = f.toSingleSlabInput();
      final noTop = SingleSlabInput(
        slabId: base.slabId,
        widthXM: base.widthXM,
        heightYM: base.heightYM,
        topEdge: base.topEdge,
        bottomEdge: base.bottomEdge,
        leftEdge: base.leftEdge,
        rightEdge: base.rightEdge,
        bottomNeighbor: base.bottomNeighbor,
        customDesignLoadN: base.customDesignLoadN,
      );
      final settings = f.toSettings(DesignCalculationMode.lectureMode);
      final old = SlabDesignPipeline.designSingleSlabLegacy(
        input: noTop,
        settings: settings,
      );
      final neu = SlabDesignPipeline.designSingleSlab(
        input: noTop,
        settings: settings,
      );
      expectEquivalent(old, neu, 'S7 بلا جار علوي');
      expect(
        neu.balancedMoments.supportBalances.map((b) => b.side).toList(),
        [EdgeSide.bottom],
      );
    });

    test('عزم سالب مباشر للجار يحلّ محل Table 3.14', () {
      final f = presetS7();
      final base = f.toSingleSlabInput();
      final given = SingleSlabInput(
        slabId: base.slabId,
        widthXM: base.widthXM,
        heightYM: base.heightYM,
        topEdge: base.topEdge,
        bottomEdge: base.bottomEdge,
        leftEdge: base.leftEdge,
        rightEdge: base.rightEdge,
        topNeighbor: base.topNeighbor!.copyWith(overrideNegativeMomentKnM: 5.0),
        bottomNeighbor: base.bottomNeighbor,
        customDesignLoadN: base.customDesignLoadN,
      );
      final settings = f.toSettings(DesignCalculationMode.lectureMode);
      final old = SlabDesignPipeline.designSingleSlabLegacy(
        input: given,
        settings: settings,
      );
      final neu = SlabDesignPipeline.designSingleSlab(
        input: given,
        settings: settings,
      );
      expectEquivalent(old, neu, 'S7 عزم الجار 5.0');
      final top = neu.balancedMoments.supportBalances
          .firstWhere((b) => b.side == EdgeSide.top);
      near(top.mNeighborInitial, 5.0, 'M neighbor');
    });

    test('أبعاد غير موجبة ترمي ArgumentError كالمسار القديم', () {
      final f = presetS7().copyWith(widthXM: 0.0);
      expect(
        () => SlabDesignPipeline.designSingleSlab(
          input: f.toSingleSlabInput(),
          settings: f.toSettings(DesignCalculationMode.lectureMode),
        ),
        throwsArgumentError,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // التوافق مع المشاريع المحفوظة
  // ---------------------------------------------------------------------------
  group('توافق JSON', () {
    test('خانة بلا edgeConditionOverrides لا تكتب المفتاح، وملف قديم بدونه يُقرأ', () {
      const cell = FloorSlabCell(
        row: 0,
        col: 0,
        id: 'S1',
        label: 'S1',
        cellType: SlabCellType.normalSolid,
      );
      expect(cell.toJson().containsKey('edgeConditionOverrides'), isFalse);

      final old = Map<String, dynamic>.from(cell.toJson());
      final back = FloorSlabCell.fromJson(old);
      expect(back.edgeConditionOverrides, isEmpty);
    });

    test('edgeConditionOverrides تُحفظ وتُستعاد، وقيمة غير معروفة تُتجاهل', () {
      const cell = FloorSlabCell(
        row: 1,
        col: 1,
        id: 'S7',
        label: 'S7',
        cellType: SlabCellType.normalSolid,
        edgeConditionOverrides: {
          EdgeSide.left: EdgeCondition.discontinuousFree,
          EdgeSide.top: EdgeCondition.continuous,
        },
      );
      final json = cell.toJson();
      final restored = FloorSlabCell.fromJson(json);
      expect(restored.edgeConditionOverrides, cell.edgeConditionOverrides);

      final withJunk = Map<String, dynamic>.from(json)
        ..['edgeConditionOverrides'] = {
          'left': 'discontinuousFree',
          'diagonal': 'continuous',
          'top': 'noSuchCondition',
        };
      final tolerant = FloorSlabCell.fromJson(withJunk);
      expect(tolerant.edgeConditionOverrides, {
        EdgeSide.left: EdgeCondition.discontinuousFree,
      });
    });
  });
}
