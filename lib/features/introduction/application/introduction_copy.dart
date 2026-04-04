import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';

String formatIntroducerIntroductionSystemMessage({
  required String recipientUsername,
  required List<String> introducedUsernames,
}) {
  final recipientName = _displayName(
    recipientUsername,
    fallback: 'your contact',
  );
  final names = introducedUsernames
      .map((username) => username.trim())
      .where((username) => username.isNotEmpty)
      .toList(growable: false);

  if (names.isEmpty) {
    return 'You made an introduction to $recipientName';
  }

  if (names.length == 1) {
    return 'You introduced ${names.first} to $recipientName';
  }

  return 'You introduced ${_summarizeNames(names)} to $recipientName';
}

String formatIncomingIntroductionMessage({
  required IntroductionModel introduction,
  required String ownPeerId,
}) {
  final introducerName = _displayName(
    introduction.introducerUsername,
    fallback: 'Someone',
  );
  final recipientName = _displayName(
    introduction.recipientUsername,
    fallback: 'someone',
  );
  final introducedName = _displayName(
    introduction.introducedUsername,
    fallback: 'someone',
  );

  late final String base;
  if (ownPeerId == introduction.recipientId) {
    base = '$introducerName introduced $introducedName to you';
  } else if (ownPeerId == introduction.introducedId) {
    base = '$introducerName introduced you to $recipientName';
  } else {
    base = '$introducerName sent you an introduction';
  }

  if (introduction.status == IntroductionOverallStatus.alreadyConnected) {
    return '$base — you\'re already connected';
  }

  return base;
}

String formatMutualAcceptanceSystemMessage({
  required String otherUsername,
  required String introducerName,
}) {
  final otherName = _displayName(otherUsername, fallback: 'your new contact');
  final introducer = _displayName(introducerName, fallback: 'a friend');
  return 'You and $otherName are now connected — introduced by $introducer';
}

String _displayName(String? username, {required String fallback}) {
  final trimmed = username?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return fallback;
  }
  return trimmed;
}

String _summarizeNames(List<String> names) {
  if (names.length == 2) {
    return '${names[0]} and ${names[1]}';
  }
  if (names.length == 3) {
    return '${names[0]}, ${names[1]}, and ${names[2]}';
  }

  final shown = names.take(3).join(', ');
  final remaining = names.length - 3;
  return '$shown, and $remaining more';
}
