import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/premium_status.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/premium_service.dart';
import '../../../shared/utils/legal_links.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';

/// Famotive Premium: what it unlocks, the plans (with the 7-day free trial),
/// restore, and the current subscription for parents who have one.
class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  PremiumPeriod _selected = PremiumPeriod.yearly;

  @override
  void initState() {
    super.initState();
    final premium = context.read<PremiumService?>();
    if (premium != null) {
      premium.clearMessages();
      WidgetsBinding.instance.addPostFrameCallback((_) => premium.loadPlans());
    }
  }

  static String get _storeName => !kIsWeb && Platform.isAndroid ? 'Google Play' : 'App Store';

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    final db = context.watch<DatabaseService>();
    final service = context.watch<PremiumService?>();
    final status = user?.premium ?? PremiumStatus.none;
    final household = db.household;
    final isAdmin = household?.isAdmin(user?.id) ?? false;
    String? adminName;
    for (final m in db.familyMembers) {
      if (m.id == household?.ownerId) adminName = m.name;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Famotive Premium')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            const _Header(),
            const SizedBox(height: 16),
            const _Features(),
            const SizedBox(height: 16),
            if (household != null && !isAdmin) ...[
              _InfoCard(
                icon: Icons.info_outline,
                text: household.hasPremium
                    ? 'Photo proof is on in ${household.name}: ${adminName ?? 'its admin'} has Premium.'
                    : 'Premium features in ${household.name} come from its admin'
                        '${adminName == null ? '' : ', $adminName'}. A subscription on your account '
                        'unlocks them in the households you are the admin of.',
              ),
              const SizedBox(height: 16),
            ],
            if (status.isActive)
              _CurrentPlan(status: status, storeName: _storeName)
            else ...[
              if (status.hasPaymentProblem) ...[
                _InfoCard(
                  icon: Icons.error_outline,
                  color: Colors.orange.shade800,
                  text: "Your last payment didn't go through, so Premium is paused. Update your payment "
                      'method in $_storeName to turn it back on.',
                  action: TextButton(
                    onPressed: () => _openManage(context, status.productId),
                    child: const Text('Update Payment'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (service == null)
                const _InfoCard(icon: Icons.storefront_outlined, text: 'Purchases are not available here.')
              else
                _Plans(
                  service: service,
                  selected: _selected,
                  trialAvailable: !status.trialUsed,
                  storeName: _storeName,
                  onSelect: (p) => setState(() => _selected = p),
                ),
            ],
            if (service?.error != null) ...[
              const SizedBox(height: 12),
              Text(
                service!.error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (service?.notice != null) ...[
              const SizedBox(height: 12),
              Text(
                service!.notice!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.growthGreen, fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 16),
            if (service != null)
              Center(
                child: TextButton(
                  onPressed: service.busy ? null : service.restore,
                  child: const Text('Restore Purchases'),
                ),
              ),
            const LegalFooter(prefix: 'Subscriptions are covered by our'),
          ],
        ),
      ),
    );
  }

  static Future<void> _openManage(BuildContext context, String? productId) async {
    final messenger = ScaffoldMessenger.of(context);
    final opened = await launchUrl(
      PremiumService.manageSubscriptionsUri(productId: productId),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      messenger.showSnackBar(
        SnackBar(content: Text('Open your $_storeName account settings to manage your subscription.')),
      );
    }
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        const Text('📸', style: TextStyle(fontSize: AppConstants.emojiIcon4xl)),
        const SizedBox(height: 8),
        Text(
          'Famotive Premium',
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'See that chores are really done.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade700),
        ),
      ],
    );
  }
}

class _Features extends StatelessWidget {
  const _Features();

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppColors.primaryBlue),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(body, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        );

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          row(Icons.photo_camera_outlined, 'Photo proof',
              'Turn it on for any task. Your child snaps a photo when they finish.'),
          row(Icons.auto_awesome_outlined, 'Smart photo check',
              'Each photo is checked on the device for a match with the task, and photos of screens are flagged.'),
          row(Icons.family_restroom, 'For the whole household',
              'Covers every child in the households you are the admin of. Photos are deleted after '
              '${AppConstants.taskPhotoRetentionDays} days.'),
        ],
      ),
    );
  }
}

class _Plans extends StatelessWidget {
  const _Plans({
    required this.service,
    required this.selected,
    required this.trialAvailable,
    required this.storeName,
    required this.onSelect,
  });

  final PremiumService service;
  final PremiumPeriod selected;
  final bool trialAvailable;
  final String storeName;
  final ValueChanged<PremiumPeriod> onSelect;

