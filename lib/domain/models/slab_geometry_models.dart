import '../../data/bs8110/slab_moment_shear_tables.dart';
import 'slab_enums.dart';
import 'slab_project_settings.dart';

/// تعريف كابولي جانبي متصل بأحد حواف بلاطة
class CantileverAttachment {
  final EdgeSide side;
  final double lengthM;
  final double? customDesignLoadN;
  final String label;

  const CantileverAttachment({
    required this.side,
    required this.lengthM,
    this.customDesignLoadN,
    this.label = 'Solid Slab (Cantilever)',
  });

  /// العزم السالب الأقصى عند مسند الكابولي: M = n * lc² / 2
  double negativeMomentKnPerM(double fallbackLoadN) {
    final n = customDesignLoadN ?? fallbackLoadN;
    return (n * lengthM * lengthM) / 2.0;
  }

  /// عزم الكابولي المعتمد عند المسند وفق [source]:
  /// - statics: M = n·lc²/2 (حتى لو وُجد عزم مسند معطى، فهو لا يُنقص العزم الستاتيكي)
  /// - givenSupportMoment: يُستخدم [givenMomentKnM] (إن كان > 0) بدل العزم الستاتيكي
  double supportMomentKnPerM(
    double fallbackLoadN, {
    CantileverMomentSource source = CantileverMomentSource.statics,
    double givenMomentKnM = 0.0,
  }) {
    if (source == CantileverMomentSource.givenSupportMoment &&
        givenMomentKnM > 0) {
      return givenMomentKnM;
    }
    return negativeMomentKnPerM(fallbackLoadN);
  }

  /// طول امتداد الحديد العلوي للكابولي داخل البلاطة المجاورة (1.5 L وفق الشرح)
  double get anchorExtensionInsideSlabM => 1.5 * lengthM;

  Map<String, dynamic> toJson() {
    return {
      'side': side.name,
      'lengthM': lengthM,
      'customDesignLoadN': customDesignLoadN,
      'label': label,
    };
  }

  factory CantileverAttachment.fromJson(Map<String, dynamic> json) {
    return CantileverAttachment(
      side: EdgeSide.values.firstWhere(
        (e) => e.name == json['side'],
        orElse: () => EdgeSide.left,
      ),
      lengthM: (json['lengthM'] as num?)?.toDouble() ?? 1.50,
      customDesignLoadN: (json['customDesignLoadN'] as num?)?.toDouble(),
      label: (json['label'] as String?) ?? 'Solid Slab (Cantilever)',
    );
  }
}

/// بيانات بلاطة مجاورة (تُستخدم في وضع الإدخال السريع "بلاطة واحدة + جيرانها")
class NeighborSlabInput {
  final String label;

  /// طول بحر الجار في نفس اتجاه الشريحة العمودية على الحافة المشتركة (m)
  final double spanAlongStripM;

  /// طول البحر العمودي على الشريحة للجار (m) لحساب عزمه الأولي تلقائياً
  final double perpendicularSpanM;

  /// هل الطرف البعيد للجار مستمر مع بلاطة أخرى؟ (يحدد جساءة k = 1/L أم 0.75/L)
  final bool isFarEndContinuous;

  /// حالة الجار من Table 3.14 (اختيارية؛ إن لم تُحدّد تُستنتج من الهندسة عبر [inferredPanelCase])
  final TwoWayPanelCase? panelCase;

  /// إمكانية إدخال العزم السالب للجار مباشرة (مفيد لحل مسائل جاهزة العزوم)
  final double? overrideNegativeMomentKnM;

  /// حمل تصميمي مخصص للجار إن اختلف عن البلاطة الأساسية
  final double? customDesignLoadN;

