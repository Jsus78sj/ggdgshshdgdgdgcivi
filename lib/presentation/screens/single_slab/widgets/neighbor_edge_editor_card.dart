import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/bs8110/slab_moment_shear_tables.dart';
import '../../../../domain/engine/engineering_engine.dart';

/// بطاقة إدخال بيانات البلاطة المجاورة لحافة مستمرة (لإجراء موازنة العزوم)
class NeighborEditorCard extends StatefulWidget {
  final EdgeSide side;
  final NeighborSlabInput neighbor;
  final int revision;
  final ValueChanged<NeighborSlabInput> onChanged;

  const NeighborEditorCard({
    super.key,
    required this.side,
    required this.neighbor,
    required this.revision,
    required this.onChanged,
  });

  @override
  State<NeighborEditorCard> createState() => _NeighborEditorCardState();
}

class _NeighborEditorCardState extends State<NeighborEditorCard> {
  late TextEditingController _labelCtrl;
  late TextEditingController _alongCtrl;
  late TextEditingController _perpCtrl;
  late TextEditingController _overrideMomCtrl;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
    _labelCtrl = TextEditingController(text: widget.neighbor.label);
    _alongCtrl = TextEditingController(
      text: widget.neighbor.spanAlongStripM.toStringAsFixed(2),
    );
    _perpCtrl = TextEditingController(
      text: widget.neighbor.perpendicularSpanM.toStringAsFixed(2),
    );
    _overrideMomCtrl = TextEditingController(
      text: widget.neighbor.overrideNegativeMomentKnM?.toStringAsFixed(2) ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant NeighborEditorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) {
      _labelCtrl.text = widget.neighbor.label;
      _alongCtrl.text = widget.neighbor.spanAlongStripM.toStringAsFixed(2);
      _perpCtrl.text = widget.neighbor.perpendicularSpanM.toStringAsFixed(2);
      _overrideMomCtrl.text =
          widget.neighbor.overrideNegativeMomentKnM?.toStringAsFixed(2) ?? '';
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _alongCtrl.dispose();
    _perpCtrl.dispose();
    _overrideMomCtrl.dispose();
    super.dispose();
  }

  void _emitUpdated({
    String? label,
    double? spanAlong,
    double? perpSpan,
    bool? isFarCont,
    TwoWayPanelCase? panelCase,
    double? overrideMoment,
    bool clearOverrideMoment = false,
    bool? lateralStart,
    bool? lateralEnd,
  }) {
    var next = widget.neighbor.copyWith(
      label: label,
      spanAlongStripM: spanAlong,
      perpendicularSpanM: perpSpan,
      isFarEndContinuous: isFarCont,
      overrideNegativeMomentKnM: overrideMoment,
      clearOverrideNegativeMoment: clearOverrideMoment,
    );
    if (panelCase != null) {
      // تثبيت Case يدوياً: يعود الجار إلى وضع «الحالة» وتُهمل الحافتان الجانبيتان المحدّدتان
      next = next.copyWith(panelCase: panelCase, clearLateralEdges: true);
    }
    if (lateralStart != null || lateralEnd != null) {
      // تعديل حافة جانبية: وضع «الحواف الأربع»، فتُشتق الحالة من الحواف وتُلغى الحالة المثبتة
      final cur = NeighborhoodBuilder.edgesFor(widget.neighbor, widget.side);
      next = next.copyWith(
        lateralStartContinuous: lateralStart ?? cur.lateralStartContinuous,
        lateralEndContinuous: lateralEnd ?? cur.lateralEndContinuous,
        clearPanelCase: true,
      );
    }
    widget.onChanged(next);
  }