  @override
  Widget build(BuildContext context) {
    if (service.loadingPlans && service.plans.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (service.plans.isEmpty) {
      return _InfoCard(
        icon: Icons.storefront_outlined,
        text: service.storeAvailable
            ? "Premium isn't available to buy right now. Please try again later."
            : "Couldn't reach the $storeName. Check your connection and try again.",
        action: TextButton(onPressed: service.loadPlans, child: const Text('Try Again')),
      );
    }

    final plan = service.plans.firstWhere((p) => p.period == selected, orElse: () => service.plans.first);
    final trial = trialAvailable && plan.freeTrialOffered;
    final days = AppConstants.premiumTrialDays;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final p in service.plans) ...[
          _PlanTile(
            plan: p,
            selected: p == plan,
            onTap: () => onSelect(p.period),
            savings: _yearlySavings(service.plans, p),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 6),
        AppButton(
          label: trial ? 'Start $days-Day Free Trial' : 'Subscribe for ${plan.perPeriod}',
          icon: Icons.workspace_premium_outlined,
          isLoading: service.busy,
          onPressed: service.busy ? null : () => service.buy(plan),
        ),
        const SizedBox(height: 10),
        // Store-required disclosure of the trial and auto-renewal terms.
        Text(
          trial
              ? 'Free for $days days, then ${plan.perPeriod}. Renews automatically until you cancel. '
                  'Cancel any time in your $storeName account settings at least 24 hours before the '
                  'trial ends and you won\'t be charged.'
              : '${plan.perPeriod}, charged to your $storeName account. Renews automatically until you '
                  'cancel. Cancel any time in your $storeName account settings at least 24 hours before '
                  'the end of the current period.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
        ),
      ],
    );
  }

  /// "Save 30%" for the yearly plan, when both prices are known.
  static String? _yearlySavings(List<PremiumPlan> plans, PremiumPlan p) {
    if (p.period != PremiumPeriod.yearly) return null;
    PremiumPlan? monthly;
    for (final x in plans) {
      if (x.period == PremiumPeriod.monthly) monthly = x;
    }
    if (monthly == null) return null;
    final yearly = p.product.rawPrice;
    final perMonth = monthly.product.rawPrice;
    if (perMonth <= 0 || yearly <= 0 || p.product.currencyCode != monthly.product.currencyCode) return null;
    // On Google Play rawPrice can be the first (trial) phase; skip then.
    if (p.price != p.product.price || monthly.price != monthly.product.price) return null;
    final pct = ((1 - yearly / (perMonth * 12)) * 100).round();
    return pct >= 5 ? 'Save $pct%' : null;
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({required this.plan, required this.selected, required this.onTap, this.savings});

  final PremiumPlan plan;
  final bool selected;
  final VoidCallback onTap;
  final String? savings;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primaryBlue : Colors.grey.shade300;
    return Material(
      color: selected ? AppColors.primaryBlue.withValues(alpha: 0.06) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        side: BorderSide(color: color, width: selected ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  plan.period == PremiumPeriod.yearly ? 'Yearly' : 'Monthly',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
              ),
              if (savings != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.growthGreen,
                    borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                  ),
                  child: Text(
                    savings!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: AppConstants.captionFontSize,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(plan.perPeriod, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CurrentPlan extends StatelessWidget {
  const _CurrentPlan({required this.status, required this.storeName});

  final PremiumStatus status;
  final String storeName;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat.yMMMd().format(status.expiresAt!.toLocal());
    final plan = status.productId == PremiumProducts.yearly ? 'Yearly' : 'Monthly';
    final String title;
    final String detail;
    if (status.state == PremiumState.complimentary) {
      title = 'Premium · Complimentary';
      detail = status.expiresAt!.year >= 2099
          ? 'Premium is included with this account.'
          : 'Premium is included with this account until $date.';
    } else if (status.isTrial) {
      title = 'Free trial';
      detail = status.willRenew
          ? 'Your trial ends $date, then your $plan plan starts.'
          : 'Your trial ends $date. It will not renew.';
    } else if (status.state == PremiumState.grace) {
      title = 'Payment issue';
      detail = "Your last payment didn't go through. Update your payment method in $storeName by $date "
          'to keep Premium.';
    } else if (status.willRenew) {
      title = 'Premium · $plan';
      detail = 'Renews $date.';
    } else {
      title = 'Premium · $plan';
      detail = 'Cancelled. Premium stays on until $date.';
    }

    final complimentary = status.state == PremiumState.complimentary;
    final managedHere = status.platform == null ||
        (status.platform == 'android') == (!kIsWeb && Platform.isAndroid);

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium, color: Colors.amber, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(detail),
          const SizedBox(height: 4),
          Text(
            'Photo proof is on in the households you are the admin of.',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (complimentary)
            const SizedBox.shrink()
          else if (managedHere)
            AppButton(
              label: 'Manage Subscription',
              variant: AppButtonVariant.secondary,
              icon: Icons.open_in_new,
              onPressed: () => _PremiumScreenState._openManage(context, status.productId),
            )
          else
            Text(
              'This subscription was bought on ${status.platform == 'android' ? 'Google Play' : 'the App Store'}. '
              'Manage it from a device signed in to that store account.',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.text, this.color, this.action});

  final IconData icon;
  final String text;
  final Color? color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color ?? Colors.grey.shade700),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: TextStyle(color: color))),
            ],
          ),
          if (action != null) Align(alignment: Alignment.centerRight, child: action),
        ],
      ),
    );
  }
}
