import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:app/core/dio_client.dart';
import 'package:app/core/secure_storage.dart';
import 'package:app/shared/tokens/pf_colors.dart';
import 'package:app/shared/tokens/pf_radius.dart';
import 'package:app/shared/tokens/pf_spacing.dart';
import 'package:app/shared/tokens/pf_typography.dart';
import 'package:app/shared/widgets/pf_card.dart';
import 'package:app/shared/widgets/pf_button.dart';
import 'package:app/shared/widgets/pf_divider.dart';
import 'package:app/shared/widgets/pf_badge.dart';
import 'package:app/features/settings/data/exchange_key.dart';
import 'package:app/features/settings/data/settings_repository.dart';

/// Section for managing exchange API keys.
class ExchangeKeySection extends StatefulWidget {
  final void Function(String)? onShowSuccess;
  final void Function(String)? onShowError;

  const ExchangeKeySection({
    super.key,
    this.onShowSuccess,
    this.onShowError,
  });

  @override
  State<ExchangeKeySection> createState() => _ExchangeKeySectionState();
}

class _ExchangeKeySectionState extends State<ExchangeKeySection> {
  List<ExchangeKey> _keys = [];
  bool _loading = true;
  bool _saving = false;
  String? _testingId;
  bool _obscureSecret = true;

  final _formKey = GlobalKey<FormState>();
  final _exchangeCtrl = TextEditingController();
  final _labelCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();
  final _apiSecretCtrl = TextEditingController();

