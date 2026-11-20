import 'package:bs8110_slab_designer/app.dart';
import 'package:bs8110_slab_designer/core/constants/design_mode.dart';
import 'package:bs8110_slab_designer/data/repositories/local_storage_service.dart';
import 'package:bs8110_slab_designer/data/templates/exam_floor_plan_template.dart';
import 'package:bs8110_slab_designer/domain/engine/engineering_engine.dart';
import 'package:bs8110_slab_designer/domain/engine/grid_validator.dart';
import 'package:bs8110_slab_designer/presentation/providers/floor_grid_provider.dart';
import 'package:bs8110_slab_designer/presentation/providers/single_slab_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    LocalStorageService.clearMemoryFallback();
  });

  group('المرحلة 4 — الربط من المخطط إلى الوضع السريع (صمّم هذه + جيرانها)', () {
    test('استخراج S7 من مخطط جامعة عدن يعطي نتائج مطابقة تماماً للمخطط الكامل',
        () {
      final plan = ExamFloorPlanTemplate.buildUniversityOfAdenExamPlan();
      final s7 = plan.findById('S7')!;

      final gridReport = SlabDesignPipeline.designFromFloorGridCell(
        plan: plan,
        row: s7.row,
        col: s7.col,
      );

      final extracted = GridQuickBridge.extractFromFloorGrid(
        plan: plan,
        row: s7.row,
        col: s7.col,
      );
      final quickReport = SlabDesignPipeline.designSingleSlab(
        input: extracted.input,
        settings: extracted.settings,
      );

      expect(extracted.input.slabId, 'S7');
      expect(extracted.input.topNeighbor?.label, 'S6');
      expect(extracted.input.bottomNeighbor?.label, 'S8');
      expect(extracted.input.topNeighbor?.hasExplicitLaterals, isTrue);
      expect(
        quickReport.balancedMoments.shortMidMomentFinal,
        closeTo(gridReport.balancedMoments.shortMidMomentFinal, 1e-6),
      );
      expect(
        quickReport.balancedMoments.longMidMomentFinal,
        closeTo(gridReport.balancedMoments.longMidMomentFinal, 1e-6),
      );
      expect(
        quickReport.balancedMoments.longSupportMomentFinal,
        closeTo(gridReport.balancedMoments.longSupportMomentFinal, 1e-6),
      );
      expect(
        quickReport.summaryRow.shortMidLecture,
        gridReport.summaryRow.shortMidLecture,
      );
      expect(
        quickReport.summaryRow.longMidLecture,
        gridReport.summaryRow.longMidLecture,
      );
      expect(
        quickReport.summaryRow.longSupportLecture,
        gridReport.summaryRow.longSupportLecture,
      );
    });

    test('استخراج S6 مع الكابولي وجيرانها ينقل الكابولي والحواف بدقة', () {
      final plan = ExamFloorPlanTemplate.buildUniversityOfAdenExamPlan();
      final s6 = plan.findById('S6')!;

      final gridReport = SlabDesignPipeline.designFromFloorGridCell(
        plan: plan,
        row: s6.row,
        col: s6.col,
      );

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final quickNotifier = container.read(singleSlabFormProvider.notifier);
      quickNotifier.loadFromFloorGridCell(
        plan: plan,
        row: s6.row,
        col: s6.col,
      );

      final form = container.read(singleSlabFormProvider);
      expect(form.slabId, 'S6');
      expect(form.leftEdge, EdgeCondition.cantilever);
      expect(form.leftCantilever?.lengthM, closeTo(1.60, 1e-9));
      expect(form.bottomNeighbor?.label, 'S7');
      expect(form.rightNeighbor?.label, 'S4');

      final quickReport =
          quickNotifier.runDesign(DesignCalculationMode.lectureMode);
      expect(
        quickReport.balancedMoments.shortMidMomentFinal,
        closeTo(gridReport.balancedMoments.shortMidMomentFinal, 1e-6),
      );
      expect(
        quickReport.balancedMoments.shortSupportMomentFinal,
        closeTo(gridReport.balancedMoments.shortSupportMomentFinal, 1e-6),
      );
      expect(
        quickReport.balancedMoments.longSupportMomentFinal,
        closeTo(gridReport.balancedMoments.longSupportMomentFinal, 1e-6),
      );
    });

    test('الاستخراج يحترم تجاوزات الحواف EdgeOverride من المرحلة 3', () {
      final base = ExamFloorPlanTemplate.buildUniversityOfAdenExamPlan();
      final s7 = base.findById('S7')!;
      final modified = s7.copyWith(
        edgeOverrides: const {EdgeSide.top: EdgeOverride.wall},
      );
      final plan = base.copyWith(
        cells: [for (final c in base.cells) c.id == 'S7' ? modified : c],
      );

      final extracted = GridQuickBridge.extractFromFloorGrid(
        plan: plan,
        row: modified.row,
        col: modified.col,
      );
      expect(extracted.input.topEdge, EdgeCondition.discontinuousFree);
      expect(extracted.input.topNeighbor, isNull);
    });
  });

  group('المرحلة 4 — الربط من الوضع السريع إلى المخطط الكامل', () {
    test('تحويل قالب S7 ينتج مخططاً سليماً بدون أخطاء ونتائج مطابقة', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final formState = container.read(singleSlabFormProvider);

      final quickReport = SlabDesignPipeline.designSingleSlab(
        input: formState.toSingleSlabInput(),
        settings: formState.toSettings(DesignCalculationMode.lectureMode),
      );

      final converted = GridQuickBridge.convertSingleSlabToGrid(
        input: formState.toSingleSlabInput(),
        settings: formState.toSettings(DesignCalculationMode.lectureMode),
      );

      expect(GridValidator.validate(converted.plan).hasErrors, isFalse);
      final center = converted.plan.cellAt(
        converted.centerRow,
        converted.centerCol,
      )!;
      expect(center.id, 'S7');

      final gridReport = SlabDesignPipeline.designFromFloorGridCell(
        plan: converted.plan,
        row: converted.centerRow,
        col: converted.centerCol,
      );
      expect(
        gridReport.topology.twoWayCase,
        quickReport.topology.twoWayCase,
      );
      expect(
        gridReport.balancedMoments.shortMidMomentFinal,
        closeTo(quickReport.balancedMoments.shortMidMomentFinal, 1e-6),
      );
      expect(
        gridReport.balancedMoments.longSupportMomentFinal,
        closeTo(quickReport.balancedMoments.longSupportMomentFinal, 1e-6),
      );
      expect(
        gridReport.summaryRow.shortMidLecture,
        quickReport.summaryRow.shortMidLecture,
      );
      expect(
        gridReport.summaryRow.longSupportLecture,
        quickReport.summaryRow.longSupportLecture,
      );
    });

    test('تحويل قالب S6 يحافظ على الكابولي والجارين بدون أخطاء في المدقق', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(singleSlabFormProvider.notifier);
      notifier.loadExamPresetS6WithCantilever();
      final formState = container.read(singleSlabFormProvider);

      final converted = GridQuickBridge.convertSingleSlabToGrid(
        input: formState.toSingleSlabInput(),
        settings: formState.toSettings(DesignCalculationMode.lectureMode),
      );

      expect(GridValidator.validate(converted.plan).hasErrors, isFalse);
      final center = converted.plan.cellAt(
        converted.centerRow,
        converted.centerCol,
      )!;
      expect(center.id, 'S6');
      expect(center.cantileverOn(EdgeSide.left)?.lengthM, closeTo(1.60, 1e-9));
      expect(converted.plan.findById('S7'), isNotNull);
      expect(converted.plan.findById('S4'), isNotNull);
    });
  });

  group('المرحلة 4 — خريطة النتائج ومؤشر «النتيجة قديمة»', () {
    test('designAllSlabs يملأ خريطة النتائج بحالة الهطول/القص ورقم Case', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(floorGridEditorProvider.notifier);

      // في وضع الشرح: S7 آمنة في الهطول والقص
      n.designAllSlabs(DesignCalculationMode.lectureMode);
      var st = container.read(floorGridEditorProvider);
      expect(st.hasDesignResults, isTrue);
      expect(st.areResultsStale, isFalse);
      final s7Lecture = st.resultsByCell[(1, 0)]!;
      expect(s7Lecture.caseNumber, 6);
      expect(s7Lecture.deflectionSafe, isTrue);
      expect(s7Lecture.shearSafe, isTrue);

      // في الوضع الصارم عند h=120mm: S7 تفشل في الهطول وتظهر غير آمنة
      n.designAllSlabs(DesignCalculationMode.strictBs8110);
      st = container.read(floorGridEditorProvider);
      final s7Strict = st.resultsByCell[(1, 0)]!;
      expect(s7Strict.deflectionSafe, isFalse);
      expect(s7Strict.safetyStatus, SlabSafetyStatus.unsafe);
      expect(s7Strict.shortStatusBadgeAr, 'هطول ✗');
      expect(st.unsafeResultsCount, greaterThan(0));
    });

    test('تعديل المخطط يفعّل مؤشر «النتيجة قديمة» والتراجع يعيده حديثاً', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(floorGridEditorProvider.notifier);

      n.designAllSlabs(DesignCalculationMode.lectureMode);
      expect(container.read(floorGridEditorProvider).areResultsStale, isFalse);

      // أي تعديل على المخطط يجعل النتائج قديمة
      n.updateColumnSpan(0, 4.50);
      var st = container.read(floorGridEditorProvider);
      expect(st.areResultsStale, isTrue);
      expect(st.isCellResultStale(1, 0), isTrue);

      // التراجع إلى المراجعة المصمَّمة يزيل مؤشر التقادم
      n.undo();
      st = container.read(floorGridEditorProvider);
      expect(st.areResultsStale, isFalse);
      expect(st.isCellResultStale(1, 0), isFalse);

      // الإعادة تُرجع مؤشر التقادم، ثم إعادة التصميم تزيله
      n.redo();
      expect(container.read(floorGridEditorProvider).areResultsStale, isTrue);
      n.designAllSlabs(DesignCalculationMode.lectureMode);
      expect(container.read(floorGridEditorProvider).areResultsStale, isFalse);

      // حذف صف بعد التصميم ثم التراجع يعيد نتائج الصف المحذوف دون تقادم
      final beforeCount =
          container.read(floorGridEditorProvider).resultsByCell.length;
      n.deleteRowAt(1);
      expect(container.read(floorGridEditorProvider).areResultsStale, isTrue);
      n.undo();
      final afterUndo = container.read(floorGridEditorProvider);
      expect(afterUndo.areResultsStale, isFalse);
      expect(afterUndo.resultsByCell.length, beforeCount);
    });

    test('تبديل وضع الحساب يُظهر أن النتائج قديمة مقارنة بالوضع الجديد', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(floorGridEditorProvider.notifier);

      n.designAllSlabs(DesignCalculationMode.lectureMode);
      final st = container.read(floorGridEditorProvider);
      expect(
        st.isResultsStaleForMode(DesignCalculationMode.lectureMode),
        isFalse,
      );
      expect(
        st.isResultsStaleForMode(DesignCalculationMode.strictBs8110),
        isTrue,
      );
    });
  });

  group('المرحلة 4 — اختبارات الواجهة للربط وخريطة النتائج', () {
    testWidgets('زر «صمّم هذه + جيرانها» وزر «حوّل إلى مخطط كامل» وشريط التقادم',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: Bs8110SlabApp()),
      );
      await tester.pumpAndSettle();

      // 1. فتح محرر المخطط الكامل
      await tester.tap(find.text('بناء مخطط سقف كامل (Grid Editor)'));
      await tester.pumpAndSettle();

      // تفعيل خريطة النتائج
      await tester.ensureVisible(find.text('خريطة النتائج'));
      await tester.tap(find.text('خريطة النتائج'));
      await tester.pumpAndSettle();
      expect(find.textContaining('النتيجة قديمة'), findsNothing);

      // تعديل المخطط -> يظهر شريط «النتيجة قديمة»
      await tester.ensureVisible(find.text('+ عمود X'));
      await tester.tap(find.text('+ عمود X'));
      await tester.pumpAndSettle();
      expect(find.text('تحديث النتائج'), findsOneWidget);
      expect(find.textContaining('النتيجة قديمة'), findsWidgets);

      // الضغط على «تحديث النتائج» -> يختفي شريط التقادم
      await tester.tap(find.text('تحديث النتائج'));
      await tester.pumpAndSettle();
      expect(find.textContaining('النتيجة قديمة'), findsNothing);

      // 2. الضغط على «صمّم هذه + جيرانها» للانتقال إلى الوضع السريع محمّلاً بـ S7
      await tester.ensureVisible(find.text('صمّم هذه + جيرانها'));
      await tester.tap(find.text('صمّم هذه + جيرانها'));
      await tester.pumpAndSettle();
      expect(find.text('تصميم بلاطة واحدة + جيرانها'), findsOneWidget);
      expect(find.text('احسب وصمّم البلاطة (S7)'), findsOneWidget);

      // 3. الضغط على «حوّل إلى مخطط كامل» للعودة إلى محرر المخطط
      await tester.ensureVisible(find.text('حوّل إلى مخطط كامل'));
      await tester.tap(find.text('حوّل إلى مخطط كامل'));
      await tester.pumpAndSettle();
      expect(find.text('صمّم البلاطة (S7) واعرض الحل الكامل'), findsOneWidget);
    });
  });
}
