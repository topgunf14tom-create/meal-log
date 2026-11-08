import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../core/dates.dart';
import '../../data/entities.dart';
import '../../widgets/weight_chart.dart';
import '../inbody/inbody_history_screen.dart';

class WeightScreen extends StatefulWidget {
  const WeightScreen({super.key});

  @override
  State<WeightScreen> createState() => _WeightScreenState();
}

class _WeightScreenState extends State<WeightScreen> {
  DateTime _date = dayOnly(DateTime.now());
  final _kg = TextEditingController();
  int _range = 30;
  List<WeightEntry> _all = [];

  AppServices get s => AppServices.I;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _kg.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await s.db.weightsSince(ymd(addDays(dayOnly(DateTime.now()), -366)));
    if (!mounted) return;
    setState(() => _all = list);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: dayOnly(DateTime.now()),
    );
    if (picked != null) setState(() => _date = dayOnly(picked));
  }

  Future<void> _save() async {
    final v = double.tryParse(_kg.text.trim());
    if (v == null || v < 20 || v > 300) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('体重を正しく入力してください（kg）')));
      return;
    }
    final kg = double.parse(v.toStringAsFixed(1));
    await s.db.saveWeight(WeightEntry(date: ymd(_date), kg: kg));
    _kg.clear();
    if (mounted) FocusScope.of(context).unfocus();
    await _load();
  }

  Future<void> _openInBody() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InBodyHistoryScreen()));
    await _load();
  }

  Future<void> _delete(WeightEntry e) async {
    await s.db.deleteWeight(e.date);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final today = dayOnly(DateTime.now());
    final from = addDays(today, -_range + 1);
    final shown = _all.where((e) => !parseYmd(e.date).isBefore(from)).toList();
    final recent = _all.reversed.take(30).toList();
    final last = _all.isEmpty ? null : _all.last;

    return Scaffold(
      appBar: AppBar(
        title: const Text('体重'),
        actions: [
          TextButton.icon(
            onPressed: _openInBody,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('InBody'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  OutlinedButton(onPressed: _pickDate, child: Text(jpDate(_date))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _kg,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: '体重',
                        hintText: last == null ? '例：65.0' : '前回 ${last.kg.toStringAsFixed(1)}',
                        suffixText: 'kg',
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _save(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _save, child: const Text('記録')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 7, label: Text('7日')),
              ButtonSegment(value: 30, label: Text('30日')),
              ButtonSegment(value: 90, label: Text('90日')),
            ],
            selected: {_range},
            onSelectionChanged: (sel) => setState(() => _range = sel.first),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: WeightChart(entries: shown, from: from, to: today),
            ),
          ),
          if (shown.length >= 2)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '期間の変化：${(shown.last.kg - shown.first.kg) >= 0 ? '+' : ''}${(shown.last.kg - shown.first.kg).toStringAsFixed(1)} kg',
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 16),
          Text('最近の記録', style: Theme.of(context).textTheme.titleMedium),
          for (final e in recent)
            ListTile(
              dense: true,
              title: Text(jpDate(parseYmd(e.date))),
              subtitle: e.isAuto ? const Text('ヘルスコネクトから自動') : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${e.kg.toStringAsFixed(1)} kg'
                      '${e.bodyFatPct == null ? '' : '  ${e.bodyFatPct!.toStringAsFixed(1)}%'}'),
                  IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(e)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
