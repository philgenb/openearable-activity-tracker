import 'dart:math' as math;
import 'activity_models.dart';
import 'push_up_detector.dart';

/// Events from one sample. Counts are deltas, so UI throttling loses no events.
class ActivityUpdate {
  const ActivityUpdate({this.steps = 0, this.repetitions = 0, this.jump});
  final int steps, repetitions;
  final JumpAttempt? jump;
}

/// Causal, replayable first implementation of the core tracking algorithms.
///
/// Requires still calibration, SI units and strictly increasing sensor time.
/// Gaps reset partial movements, never confirmed counts. These heuristics need
/// ear-worn, participant-independent evaluation before accuracy claims.
class ActivityEngine {
  static const gravity = 9.80665;
  ActivityKind kind = ActivityKind.steps;
  bool calibrated = false;
  double calibrationProgress = 0;
  String phase = 'Stand still briefly';
  double movement = 0;
  String quality = 'Waiting for motion data';
  double? _lastTime;
  MotionVector _up = const MotionVector(0, 0, 1);
  MotionVector _calibrationSum = MotionVector.zero;
  double _calibrationSeconds = 0;
  int _calibrationSamples = 0;
  double _gravityMagnitude = gravity;
  double _smooth = 0;
  final _steps = _StepDetector();
  final _reps = _RepetitionDetector();
  final _pushUps = PushUpDetector();
  final _jumps = _JumpDetector();

  /// Validated calibration snapshot for reproducing a session offline.
  Map<String, double> get calibration =>
      {'x': _up.x, 'y': _up.y, 'z': _up.z, 'gravity': _gravityMagnitude};
  void restoreCalibration(Map<String, double> value) {
    final up = MotionVector(value['x'] ?? 0, value['y'] ?? 0, value['z'] ?? 0);
    final g = value['gravity'] ?? 0;
    if (!up.isFinite ||
        (up.length - 1).abs() > 0.05 ||
        !g.isFinite ||
        (g - gravity).abs() > 0.6) {
      throw ArgumentError('Invalid initial IMU calibration');
    }
    recalibrate();
    _up = up.unit;
    _gravityMagnitude = g;
    calibrated = true;
    calibrationProgress = 1;
  }

  /// Clears transient state on pause/reconnect, requiring a fresh still window.
  void recalibrate() {
    calibrated = false;
    calibrationProgress = 0;
    _lastTime = null;
    _calibrationSum = MotionVector.zero;
    _calibrationSeconds = 0;
    _calibrationSamples = 0;
    _smooth = 0;
    movement = 0;
    _steps.reset();
    _reps.reset();
    _pushUps.reset();
    _jumps.reset();
    phase = 'Stand still briefly';
  }

  /// Switching modes discards incomplete cycles and provisional steps.
  void select(ActivityKind next) {
    kind = next;
    _steps.reset();
    _reps.reset();
    _pushUps.reset();
    _jumps.reset();
    _smooth = 0;
    phase = next == ActivityKind.steps
        ? 'Tracking steps'
        : 'Hold the start position';
  }

