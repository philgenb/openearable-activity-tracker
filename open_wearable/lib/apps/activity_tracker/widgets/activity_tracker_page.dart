import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_wearable/widgets/common/app_section_card.dart';
import 'package:open_wearable/apps/widgets/select_earable_view.dart';
import 'package:open_wearable/apps/widgets/app_compatibility.dart';
import 'package:provider/provider.dart';
import '../models/activity_models.dart';
import '../view_models/activity_tracker_controller.dart';
import 'activity_session_pages.dart';
import 'activity_widgets.dart';

/// Built-in mini-app entry; history and interrupted sessions work offline.
///
/// The overview records nothing. Each activity tile starts its own session,
/// and leaving the activity page ends it.
class ActivityTrackerPage extends StatefulWidget {
  const ActivityTrackerPage({super.key, this.wearable});
  final Wearable? wearable;
  @override
  State<ActivityTrackerPage> createState() => _ActivityTrackerPageState();
}

class _ActivityTrackerPageState extends State<ActivityTrackerPage> {
  bool _fitChecked = false, _starting = false;
  late ActivityTrackerController _controller;
  @override
  void initState() {
    super.initState();
    _controller = context.read<ActivityTrackerController>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.wearable != null) {
        _controller.prepare(widget.wearable!.deviceId);
      }
    });
  }

  @override
  void dispose() {
    _controller.leave();
    super.dispose();
  }

  Future<void> _start(ActivityKind kind) async {
    setState(() => _starting = true);
    await _controller.startActivity(kind);
    if (!mounted) return;
    setState(() => _starting = false);
    if (_controller.isTracking) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const _ActivityPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Consumer<ActivityTrackerController>(
        builder: (context, c, _) {
          if (!c.isTracking && c.deviceId == null) {
            return ActivityLayout(
              title: 'Activity Tracker',
              actions: [
                OutlinedButton(
                  onPressed: () =>
                      Navigator.push(context, ActivitySessionsPage.route()),
                  child: const Text('View sessions'),
                ),
                ElevatedButton(
                  onPressed: () => _chooseWearable(context),
                  child: const Text('Choose wearable'),
                ),
              ],
              children: const [
                SizedBox(height: 12),
                Text(
                  'Ready to move?',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
                ActivityNotice(
                  'Connect your earable',
                  'Choose a connected OpenEarable to start tracking. Your saved sessions are available at any time.',
                ),
              ],
            );
          }
          return _overview(c);
        },
      );

  Widget _overview(ActivityTrackerController c) {
    final canStart = !_starting &&
        !c.isTracking &&
        _fitChecked &&
        c.connected &&
        c.engine.calibrated;
    final latest = c.sessions.where((s) => s.endedAt != null).firstOrNull;
    final lastJump = c.sessions
        .expand((s) => s.jumps.reversed)
        .where((j) => j.heightCm != null)
        .firstOrNull;
    Widget tile(ActivityKind kind, String detail) => _activityCard(
          context,
          kind,
          detail,
          canStart ? () => _start(kind) : null,
        );
    return ActivityLayout(
      title: 'Activity Tracker',
      actions: [
        ElevatedButton(
          onPressed: () =>
              Navigator.push(context, ActivitySessionsPage.route()),
          child: const Text('View sessions'),
        ),
      ],
      children: [
        const SizedBox(height: 12),
        const Text(
          'Ready to move?',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        Text(
          'Wear your earable securely and take a moment to get comfortable.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        ActivityCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.hearing,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.deviceName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ActivityCaption(
                          c.connected
                              ? 'Connected · motion data available'
                              : 'Connecting to motion sensors',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const ActivityBadge('Selected'),
            ],
          ),
        ),
        AppSectionCard(
          title: 'A quick check',
          child: Column(
            children: [
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  '1. Check the fit',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                subtitle: const ActivityCaption('Wear your earable securely.'),
                value: _fitChecked,
                onChanged: (v) => setState(() => _fitChecked = v ?? false),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  '2. Stand still briefly',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                subtitle: const ActivityCaption(
                  'Keep your head relaxed for 1.5 seconds.',
                ),
                trailing: c.engine.calibrated
                    ? const Icon(Icons.check)
                    : SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          value:
                              c.connected ? c.engine.calibrationProgress : null,
                          strokeWidth: 2,
                        ),
                      ),
              ),
              const Divider(),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '3. Choose an activity',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                subtitle: ActivityCaption(
                  'Each activity is saved as its own session.',
                ),
              ),
            ],
          ),
        ),
        ActivityNotice(
          c.engine.calibrated ? 'You’re ready' : 'Waiting for a steady signal',
          c.engine.calibrated
              ? 'Motion data is available. Choose an activity to begin.'
              : c.interruption ??
                  'Stand still while the motion sensors calibrate.',
        ),
        if (c.interruption != null && !c.preparing)
          TextButton.icon(
            onPressed: c.reconnect,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry connection'),
          ),
        if (c.storageError != null)
          ActivityNotice(
            'Storage needs attention',
            c.storageError!,
            warning: true,
          ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Choose an activity',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              SizedBox(width: 8),
              Flexible(child: ActivityCaption('One session each')),
            ],
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: tile(
                ActivityKind.steps,
                'Today ${_number(c.todaySteps)} steps',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: tile(ActivityKind.squats, 'Count complete repetitions'),
            ),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: tile(ActivityKind.pushUps, 'Count complete repetitions'),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: tile(
                ActivityKind.jumps,
                lastJump == null
                    ? 'Detect jumps and estimate height'
                    : 'Last estimate ${lastJump.heightCm!.toStringAsFixed(1)} cm',
              ),
            ),
          ],
        ),
        if (latest != null)
          ActivityCard(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ActivitySummaryPage(session: latest),
              ),
            ),
            child: Row(
              children: [
                ActivityIcon(activityIconName(latest.kind), box: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Last session · ${latest.kind?.label ?? 'Workout'}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      ActivityCaption(activitySessionResult(latest)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        const ActivityCaption(
          'Jump height is an estimate. Tracking pauses when the app moves to the background. Leaving an activity ends its session.',
        ),
      ],
    );
  }
}

