import 'package:flutter/material.dart';
import 'package:flutter_app/shared/widgets/feature_page_route.dart';

/// Builds the route used when entering Feed.
Route<T> buildFeedSlideUpRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
}) => FeaturePageRoute<T>(builder: builder, settings: settings);
