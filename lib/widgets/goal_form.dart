import 'package:flutter/material.dart';

import '../core/dates.dart';
import '../core/format.dart';
import '../core/nutrition.dart';
import '../data/entities.dart';

/// 目標カロリーと PFC 比率の入力フォーム（初回案内と設定で共用）
class GoalForm extends StatefulWidget {
  const GoalForm({super.key, required this.initial, required this.onSave, this.buttonLabel = '目標を保存'});

  final Goal initial;
  final Future<void> Function(Goal goal) onSave;
  final String buttonLabel;

  @override
  State<GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends State<GoalForm> {
  late final _kcal = TextEditingController(text: widget.initial.targetKcal.toString());
  late final _p = TextEditingController(text: widget.initial.pRatio.toString());
  late final _f = TextEditingController(text: widget.initial.fRatio.toString());
  late final _c = TextEditingController(text: widget.initial.cRatio.toString());
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_kcal, _p, _f, _c]) {
      c.dispose();
    }
    super.dispose();
  }

  Goal? _current() {
    final k = int.tryParse(_kcal.text.trim());
    final p = int.tryParse(_p.text.trim());
    final f = int.tryParse(_f.text.trim());
    final c = int.tryParse(_c.text.trim());
    if (k == null || p == null || f == null || c == null) return null;
    return Goal(startDate: ymd(DateTime.now()), targetKcal: k, pRatio: p, fRatio: f, cRatio: c);
  }

  Future<void> _save() async {
    final g = _current();
    String? err;
    if (g == null) {
      err = '数値を入力してください';
    } else if (g.targetKcal < 800 || g.targetKcal > 6000) {
      err = '目標カロリーは800〜6000kcalの範囲で入力してください';
    } else if (g.pRatio + g.fRatio + g.cRatio != 100) {
      err = 'P・F・Cの合計が100%になるようにしてください（現在 ${g.pRatio + g.fRatio + g.cRatio}%）';
    }
    setState(() => _error = err);
    if (err != null || g == null) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(g);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _num(TextEditingController c, String label, {String? suffix}) => TextField(
        controller: c,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label, suffixText: suffix, border: const OutlineInputBorder()),
        onChanged: (_) => setState(() {}),
      );

  @override
  Widget build(BuildContext context) {
    final g = _current();
    final grams = g == null ? null : targetGrams(g);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _num(_kcal, '目標カロリー（1日）', suffix: 'kcal'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _num(_p, 'P たんぱく質', suffix: '%')),
            const SizedBox(width: 8),
            Expanded(child: _num(_f, 'F 脂質', suffix: '%')),
            const SizedBox(width: 8),
            Expanded(child: _num(_c, 'C 炭水化物', suffix: '%')),
          ],
        ),
        const SizedBox(height: 8),
        if (grams != null)
          Text('目標量：P ${kcal0(grams.p)}g / F ${kcal0(grams.f)}g / C ${kcal0(grams.c)}g',
              style: Theme.of(context).textTheme.bodySmall),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 12),
        FilledButton(onPressed: _saving ? null : _save, child: Text(widget.buttonLabel)),
      ],
    );
  }
}