  ActivityUpdate add(MotionSample s) {
    if (!s.seconds.isFinite ||
        !s.acceleration.isFinite ||
        (s.gyroscope != null && !s.gyroscope!.isFinite)) {
      recalibrate();
      quality = 'Invalid sample · stand still';
      return const ActivityUpdate();
    }
    final previousTime = _lastTime;
    final dt = previousTime == null ? 0.01 : s.seconds - previousTime;
    // Duplicate/out-of-order packets must not advance any detector.
    if (dt <= 0) {
      if (dt < -0.5) {
        recalibrate();
        quality = 'Sensor clock restarted · stand still';
      }
      return const ActivityUpdate();
    }
    if (previousTime != null && dt > 0.12) {
      recalibrate();
      quality = 'Data gap · stand still to resume';
    }
    _lastTime = s.seconds;
    final magnitude = s.acceleration.length;
    final angularSpeed = s.gyroscope?.length ?? 0;
    final clipped = [s.acceleration.x, s.acceleration.y, s.acceleration.z]
        .any((v) => v.abs() >= 19.4); // OE2 compact IMU format is ±2 g.
    if (!calibrated) {
      final still = (magnitude - gravity).abs() < 0.55 && angularSpeed < 0.18;
      if (!still || dt > 0.12) {
        _calibrationSum = MotionVector.zero;
        _calibrationSamples = 0;
        _calibrationSeconds = 0;
      } else {
        _calibrationSeconds += dt;
        _calibrationSum = _calibrationSum + s.acceleration;
        _calibrationSamples++;
      }
      calibrationProgress = (_calibrationSeconds / 1.5).clamp(0, 1);
      if (_calibrationSeconds >= 1.5 && _calibrationSamples >= 50) {
        final mean = _calibrationSum * (1 / _calibrationSamples);
        _up = mean.unit;
        _gravityMagnitude = mean.length;
        calibrated = true;
      }
      quality = calibrated ? 'Signal ready' : 'Stand still briefly';
      return const ActivityUpdate();
    }
    // Complementary gravity direction: gyro propagation plus slow correction
    // only near 1 g. This avoids interpreting a head turn as vertical motion.
    if (s.gyroscope != null) {
      _up = (_up - s.gyroscope!.cross(_up) * dt).unit;
    }
    if ((magnitude - _gravityMagnitude).abs() < 1.2) {
      final a = dt / (2.5 + dt);
      _up = (_up * (1 - a) + s.acceleration.unit * a).unit;
    }
    final vertical = s.acceleration.dot(_up) - _gravityMagnitude;
    _smooth += dt / (0.055 + dt) * (vertical - _smooth);
    movement = _smooth;
    quality = clipped
        ? 'Impact clipped'
        : dt > 0.035
            ? 'Low sample rate'
            : 'Steady signal';
    final jump = (kind == ActivityKind.steps || kind == ActivityKind.jumps)
        ? _jumps.add(s.seconds, magnitude, angularSpeed, dt, clipped)
        : null;
    if (kind == ActivityKind.steps) {
      phase = 'Tracking steps';
      var count = 0;
      if (_jumps.inMotion || clipped) {
        _steps.reset();
      } else {
        count = _steps.add(s.seconds, _smooth, angularSpeed);
      }
      return ActivityUpdate(steps: count, jump: jump);
    }
    if (kind == ActivityKind.jumps) {
      phase = _jumps.inMotion ? 'Jump in progress' : 'Ready for next jump';
      return ActivityUpdate(jump: jump);
    }
    if (kind == ActivityKind.pushUps) {
      if (clipped) {
        _pushUps.discardMovement();
        // Do not feed the impact's low-pass tail into the next movement.
        _smooth = movement = 0;
      }
      final count =
          clipped ? 0 : _pushUps.add(s.seconds, _smooth, dt, angularSpeed);
      phase = _pushUps.phase;
      return ActivityUpdate(repetitions: count);
    }
    final count = clipped ? 0 : _reps.add(s.seconds, _smooth, dt, 0.065);
    if (clipped) _reps.reset();
    phase = _reps.phase;
    return ActivityUpdate(repetitions: count);
  }
}

class _StepDetector {
  double _previous = 0, _slope = 0, _trough = 0, _amplitude = 2;
  double _lastPeak = -100, _previousInterval = 0;
  int _pending = 0;
  bool _confirmedBout = false;
  void reset() {
    _previous = _slope = _trough = 0;
    _amplitude = 2;
    _lastPeak = -100;
    _previousInterval = 0;
    _pending = 0;
    _confirmedBout = false;
  }

  int add(double time, double value, double angularSpeed) {
    _trough = math.min(_trough, value);
    final slope = value - _previous;
    var count = 0;
    if (_slope > 0 &&
        slope <= 0 &&
        _previous > math.max(0.65, _amplitude * 0.28) &&
        _previous - _trough > 1.1 &&
        angularSpeed < 1.6) {
      final interval = time - _lastPeak;
      if (interval >= 0.28) {
        final regular = interval <= 1.5 &&
            (_previousInterval == 0 ||
                (interval - _previousInterval).abs() < _previousInterval * 0.4);
        if (!regular) {
          _pending = 1;
          _confirmedBout = false;
          _previousInterval = 0;
        } else {
          _pending++;
          if (_confirmedBout) {
            count = 1;
          } else if (_pending >= 3) {
            count = _pending; // Confirm the first steps retroactively.
            _confirmedBout = true;
          }
          _previousInterval = interval;
        }
        _lastPeak = time;
        _amplitude = 0.8 * _amplitude + 0.2 * (_previous - _trough);
        _trough = 0;
      }
    }
    _slope = slope;
    _previous = value;
    return count;
  }
}