Widget _activityCard(
  BuildContext context,
  ActivityKind kind,
  String detail,
  VoidCallback? onTap,
) =>
    ActivityCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ActivityIcon(activityIconName(kind), box: true),
          const SizedBox(height: 8),
          Text(
            kind.label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          SizedBox(height: 34, child: ActivityCaption(detail)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Start',
                  style: TextStyle(
                    fontSize: 12,
                    color: onTap == null
                        ? Theme.of(context).disabledColor
                        : Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 16,
                color: onTap == null
                    ? Theme.of(context).disabledColor
                    : Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        ],
      ),
    );

void _chooseWearable(BuildContext context) => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SelectEarableView(
          supportedDevicePrefixes: const ['OpenEarable'],
          requiredCapabilities: [
            WearableCapabilityRequirement.capability<SensorManager>(
              label: 'sensor streaming',
            ),
            WearableCapabilityRequirement.capability<
                SensorConfigurationManager>(label: 'sensor configuration'),
          ],
          startApp: (wearable, _) async =>
              ActivityTrackerPage(wearable: wearable),
        ),
      ),
    );
String _number(int value) => value
    .toString()
    .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

class _DeviceStrip extends StatelessWidget {
  const _DeviceStrip(this.controller);
  final ActivityTrackerController controller;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        child: Row(
          children: [
            const Icon(Icons.bluetooth, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: ActivityCaption(
                '${controller.deviceName} · ${controller.connected ? 'Connected' : 'Disconnected'}',
              ),
            ),
          ],
        ),
      );
}