  /// الحافتان الجانبيتان للجار (الموازيتان لاتجاه الشريحة)، وهما مع الحافة المشتركة والطرف
  /// البعيد حوافه الأربع. «البداية» هي الحافة اليسرى للجار العلوي/السفلي، والعلوية للجار
  /// الأيسر/الأيمن؛ و«النهاية» هي المقابلة لها.
  /// عند تحديد الاثنتين معاً (تعديل يدوي من بطاقة الجار) تُشتق حالة الجار في Table 3.14
  /// من الحواف الأربع مباشرة ويُهمل [panelCase]. وعند تركهما null (قوالب وبيانات قديمة)
  /// تُحوَّل [panelCase] أو الحالة المستنتجة إلى حواف جانبية مكافئة في `NeighborhoodBuilder`.
  final bool? lateralStartContinuous;
  final bool? lateralEndContinuous;

  const NeighborSlabInput({
    required this.label,
    required this.spanAlongStripM,
    required this.perpendicularSpanM,
    this.isFarEndContinuous = false,
    this.panelCase,
    this.overrideNegativeMomentKnM,
    this.customDesignLoadN,
    this.lateralStartContinuous,
    this.lateralEndContinuous,
  });

  /// هل حُدِّدت الحافتان الجانبيتان صراحةً (وضع «الحواف الأربع»)؟
  bool get hasExplicitLaterals =>
      lateralStartContinuous != null && lateralEndContinuous != null;

  NeighborSlabInput copyWith({
    String? label,
    double? spanAlongStripM,
    double? perpendicularSpanM,
    bool? isFarEndContinuous,
    TwoWayPanelCase? panelCase,
    bool clearPanelCase = false,
    double? overrideNegativeMomentKnM,
    bool clearOverrideNegativeMoment = false,
    double? customDesignLoadN,
    bool clearCustomDesignLoad = false,
    bool? lateralStartContinuous,
    bool? lateralEndContinuous,
    bool clearLateralEdges = false,
  }) {
    return NeighborSlabInput(
      label: label ?? this.label,
      spanAlongStripM: spanAlongStripM ?? this.spanAlongStripM,
      perpendicularSpanM: perpendicularSpanM ?? this.perpendicularSpanM,
      isFarEndContinuous: isFarEndContinuous ?? this.isFarEndContinuous,
      panelCase: clearPanelCase ? null : (panelCase ?? this.panelCase),
      overrideNegativeMomentKnM: clearOverrideNegativeMoment
          ? null
          : (overrideNegativeMomentKnM ?? this.overrideNegativeMomentKnM),
      customDesignLoadN: clearCustomDesignLoad
          ? null
          : (customDesignLoadN ?? this.customDesignLoadN),
      lateralStartContinuous: clearLateralEdges
          ? null
          : (lateralStartContinuous ?? this.lateralStartContinuous),
      lateralEndContinuous: clearLateralEdges
          ? null
          : (lateralEndContinuous ?? this.lateralEndContinuous),
    );
  }

  /// استنتاج حالة الجار في Table 3.14 عند غياب [panelCase] (بدل تخمين Case 2/3 ثابت):
  /// - الحافة المشتركة مع البلاطة المدروسة مستمرة دائماً.
  /// - الحافة البعيدة مستمرة إذا [isFarEndContinuous]، وإلا فهي غير مستمرة.
  /// - حافتا الجار الموازيتان للشريحة لا معلومات عنهما فتُفترضان مستمرتين.
  /// - الحافة البعيدة غير المستمرة طولها = [perpendicularSpanM]؛ تُعدّ «قصيرة» إذا كان هذا
  ///   البعد هو الأصغر، وإلا «طويلة».
  TwoWayPanelCase get inferredPanelCase {
    if (isFarEndContinuous) return TwoWayPanelCase.interiorPanels;
    return perpendicularSpanM <= spanAlongStripM
        ? TwoWayPanelCase.oneShortEdgeDiscontinuous
        : TwoWayPanelCase.oneLongEdgeDiscontinuous;
  }

  /// الحالة المعتمدة فعلياً: المحدّدة يدوياً أو المستنتجة
  TwoWayPanelCase get effectivePanelCase => panelCase ?? inferredPanelCase;

  /// هل الحالة مفترضة (لم يحدّدها المستخدم لا يدوياً ولا عبر الحواف الأربع)؟
  bool get isPanelCaseAssumed => panelCase == null && !hasExplicitLaterals;
}

