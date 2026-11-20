import 'package:bs8110_slab_designer/core/constants/design_mode.dart';
import 'package:bs8110_slab_designer/data/repositories/local_storage_service.dart';
import 'package:bs8110_slab_designer/data/templates/exam_floor_plan_template.dart';
import 'package:bs8110_slab_designer/domain/engine/engineering_engine.dart';
import 'package:bs8110_slab_designer/domain/engine/grid_validator.dart';
import 'package:bs8110_slab_designer/presentation/providers/floor_grid_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    LocalStorageService.clearMemoryFallback();
  });

  group('المرحلة 3 — إدراج وحذف الصفوف والأعمدة والحد 12', () {
    test('إدراج صف وعمود في المنتصف والبداية يزيح الإحداثيات ويحفظ السلامة',
        () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(floorGridEditorProvider.notifier);

      // مخطط الامتحان: 4 صفوف × 3 أعمدة، S7 في (1, 0)
      n.insertRowAt(1, spanM: 3.80);
      var plan = container.read(floorGridEditorProvider).plan;
      expect(plan.rowsCount, 5);
      expect(plan.ySpansM[1], closeTo(3.80, 1e-9));
      expect(plan.findById('S7')?.row, 2);
      expect(GridValidator.validate(plan).hasErrors, isFalse);

      n.insertColumnAt(0, spanM: 3.50);
      plan = container.read(floorGridEditorProvider).plan;
      expect(plan.colsCount, 4);
      expect(plan.xSpansM[0], closeTo(3.50, 1e-9));
      expect(plan.findById('S7')?.col, 1);
      expect(GridValidator.validate(plan).hasErrors, isFalse);
    });

    test('حذف صف وعمود من الوسط يعيد فهرسة الخانات ويدعم التراجع Undo', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(floorGridEditorProvider.notifier);

      n.deleteRowAt(1);
      var plan = container.read(floorGridEditorProvider).plan;
      expect(plan.rowsCount, 3);
      expect(plan.findById('S7'), isNull);
      expect(GridValidator.validate(plan).hasErrors, isFalse);

      n.deleteColumnAt(0);
      plan = container.read(floorGridEditorProvider).plan;
      expect(plan.colsCount, 2);
      expect(GridValidator.validate(plan).hasErrors, isFalse);

      n.undo();
      n.undo();
      plan = container.read(floorGridEditorProvider).plan;
      expect(plan.rowsCount, 4);
      expect(plan.colsCount, 3);
      expect(plan.findById('S7')?.row, 1);
    });

    test('الحد الأقصى للصفوف والأعمدة 12 ولا يتجاوزه', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(floorGridEditorProvider.notifier);

      for (int i = 0; i < 15; i++) {
        n.addColumn();
        n.addRow();
      }
      final plan = container.read(floorGridEditorProvider).plan;
      expect(plan.colsCount, 12);
      expect(plan.rowsCount, 12);
      expect(GridValidator.validate(plan).hasErrors, isFalse);
    });
  });

  group('المرحلة 3 — EdgeOverride في resolveGridEdge والمدقق', () {
    test('حائط/جسر/غير مستمرة تقطع الاستمرارية، ومستمرة قسراً تفرضها', () {
      final base = ExamFloorPlanTemplate.buildUniversityOfAdenExamPlan();
      final s7 = base.findById('S7')!;

      // في الأصل: أعلى S7 مستمر مع S6، ويسار S7 غير مستمر
      expect(
        TopologyResolver.resolveGridEdge(
          plan: base,
          cell: s7,
          side: EdgeSide.top,
        ),
        EdgeCondition.continuous,
      );

      for (final ov in const [
        EdgeOverride.wall,
        EdgeOverride.beam,
        EdgeOverride.forcedDiscontinuous,
      ]) {
        final modified = s7.copyWith(edgeOverrides: {EdgeSide.top: ov});
        final plan = base.copyWith(
          cells: [for (final c in base.cells) c.id == 'S7' ? modified : c],
        );
        expect(
          TopologyResolver.resolveGridEdge(
            plan: plan,
            cell: modified,
            side: EdgeSide.top,
          ),
          EdgeCondition.discontinuousFree,
          reason: ov.name,
        );
      }

      final forcedCont = s7.copyWith(
        edgeOverrides: const {EdgeSide.left: EdgeOverride.forcedContinuous},
      );
      final planCont = base.copyWith(
        cells: [for (final c in base.cells) c.id == 'S7' ? forcedCont : c],
      );
      expect(
        TopologyResolver.resolveGridEdge(
          plan: planCont,
          cell: forcedCont,
          side: EdgeSide.left,
        ),
        EdgeCondition.continuous,
      );

      // المدقق يُصدر تحذيراً (لا خطأ) لفرض استمرارية بلا جار
      final report = GridValidator.validate(planCont);
      expect(report.hasErrors, isFalse);
      expect(
        report.warnings
            .any((w) => w.code == GridIssueCode.forcedContinuousWithoutNeighbor),
        isTrue,
      );

      // التصميم يعمل بسلاسة مع EdgeOverride
      final design = SlabDesignPipeline.designFromFloorGridCell(
        plan: planCont,
        row: forcedCont.row,
        col: forcedCont.col,
      );
      expect(design.topology.leftEdge, EdgeCondition.continuous);
    });
  });

  group('المرحلة 3 — التحديد المتعدد والتعديل الجماعي ونسخ الخصائص', () {
    test('تعديل جماعي على عدة خانات يُسجّل كخطوة Undo واحدة', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(floorGridEditorProvider.notifier);

      n.toggleMultiSelectMode(enabled: true);
      n.toggleCellSelection(0, 0);
      n.toggleCellSelection(0, 1);

      final count = n.bulkUpdateCells(
        targets: const {(0, 0), (0, 1)},
        customDesignLoadN: 15.5,
        edgeOverrideSide: EdgeSide.top,
        edgeOverrideValue: EdgeOverride.beam,
      );
      expect(count, 2);

      final plan = container.read(floorGridEditorProvider).plan;
      expect(plan.cellAt(0, 0)!.customDesignLoadN, closeTo(15.5, 1e-9));
      expect(plan.cellAt(0, 1)!.customDesignLoadN, closeTo(15.5, 1e-9));
      expect(plan.cellAt(0, 0)!.edgeOverrides[EdgeSide.top], EdgeOverride.beam);
      expect(plan.cellAt(0, 1)!.edgeOverrides[EdgeSide.top], EdgeOverride.beam);

      // تراجع واحد يعيد الخانتين معاً
      n.undo();
      final undone = container.read(floorGridEditorProvider).plan;
      expect(undone.cellAt(0, 0)!.customDesignLoadN, isNull);
      expect(undone.cellAt(0, 1)!.customDesignLoadN, isNull);
      expect(undone.cellAt(0, 0)!.edgeOverrides, isEmpty);
    });

    test('نسخ خصائص خانة ولصقها يحافظ على فرادة المعرّفات', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(floorGridEditorProvider.notifier);

      n.updateCellProperties(
        row: 1,
        col: 0,
        id: 'S7',
        label: 'S7',
        customDesignLoadN: 16.0,
      );
      n.setEdgeOverride(
        row: 1,
        col: 0,
        side: EdgeSide.left,
        override: EdgeOverride.wall,
      );

      expect(n.copyCellProperties(1, 0), isTrue);
      final pasted = n.pasteCellPropertiesTo(const {(0, 1), (2, 1)});
      expect(pasted, 2);

      final plan = container.read(floorGridEditorProvider).plan;
      expect(plan.cellAt(0, 1)!.id, 'S4');
      expect(plan.cellAt(0, 1)!.customDesignLoadN, closeTo(16.0, 1e-9));
      expect(
        plan.cellAt(0, 1)!.edgeOverrides[EdgeSide.left],
        EdgeOverride.wall,
      );
      expect(GridValidator.validate(plan).hasErrors, isFalse);
    });
  });

  group('المرحلة 3 — توافق JSON مع المشاريع المحفوظة سابقاً', () {
    test('ملف قديم بدون edgeOverrides يُقرأ بنجاح، وملف جديد يحفظها ويستعيدها',
        () {
      final base = ExamFloorPlanTemplate.buildUniversityOfAdenExamPlan();
      final legacyJson = base.toJson();

      for (final rawCell in legacyJson['cells'] as List) {
        expect((rawCell as Map).containsKey('edgeOverrides'), isFalse);
      }
      final fromLegacy = FloorGridPlan.fromJson(legacyJson);
      expect(fromLegacy.findById('S7')!.edgeOverrides, isEmpty);

      final s7 = base.findById('S7')!.copyWith(
        edgeOverrides: const {
          EdgeSide.left: EdgeOverride.wall,
          EdgeSide.top: EdgeOverride.beam,
        },
      );
      final jsonWithOv = s7.toJson();
      expect(jsonWithOv['edgeOverrides'], {'left': 'wall', 'top': 'beam'});

      final restored = FloorSlabCell.fromJson(jsonWithOv);
      expect(restored.edgeOverrides, s7.edgeOverrides);

      final futureJson = Map<String, dynamic>.from(jsonWithOv)
        ..['edgeOverrides'] = {
          'left': 'wall',
          'right': 'unknownFutureType',
          'unknownSide': 'beam',
        };
      final tolerant = FloorSlabCell.fromJson(futureJson);
      expect(tolerant.edgeOverrides, const {EdgeSide.left: EdgeOverride.wall});

      final r = SlabDesignPipeline.designFromFloorGrid(
        plan: fromLegacy,
        slabId: 'S7',
      );
      expect(r.settingsUsed.calculationMode, DesignCalculationMode.lectureMode);
    });

    test('تجاوز الحافة متماثل: الجارة ترى الحافة المشتركة نفسها بلا تحذير', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(floorGridEditorProvider.notifier);

      // S7 في (1, 0) وجارتها العليا S6 في (0, 0)
      n.setEdgeOverride(
        row: 1,
        col: 0,
        side: EdgeSide.top,
        override: EdgeOverride.wall,
      );
      final plan = container.read(floorGridEditorProvider).plan;
      final s6 = plan.cellAt(0, 0)!;
      final s7 = plan.cellAt(1, 0)!;

      expect(
        TopologyResolver.resolveGridEdge(
            plan: plan, cell: s7, side: EdgeSide.top),
        EdgeCondition.discontinuousFree,
      );
      // الحافة السفلية في S6 هي الحافة نفسها فتصير غير مستمرة دون أي تجاوز عليها
      expect(s6.edgeOverrides, isEmpty);
      expect(
        TopologyResolver.resolveGridEdge(
            plan: plan, cell: s6, side: EdgeSide.bottom),
        EdgeCondition.discontinuousFree,
      );

      final report = GridValidator.validate(plan);
      expect(report.hasErrors, isFalse);
      expect(
        report.warnings
            .any((w) => w.code == GridIssueCode.asymmetricEdgeOverride),
        isFalse,
      );

      // مسح التجاوز يعيد الحافتين مستمرتين والمخطط سليماً تماماً
      n.clearEdgeOverrides(1, 0);
      final cleared = container.read(floorGridEditorProvider).plan;
      expect(
        TopologyResolver.resolveGridEdge(
            plan: cleared,
            cell: cleared.cellAt(0, 0)!,
            side: EdgeSide.bottom),
        EdgeCondition.continuous,
      );
      expect(GridValidator.validate(cleared).isClean, isTrue);
    });

    test('تجاوزان متعارضان على الحافة المشتركة يُصدران تحذيراً لا خطأ', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(floorGridEditorProvider.notifier);

      n.setEdgeOverride(
        row: 1,
        col: 0,
        side: EdgeSide.top,
        override: EdgeOverride.wall,
      );
      n.setEdgeOverride(
        row: 0,
        col: 0,
        side: EdgeSide.bottom,
        override: EdgeOverride.forcedContinuous,
      );
      final report = GridValidator.validate(
        container.read(floorGridEditorProvider).plan,
      );
      expect(report.hasErrors, isFalse);
      expect(
        report.warnings
            .where((w) => w.code == GridIssueCode.asymmetricEdgeOverride)
            .length,
        1,
      );

      n.clearEdgeOverrides(1, 0);
      n.clearEdgeOverrides(0, 0);
      expect(
        GridValidator.validate(container.read(floorGridEditorProvider).plan)
            .isClean,
        isTrue,
      );
    });
  });
}