  late SettingsRepository _repo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initRepo();
      if (mounted) _load();
    });
  }

  Future<void> _initRepo() async {
    final storage = SecureStorage();
    final dio = DioClient(storage);
    _repo = SettingsRepository(dio.dio);
  }

  @override
  void dispose() {
    _exchangeCtrl.dispose();
    _labelCtrl.dispose();
    _apiKeyCtrl.dispose();
    _apiSecretCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final keys = await _repo.getExchangeKeys();
      if (mounted) setState(() { _keys = keys; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _error('Не удалось загрузить ключи: $e');
      }
    }
  }

  Future<void> _addKey() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await _repo.createExchangeKey(
        exchange: _exchangeCtrl.text.trim().toLowerCase(),
        label: _labelCtrl.text.trim(),
        apiKey: _apiKeyCtrl.text.trim(),
        apiSecret: _apiSecretCtrl.text.trim(),
      );
      _exchangeCtrl.clear();
      _labelCtrl.clear();
      _apiKeyCtrl.clear();
      _apiSecretCtrl.clear();
      await _load();
      if (mounted) _success('Ключ добавлен');
    } catch (e) {
      if (mounted) _error('Ошибка: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteKey(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить ключ?'),
        content: const Text('Это действие нельзя отменить.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _repo.deleteExchangeKey(id);
      await _load();
      if (mounted) _success('Ключ удалён');
    } catch (e) {
      if (mounted) _error('Ошибка: $e');
    }
  }

  Future<void> _checkKey(String id) async {
    setState(() => _testingId = id);
    try {
      final updated = await _repo.checkExchangeKey(id);
      if (mounted) {
        setState(() {
          final idx = _keys.indexWhere((k) => k.id == id);
          if (idx >= 0) _keys[idx] = updated;
          _testingId = null;
        });
        _success('Ключ проверен: ${updated.statusLabel}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _testingId = null);
        _error('Ошибка проверки: $e');
      }
    }
  }

  void _success(String msg) {
    widget.onShowSuccess?.call(msg);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: const Color(0xFF2E7D32)),
      );
    }
  }

  void _error(String msg) {
    widget.onShowError?.call(msg);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red.shade800),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pc = PfColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ──
        Row(
          children: [
            Container(
              width: 8, height: 8,
              decoration: const BoxDecoration(
                color: PfColors.accentSettings, shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'API ключи бирж',
              style: PfTypography.titleMd.copyWith(color: pc.foregroundC),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Ключи шифруются и хранятся в БД. Никто, кроме вас, не имеет к ним доступа.',
          style: PfTypography.bodySm.copyWith(color: pc.mutedForegroundC),
        ),
        const SizedBox(height: 24),

        // ── Existing keys ──
        if (_loading)
          const Center(child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ))
        else if (_keys.isEmpty)
          _buildEmpty(pc)
        else
          ..._keys.map((k) => _buildKeyCard(k, pc)),

        const SizedBox(height: 24),
        const PfDivider(),
        const SizedBox(height: 24),

        // ── Add new key form ──
        Text(
          'Добавить ключ',
          style: PfTypography.titleMd.copyWith(color: pc.foregroundC),
        ),
        const SizedBox(height: 16),
        Form(
          key: _formKey,
          child: Column(
            children: [
              _buildTextField(
                controller: _exchangeCtrl,
                label: 'Биржа',
                hint: 'binance',
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Укажите биржу';
                  final e = v.trim().toLowerCase();
                  if (!['binance', 'mexc', 'bybit'].contains(e)) {
                    return 'Поддерживаются: binance, mexc, bybit';
                  }
                  return null;
                },
                pc: pc,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _labelCtrl,
                label: 'Название (опционально)',
                hint: 'Binance основной',
                pc: pc,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _apiKeyCtrl,
                label: 'API Key',
                hint: 'Вставьте API ключ',
                validator: (v) => v == null || v.trim().isEmpty ? 'Обязательное поле' : null,
                pc: pc,
              ),
              const SizedBox(height: 12),
              _buildSecretField(pc),
              const SizedBox(height: 20),
              PfButton(
                label: _saving ? 'Добавление...' : 'Добавить ключ',
                icon: PhosphorIconsFill.plus,
                expanded: true,
                onPressed: _saving ? null : _addKey,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty(PfColors pc) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            PhosphorIcon(
              PhosphorIconsFill.key,
              size: 48,
              color: pc.mutedForegroundC.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text(
              'Нет API ключей',
              style: PfTypography.titleMd.copyWith(color: pc.mutedForegroundC),
            ),
            const SizedBox(height: 4),
            Text(
              'Добавьте ключ биржи для real-time торговли',
              style: PfTypography.bodySm.copyWith(
                  color: pc.mutedForegroundC.withValues(alpha: 0.6)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyCard(ExchangeKey key, PfColors pc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: PfSpacing.sm),
      child: PfCard(
        padding: const EdgeInsets.all(PfSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _exchangeIcon(key.exchange, pc),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        key.label.isNotEmpty ? key.label : key.exchange.toUpperCase(),
                        style: PfTypography.titleMd.copyWith(color: pc.foregroundC, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        key.exchange.toUpperCase(),
                        style: PfTypography.bodySm.copyWith(color: pc.mutedForegroundC),
                      ),
                    ],
                  ),
                ),
                PfBadge(label: key.statusLabel, variant: key.status == 'valid' ? 'success' : key.status == 'invalid' ? 'destructive' : 'default'),
              ],
            ),
            if (key.balance != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  PhosphorIcon(PhosphorIconsFill.wallet, size: 14, color: pc.mutedForegroundC),
                  const SizedBox(width: 6),
                  Text(
                    'Баланс: \$${key.balance!.toStringAsFixed(2)}',
                    style: PfTypography.bodyMd.copyWith(color: pc.foregroundC),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: PfButton(
                    label: _testingId == key.id ? 'Проверка...' : 'Проверить',
                    icon: PhosphorIconsFill.arrowClockwise,
                    size: 'sm',
                    variant: 'secondary',
                    onPressed: _testingId != null ? null : () => _checkKey(key.id),
                  ),
                ),
                const SizedBox(width: 8),
                PfButton(
                  label: 'Удалить',
                  icon: PhosphorIconsFill.trash,
                  size: 'sm',
                  variant: 'destructive',
                  onPressed: () => _deleteKey(key.id),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? Function(String?)? validator,
    required PfColors pc,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: pc.surfaceC,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: pc.borderC),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: pc.borderC.withValues(alpha: 0.5)),
        ),
      ),
      style: TextStyle(color: pc.foregroundC),
    );
  }

  Widget _buildSecretField(PfColors pc) {
    return TextFormField(
      controller: _apiSecretCtrl,
      obscureText: _obscureSecret,
      validator: (v) => v == null || v.trim().isEmpty ? 'Обязательное поле' : null,
      decoration: InputDecoration(
        labelText: 'API Secret',
        hintText: 'Вставьте секретный ключ',
        filled: true,
        fillColor: pc.surfaceC,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: pc.borderC),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: pc.borderC.withValues(alpha: 0.5)),
        ),
        suffixIcon: IconButton(
          icon: PhosphorIcon(
            _obscureSecret ? PhosphorIconsFill.eye : PhosphorIconsFill.eyeSlash,
            size: 20, color: pc.mutedForegroundC,
          ),
          onPressed: () => setState(() => _obscureSecret = !_obscureSecret),
        ),
      ),
      style: TextStyle(color: pc.foregroundC),
    );
  }

  Widget _exchangeIcon(String exchange, PfColors pc) {
    IconData icon;
    switch (exchange.toLowerCase()) {
      case 'binance':
        icon = PhosphorIconsFill.coin;
      case 'mexc':
        icon = PhosphorIconsFill.coin;
      case 'bybit':
        icon = PhosphorIconsFill.coin;
      default:
        icon = PhosphorIconsFill.buildings;
    }
    return Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: PfRadius.borderRadiusMd,
      ),
      child: Center(
        child: PhosphorIcon(icon, size: 20,
            color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