/// مدخلات وضع الإدخال السريع: بلاطة واحدة + حوافها الأربع + جيرانها (إن وُجدوا)
class SingleSlabInput {
  final String slabId;
  final double widthXM; // البعد الأفقي (X) بالمتر
  final double heightYM; // البعد الرأسي (Y) بالمتر
  final SlabCellType cellType;

  final EdgeCondition topEdge;
  final EdgeCondition bottomEdge;
  final EdgeCondition leftEdge;
  final EdgeCondition rightEdge;

  final NeighborSlabInput? topNeighbor;
  final NeighborSlabInput? bottomNeighbor;
  final NeighborSlabInput? leftNeighbor;
  final NeighborSlabInput? rightNeighbor;

  final CantileverAttachment? topCantilever;
  final CantileverAttachment? bottomCantilever;
  final CantileverAttachment? leftCantilever;
  final CantileverAttachment? rightCantilever;

  /// للبلاطة المهبطة (Dropped Slab): سماكة الردم بالمتر وكثافته الوزنية (kN/m³)
  final double fillDepthM;
  final double fillUnitWeightKnM3;

  /// حمل تصميمي مخصص لهذه البلاطة فقط (اختياري)
  final double? customDesignLoadN;

  /// عزم مسند إضافي (إن طُلب في الاختبار مثل: support B.M. = 1 kN.m/m)
  final double additionalSupportMomentKnM;

  /// مصدر عزم الكابولي: ستاتيكي (n·l²/2) أو العزم المعطى في السؤال
  final CantileverMomentSource cantileverMomentSource;

  const SingleSlabInput({
    required this.slabId,
    required this.widthXM,
    required this.heightYM,
    this.cellType = SlabCellType.normalSolid,
    required this.topEdge,
    required this.bottomEdge,
    required this.leftEdge,
    required this.rightEdge,
    this.topNeighbor,
    this.bottomNeighbor,
    this.leftNeighbor,
    this.rightNeighbor,
    this.topCantilever,
    this.bottomCantilever,
    this.leftCantilever,
    this.rightCantilever,
    this.fillDepthM = 0.0,
    this.fillUnitWeightKnM3 = 18.5,
    this.customDesignLoadN,
    this.additionalSupportMomentKnM = 0.0,
    this.cantileverMomentSource = CantileverMomentSource.statics,
  });

  EdgeCondition edgeFor(EdgeSide side) {
    switch (side) {
      case EdgeSide.top:
        return topEdge;
      case EdgeSide.bottom:
        return bottomEdge;
      case EdgeSide.left:
        return leftEdge;
      case EdgeSide.right:
        return rightEdge;
    }
  }

  NeighborSlabInput? neighborFor(EdgeSide side) {
    switch (side) {
      case EdgeSide.top:
        return topNeighbor;
      case EdgeSide.bottom:
        return bottomNeighbor;
      case EdgeSide.left:
        return leftNeighbor;
      case EdgeSide.right:
        return rightNeighbor;
    }
  }

  CantileverAttachment? cantileverFor(EdgeSide side) {
    switch (side) {
      case EdgeSide.top:
        return topCantilever;
      case EdgeSide.bottom:
        return bottomCantilever;
      case EdgeSide.left:
        return leftCantilever;
      case EdgeSide.right:
        return rightCantilever;
    }
  }
}

/// خانة واحدة داخل محرر المخطط الشبكي الكامل للسقف
class FloorSlabCell {
  final int row;
  final int col;
  final String id; // مثال: S7, S6, Dropped, Stair
  final String label;
  final SlabCellType cellType;

  /// تجاوز اختياري لطول البحر الأفقي أو الرأسي لهذه الخانة (مثل S3 بطول 4.20 مقابل S9 بطول 4.00)
  final double? overrideWidthXM;
  final double? overrideHeightYM;

  final double? customDesignLoadN;
  final double fillDepthM;
  final double fillUnitWeightKnM3;

