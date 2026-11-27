import 'package:flutter/material.dart';
import 'package:flutter_app/shared/widgets/feature_page_route.dart';

/// Builds the route used when entering Orbit.
Route<T> buildOrbitSlideUpRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
}) => FeaturePageRoute<T>(builder: builder, settings: settings);
