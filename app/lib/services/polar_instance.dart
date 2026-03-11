import 'package:polar/polar.dart';

/// Single shared [Polar] SDK instance for the whole app.
///
/// The underlying native `polar/events` channel can only have one active
/// binary-messenger handler at a time. Creating multiple [Polar] instances
/// causes each new instance's [EventChannel.receiveBroadcastStream] to replace
/// the previous handler, silently dropping all events for the earlier instance.
/// Both [PolarH10Service] and [PolarPacerService] must therefore share this
/// one object.
final Polar sharedPolar = Polar();