/// Live page of one activity session; leaving it ends the session.
class _ActivityPage extends StatelessWidget {
  const _ActivityPage();
  @override
  Widget build(BuildContext context) => Consumer<ActivityTrackerController>(
        builder: (context, c, _) {
          if (!c.isTracking) {
            return ActivityLayout(
              title: 'Session saved',
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Back to overview'),
                ),
              ],
              children: const [
                ActivityNotice(
                  'Session saved',
                  'Your confirmed results are in Sessions.',
                ),
              ],
            );
          }
          if (!c.connected || c.paused) {
            return _ConfirmLeave(
              controller: c,
              child: ActivityInterruptionView(controller: c),
            );
          }
          final session = c.current!;
          final jumpMode = c.mode == ActivityKind.jumps;
          final stepMode = c.mode == ActivityKind.steps;
          final last = session.jumps.lastOrNull;
          return _ConfirmLeave(
            controller: c,
            child: ActivityLayout(
              title: c.mode.label,
              actions: [
                OutlinedButton(onPressed: c.pause, child: const Text('Pause')),
                ElevatedButton(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    await c.finish();
                    navigator.pop();
                  },
                  child: const Text('End session'),
                ),
              ],
              children: [
                _DeviceStrip(c),
                ActivityCard(
                  padding: 18,
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      children: [
                        ActivityBadge(
                          !c.engine.calibrated
                              ? 'Stand still to calibrate'
                              : jumpMode
                                  ? c.engine.phase
                                  : stepMode
                                      ? 'Counting steps'
                                      : 'Counting repetitions',
                        ),
                        const SizedBox(height: 12),
                        ActivityIcon(activityIconName(c.mode), size: 30),
                        const SizedBox(height: 8),
                        Text(
                          jumpMode
                              ? last?.heightCm?.toStringAsFixed(1) ?? '—'
                              : stepMode
                                  ? _number(session.steps)
                                  : '${c.repetitions}',
                          style: const TextStyle(
                            fontSize: 80,
                            height: 1.15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ActivityCaption(
                          jumpMode
                              ? 'cm · estimated height'
                              : stepMode
                                  ? 'steps in this session'
                                  : 'repetitions',
                        ),
                        const SizedBox(height: 12),
                        if (jumpMode)
                          Text(
                            session.bestHeightCm == null
                                ? 'Your next jump will appear here'
                                : 'Session best ${session.bestHeightCm!.toStringAsFixed(1)} cm',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        else if (!stepMode) ...[
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(
                              4,
                              (i) => Container(
                                width: 38,
                                height: 4,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 3),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(
                                        alpha: i <
                                                (c.engine.phase ==
                                                        'Returning to start'
                                                    ? 3
                                                    : c.engine.phase ==
                                                            'Lowering'
                                                        ? 2
                                                        : 1)
                                            ? 1
                                            : 0.16,
                                      ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ActivityCaption(
                            c.engine.phase,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (!jumpMode) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ActivityMetric(
                          'Started',
                          activityTime(session.startedAt),
                          detail: 'This session',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: stepMode
                            ? ActivityMetric(
                                'Today',
                                _number(c.todaySteps),
                                detail: 'All step sessions',
                              )
                            : ActivityMetric(
                                'Elapsed',
                                activityDuration(c.setSeconds),
                                detail: 'Tracking active',
                              ),
                      ),
                    ],
                  ),
                  AppSectionCard(
                    title: 'Movement',
                    subtitle: c.engine.quality,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ActivitySignal(c.signal),
                        const SizedBox(height: 10),
                        ActivityCaption(
                          switch (c.mode) {
                            ActivityKind.pushUps =>
                              'Hold the start position once, then continue at your own pace. No pause is needed between repetitions. Keep your head aligned with your body.',
                            ActivityKind.squats =>
                              'Hold the start position briefly. Lower and return fully; keep your head aligned with your body.',
                            _ =>
                              'Walk normally. The first steps appear after three regular steps.',
                          },
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  const ActivityNotice(
                    'Jump straight up',
                    'Begin from a still position. Keep take-off and landing posture similar. Height uses flight time and is an estimate.',
                  ),
                  AppSectionCard(
                    title: 'Recent attempts',
                    child: session.jumps.isEmpty
                        ? const ActivityCaption(
                            'Stand still briefly, then jump and land in place.',
                          )
                        : Column(
                            children: session.jumps.reversed
                                .take(5)
                                .map(
                                  (j) => ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      'Jump ${session.jumps.indexOf(j) + 1}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: ActivityCaption(
                                      j.reason ??
                                          'Good signal · flight ${j.flightSeconds.toStringAsFixed(2)} s',
                                    ),
                                    trailing: Text(
                                      j.heightCm == null
                                          ? '—'
                                          : '${j.heightCm!.toStringAsFixed(1)} cm',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                  ),
                ],
              ],
            ),
          );
        },
      );
}

/// Back navigation asks before ending the activity's session; there is no
/// option to leave it running in the background.
class _ConfirmLeave extends StatelessWidget {
  const _ConfirmLeave({required this.controller, required this.child});
  final ActivityTrackerController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final c = controller;
          final end = await showDialog<bool>(
            context: context,
            builder: (dialog) => AlertDialog(
              title: Text('End ${c.mode.label.toLowerCase()} session?'),
              content: const Text(
                'Your results are saved and you return to the overview.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialog),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialog, true),
                  child: const Text('End session'),
                ),
              ],
            ),
          );
          if (end != true || !context.mounted) return;
          final navigator = Navigator.of(context);
          await c.finish();
          navigator.pop();
        },
        child: child,
      );
}

/// Pause and disconnect states preserve counters and offer explicit recovery.
class ActivityInterruptionView extends StatelessWidget {
  const ActivityInterruptionView({super.key, required this.controller});
  final ActivityTrackerController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final lost = !c.connected;
    final (count, unit) = switch (c.mode) {
      ActivityKind.steps => (c.current?.steps ?? 0, 'confirmed session steps'),
      ActivityKind.jumps => (c.current?.jumps.length ?? 0, 'jump attempts'),
      _ => (c.repetitions, 'confirmed repetitions'),
    };
    return ActivityLayout(
      title: c.mode.label,
      actions: [
        OutlinedButton(
          onPressed: () async {
            final session = await c.finish();
            if (context.mounted && session != null) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => ActivitySummaryPage(session: session),
                ),
              );
            }
          },
          child: const Text('End session'),
        ),
        ElevatedButton(
          onPressed: lost
              ? () async {
                  await c.reconnect();
                  if (context.mounted && !c.connected) {
                    GoRouter.maybeOf(context)?.push('/connect-devices');
                  }
                }
              : c.resume,
          child: Text(lost ? 'Reconnect' : 'Resume'),
        ),
      ],
      children: [
        _DeviceStrip(c),
        ActivityNotice(
          lost ? 'Connection lost' : 'Take your time',
          lost
              ? 'Your confirmed results are saved. Reconnect your earable, then stand still briefly.'
              : 'Counting is paused. Your confirmed results are saved.',
          warning: lost,
        ),
        ActivityCard(
          padding: 24,
          child: Column(
            children: [
              Icon(
                lost ? Icons.bluetooth_disabled : Icons.pause_circle_outline,
                size: 38,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                '$count',
                style: const TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.w700,
                ),
              ),
              ActivityCaption(unit),
              const SizedBox(height: 18),
              ActivityBadge(
                lost ? 'Tracking interrupted' : 'Paused',
                warning: lost,
              ),
            ],
          ),
        ),
        ActivityNotice(
          lost ? 'Bring your earable closer' : 'Ready when you are',
          lost
              ? c.interruption ??
                  'Check that your earable is switched on and seated securely.'
              : 'Resume to continue this session, or end it.',
        ),
      ],
    );
  }
}