class _RepetitionDetector {
  double _velocity = 0, _position = 0, _minimum = 0, _began = 0, _settle = 0;
  int _state = 0;
  String phase = 'Hold the start position';
  void reset() {
    _velocity = _position = _minimum = _began = _settle = 0;
    _state = 0;
    phase = 'Hold the start position';
  }

  int add(double t, double a, double dt, double minDepth) {
    // Bounded integration is a movement proxy, not a measurement of depth.
    // Rebase each complete cycle to prevent unbounded displacement drift.
    if (_settle < 0.7) {
      _settle = a.abs() < 0.5 ? _settle + dt : 0;
      return 0;
    }
    _velocity = _velocity * math.exp(-dt / 1.5) + a * dt;
    _position = _position * math.exp(-dt / 4) + _velocity * dt;
    _minimum = math.min(_minimum, _position);
    if (_state == 0) {
      phase = 'Ready · lower your body';
      if (_position < -minDepth * 0.4 && _velocity < -0.035) {
        _state = 1;
        _began = t;
        phase = 'Lowering';
      } else if (a.abs() < 0.15 && _velocity.abs() < 0.025) {
        _position = _minimum = 0;
      }
    } else if (t - _began > 8) {
      reset();
    } else if (_state == 1 && _minimum <= -minDepth && _velocity > 0.025) {
      _state = 2;
      phase = 'Returning to start';
    } else if (_state == 2 &&
        _velocity <= 0 &&
        _position >= _minimum * 0.2 &&
        _position - _minimum >= minDepth * 0.8 &&
        t - _began >= 0.65) {
      _state = 0;
      _velocity = _position = _minimum = 0;
      phase = 'Repetition complete';
      return 1;
    }
    return 0;
  }
}

class _JumpDetector {
  double _still = 0,
      _armedAt = -100,
      _takeoff = -100,
      _endFlight = -100,
      _cooldown = -100;
  bool _airborne = false, _clipped = false, _slow = false;
  bool get inMotion => _airborne || _endFlight > 0;
  void reset() {
    _still = 0;
    _armedAt = _takeoff = _endFlight = _cooldown = -100;
    _airborne = _clipped = _slow = false;
  }

  JumpAttempt? add(
    double t,
    double magnitude,
    double gyro,
    double dt,
    bool clipped,
  ) {
    if (t < _cooldown) return null;
    _still = (magnitude - ActivityEngine.gravity).abs() < 0.8 && gyro < 0.3
        ? _still + dt
        : 0;
    if (!_airborne && _endFlight < 0) {
      if (_still >= 0.5) _armedAt = t;
      if (t - _armedAt < 0.7 && magnitude > 12.3) {
        _takeoff = t;
        _clipped |= clipped;
      }
      if (t - _takeoff < 0.5 && magnitude < 3.5) {
        _airborne = true;
        _takeoff = t;
        _clipped |= clipped;
        _slow = dt > 0.025;
      }
      return null;
    }
    _clipped |= clipped;
    _slow |= dt > 0.025;
    if (_airborne && magnitude >= 3.5) {
      _airborne = false;
      _endFlight = t;
    }
    if (_airborne && t - _takeoff > 0.85) {
      reset();
      return null;
    }
    if (_endFlight > 0 && (magnitude > 12.3 || t - _endFlight > 0.12)) {
      final flight = _endFlight - _takeoff;
      final landed = magnitude > 12.3;
      final valid =
          flight >= 0.12 && flight <= 0.85 && landed && !_clipped && !_slow;
      final result = flight >= 0.08
          ? JumpAttempt(
              at: t,
              flightSeconds: flight,
              heightCm: valid
                  ? ActivityEngine.gravity * flight * flight / 8 * 100
                  : null,
              reason: valid
                  ? null
                  : _clipped
                      ? 'Impact clipped'
                      : _slow
                          ? 'Sample rate too low'
                          : 'Unclear take-off or landing',
            )
          : null;
      reset();
      _cooldown = t + 0.8;
      return result;
    }
    return null;
  }
}
