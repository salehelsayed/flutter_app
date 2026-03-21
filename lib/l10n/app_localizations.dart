import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('de'),
    Locale('en')
  ];

  /// No description provided for @nav_feed.
  ///
  /// In en, this message translates to:
  /// **'Feed'**
  String get nav_feed;

  /// No description provided for @nav_remember.
  ///
  /// In en, this message translates to:
  /// **'Remember'**
  String get nav_remember;

  /// No description provided for @nav_posts.
  ///
  /// In en, this message translates to:
  /// **'Posts'**
  String get nav_posts;

  /// No description provided for @nav_orbit.
  ///
  /// In en, this message translates to:
  /// **'Orbit'**
  String get nav_orbit;

  /// No description provided for @onboarding_new_here.
  ///
  /// In en, this message translates to:
  /// **'I\'m new here'**
  String get onboarding_new_here;

  /// No description provided for @onboarding_new_desc.
  ///
  /// In en, this message translates to:
  /// **'Generate a fresh identity'**
  String get onboarding_new_desc;

  /// No description provided for @onboarding_load_key.
  ///
  /// In en, this message translates to:
  /// **'Load my key'**
  String get onboarding_load_key;

  /// No description provided for @onboarding_load_desc.
  ///
  /// In en, this message translates to:
  /// **'Restore from recovery phrase'**
  String get onboarding_load_desc;

  /// No description provided for @onboarding_privacy_1.
  ///
  /// In en, this message translates to:
  /// **'Only you can read your messages'**
  String get onboarding_privacy_1;

  /// No description provided for @onboarding_privacy_2.
  ///
  /// In en, this message translates to:
  /// **'Everything stays on your phone. Nobody is watching.'**
  String get onboarding_privacy_2;

  /// No description provided for @progress_securing.
  ///
  /// In en, this message translates to:
  /// **'Securing your identity'**
  String get progress_securing;

  /// No description provided for @progress_securing_desc.
  ///
  /// In en, this message translates to:
  /// **'Saving your identity to secure storage.'**
  String get progress_securing_desc;

  /// No description provided for @progress_creating.
  ///
  /// In en, this message translates to:
  /// **'Creating your secure identity'**
  String get progress_creating;

  /// No description provided for @progress_creating_desc.
  ///
  /// In en, this message translates to:
  /// **'Generating encryption keys on this device. This only happens once.'**
  String get progress_creating_desc;

  /// No description provided for @progress_keep_open.
  ///
  /// In en, this message translates to:
  /// **'Please keep the app open.'**
  String get progress_keep_open;

  /// No description provided for @progress_almost.
  ///
  /// In en, this message translates to:
  /// **'Almost there.'**
  String get progress_almost;

  /// No description provided for @progress_step_keys.
  ///
  /// In en, this message translates to:
  /// **'Generate keys'**
  String get progress_step_keys;

  /// No description provided for @progress_step_save.
  ///
  /// In en, this message translates to:
  /// **'Save to device'**
  String get progress_step_save;

  /// No description provided for @mnemonic_title.
  ///
  /// In en, this message translates to:
  /// **'Recovery phrase'**
  String get mnemonic_title;

  /// No description provided for @mnemonic_error_12.
  ///
  /// In en, this message translates to:
  /// **'Please enter exactly 12 words'**
  String get mnemonic_error_12;

  /// No description provided for @mnemonic_error_invalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid recovery phrase'**
  String get mnemonic_error_invalid;

  /// No description provided for @mnemonic_error_generic.
  ///
  /// In en, this message translates to:
  /// **'An error occurred. Please try again.'**
  String get mnemonic_error_generic;

  /// No description provided for @mnemonic_hint.
  ///
  /// In en, this message translates to:
  /// **'word1 word2 word3 word4\\nword5 word6 word7 word8\\nword9 word10 word11 word12'**
  String get mnemonic_hint;

  /// No description provided for @qr_show_desc.
  ///
  /// In en, this message translates to:
  /// **'Show this to someone you want in your circle...'**
  String get qr_show_desc;

  /// No description provided for @qr_copy_hint.
  ///
  /// In en, this message translates to:
  /// **'Long-press QR to copy data'**
  String get qr_copy_hint;

  /// No description provided for @qr_copied.
  ///
  /// In en, this message translates to:
  /// **'QR data copied to clipboard!'**
  String get qr_copied;

  /// No description provided for @qr_scan_title.
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code'**
  String get qr_scan_title;

  /// No description provided for @qr_scan_instruction.
  ///
  /// In en, this message translates to:
  /// **'Point your camera at a friend\'s QR code'**
  String get qr_scan_instruction;

  /// No description provided for @qr_scan_subtitle.
  ///
  /// In en, this message translates to:
  /// **'They\'ll be added to your circle'**
  String get qr_scan_subtitle;

  /// No description provided for @qr_my_code.
  ///
  /// In en, this message translates to:
  /// **'My QR Code'**
  String get qr_my_code;

  /// No description provided for @qr_no_identity.
  ///
  /// In en, this message translates to:
  /// **'No Identity'**
  String get qr_no_identity;

  /// No description provided for @qr_error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get qr_error;

  /// No description provided for @qr_try_again.
  ///
  /// In en, this message translates to:
  /// **'Try Again'**
  String get qr_try_again;

  /// No description provided for @qr_paste_title.
  ///
  /// In en, this message translates to:
  /// **'Paste QR Data'**
  String get qr_paste_title;

  /// No description provided for @qr_paste_hint.
  ///
  /// In en, this message translates to:
  /// **'Paste the JSON QR payload from another device:'**
  String get qr_paste_hint;

  /// No description provided for @qr_paste_button.
  ///
  /// In en, this message translates to:
  /// **'Paste from Clipboard'**
  String get qr_paste_button;

  /// No description provided for @posts_title.
  ///
  /// In en, this message translates to:
  /// **'Posts'**
  String get posts_title;

  /// No description provided for @posts_header_subtitle.
  ///
  /// In en, this message translates to:
  /// **'What\'s happening around your friends today, {username}?'**
  String posts_header_subtitle(String username);

  /// No description provided for @posts_compose_button.
  ///
  /// In en, this message translates to:
  /// **'Share something with your friends'**
  String get posts_compose_button;

  /// No description provided for @posts_empty_title.
  ///
  /// In en, this message translates to:
  /// **'You\'re all caught up'**
  String get posts_empty_title;

  /// No description provided for @posts_empty_desc.
  ///
  /// In en, this message translates to:
  /// **'Your direct-friend posts will appear here after they land or replay.'**
  String get posts_empty_desc;

  /// No description provided for @posts_empty_button.
  ///
  /// In en, this message translates to:
  /// **'Create your first post'**
  String get posts_empty_button;

  /// No description provided for @posts_caught_up.
  ///
  /// In en, this message translates to:
  /// **'You\'re all caught up'**
  String get posts_caught_up;

  /// No description provided for @posts_time_now.
  ///
  /// In en, this message translates to:
  /// **'Right now'**
  String get posts_time_now;

  /// No description provided for @posts_time_earlier.
  ///
  /// In en, this message translates to:
  /// **'Earlier today'**
  String get posts_time_earlier;

  /// No description provided for @posts_time_yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get posts_time_yesterday;

  /// No description provided for @compose_title.
  ///
  /// In en, this message translates to:
  /// **'Create Post'**
  String get compose_title;

  /// No description provided for @compose_hint.
  ///
  /// In en, this message translates to:
  /// **'What do you want to share?'**
  String get compose_hint;

  /// No description provided for @compose_audience_all.
  ///
  /// In en, this message translates to:
  /// **'All Friends'**
  String get compose_audience_all;

  /// No description provided for @compose_audience_nearby.
  ///
  /// In en, this message translates to:
  /// **'People Nearby'**
  String get compose_audience_nearby;

  /// No description provided for @compose_audience_pick.
  ///
  /// In en, this message translates to:
  /// **'Pick People'**
  String get compose_audience_pick;

  /// No description provided for @compose_radius.
  ///
  /// In en, this message translates to:
  /// **'Radius'**
  String get compose_radius;

  /// No description provided for @compose_radius_500.
  ///
  /// In en, this message translates to:
  /// **'500m'**
  String get compose_radius_500;

  /// No description provided for @compose_radius_1k.
  ///
  /// In en, this message translates to:
  /// **'1km'**
  String get compose_radius_1k;

  /// No description provided for @compose_radius_2k.
  ///
  /// In en, this message translates to:
  /// **'2km'**
  String get compose_radius_2k;

  /// No description provided for @compose_media.
  ///
  /// In en, this message translates to:
  /// **'Media'**
  String get compose_media;

  /// No description provided for @compose_media_adding.
  ///
  /// In en, this message translates to:
  /// **'Adding...'**
  String get compose_media_adding;

  /// No description provided for @compose_voice.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get compose_voice;

  /// No description provided for @compose_voice_stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get compose_voice_stop;

  /// No description provided for @compose_voice_attached.
  ///
  /// In en, this message translates to:
  /// **'Voice attached'**
  String get compose_voice_attached;

  /// No description provided for @compose_attachments.
  ///
  /// In en, this message translates to:
  /// **'{count} attachments'**
  String compose_attachments(int count);

  /// No description provided for @compose_pick_people.
  ///
  /// In en, this message translates to:
  /// **'Pick People'**
  String get compose_pick_people;

  /// No description provided for @compose_posting.
  ///
  /// In en, this message translates to:
  /// **'Posting...'**
  String get compose_posting;

  /// No description provided for @compose_post.
  ///
  /// In en, this message translates to:
  /// **'Post'**
  String get compose_post;

  /// No description provided for @compose_manage.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get compose_manage;

  /// No description provided for @compose_pinned_1.
  ///
  /// In en, this message translates to:
  /// **'You already have 1 active pinned post'**
  String get compose_pinned_1;

  /// No description provided for @compose_pinned_n.
  ///
  /// In en, this message translates to:
  /// **'You already have {count} active pinned posts'**
  String compose_pinned_n(int count);

  /// No description provided for @compose_nearby_off.
  ///
  /// In en, this message translates to:
  /// **'People Nearby is off in Settings'**
  String get compose_nearby_off;

  /// No description provided for @compose_nearby_ready.
  ///
  /// In en, this message translates to:
  /// **'People Nearby is ready'**
  String get compose_nearby_ready;

  /// No description provided for @compose_nearby_refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh nearby before posting'**
  String get compose_nearby_refresh;

  /// No description provided for @compose_nearby_allow.
  ///
  /// In en, this message translates to:
  /// **'Allow location to use People Nearby'**
  String get compose_nearby_allow;

  /// No description provided for @compose_nearby_perm_off.
  ///
  /// In en, this message translates to:
  /// **'Location permission is off'**
  String get compose_nearby_perm_off;

  /// No description provided for @compose_nearby_services.
  ///
  /// In en, this message translates to:
  /// **'Turn on location services'**
  String get compose_nearby_services;

  /// No description provided for @compose_nearby_off_desc.
  ///
  /// In en, this message translates to:
  /// **'Turn it on in Settings before posting to nearby friends.'**
  String get compose_nearby_off_desc;

  /// No description provided for @compose_nearby_ready_desc.
  ///
  /// In en, this message translates to:
  /// **'Your nearby snapshot is fresh enough to use for posting.'**
  String get compose_nearby_ready_desc;

  /// No description provided for @compose_nearby_refresh_desc.
  ///
  /// In en, this message translates to:
  /// **'Refresh your nearby snapshot before using this audience.'**
  String get compose_nearby_refresh_desc;

  /// No description provided for @compose_nearby_allow_desc.
  ///
  /// In en, this message translates to:
  /// **'Refresh nearby to grant location permission for nearby posts.'**
  String get compose_nearby_allow_desc;

  /// No description provided for @compose_nearby_perm_desc.
  ///
  /// In en, this message translates to:
  /// **'Open system settings to re-enable location access.'**
  String get compose_nearby_perm_desc;

  /// No description provided for @compose_nearby_services_desc.
  ///
  /// In en, this message translates to:
  /// **'Enable location services, then refresh nearby again.'**
  String get compose_nearby_services_desc;

  /// No description provided for @compose_open_settings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get compose_open_settings;

  /// No description provided for @compose_refreshing.
  ///
  /// In en, this message translates to:
  /// **'Refreshing...'**
  String get compose_refreshing;

  /// No description provided for @compose_refresh_nearby.
  ///
  /// In en, this message translates to:
  /// **'Refresh nearby'**
  String get compose_refresh_nearby;

  /// No description provided for @post_badge_friend.
  ///
  /// In en, this message translates to:
  /// **'Friend'**
  String get post_badge_friend;

  /// No description provided for @post_uploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading media...'**
  String get post_uploading;

  /// No description provided for @post_sending.
  ///
  /// In en, this message translates to:
  /// **'Sending...'**
  String get post_sending;

  /// No description provided for @post_partial.
  ///
  /// In en, this message translates to:
  /// **'Partially sent'**
  String get post_partial;

  /// No description provided for @post_upload_failed.
  ///
  /// In en, this message translates to:
  /// **'Upload failed'**
  String get post_upload_failed;

  /// No description provided for @post_send_failed.
  ///
  /// In en, this message translates to:
  /// **'Send failed'**
  String get post_send_failed;

  /// No description provided for @pinned_title.
  ///
  /// In en, this message translates to:
  /// **'Pinned posts'**
  String get pinned_title;

  /// No description provided for @pinned_count_1.
  ///
  /// In en, this message translates to:
  /// **'1 pinned post'**
  String get pinned_count_1;

  /// No description provided for @pinned_count_n.
  ///
  /// In en, this message translates to:
  /// **'{count} pinned posts'**
  String pinned_count_n(int count);

  /// No description provided for @pinned_see_all.
  ///
  /// In en, this message translates to:
  /// **'See all {count} pinned posts'**
  String pinned_see_all(int count);

  /// No description provided for @pinned_dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get pinned_dismiss;

  /// No description provided for @pinned_message.
  ///
  /// In en, this message translates to:
  /// **'Message {username}'**
  String pinned_message(String username);

  /// No description provided for @pinned_edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get pinned_edit;

  /// No description provided for @pinned_remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get pinned_remove;

  /// No description provided for @edit_pinned_hint.
  ///
  /// In en, this message translates to:
  /// **'Update your post'**
  String get edit_pinned_hint;

  /// No description provided for @orbit_close_friends.
  ///
  /// In en, this message translates to:
  /// **'Close Friends'**
  String get orbit_close_friends;

  /// No description provided for @orbit_new_group.
  ///
  /// In en, this message translates to:
  /// **'New Group'**
  String get orbit_new_group;

  /// No description provided for @orbit_new_announce.
  ///
  /// In en, this message translates to:
  /// **'New Announce'**
  String get orbit_new_announce;

  /// No description provided for @orbit_my_qr.
  ///
  /// In en, this message translates to:
  /// **'My QR'**
  String get orbit_my_qr;

  /// No description provided for @orbit_scan.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get orbit_scan;

  /// No description provided for @orbit_qr_share.
  ///
  /// In en, this message translates to:
  /// **'Share to add friends'**
  String get orbit_qr_share;

  /// No description provided for @orbit_qr_scan_desc.
  ///
  /// In en, this message translates to:
  /// **'Add a friend instantly'**
  String get orbit_qr_scan_desc;

  /// No description provided for @orbit_filter_all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get orbit_filter_all;

  /// No description provided for @orbit_filter_intros.
  ///
  /// In en, this message translates to:
  /// **'Intros'**
  String get orbit_filter_intros;

  /// No description provided for @orbit_filter_archived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get orbit_filter_archived;

  /// No description provided for @orbit_search.
  ///
  /// In en, this message translates to:
  /// **'Search friends...'**
  String get orbit_search;

  /// No description provided for @orbit_block_title.
  ///
  /// In en, this message translates to:
  /// **'Block {username}?'**
  String orbit_block_title(String username);

  /// No description provided for @orbit_delete_chat.
  ///
  /// In en, this message translates to:
  /// **'Delete chat?'**
  String get orbit_delete_chat;

  /// No description provided for @orbit_leave_group.
  ///
  /// In en, this message translates to:
  /// **'Leave & delete group?'**
  String get orbit_leave_group;

  /// No description provided for @conversation_hint.
  ///
  /// In en, this message translates to:
  /// **'Write something...'**
  String get conversation_hint;

  /// No description provided for @conversation_voice_fail.
  ///
  /// In en, this message translates to:
  /// **'Failed to send voice message.'**
  String get conversation_voice_fail;

  /// No description provided for @conversation_block.
  ///
  /// In en, this message translates to:
  /// **'Block {username}?'**
  String conversation_block(String username);

  /// No description provided for @conversation_delete_chat.
  ///
  /// In en, this message translates to:
  /// **'Delete chat?'**
  String get conversation_delete_chat;

  /// No description provided for @conversation_reply.
  ///
  /// In en, this message translates to:
  /// **'Reply...'**
  String get conversation_reply;

  /// No description provided for @conversation_continue.
  ///
  /// In en, this message translates to:
  /// **'Continue...'**
  String get conversation_continue;

  /// No description provided for @comment_hint.
  ///
  /// In en, this message translates to:
  /// **'Write a comment...'**
  String get comment_hint;

  /// No description provided for @group_create_title.
  ///
  /// In en, this message translates to:
  /// **'Create Group'**
  String get group_create_title;

  /// No description provided for @group_name_hint.
  ///
  /// In en, this message translates to:
  /// **'Enter group name'**
  String get group_name_hint;

  /// No description provided for @group_desc_hint.
  ///
  /// In en, this message translates to:
  /// **'What is this group about?'**
  String get group_desc_hint;

  /// No description provided for @group_name_optional.
  ///
  /// In en, this message translates to:
  /// **'Group name (optional)'**
  String get group_name_optional;

  /// No description provided for @group_message_hint.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get group_message_hint;

  /// No description provided for @group_create_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create group'**
  String get group_create_failed;

  /// No description provided for @group_invite_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to invite members'**
  String get group_invite_failed;

  /// No description provided for @picker_introduce_to.
  ///
  /// In en, this message translates to:
  /// **'Introduce to {username}'**
  String picker_introduce_to(String username);

  /// No description provided for @picker_search.
  ///
  /// In en, this message translates to:
  /// **'Search friends...'**
  String get picker_search;

  /// No description provided for @picker_no_friends.
  ///
  /// In en, this message translates to:
  /// **'No friends available to introduce'**
  String get picker_no_friends;

  /// No description provided for @picker_no_results.
  ///
  /// In en, this message translates to:
  /// **'No friends matching \"{query}\"'**
  String picker_no_results(String query);

  /// No description provided for @picker_introduce_count.
  ///
  /// In en, this message translates to:
  /// **'Introduce ({count})'**
  String picker_introduce_count(int count);

  /// No description provided for @picker_introduce.
  ///
  /// In en, this message translates to:
  /// **'Introduce'**
  String get picker_introduce;

  /// No description provided for @picker_search_contacts.
  ///
  /// In en, this message translates to:
  /// **'Search contacts...'**
  String get picker_search_contacts;

  /// No description provided for @picker_search_all.
  ///
  /// In en, this message translates to:
  /// **'Search contacts & groups'**
  String get picker_search_all;

  /// No description provided for @settings_title.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings_title;

  /// No description provided for @settings_video_quality.
  ///
  /// In en, this message translates to:
  /// **'Video Quality'**
  String get settings_video_quality;

  /// No description provided for @settings_compressed.
  ///
  /// In en, this message translates to:
  /// **'Compressed'**
  String get settings_compressed;

  /// No description provided for @settings_original.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get settings_original;

  /// No description provided for @settings_original_desc.
  ///
  /// In en, this message translates to:
  /// **'Full quality, larger file size. Metadata is always removed.'**
  String get settings_original_desc;

  /// No description provided for @settings_compressed_desc.
  ///
  /// In en, this message translates to:
  /// **'Smaller file size, faster sending. Metadata is always removed.'**
  String get settings_compressed_desc;

  /// No description provided for @settings_photo_fail.
  ///
  /// In en, this message translates to:
  /// **'Failed to upload profile picture'**
  String get settings_photo_fail;

  /// No description provided for @picker_take_photo.
  ///
  /// In en, this message translates to:
  /// **'Take Photo'**
  String get picker_take_photo;

  /// No description provided for @picker_gallery.
  ///
  /// In en, this message translates to:
  /// **'Choose from Gallery'**
  String get picker_gallery;

  /// No description provided for @notif_new_intro.
  ///
  /// In en, this message translates to:
  /// **'New Introduction'**
  String get notif_new_intro;

  /// No description provided for @notif_new_connection.
  ///
  /// In en, this message translates to:
  /// **'New Connection'**
  String get notif_new_connection;

  /// No description provided for @startup_checking.
  ///
  /// In en, this message translates to:
  /// **'Preparing your space...'**
  String get startup_checking;

  /// No description provided for @startup_checking_desc.
  ///
  /// In en, this message translates to:
  /// **'Checking identity and startup state'**
  String get startup_checking_desc;

  /// No description provided for @startup_feed.
  ///
  /// In en, this message translates to:
  /// **'Opening Feed...'**
  String get startup_feed;

  /// No description provided for @startup_feed_desc.
  ///
  /// In en, this message translates to:
  /// **'Handing off to your conversations'**
  String get startup_feed_desc;

  /// No description provided for @startup_setup.
  ///
  /// In en, this message translates to:
  /// **'Opening setup...'**
  String get startup_setup;

  /// No description provided for @startup_setup_desc.
  ///
  /// In en, this message translates to:
  /// **'Getting your first-time experience ready'**
  String get startup_setup_desc;

  /// No description provided for @startup_onboarding.
  ///
  /// In en, this message translates to:
  /// **'Opening onboarding...'**
  String get startup_onboarding;

  /// No description provided for @startup_onboarding_desc.
  ///
  /// In en, this message translates to:
  /// **'Let\'s get your identity ready'**
  String get startup_onboarding_desc;

  /// No description provided for @btn_retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get btn_retry;

  /// No description provided for @btn_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get btn_cancel;

  /// No description provided for @btn_submit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get btn_submit;

  /// No description provided for @error_add_contact.
  ///
  /// In en, this message translates to:
  /// **'Failed to add contact. Please try again.'**
  String get error_add_contact;

  /// No description provided for @error_send_message.
  ///
  /// In en, this message translates to:
  /// **'Message failed to send. Try again.'**
  String get error_send_message;

  /// No description provided for @error_update_photo.
  ///
  /// In en, this message translates to:
  /// **'Failed to update photo: {error}'**
  String error_update_photo(String error);

  /// No description provided for @error_update_username.
  ///
  /// In en, this message translates to:
  /// **'Failed to update username. Please try again.'**
  String get error_update_username;

  /// No description provided for @error_generic.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String error_generic(String error);

  /// No description provided for @status_processing_video.
  ///
  /// In en, this message translates to:
  /// **'Processing video...'**
  String get status_processing_video;

  /// No description provided for @perm_camera.
  ///
  /// In en, this message translates to:
  /// **'This app needs camera access to scan QR codes and take photos'**
  String get perm_camera;

  /// No description provided for @perm_photos.
  ///
  /// In en, this message translates to:
  /// **'This app needs access to your photo library to share images'**
  String get perm_photos;

  /// No description provided for @perm_microphone.
  ///
  /// In en, this message translates to:
  /// **'This app needs microphone access to record voice messages'**
  String get perm_microphone;

  /// No description provided for @perm_location.
  ///
  /// In en, this message translates to:
  /// **'This app needs location access to share nearby posts with your direct friends'**
  String get perm_location;

  /// No description provided for @perm_local_network.
  ///
  /// In en, this message translates to:
  /// **'mknoon looks for your friends on the same WiFi to send messages directly to their phone. It\'s faster, more private, and we never collect your data.'**
  String get perm_local_network;

  /// No description provided for @perm_notifications.
  ///
  /// In en, this message translates to:
  /// **'This app needs notification access to alert you of incoming messages'**
  String get perm_notifications;

  /// No description provided for @connected_date.
  ///
  /// In en, this message translates to:
  /// **'Connected {date}'**
  String connected_date(String date);

  /// No description provided for @date_today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get date_today;

  /// No description provided for @date_yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get date_yesterday;

  /// No description provided for @feed_collapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get feed_collapse;

  /// No description provided for @feed_tap_expand.
  ///
  /// In en, this message translates to:
  /// **'Tap to expand'**
  String get feed_tap_expand;

  /// No description provided for @feed_you.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get feed_you;

  /// No description provided for @feed_you_replied.
  ///
  /// In en, this message translates to:
  /// **'You replied {time}'**
  String feed_you_replied(String time);

  /// No description provided for @settings_photo_quality.
  ///
  /// In en, this message translates to:
  /// **'Photo Quality'**
  String get settings_photo_quality;

  /// No description provided for @settings_share_nearby.
  ///
  /// In en, this message translates to:
  /// **'Share People Nearby'**
  String get settings_share_nearby;

  /// No description provided for @settings_share_nearby_on.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get settings_share_nearby_on;

  /// No description provided for @settings_share_nearby_off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get settings_share_nearby_off;

  /// No description provided for @settings_share_nearby_desc.
  ///
  /// In en, this message translates to:
  /// **'Shares only an approximate location with direct friends. No live maps, and never strangers.'**
  String get settings_share_nearby_desc;

  /// No description provided for @settings_recovery_title.
  ///
  /// In en, this message translates to:
  /// **'RECOVERY PHRASE'**
  String get settings_recovery_title;

  /// No description provided for @settings_recovery_warning.
  ///
  /// In en, this message translates to:
  /// **'Never share this phrase with anyone. It grants full access to your account.'**
  String get settings_recovery_warning;

  /// No description provided for @settings_recovery_tap.
  ///
  /// In en, this message translates to:
  /// **'Tap to reveal'**
  String get settings_recovery_tap;

  /// No description provided for @settings_recovery_copied.
  ///
  /// In en, this message translates to:
  /// **'Copied!'**
  String get settings_recovery_copied;

  /// No description provided for @settings_recovery_copy.
  ///
  /// In en, this message translates to:
  /// **'Copy to clipboard'**
  String get settings_recovery_copy;

  /// No description provided for @settings_recovery_hide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get settings_recovery_hide;

  /// No description provided for @connected_title.
  ///
  /// In en, this message translates to:
  /// **'Connected!'**
  String get connected_title;

  /// No description provided for @send_message.
  ///
  /// In en, this message translates to:
  /// **'Send Message'**
  String get send_message;

  /// No description provided for @introduced_by.
  ///
  /// In en, this message translates to:
  /// **'Introduced by {username}'**
  String introduced_by(String username);
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['ar', 'de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar': return AppLocalizationsAr();
    case 'de': return AppLocalizationsDe();
    case 'en': return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
