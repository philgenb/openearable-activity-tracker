import 'dart:math' as math;

/// Counts manually selected push-ups from filtered vertical acceleration.
///
/// Inputs are sensor seconds, m/s², seconds and angular speed in rad/s.
/// Displacement is a short-lived motion proxy, not measured exercise depth.
/// Unlike a leaky position integrator, a stationary hold cannot erase the
/// descent and make a small return look like a complete repetition.
class PushUpDetector {
  static const _minimumExcursion = 0.035;
  double _velocity = 0, _position = 0, _minimum = 0;
  double _began = 0, _settle = 0, _quiet = 0;
  double _baseline = 0, _baselineSum = 0;
  double? _settleAnchor;
  int _baselineSamples = 0;
  int _state = 0;

  /// Current phase for live exercise feedback.
  String phase = 'Hold the start position';

  /// Discards the current movement and requires a new quiet starting window.
  void reset() {
    _velocity = _position = _minimum = _began = _settle = _quiet = 0;
    _baseline = _baselineSum = 0;
    _baselineSamples = 0;
    _settleAnchor = null;
    _state = 0;
    phase = 'Hold the start position';
  }

  /// Returns one only after a descent and a substantial return to its origin.
  int add(double time, double acceleration, double dt, double angularSpeed) {
    // The engine handles data gaps and clipping. Reject large head rotations
    // locally as well; the settling window must include a quiet gyroscope.
    if (angularSpeed > 1.6) {
      reset();
      return 0;
    }
    if (_settle < 0.7) {
      final quiet = acceleration.abs() < 0.5 && angularSpeed < 0.18;
      if (!quiet ||
          (_settleAnchor != null &&
              (acceleration - _settleAnchor!).abs() > 0.05)) {
        _settle = _baselineSum = 0;
        _baselineSamples = 0;
        _settleAnchor = null;
      }
      if (quiet) {
        _settleAnchor ??= acceleration;
        _settle += dt;
        // Let the causal low-pass filter settle before measuring its offset.
        if (_settle >= 0.45) {
          _baselineSum += acceleration;
          _baselineSamples++;
        }
        if (_settle >= 0.7) _baseline = _baselineSum / _baselineSamples;
      }
      return 0;
    }
    // Estimate a local residual offset in the starting pose. A small gravity
    // calibration error must not integrate into velocity throughout the set.
    acceleration -= _baseline;
    final previousVelocity = _velocity;
    _velocity += acceleration * dt;
    _position += (previousVelocity + _velocity) * 0.5 * dt;
    // Apply a zero-velocity correction only near rest, never decay position.
    // Small acceleration alone is insufficient: constant-speed motion also
    // has near-zero acceleration, so velocity must already be near zero.
    _quiet =
        acceleration.abs() < 0.008 && _velocity.abs() < 0.025 ? _quiet + dt : 0;
    if (_quiet >= 0.25) _velocity = 0;
    if (_velocity.abs() > 2 || _position.abs() > 0.75) {
      reset();
      return 0;
    }
    if (_state != 0 && time - _began > 8) {
      reset();
      return 0;
    }
    if (_state == 0) {
      phase = 'Ready · lower your body';
      _minimum = math.min(_minimum, _position);
      if (_position < -_minimumExcursion * 0.4 && _velocity < -0.035) {
        _state = 1;
        _began = time;
        phase = 'Lowering';
      } else if (_quiet >= 0.25) {
        _position = _minimum = 0;
      }
    } else if (_state == 1) {
      _minimum = math.min(_minimum, _position);
      if (_minimum <= -_minimumExcursion && _velocity > 0.025) {
        _state = 2;
        phase = 'Returning to start';
      }
    } else {
      final returned = _position >= _minimum * 0.2 &&
          _position - _minimum >= _minimumExcursion * 0.8;
      if (returned && _velocity.abs() <= 0.025 && time - _began >= 0.65) {
        _state = 0;
        // Keep residual velocity for the start of the next continuous cycle;
        // resetting it mid-transition would inject integration drift.
        _position = _minimum = 0;
        if (_quiet >= 0.25) _velocity = 0;
        phase = 'Repetition complete';
        return 1;
      }
      if (!returned && _velocity < -0.035) reset();
    }
    return 0;
  }
}
