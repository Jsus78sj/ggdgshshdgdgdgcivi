import 'package:bs8110_slab_designer/app.dart';
import 'package:bs8110_slab_designer/core/constants/design_mode.dart';
import 'package:bs8110_slab_designer/core/utils/natural_compare.dart';
import 'package:bs8110_slab_designer/data/repositories/local_storage_service.dart';
import 'package:bs8110_slab_designer/data/templates/exam_floor_plan_template.dart';
import 'package:bs8110_slab_designer/domain/engine/engineering_engine.dart';
import 'package:bs8110_slab_designer/domain/engine/grid_validator.dart';
import 'package:bs8110_slab_designer/presentation/providers/floor_grid_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

FloorGridPlan _mapCell(
  FloorGridPlan p,
  String id,
  FloorSlabCell Function(FloorSlabCell) f,
) {
  return p.copyWith(
    cells: [for (final c in p.cells) c.id == id ? f(c) : c],
  );
}

bool _hasCode(GridValidationReport r, GridIssueCode code) =>
    r.issues.any((i) => i.code == code);

void main() {
  setUp(() {
    LocalStorageService.clearMemoryFallback();
  });

  group('المرحلة 1 — الترتيب الطبيعي', () {
    test('S2 قبل S10 والأحرف بلا حساسية للحالة', () {
      final ids = ['S10', 'S2', 'S1', 'Dropped', 'S0', 's3'];
      ids.sort(naturalCompare);
      expect(ids, ['Dropped', 'S0', 'S1', 'S2', 's3', 'S10']);
    });
  });

  group('المرحلة 1 — GridValidator', () {
    test('قالب اختبار جامعة عدن سليم تماماً (لا أخطاء ولا تحذيرات)', () {
      final plan = ExamFloorPlanTemplate.buildUniversityOfAdenExamPlan();
      final report = GridValidator.validate(plan);
      expect(report.isClean, isTrue,
          reason: report.issues.map((i) => i.messageAr).join(' | '));
    });

    test('معرّف مكرر (بلا حساسية للحالة) = خطأ', () {
      final base = ExamFloorPlanTemplate.buildUniversityOfAdenExamPlan();
      final plan = _mapCell(base, 'S4', (c) => c.copyWith(id: 's7'));
      final report = GridValidator.validate(plan);
      expect(report.hasErrors, isTrue);
      expect(_hasCode(report, GridIssueCode.duplicateId), isTrue);
    });

    test('معرّف فارغ = خطأ', () {
      final base = ExamFloorPlanTemplate.buildUniversityOfAdenExamPlan();
      final plan = _mapCell(base, 'S4', (c) => c.copyWith(id: '   '));
      expect(_hasCode(GridValidator.validate(plan), GridIssueCode.emptyId),
          isTrue);
    });

    test('طول محور غير موجب = خطأ', () {
      final base = ExamFloorPlanTemplate.buildUniversityOfAdenExamPlan();
      final plan = base.copyWith(xSpansM: [4.10, 0.0, 4.10]);
      final report = GridValidator.validate(plan);
      expect(report.hasErrors, isTrue);
      expect(_hasCode(report, GridIssueCode.nonPositiveSpan), isTrue);
    });

    test('خانة ناقصة = خطأ', () {
      final base = ExamFloorPlanTemplate.buildUniversityOfAdenExamPlan();
      final plan = base.copyWith(
        cells: base.cells.where((c) => c.id != 'S5').toList(),
      );
      expect(_hasCode(GridValidator.validate(plan), GridIssueCode.missingCell),
          isTrue);
    });

    test('حافة مستمرة بطولين مختلفين = تحذير (وليس خطأ)', () {
      final base = ExamFloorPlanTemplate.buildUniversityOfAdenExamPlan();
      // S6 | S4 في الصف نفسه: نغيّر طول S4 فيختلف طول الحافة المشتركة
      final plan =
          _mapCell(base, 'S4', (c) => c.copyWith(overrideHeightYM: 3.50));
      final report = GridValidator.validate(plan);
      expect(report.hasErrors, isFalse);
      expect(_hasCode(report, GridIssueCode.sharedEdgeLengthMismatch), isTrue);
    });

    test('كابولي على حافة يقابلها جار = تحذير', () {
      final base = ExamFloorPlanTemplate.buildUniversityOfAdenExamPlan();
      final plan = _mapCell(
        base,
        'S4',
        (c) => c.copyWith(cantilevers: [
          const CantileverAttachment(side: EdgeSide.right, lengthM: 1.2),
        ]),
      );
      final report = GridValidator.validate(plan);
      expect(report.hasErrors, isFalse);
      expect(_hasCode(report, GridIssueCode.cantileverOnInteriorEdge), isTrue);
    });

    test('مخطط بلا بلاطات قابلة للتصميم = تحذير', () {
      final base = ExamFloorPlanTemplate.buildUniversityOfAdenExamPlan();
      final plan = base.copyWith(
        cells: [
          for (final c in base.cells)
            c.copyWith(
              id: 'Void_${c.row}_${c.col}',
              cellType: SlabCellType.exteriorEmpty,
              cantilevers: const [],
            ),
        ],
      );
      final report = GridValidator.validate(plan);
      expect(_hasCode(report, GridIssueCode.noDesignableSlab), isTrue);
    });

    test('الأخطاء تسبق التحذيرات في القائمة', () {
      final base = ExamFloorPlanTemplate.buildUniversityOfAdenExamPlan();
      var plan = _mapCell(base, 'S4', (c) => c.copyWith(id: 'S7'));
      plan = _mapCell(plan, 'S0', (c) => c.copyWith(overrideHeightYM: 3.0));
      final issues = GridValidator.validate(plan).issues;
      final firstWarning = issues.indexWhere((i) => !i.isError);
      final lastError = issues.lastIndexWhere((i) => i.isError);
      expect(lastError, isNonNegative);
      if (firstWarning != -1) {
        expect(lastError, lessThan(firstWarning));
      }
    });
  });

  group('المرحلة 1 — منع تكرار المعرّفات في المحرر', () {
    test('تعديل معرّف إلى معرّف خانة أخرى يُرفض ولا يغيّر شيئاً', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(floorGridEditorProvider.notifier);

      final err = n.updateCellProperties(
        row: 0,
        col: 1,
        id: 's7', // مستعمل في S7 (صف 1، عمود 0)
        label: 'x',
      );
      expect(err, isNotNull);

      final st = container.read(floorGridEditorProvider);
      expect(st.plan.findById('S4'), isNotNull);
      expect(st.canUndo, isFalse, reason: 'الرفض لا يسجّل خطوة تراجع');
      expect(st.hasUnsavedChanges, isFalse);
    });

    test('الإبقاء على معرّف الخانة نفسها مقبول', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(floorGridEditorProvider.notifier);

      final err = n.updateCellProperties(
        row: 1,
        col: 0,
        id: 'S7',
        label: 'S7 معدّلة',
      );
      expect(err, isNull);
      expect(
        container.read(floorGridEditorProvider).plan.findById('S7')!.label,
        'S7 معدّلة',
      );
    });
  });

  group('المرحلة 1 — التصميم بالموضع', () {
    test('معرّفان مكرران من ملف قديم: كل موضع يُصمَّم بهندسته هو', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(floorGridEditorProvider.notifier);

      final base = ExamFloorPlanTemplate.buildUniversityOfAdenExamPlan();
      n.loadPlan(_mapCell(base, 'S4', (c) => c.copyWith(id: 'S7')));

      final atS4 =
          n.designCell(0, 1, DesignCalculationMode.lectureMode); // 3.70 × 4.20
      final atS7 =
          n.designCell(1, 0, DesignCalculationMode.lectureMode); // 4.10 × 4.20
      expect(atS4.topology.widthXM, closeTo(3.70, 1e-9));
      expect(atS7.topology.widthXM, closeTo(4.10, 1e-9));
    });

    test('designAllSlabs يرتّب ترتيباً طبيعياً ويعيد الخانة مع كل تقرير', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(floorGridEditorProvider.notifier);

      final base = ExamFloorPlanTemplate.buildUniversityOfAdenExamPlan();
      n.loadPlan(_mapCell(base, 'S9', (c) => c.copyWith(id: 'S10')));

      final designs = n.designAllSlabs(DesignCalculationMode.lectureMode);
      expect(
        designs.map((d) => d.cell.id).toList(),
        [
          'Dropped',
          'S0',
          'S1',
          'S2',
          'S3',
          'S4',
          'S5',
          'S6',
          'S7',
          'S8',
          'S10',
        ],
      );
      for (final d in designs) {
        expect(d.report.slabId, d.cell.id);
      }
    });
  });

  group('المرحلة 1 — التراجع والإعادة', () {
    test('تراجع ثم إعادة، وتعود علامة «غير محفوظ» عند الرجوع للنسخة الأصلية', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(floorGridEditorProvider.notifier);

      var st = container.read(floorGridEditorProvider);
      expect(st.canUndo, isFalse);
      expect(st.canRedo, isFalse);

      n.updateColumnSpan(0, 5.0);
      st = container.read(floorGridEditorProvider);
      expect(st.plan.xSpansM[0], 5.0);
      expect(st.canUndo, isTrue);
      expect(st.hasUnsavedChanges, isTrue);

      n.undo();
      st = container.read(floorGridEditorProvider);
      expect(st.plan.xSpansM[0], 4.10);
      expect(st.canUndo, isFalse);
      expect(st.canRedo, isTrue);
      expect(st.hasUnsavedChanges, isFalse);

      n.redo();
      st = container.read(floorGridEditorProvider);
      expect(st.plan.xSpansM[0], 5.0);
      expect(st.canRedo, isFalse);
      expect(st.hasUnsavedChanges, isTrue);
    });

    test('تعديل جديد بعد التراجع يمسح سجل الإعادة', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(floorGridEditorProvider.notifier);

      n.updateColumnSpan(0, 5.0);
      n.undo();
      expect(container.read(floorGridEditorProvider).canRedo, isTrue);

      n.updateColumnSpan(1, 3.0);
      expect(container.read(floorGridEditorProvider).canRedo, isFalse);
    });

    test('السجل محدود بـ 50 خطوة', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(floorGridEditorProvider.notifier);

      for (var i = 0; i < 60; i++) {
        n.updateColumnSpan(0, 4.0 + (i + 1) * 0.01);
      }
      var steps = 0;
      while (container.read(floorGridEditorProvider).canUndo) {
        n.undo();
        steps++;
        if (steps > 100) break;
      }
      expect(steps, 50);
    });

    test('التراجع عن حذف عمود يُرجع العمود وخلاياه', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(floorGridEditorProvider.notifier);

      final before = container.read(floorGridEditorProvider).plan;
      n.removeLastColumn();
      expect(container.read(floorGridEditorProvider).plan.colsCount, 2);

      n.undo();
      final after = container.read(floorGridEditorProvider).plan;
      expect(after.colsCount, before.colsCount);
      expect(after.cells.length, before.cells.length);
    });

    test('تحميل مخطط جديد يصفّر السجل', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(floorGridEditorProvider.notifier);

      n.updateColumnSpan(0, 5.0);
      expect(container.read(floorGridEditorProvider).canUndo, isTrue);
      n.createNewBlankPlan();
      final st = container.read(floorGridEditorProvider);
      expect(st.canUndo, isFalse);
      expect(st.canRedo, isFalse);
    });
  });

  group('المرحلة 1 — الحفظ التلقائي (مسوّدة)', () {
    test('تعديل غير محفوظ يُستعاد في جلسة جديدة', () async {
      final c1 = ProviderContainer();
      c1.read(floorGridEditorProvider.notifier).updateColumnSpan(0, 5.25);
      await Future<void>.delayed(Duration.zero);
      c1.dispose();

      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      final st = c2.read(floorGridEditorProvider);
      expect(st.plan.xSpansM[0], 5.25);
      expect(st.hasUnsavedChanges, isTrue);
    });

    test('بعد الحفظ الصريح تُمحى المسوّدة فلا تُستعاد', () async {
      final c1 = ProviderContainer();
      final n = c1.read(floorGridEditorProvider.notifier);
      n.updateColumnSpan(0, 5.25);
      await n.saveCurrentPlan();
      expect(c1.read(floorGridEditorProvider).hasUnsavedChanges, isFalse);
      await Future<void>.delayed(Duration.zero);
      c1.dispose();

      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      final st = c2.read(floorGridEditorProvider);
      expect(st.plan.xSpansM[0], 4.10, reason: 'لا مسوّدة: يفتح قالب الاختبار');
      expect(st.hasUnsavedChanges, isFalse);
    });

    test('مسوّدة تالفة تُتجاهل ويفتح القالب الافتراضي', () {
      LocalStorageService.writeSetting('floor_grid_draft_v1', '{not json');
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final st = c.read(floorGridEditorProvider);
      expect(st.plan.projectId, 'aden_exam_2026_2027');
    });
  });

  group('المرحلة 1 — واجهة المحرر', () {
    testWidgets('شريط الأدوات: «المخطط سليم» ثم تراجع عن إضافة عمود',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: Bs8110SlabApp()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('بناء مخطط سقف كامل (Grid Editor)'));
      await tester.pumpAndSettle();

      expect(find.text('المخطط سليم'), findsOneWidget);

      final container =
          ProviderScope.containerOf(tester.element(find.text('المخطط سليم')));
      expect(container.read(floorGridEditorProvider).plan.colsCount, 3);

      await tester.ensureVisible(find.text('+ عمود X'));
      await tester.tap(find.text('+ عمود X'));
      await tester.pumpAndSettle();
      expect(container.read(floorGridEditorProvider).plan.colsCount, 4);

      await tester.ensureVisible(find.text('تراجع'));
      await tester.tap(find.text('تراجع'));
      await tester.pumpAndSettle();
      expect(container.read(floorGridEditorProvider).plan.colsCount, 3);
    });
  });
}