  /// كوابيل متصلة بحواف هذه الخانة (مثال: كابولي 1.60m يسار S6 ويمين S1 و S2)
  final List<CantileverAttachment> cantilevers;

  /// حالة حافة مفروضة على الخانة بدل استنتاجها من الخانة المجاورة (اختياري).
  /// تُستعمل لبناء المخطط المصغّر للوضع السريع (`NeighborhoodBuilder`) حيث تُعطى حالة كل
  /// حافة مباشرة. الافتراضي فارغ فلا يتغير سلوك أي مخطط محفوظ سابقاً، ولا تُكتب في JSON
  /// إلا عند وجودها.
  final Map<EdgeSide, EdgeCondition> edgeConditionOverrides;

  /// تجاوزات الحواف اليدوية على الخانة في محرر المخطط الكامل (حائط / جسر / غير مستمرة /
  /// مستمرة قسراً). اختياري وافتراضياً فارغ؛ لا يُكتب في JSON إلا عند وجوده لضمان
  /// التوافق الكامل مع المشاريع المحفوظة سابقاً.
  final Map<EdgeSide, EdgeOverride> edgeOverrides;

  const FloorSlabCell({
    required this.row,
    required this.col,
    required this.id,
    required this.label,
    required this.cellType,
    this.overrideWidthXM,
    this.overrideHeightYM,
    this.customDesignLoadN,
    this.fillDepthM = 0.0,
    this.fillUnitWeightKnM3 = 18.5,
    this.cantilevers = const [],
    this.edgeConditionOverrides = const {},
    this.edgeOverrides = const {},
  });

  CantileverAttachment? cantileverOn(EdgeSide side) {
    for (final c in cantilevers) {
      if (c.side == side) return c;
    }
    return null;
  }

  FloorSlabCell copyWith({
    int? row,
    int? col,
    String? id,
    String? label,
    SlabCellType? cellType,
    double? overrideWidthXM,
    bool clearOverrideWidthX = false,
    double? overrideHeightYM,
    bool clearOverrideHeightY = false,
    double? customDesignLoadN,
    bool clearCustomDesignLoad = false,
    double? fillDepthM,
    double? fillUnitWeightKnM3,
    List<CantileverAttachment>? cantilevers,
    Map<EdgeSide, EdgeCondition>? edgeConditionOverrides,
    Map<EdgeSide, EdgeOverride>? edgeOverrides,
  }) {
    return FloorSlabCell(
      row: row ?? this.row,
      col: col ?? this.col,
      id: id ?? this.id,
      label: label ?? this.label,
      cellType: cellType ?? this.cellType,
      overrideWidthXM:
          clearOverrideWidthX ? null : (overrideWidthXM ?? this.overrideWidthXM),
      overrideHeightYM: clearOverrideHeightY
          ? null
          : (overrideHeightYM ?? this.overrideHeightYM),
      customDesignLoadN: clearCustomDesignLoad
          ? null
          : (customDesignLoadN ?? this.customDesignLoadN),
      fillDepthM: fillDepthM ?? this.fillDepthM,
      fillUnitWeightKnM3: fillUnitWeightKnM3 ?? this.fillUnitWeightKnM3,
      cantilevers: cantilevers ?? this.cantilevers,
      edgeConditionOverrides:
          edgeConditionOverrides ?? this.edgeConditionOverrides,
      edgeOverrides: edgeOverrides ?? this.edgeOverrides,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'row': row,
      'col': col,
      'id': id,
      'label': label,
      'cellType': cellType.name,
      'overrideWidthXM': overrideWidthXM,
      'overrideHeightYM': overrideHeightYM,
      'customDesignLoadN': customDesignLoadN,
      'fillDepthM': fillDepthM,
      'fillUnitWeightKnM3': fillUnitWeightKnM3,
      'cantilevers': cantilevers.map((c) => c.toJson()).toList(),
      if (edgeConditionOverrides.isNotEmpty)
        'edgeConditionOverrides': {
          for (final e in edgeConditionOverrides.entries)
            e.key.name: e.value.name,
        },
      if (edgeOverrides.isNotEmpty)
        'edgeOverrides': {
          for (final e in edgeOverrides.entries) e.key.name: e.value.name,
        },
    };
  }

