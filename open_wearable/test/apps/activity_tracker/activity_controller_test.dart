import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_wearable/apps/activity_tracker/models/activity_models.dart';
import 'package:open_wearable/apps/activity_tracker/view_models/activity_tracker_controller.dart';
import 'activity_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('each activity is one session; pause, disconnect and restart recovery',
      () async {
    final source = ReplayActivitySource();
    final storage = MemoryActivityStorage();
    final c = ActivityTrackerController(
      source: source,
      storage: storage,
      observeLifecycle: false,
    );
    await c.prepare('ear');
    source.still();
    expect(c.engine.calibrated, isTrue);
    // Walking on the overview creates no session and counts nothing.
    source.walk(10);
    expect(c.isTracking, isFalse);
    expect(c.sessions, isEmpty);
    expect(c.todaySteps, 0);
    await c.startActivity(ActivityKind.steps);
    source.walk(10);
    expect(c.current!.steps, 10);
    expect(c.todaySteps, 10);
    c.pause();
    source.walk(10);
    expect(c.current!.steps, 10);
    c.resume();
    source.still();
    source.walk(5);
    expect(c.current!.steps, 15);
    source.status.add('Connection lost');
    expect(c.connected, isFalse);
    expect(c.current!.steps, 15);
    source.still();
    source.walk(5);
    expect(c.current!.steps, 20);
    final steps = await c.finish();
    expect(steps!.kind, ActivityKind.steps);
    expect(steps.endedAt, isNotNull);
    expect(c.isTracking, isFalse);
    await c.startActivity(ActivityKind.squats);
    source.walk(6);
    expect(c.current!.steps, 0);
    await c.checkpoint();
    expect(storage.rawSamples, greaterThan(1000));
    c.dispose();
    await Future<void>.delayed(Duration.zero);
    final restored = ActivityTrackerController(
      source: ReplayActivitySource(),
      storage: storage,
      observeLifecycle: false,
    );
    await restored.ready;
    expect(restored.isTracking, isFalse);
    expect(restored.sessions, hasLength(2));
    final squats = restored.sessions.first;
    expect(squats.kind, ActivityKind.squats);
    expect(squats.interrupted, isTrue);
    expect(squats.endedAt, isNotNull);
    expect(restored.sessions.last.steps, 20);
    expect(restored.sessions.last.interrupted, isFalse);
    expect(restored.todaySteps, 20);
    restored.dispose();
  });
  test('deleting a session removes it, its files and its daily steps',
      () async {
    final source = ReplayActivitySource();
    final storage = MemoryActivityStorage();
    final c = ActivityTrackerController(
      source: source,
      storage: storage,
      observeLifecycle: false,
    );
    await c.prepare('ear');
    source.still();
    await c.startActivity(ActivityKind.steps);
    source.walk(10);
    final first = (await c.finish())!;
    await c.startActivity(ActivityKind.steps);
    source.walk(4);
    expect(c.todaySteps, 14);
    // The running session is protected.
    await c.deleteSession(c.current!);
    expect(c.sessions, hasLength(2));
    await c.deleteSession(first);
    expect(c.sessions.single, same(c.current));
    expect(c.todaySteps, 4);
    expect(storage.deletedIds, [first.id]);
    expect(
      (storage.snapshot!['sessions'] as List).map((s) => s['id']),
      isNot(contains(first.id)),
    );
    c.dispose();
  });
  test('foreground resumes with calibration; background never adds counts',
      () async {
    final source = ReplayActivitySource();
    final c = ActivityTrackerController(
      source: source,
      storage: MemoryActivityStorage(),
      observeLifecycle: false,
    );
    await c.prepare('ear');
    source.still();
    await c.startActivity(ActivityKind.steps);
    c.didChangeAppLifecycleState(AppLifecycleState.paused);
    source.walk(10);
    expect(c.current!.steps, 0);
    c.didChangeAppLifecycleState(AppLifecycleState.resumed);
    source.still();
    source.walk(5);
    expect(c.current!.steps, 5);
    final session = await c.finish();
    expect(session!.endedAt, isNotNull);
    expect(c.isTracking, isFalse);
    // Ending a session keeps the wearable ready for the next activity.
    expect(source.closed, isFalse);
    expect(c.deviceId, isNotNull);
    // Leaving the tracker ends a running session instead of keeping it open.
    await c.startActivity(ActivityKind.jumps);
    expect(c.isTracking, isTrue);
    await c.leave();
    expect(c.isTracking, isFalse);
    expect(c.sessions.first.kind, ActivityKind.jumps);
    expect(c.sessions.first.endedAt, isNotNull);
    expect(source.closed, isTrue);
    c.dispose();
  });
  test('reference errors and unavailable height survive serialization', () {
    final session = ActivitySession(
      id: 'test',
      startedAt: DateTime(2026),
      deviceName: 'ear',
    );
    session.trials.add(
      const ValidationTrial(
        participant: 'P01',
        pattern: 'Slow',
        referenceSource: 'Video',
        kind: ActivityKind.squats,
        detected: 19,
        reference: 20,
      ),
    );
    session.trials.add(
      const ValidationTrial(
        participant: 'P02',
        pattern: 'Head turn',
        referenceSource: 'Video',
        kind: ActivityKind.steps,
        detected: 1,
        reference: 0,
      ),
    );
    session.jumps.add(
      const JumpAttempt(at: 2, flightSeconds: 0.3, reason: 'Impact clipped'),
    );
    final copy = ActivitySession.fromJson(session.toJson());
    expect(copy.trials.first.countError, -1);
    expect(copy.trials.first.absolutePercentageError, 5);
    expect(copy.trials.last.absolutePercentageError, isNull);
    expect(copy.jumps.single.heightCm, isNull);
  });
}
