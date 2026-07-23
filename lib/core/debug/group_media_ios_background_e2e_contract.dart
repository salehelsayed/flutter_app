import 'group_media_ios_disposable_profile.dart';

/// Host-safe constants shared by the installed app and the physical-device
/// fixture driver. Keep this library free of Flutter and `dart:ui` imports so
/// the repo-owned driver remains directly executable by the Dart VM.
const String groupMediaIosBackgroundE2EAction =
    'group_media_ios_background_recovery';
const String groupMediaIosBackgroundE2ECommandSchema =
    'mknoon.group-media-ios-background-command.v1';
const String groupMediaIosBackgroundE2EResultSchema =
    'mknoon.group-media-ios-background-endpoint.v1';
const String groupMediaIosBackgroundE2EStateSchema =
    'mknoon.group-media-ios-background-state.v1';
const String groupMediaIosBackgroundScenario =
    'group_media_ios_receiver_background_recovery';
const String groupMediaIosBackgroundBuildProfile =
    groupMediaIosDisposableBuildProfile;
const String groupMediaIosAndroidSenderBuildProfile =
    groupMediaAndroidDisposableBuildProfile;

const String groupMediaIosIdentityPhase = 'identity';
const String groupMediaIosAddContactPhase = 'add_contact';
const String groupMediaIosSenderSetupPhase = 'sender_setup';
const String groupMediaIosReceiverArmPhase = 'receiver_arm';
const String groupMediaIosSenderSendPhase = 'sender_send';
const String groupMediaIosReceiverObservePhase = 'receiver_observe';
const String groupMediaIosReceiverRecoverPhase = 'receiver_recover';