  factory FloorSlabCell.fromJson(Map<String, dynamic> json) {
    final rawCant = (json['cantilevers'] as List<dynamic>?) ?? const [];
    return FloorSlabCell(
      row: (json['row'] as num).toInt(),
      col: (json['col'] as num).toInt(),
      id: (json['id'] as String?) ?? 'S',
      label: (json['label'] as String?) ?? 'S',
      cellType: SlabCellType.values.firstWhere(
        (t) => t.name == json['cellType'],
        orElse: () => SlabCellType.normalSolid,
      ),
      overrideWidthXM: (json['overrideWidthXM'] as num?)?.toDouble(),
      overrideHeightYM: (json['overrideHeightYM'] as num?)?.toDouble(),
      customDesignLoadN: (json['customDesignLoadN'] as num?)?.toDouble(),
      fillDepthM: (json['fillDepthM'] as num?)?.toDouble() ?? 0.0,
      fillUnitWeightKnM3:
          (json['fillUnitWeightKnM3'] as num?)?.toDouble() ?? 18.5,
      cantilevers: rawCant
          .map((e) => CantileverAttachment.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList(),
      edgeConditionOverrides:
          _edgeOverridesFromJson(json['edgeConditionOverrides']),
      edgeOverrides: _manualEdgeOverridesFromJson(json['edgeOverrides']),
    );
  }

  /// قراءة متسامحة: مفتاح غير معروف أو قيمة غير معروفة يُتجاهلان (ملفات قديمة/أحدث).
  static Map<EdgeSide, EdgeCondition> _edgeOverridesFromJson(Object? raw) {
    if (raw is! Map) return const {};
    final out = <EdgeSide, EdgeCondition>{};
    for (final entry in raw.entries) {
      EdgeSide? side;
      for (final s in EdgeSide.values) {
        if (s.name == entry.key) side = s;
      }
      EdgeCondition? cond;
      for (final c in EdgeCondition.values) {
        if (c.name == entry.value) cond = c;
      }
      if (side != null && cond != null) out[side] = cond;
    }
    return out;
  }

  /// قراءة متسامحة لتجاوزات الحواف اليدوية (`EdgeOverride`) لضمان توافق المشاريع المحفوظة.
  static Map<EdgeSide, EdgeOverride> _manualEdgeOverridesFromJson(Object? raw) {
    if (raw is! Map) return const {};
    final out = <EdgeSide, EdgeOverride>{};
    for (final entry in raw.entries) {
      EdgeSide? side;
      for (final s in EdgeSide.values) {
        if (s.name == entry.key) side = s;
      }
      EdgeOverride? ov;
      for (final o in EdgeOverride.values) {
        if (o.name == entry.value) ov = o;
      }
      if (side != null && ov != null) out[side] = ov;
    }
    return out;
  }
}

/// نموذج المخطط الشبكي الكامل للسقف (Full Floor Grid Plan)
class FloorGridPlan {
  final String projectId;
  final String projectName;
  final List<double> xSpansM; // أطوال المحاور الأفقية لكل عمود
  final List<double> ySpansM; // أطوال المحاور الرأسية لكل صف
  final List<FloorSlabCell> cells;
  final SlabProjectSettings settings;

  /// عزم مسند إضافي لجميع البلاطات (مثل ملاحظة الاختبار = 1 kN.m/m؛ افتراضياً 0.0)
  final double additionalSupportMomentKnM;

  /// مصدر عزم الكوابيل: ستاتيكي (n·l²/2، الافتراضي) أو العزم المعطى في السؤال
  final CantileverMomentSource cantileverMomentSource;

  const FloorGridPlan({
    required this.projectId,
    required this.projectName,
    required this.xSpansM,
    required this.ySpansM,
    required this.cells,
    this.settings = const SlabProjectSettings(),
    this.additionalSupportMomentKnM = 0.0,
    this.cantileverMomentSource = CantileverMomentSource.statics,
  });