  /// نص الحالة المشتقة من حواف الجار الأربع (أو null إذا تعذّر التحليل لقيم غير صالحة)
  String? _derivedCaseText() {
    try {
      final topo = NeighborhoodBuilder.resolveNeighborTopology(
        widget.neighbor,
        widget.side,
      );
      final c = topo.twoWayCase;
      if (c == null) return 'الحالة المشتقة من الحواف: بلاطة عاملة باتجاه واحد';
      return 'الحالة المشتقة من الحواف: Case ${c.caseNumber} — ${c.titleAr}';
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool explicitEdges = widget.neighbor.hasExplicitLaterals;
    // في وضع «الحواف الأربع» لا توجد حالة مثبتة، فتبقى القائمة بلا اختيار
    final TwoWayPanelCase? selectedCase =
        explicitEdges ? null : widget.neighbor.effectivePanelCase;
    final edges = NeighborhoodBuilder.edgesFor(widget.neighbor, widget.side);
    final bool sidesAreVertical =
        widget.side == EdgeSide.top || widget.side == EdgeSide.bottom;
    final String startName = sidesAreVertical ? 'اليسرى' : 'العلوية';
    final String endName = sidesAreVertical ? 'اليمنى' : 'السفلية';
    final String? derivedText = _derivedCaseText();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.rebarBottomX.withAlpha(90)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.link_rounded,
                size: 18,
                color: AppColors.rebarBottomX,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'بيانات الجار عند ${widget.side.titleAr} (لموازنة العزوم)',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _labelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اسم الجار',
                    hintText: 'S6',
                  ),
                  onChanged: (v) => _emitUpdated(label: v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _alongCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'بحر الجار بالشريحة (m)',
                  ),
                  onChanged: (v) {
                    final parsed = double.tryParse(v);
                    if (parsed != null && parsed > 0) {
                      _emitUpdated(spanAlong: parsed);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _perpCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'البحر العمودي (m)',
                  ),
                  onChanged: (v) {
                    final parsed = double.tryParse(v);
                    if (parsed != null && parsed > 0) {
                      _emitUpdated(perpSpan: parsed);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<TwoWayPanelCase>(
            // value يتحكم به الـ state؛ initialValue لا يتحدّث بعد أول بناء.
            // ignore: deprecated_member_use
            value: selectedCase,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'حالة البلاطة المجاورة (Table 3.14)',
              hintText: 'مشتقة من حواف الجار أدناه',
              helperText: explicitEdges
                  ? 'مشتقة من حواف الجار الأربع — اخترها لتثبيتها يدوياً بدل الحواف'
                  : (widget.neighbor.isPanelCaseAssumed
                      ? 'مقترحة تلقائياً من الهندسة — اخترها يدوياً لتثبيتها'
                      : null),
            ),
            items: TwoWayPanelCase.values
                .map(
                  (c) => DropdownMenuItem<TwoWayPanelCase>(
                    value: c,
                    child: Text(
                      'Case ${c.caseNumber}: ${c.titleAr}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                )
                .toList(),
            onChanged: (c) {
              if (c != null) _emitUpdated(panelCase: c);
            },
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('الطرف البعيد للجار مستمر مع بلاطة أخرى'),
            subtitle: Text(
              widget.neighbor.isFarEndContinuous
                  ? 'الجساءة النسبية للجار: k = 1.0 / L'
                  : 'الجساءة النسبية للجار: k = 0.75 / L',
              style: theme.textTheme.labelSmall,
            ),
            value: widget.neighbor.isFarEndContinuous,
            onChanged: (val) => _emitUpdated(isFarCont: val),
          ),
          const SizedBox(height: 4),
          Text(
            'حواف الجار الأربع',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            'الحافة المشتركة مع البلاطة المدروسة: مستمرة دائماً',
            style: theme.textTheme.labelSmall,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text('الحافة $startName للجار مستمرة'),
            value: edges.lateralStartContinuous,
            onChanged: (val) => _emitUpdated(lateralStart: val),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text('الحافة $endName للجار مستمرة'),
            value: edges.lateralEndContinuous,
            onChanged: (val) => _emitUpdated(lateralEnd: val),
          ),
          if (derivedText != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                derivedText,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          if (edges.conflictNoteAr != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                edges.conflictNoteAr!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          const SizedBox(height: 4),
          TextField(
            controller: _overrideMomCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'عزم سالب مباشر للجار (اختياري — kN.m/m)',
              hintText: 'اتركه فارغاً ليُحسب تلقائياً من Table 3.14',
            ),
            onChanged: (v) {
              if (v.trim().isEmpty) {
                _emitUpdated(clearOverrideMoment: true);
              } else {
                final parsed = double.tryParse(v);
                if (parsed != null && parsed >= 0) {
                  _emitUpdated(overrideMoment: parsed);
                }
              }
            },
          ),
        ],
      ),
    );
  }
}

/// بطاقة إدخال بيانات كابولي متصل بحافة من حواف البلاطة
class CantileverEditorCard extends StatefulWidget {
  final EdgeSide side;
  final CantileverAttachment cantilever;
  final double fallbackLoadN;
  final int revision;
  final ValueChanged<CantileverAttachment> onChanged;

  /// مصدر عزم الكابولي (ستاتيكي أو المعطى في السؤال) وقيمة العزم المعطى (kN.m/m)
  final CantileverMomentSource momentSource;
  final double givenMomentKnM;
  final ValueChanged<CantileverMomentSource>? onMomentSourceChanged;

  const CantileverEditorCard({
    super.key,
    required this.side,
    required this.cantilever,
    required this.fallbackLoadN,
    required this.revision,
    required this.onChanged,
    this.momentSource = CantileverMomentSource.statics,
    this.givenMomentKnM = 0.0,
    this.onMomentSourceChanged,
  });

  @override
  State<CantileverEditorCard> createState() => _CantileverEditorCardState();
}

class _CantileverEditorCardState extends State<CantileverEditorCard> {
  late TextEditingController _lengthCtrl;

  @override
  void initState() {
    super.initState();
    _lengthCtrl = TextEditingController(
      text: widget.cantilever.lengthM.toStringAsFixed(2),
    );
  }

  @override
  void didUpdateWidget(covariant CantileverEditorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) {
      _lengthCtrl.text = widget.cantilever.lengthM.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _lengthCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mStatic =
        widget.cantilever.negativeMomentKnPerM(widget.fallbackLoadN);
    final mCant = widget.cantilever.supportMomentKnPerM(
      widget.fallbackLoadN,
      source: widget.momentSource,
      givenMomentKnM: widget.givenMomentKnM,
    );
    final bool usesGiven = (mCant - mStatic).abs() > 1e-9;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.safeGreen.withAlpha(110)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.balcony_rounded,
                size: 18,
                color: AppColors.safeGreen,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'بيانات الكابولي عند ${widget.side.titleAr}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.safeGreen,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _lengthCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'طول الكابولي lc (m)',
                    suffixText: 'm',
                  ),
                  onChanged: (v) {
                    final parsed = double.tryParse(v);
                    if (parsed != null && parsed > 0) {
                      widget.onChanged(
                        CantileverAttachment(
                          side: widget.side,
                          lengthM: parsed,
                          customDesignLoadN:
                              widget.cantilever.customDesignLoadN,
                          label: widget.cantilever.label,
                        ),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.safeGreen.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'عزم الكابولي: ${mCant.toStringAsFixed(2)} kN.m/m',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.safeGreen,
                        ),
                      ),
                      if (usesGiven) ...[
                        const SizedBox(height: 2),
                        Text(
                          'العزم الستاتيكي n·l²/2 = ${mStatic.toStringAsFixed(2)} kN.m/m',
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                      const SizedBox(height: 2),
                      Text(
                        'امتداد التسليح 1.5L = ${widget.cantilever.anchorExtensionInsideSlabM.toStringAsFixed(2)} m',
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (widget.onMomentSourceChanged != null) ...[
            const SizedBox(height: 10),
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
              selected: {widget.momentSource},
              onSelectionChanged: (v) =>
                  widget.onMomentSourceChanged!(v.first),
            ),
            if (widget.momentSource == CantileverMomentSource.givenSupportMoment &&
                widget.givenMomentKnM <= 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'لم يُدخل عزم مسند معطى (الخيارات المتقدمة)؛ سيُستخدم العزم الستاتيكي.',
                  style: theme.textTheme.labelSmall,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