  int get rowsCount => ySpansM.length;
  int get colsCount => xSpansM.length;

  int get designableSlabsCount =>
      cells.where((c) => c.cellType.isDesignableSlab).length;

  FloorSlabCell? cellAt(int row, int col) {
    if (row < 0 || row >= rowsCount || col < 0 || col >= colsCount) {
      return null;
    }
    for (final c in cells) {
      if (c.row == row && c.col == col) return c;
    }
    return null;
  }

  FloorSlabCell? findById(String slabId) {
    for (final c in cells) {
      if (c.id.toLowerCase() == slabId.toLowerCase()) return c;
    }
    return null;
  }

  double widthOf(FloorSlabCell cell) =>
      cell.overrideWidthXM ?? xSpansM[cell.col];

  double heightOf(FloorSlabCell cell) =>
      cell.overrideHeightYM ?? ySpansM[cell.row];

  FloorGridPlan copyWith({
    String? projectId,
    String? projectName,
    List<double>? xSpansM,
    List<double>? ySpansM,
    List<FloorSlabCell>? cells,
    SlabProjectSettings? settings,
    double? additionalSupportMomentKnM,
    CantileverMomentSource? cantileverMomentSource,
  }) {
    return FloorGridPlan(
      projectId: projectId ?? this.projectId,
      projectName: projectName ?? this.projectName,
      xSpansM: xSpansM ?? this.xSpansM,
      ySpansM: ySpansM ?? this.ySpansM,
      cells: cells ?? this.cells,
      settings: settings ?? this.settings,
      additionalSupportMomentKnM:
          additionalSupportMomentKnM ?? this.additionalSupportMomentKnM,
      cantileverMomentSource:
          cantileverMomentSource ?? this.cantileverMomentSource,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'projectId': projectId,
      'projectName': projectName,
      'xSpansM': xSpansM,
      'ySpansM': ySpansM,
      'cells': cells.map((c) => c.toJson()).toList(),
      'settings': settings.toJson(),
      'additionalSupportMomentKnM': additionalSupportMomentKnM,
      'cantileverMomentSource': cantileverMomentSource.name,
    };
  }

  factory FloorGridPlan.fromJson(Map<String, dynamic> json) {
    final rawX = (json['xSpansM'] as List<dynamic>?) ?? const [4.0];
    final rawY = (json['ySpansM'] as List<dynamic>?) ?? const [4.0];
    final rawCells = (json['cells'] as List<dynamic>?) ?? const [];

    return FloorGridPlan(
      projectId: (json['projectId'] as String?) ?? 'project_1',
      projectName: (json['projectName'] as String?) ?? 'مشروع سقف محفوظ',
      xSpansM: rawX.map((e) => (e as num).toDouble()).toList(),
      ySpansM: rawY.map((e) => (e as num).toDouble()).toList(),
      cells: rawCells
          .map((e) =>
              FloorSlabCell.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      settings: json['settings'] is Map
          ? SlabProjectSettings.fromJson(
              Map<String, dynamic>.from(json['settings'] as Map),
            )
          : const SlabProjectSettings(),
      additionalSupportMomentKnM:
          (json['additionalSupportMomentKnM'] as num?)?.toDouble() ?? 0.0,
      cantileverMomentSource: CantileverMomentSource.fromStorage(
        json['cantileverMomentSource'] as String?,
      ),
    );
  }

  /// معادلة الرقم السحري من ورقة الاختبار:
  /// S_No. = 9 - |d1 - d2| حيث d1 و d2 آخر رقمين في رقم القيد
  static int calculateMagicSlabNumber(int digit1, int digit2) {
    if (digit1 < 0 || digit1 > 9 || digit2 < 0 || digit2 > 9) {
      throw ArgumentError('يجب أن يكون كل رقم بين 0 و 9.');
    }
    return 9 - (digit1 - digit2).abs();
  }

  static String magicSlabId(int digit1, int digit2) {
    return 'S${calculateMagicSlabNumber(digit1, digit2)}';
  }
}
