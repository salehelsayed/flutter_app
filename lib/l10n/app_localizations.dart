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
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

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
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('de'),
    Locale('en'),
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
  /// **'{count, plural, =0{No attachments} =1{1 attachment} other{{count} attachments}}'**
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

  /// No description provided for @conversation_context_reply.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get conversation_context_reply;

  /// No description provided for @conversation_context_edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get conversation_context_edit;

  /// No description provided for @conversation_context_copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get conversation_context_copy;

  /// No description provided for @conversation_context_delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get conversation_context_delete;

  /// No description provided for @conversation_context_copied.
  ///
  /// In en, this message translates to:
  /// **'Message copied to clipboard'**
  String get conversation_context_copied;

  /// No description provided for @conversation_editing_message.
  ///
  /// In en, this message translates to:
  /// **'Editing message'**
  String get conversation_editing_message;

  /// No description provided for @conversation_cancel_edit.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get conversation_cancel_edit;

  /// No description provided for @conversation_edited_indicator.
  ///
  /// In en, this message translates to:
  /// **'(edited)'**
  String get conversation_edited_indicator;

  /// No description provided for @conversation_delete_message_prompt.
  ///
  /// In en, this message translates to:
  /// **'Who would you like to delete this message for?'**
  String get conversation_delete_message_prompt;

  /// No description provided for @conversation_delete_for_me.
  ///
  /// In en, this message translates to:
  /// **'Delete for Me'**
  String get conversation_delete_for_me;

  /// No description provided for @conversation_delete_for_everyone.
  ///
  /// In en, this message translates to:
  /// **'Delete for Everyone'**
  String get conversation_delete_for_everyone;

  /// No description provided for @conversation_delete_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get conversation_delete_cancel;

  /// No description provided for @conversation_message_deleted.
  ///
  /// In en, this message translates to:
  /// **'This message was deleted'**
  String get conversation_message_deleted;

  /// No description provided for @conversation_delete_failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t finish deleting this message.'**
  String get conversation_delete_failed;

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

  /// No description provided for @group_create_member_limit_reached.
  ///
  /// In en, this message translates to:
  /// **'Groups can have up to {maxMembers} members including you. Reduce your selection by {overflowCount} and try again.'**
  String group_create_member_limit_reached(int maxMembers, int overflowCount);

  /// No description provided for @group_invite_member_limit_reached.
  ///
  /// In en, this message translates to:
  /// **'Groups can have up to {maxMembers} members. Reduce your selection by {overflowCount} and try again.'**
  String group_invite_member_limit_reached(int maxMembers, int overflowCount);

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

  /// No description provided for @picker_sending_progress.
  ///
  /// In en, this message translates to:
  /// **'Sending {completed} of {total}'**
  String picker_sending_progress(int completed, int total);

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

  /// No description provided for @settings_background.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get settings_background;

  /// No description provided for @settings_background_default.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get settings_background_default;

  /// No description provided for @settings_background_default_desc.
  ///
  /// In en, this message translates to:
  /// **'The current ambient background.'**
  String get settings_background_default_desc;

  /// No description provided for @settings_background_cosmic.
  ///
  /// In en, this message translates to:
  /// **'Cosmic'**
  String get settings_background_cosmic;

  /// No description provided for @settings_background_cosmic_desc.
  ///
  /// In en, this message translates to:
  /// **'A deep starfield for Feed.'**
  String get settings_background_cosmic_desc;

  /// No description provided for @settings_background_cosmic_selected.
  ///
  /// In en, this message translates to:
  /// **'Cosmic selected'**
  String get settings_background_cosmic_selected;

  /// No description provided for @settings_background_cosmic_mirrored.
  ///
  /// In en, this message translates to:
  /// **'Mirrored cosmic'**
  String get settings_background_cosmic_mirrored;

  /// No description provided for @settings_background_cosmic_mirrored_desc.
  ///
  /// In en, this message translates to:
  /// **'The cosmic starfield with mirrored color blooms.'**
  String get settings_background_cosmic_mirrored_desc;

  /// No description provided for @settings_background_cosmic_mirrored_selected.
  ///
  /// In en, this message translates to:
  /// **'Mirrored cosmic selected'**
  String get settings_background_cosmic_mirrored_selected;

  /// No description provided for @settings_background_daylight_lagoon.
  ///
  /// In en, this message translates to:
  /// **'Daylight Lagoon'**
  String get settings_background_daylight_lagoon;

  /// No description provided for @settings_background_daylight_lagoon_desc.
  ///
  /// In en, this message translates to:
  /// **'A bright lagoon sky with soft pastel blooms.'**
  String get settings_background_daylight_lagoon_desc;

  /// No description provided for @settings_background_daylight_lagoon_selected.
  ///
  /// In en, this message translates to:
  /// **'Daylight Lagoon selected'**
  String get settings_background_daylight_lagoon_selected;

  /// No description provided for @settings_background_save_fail.
  ///
  /// In en, this message translates to:
  /// **'Background choice could not be saved'**
  String get settings_background_save_fail;

  /// No description provided for @settings_background_semantics.
  ///
  /// In en, this message translates to:
  /// **'App background setting'**
  String get settings_background_semantics;

  /// No description provided for @settings_background_default_selected.
  ///
  /// In en, this message translates to:
  /// **'Default selected'**
  String get settings_background_default_selected;

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

  /// No description provided for @load_retry_hint.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get load_retry_hint;

  /// No description provided for @upload_leave_title.
  ///
  /// In en, this message translates to:
  /// **'Leave conversation?'**
  String get upload_leave_title;

  /// No description provided for @upload_leave_body.
  ///
  /// In en, this message translates to:
  /// **'An upload is in progress. Leaving may interrupt it. Are you sure?'**
  String get upload_leave_body;

  /// No description provided for @upload_leave_stay.
  ///
  /// In en, this message translates to:
  /// **'Stay'**
  String get upload_leave_stay;

  /// No description provided for @upload_leave_confirm.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get upload_leave_confirm;

  /// No description provided for @upload_cancelled.
  ///
  /// In en, this message translates to:
  /// **'Upload cancelled.'**
  String get upload_cancelled;

  /// No description provided for @media_too_large_title.
  ///
  /// In en, this message translates to:
  /// **'Media Too Large'**
  String get media_too_large_title;

  /// No description provided for @media_too_large_prompt.
  ///
  /// In en, this message translates to:
  /// **'The attached media is {totalSize} and exceeds the {limitSize} limit. Would you like to compress and send, or cancel?'**
  String media_too_large_prompt(String totalSize, String limitSize);

  /// No description provided for @media_compress.
  ///
  /// In en, this message translates to:
  /// **'Compress'**
  String get media_compress;

  /// No description provided for @media_too_large_after_compress.
  ///
  /// In en, this message translates to:
  /// **'The media is too large even after compression.'**
  String get media_too_large_after_compress;

  /// No description provided for @media_gif_too_large.
  ///
  /// In en, this message translates to:
  /// **'GIF files larger than 25 MB cannot be added.'**
  String get media_gif_too_large;

  /// No description provided for @media_unavailable.
  ///
  /// In en, this message translates to:
  /// **'Media unavailable'**
  String get media_unavailable;

  /// No description provided for @media_retry_unavailable.
  ///
  /// In en, this message translates to:
  /// **'Retry unavailable media'**
  String get media_retry_unavailable;

  /// No description provided for @edit_save_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save edit.'**
  String get edit_save_failed;

  /// No description provided for @intro_pass.
  ///
  /// In en, this message translates to:
  /// **'Pass'**
  String get intro_pass;

  /// No description provided for @intro_accept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get intro_accept;

  /// No description provided for @intro_accepting.
  ///
  /// In en, this message translates to:
  /// **'Accepting...'**
  String get intro_accepting;

  /// No description provided for @failed_message_retry_semantics.
  ///
  /// In en, this message translates to:
  /// **'Retry failed message'**
  String get failed_message_retry_semantics;

  /// No description provided for @failed_media_retry_semantics.
  ///
  /// In en, this message translates to:
  /// **'Retry failed media message'**
  String get failed_media_retry_semantics;

  /// No description provided for @failed_media_delete_semantics.
  ///
  /// In en, this message translates to:
  /// **'Delete failed media message'**
  String get failed_media_delete_semantics;

  /// No description provided for @message_status_semantics.
  ///
  /// In en, this message translates to:
  /// **'Message status: {status}'**
  String message_status_semantics(String status);

  /// No description provided for @message_status_delivered.
  ///
  /// In en, this message translates to:
  /// **'delivered'**
  String get message_status_delivered;

  /// No description provided for @message_status_failed.
  ///
  /// In en, this message translates to:
  /// **'failed'**
  String get message_status_failed;

  /// No description provided for @message_status_sending.
  ///
  /// In en, this message translates to:
  /// **'sending'**
  String get message_status_sending;

  /// No description provided for @message_status_sent.
  ///
  /// In en, this message translates to:
  /// **'sent'**
  String get message_status_sent;

  /// No description provided for @message_status_pending_inbox.
  ///
  /// In en, this message translates to:
  /// **'pending delivery via inbox'**
  String get message_status_pending_inbox;

  /// No description provided for @share_send_failed.
  ///
  /// In en, this message translates to:
  /// **'Could not share to the selected targets.'**
  String get share_send_failed;

  /// No description provided for @group_info_title.
  ///
  /// In en, this message translates to:
  /// **'Group Info'**
  String get group_info_title;

  /// No description provided for @group_edit_details.
  ///
  /// In en, this message translates to:
  /// **'Edit Details'**
  String get group_edit_details;

  /// No description provided for @group_member_count.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 member} other{{count} members}}'**
  String group_member_count(int count);

  /// No description provided for @group_security_title.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get group_security_title;

  /// No description provided for @group_security_key_change_visible.
  ///
  /// In en, this message translates to:
  /// **'Key change visible'**
  String get group_security_key_change_visible;

  /// No description provided for @group_security_verification_warning.
  ///
  /// In en, this message translates to:
  /// **'Verification warning'**
  String get group_security_verification_warning;

  /// No description provided for @group_security_identity_warning_detail.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 identity has changed. Review safety numbers below.} other{{count} identities have changed. Review safety numbers below.}}'**
  String group_security_identity_warning_detail(int count);

  /// No description provided for @group_dissolved.
  ///
  /// In en, this message translates to:
  /// **'Group dissolved'**
  String get group_dissolved;

  /// No description provided for @group_dissolved_read_only_desc.
  ///
  /// In en, this message translates to:
  /// **'This conversation is now read-only. Previous messages stay available for reference.'**
  String get group_dissolved_read_only_desc;

  /// No description provided for @group_mute_notifications.
  ///
  /// In en, this message translates to:
  /// **'Mute Notifications'**
  String get group_mute_notifications;

  /// No description provided for @group_mute_on_desc.
  ///
  /// In en, this message translates to:
  /// **'New messages still arrive, but this group stays quiet.'**
  String get group_mute_on_desc;

  /// No description provided for @group_mute_off_desc.
  ///
  /// In en, this message translates to:
  /// **'Get notified when new messages arrive in this group.'**
  String get group_mute_off_desc;

  /// No description provided for @group_members_title.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get group_members_title;

  /// No description provided for @group_add_member.
  ///
  /// In en, this message translates to:
  /// **'Add Member'**
  String get group_add_member;

  /// No description provided for @group_leave.
  ///
  /// In en, this message translates to:
  /// **'Leave Group'**
  String get group_leave;

  /// No description provided for @group_dissolve.
  ///
  /// In en, this message translates to:
  /// **'Dissolve Group'**
  String get group_dissolve;

  /// No description provided for @group_delete_from_device.
  ///
  /// In en, this message translates to:
  /// **'Delete from this device'**
  String get group_delete_from_device;

  /// No description provided for @group_delete_local_desc.
  ///
  /// In en, this message translates to:
  /// **'Keep this dissolved history as long as you want, or remove it from this device only. This will not affect anyone else.'**
  String get group_delete_local_desc;

  /// No description provided for @group_delete_locally.
  ///
  /// In en, this message translates to:
  /// **'Delete Group Locally'**
  String get group_delete_locally;

  /// No description provided for @group_no_messages.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get group_no_messages;

  /// No description provided for @group_empty_dissolved_desc.
  ///
  /// In en, this message translates to:
  /// **'This group has been dissolved. New messages are disabled.'**
  String get group_empty_dissolved_desc;

  /// No description provided for @group_empty_start.
  ///
  /// In en, this message translates to:
  /// **'Send a message to start the conversation'**
  String get group_empty_start;

  /// No description provided for @group_empty_waiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for messages'**
  String get group_empty_waiting;

  /// No description provided for @group_recovery_banner.
  ///
  /// In en, this message translates to:
  /// **'Catching up missed messages. New messages will still appear here.'**
  String get group_recovery_banner;

  /// No description provided for @group_read_only_dissolved.
  ///
  /// In en, this message translates to:
  /// **'This group has been dissolved. History stays available, but new messages are disabled.'**
  String get group_read_only_dissolved;

  /// No description provided for @group_read_only_admin_only.
  ///
  /// In en, this message translates to:
  /// **'Only admins can send messages in this group'**
  String get group_read_only_admin_only;

  /// No description provided for @group_removed_snackbar.
  ///
  /// In en, this message translates to:
  /// **'You were removed from this group.'**
  String get group_removed_snackbar;

  /// No description provided for @group_dissolved_snackbar.
  ///
  /// In en, this message translates to:
  /// **'This group has been dissolved'**
  String get group_dissolved_snackbar;

  /// No description provided for @group_info_mute_update_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to update mute'**
  String get group_info_mute_update_failed;

  /// No description provided for @group_info_dissolve_title.
  ///
  /// In en, this message translates to:
  /// **'Dissolve this group for everyone?'**
  String get group_info_dissolve_title;

  /// No description provided for @group_info_dissolve_body.
  ///
  /// In en, this message translates to:
  /// **'This ends the group for all members. History stays visible, but no one can send new messages after it is dissolved.'**
  String get group_info_dissolve_body;

  /// No description provided for @group_info_dissolve_action.
  ///
  /// In en, this message translates to:
  /// **'Dissolve'**
  String get group_info_dissolve_action;

  /// No description provided for @group_info_dissolved_recovery.
  ///
  /// In en, this message translates to:
  /// **'Group dissolved. Some members may need recovery to see it.'**
  String get group_info_dissolved_recovery;

  /// No description provided for @group_info_already_dissolved.
  ///
  /// In en, this message translates to:
  /// **'Group already dissolved'**
  String get group_info_already_dissolved;

  /// No description provided for @group_info_admins_only_dissolve.
  ///
  /// In en, this message translates to:
  /// **'Only admins can dissolve groups'**
  String get group_info_admins_only_dissolve;

  /// No description provided for @group_info_not_found.
  ///
  /// In en, this message translates to:
  /// **'Group no longer exists'**
  String get group_info_not_found;

  /// No description provided for @group_info_dissolve_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to dissolve group'**
  String get group_info_dissolve_failed;

  /// No description provided for @group_info_delete_local_title.
  ///
  /// In en, this message translates to:
  /// **'Delete this dissolved group from this device?'**
  String get group_info_delete_local_title;

  /// No description provided for @group_info_delete_local_body.
  ///
  /// In en, this message translates to:
  /// **'This removes the dissolved history from this device only. It will not affect anyone else or send a new leave event.'**
  String get group_info_delete_local_body;

  /// No description provided for @group_info_delete_local_action.
  ///
  /// In en, this message translates to:
  /// **'Delete Locally'**
  String get group_info_delete_local_action;

  /// No description provided for @group_info_remove_member_title.
  ///
  /// In en, this message translates to:
  /// **'Remove {username} from the group?'**
  String group_info_remove_member_title(String username);

  /// No description provided for @group_info_remove_member_body.
  ///
  /// In en, this message translates to:
  /// **'They will stop receiving new messages from this group.'**
  String get group_info_remove_member_body;

  /// No description provided for @group_info_remove_action.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get group_info_remove_action;

  /// No description provided for @group_info_member_fallback.
  ///
  /// In en, this message translates to:
  /// **'member'**
  String get group_info_member_fallback;

  /// No description provided for @group_info_make_admin_title.
  ///
  /// In en, this message translates to:
  /// **'Make {username} an admin?'**
  String group_info_make_admin_title(String username);

  /// No description provided for @group_info_remove_admin_title.
  ///
  /// In en, this message translates to:
  /// **'Remove admin access from {username}?'**
  String group_info_remove_admin_title(String username);

  /// No description provided for @group_info_make_admin_body.
  ///
  /// In en, this message translates to:
  /// **'They will be able to add, remove, and manage members.'**
  String get group_info_make_admin_body;

  /// No description provided for @group_info_remove_admin_body.
  ///
  /// In en, this message translates to:
  /// **'They will lose admin-only actions after the change syncs.'**
  String get group_info_remove_admin_body;

  /// No description provided for @group_info_make_admin_action.
  ///
  /// In en, this message translates to:
  /// **'Make Admin'**
  String get group_info_make_admin_action;

  /// No description provided for @group_info_remove_admin_action.
  ///
  /// In en, this message translates to:
  /// **'Remove Admin'**
  String get group_info_remove_admin_action;

  /// No description provided for @group_info_admin_added.
  ///
  /// In en, this message translates to:
  /// **'{username} is now an admin'**
  String group_info_admin_added(String username);

  /// No description provided for @group_info_admin_removed.
  ///
  /// In en, this message translates to:
  /// **'{username} is no longer an admin'**
  String group_info_admin_removed(String username);

  /// No description provided for @group_info_member_role_update_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to update member role'**
  String get group_info_member_role_update_failed;

  /// No description provided for @group_info_details_updated.
  ///
  /// In en, this message translates to:
  /// **'Group details updated'**
  String get group_info_details_updated;

  /// No description provided for @group_info_details_update_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to update group details'**
  String get group_info_details_update_failed;

  /// No description provided for @group_info_invite_resend_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to resend invite'**
  String get group_info_invite_resend_failed;

  /// No description provided for @group_info_invite_sent.
  ///
  /// In en, this message translates to:
  /// **'Invite sent to {username}'**
  String group_info_invite_sent(String username);

  /// No description provided for @group_info_invite_queued.
  ///
  /// In en, this message translates to:
  /// **'Invite is in {username}\'s inbox'**
  String group_info_invite_queued(String username);

  /// No description provided for @group_info_invite_needs_resend.
  ///
  /// In en, this message translates to:
  /// **'Invite still needs to be resent'**
  String get group_info_invite_needs_resend;

  /// No description provided for @group_info_invite_joined.
  ///
  /// In en, this message translates to:
  /// **'{username} already joined'**
  String group_info_invite_joined(String username);

  /// No description provided for @group_info_invite_unknown.
  ///
  /// In en, this message translates to:
  /// **'Invite status unknown'**
  String get group_info_invite_unknown;

  /// No description provided for @group_edit_photo_pick_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to pick group photo'**
  String get group_edit_photo_pick_failed;

  /// No description provided for @group_edit_details_title.
  ///
  /// In en, this message translates to:
  /// **'Edit Group Details'**
  String get group_edit_details_title;

  /// No description provided for @group_edit_change_photo.
  ///
  /// In en, this message translates to:
  /// **'Change Photo'**
  String get group_edit_change_photo;

  /// No description provided for @group_edit_add_photo.
  ///
  /// In en, this message translates to:
  /// **'Add Photo'**
  String get group_edit_add_photo;

  /// No description provided for @group_edit_remove_photo.
  ///
  /// In en, this message translates to:
  /// **'Remove Photo'**
  String get group_edit_remove_photo;

  /// No description provided for @group_edit_name.
  ///
  /// In en, this message translates to:
  /// **'Group Name'**
  String get group_edit_name;

  /// No description provided for @group_edit_description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get group_edit_description;

  /// No description provided for @btn_save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get btn_save;

  /// No description provided for @group_member_sending.
  ///
  /// In en, this message translates to:
  /// **'Sending...'**
  String get group_member_sending;

  /// No description provided for @group_member_resend.
  ///
  /// In en, this message translates to:
  /// **'Resend'**
  String get group_member_resend;

  /// No description provided for @group_member_manage_role.
  ///
  /// In en, this message translates to:
  /// **'Manage role'**
  String get group_member_manage_role;

  /// No description provided for @group_role_admin.
  ///
  /// In en, this message translates to:
  /// **'admin'**
  String get group_role_admin;

  /// No description provided for @group_role_writer.
  ///
  /// In en, this message translates to:
  /// **'writer'**
  String get group_role_writer;

  /// No description provided for @group_role_reader.
  ///
  /// In en, this message translates to:
  /// **'reader'**
  String get group_role_reader;

  /// No description provided for @group_identity_changed.
  ///
  /// In en, this message translates to:
  /// **'Identity changed'**
  String get group_identity_changed;

  /// No description provided for @group_current_safety.
  ///
  /// In en, this message translates to:
  /// **'Current safety'**
  String get group_current_safety;

  /// No description provided for @group_saved_safety.
  ///
  /// In en, this message translates to:
  /// **'Saved safety'**
  String get group_saved_safety;

  /// No description provided for @group_card_no_messages.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get group_card_no_messages;

  /// No description provided for @group_security_encrypted.
  ///
  /// In en, this message translates to:
  /// **'End-to-end encrypted'**
  String get group_security_encrypted;

  /// No description provided for @group_security_pending.
  ///
  /// In en, this message translates to:
  /// **'Encryption pending'**
  String get group_security_pending;

  /// No description provided for @group_security_no_key.
  ///
  /// In en, this message translates to:
  /// **'No group key on this device'**
  String get group_security_no_key;

  /// No description provided for @group_security_key_changed.
  ///
  /// In en, this message translates to:
  /// **'Group key changed to epoch {keyEpoch}'**
  String group_security_key_changed(int keyEpoch);

  /// No description provided for @group_security_current_key_epoch.
  ///
  /// In en, this message translates to:
  /// **'Current key epoch {keyEpoch}'**
  String group_security_current_key_epoch(int keyEpoch);

  /// No description provided for @group_security_no_members.
  ///
  /// In en, this message translates to:
  /// **'No members to verify'**
  String get group_security_no_members;

  /// No description provided for @group_security_all_members_verified.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{All 1 member verified} other{All {count} members verified}}'**
  String group_security_all_members_verified(int count);

  /// No description provided for @group_security_members_verified.
  ///
  /// In en, this message translates to:
  /// **'{verifiedCount} of {memberCount} members verified'**
  String group_security_members_verified(int verifiedCount, int memberCount);

  /// No description provided for @group_security_members_need_review.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 member needs verification review} other{{count} members need verification review}}'**
  String group_security_members_need_review(int count);

  /// No description provided for @group_security_members_unverified.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 member not verified from saved contacts} other{{count} members not verified from saved contacts}}'**
  String group_security_members_unverified(int count);

  /// No description provided for @group_security_no_warnings.
  ///
  /// In en, this message translates to:
  /// **'No verification warnings'**
  String get group_security_no_warnings;

  /// No description provided for @group_security_compact_encrypted_epoch.
  ///
  /// In en, this message translates to:
  /// **'Encrypted - key epoch {keyEpoch}'**
  String group_security_compact_encrypted_epoch(int keyEpoch);

  /// No description provided for @invite_status_sent.
  ///
  /// In en, this message translates to:
  /// **'Invite sent'**
  String get invite_status_sent;

  /// No description provided for @invite_status_queued.
  ///
  /// In en, this message translates to:
  /// **'In their inbox'**
  String get invite_status_queued;

  /// No description provided for @invite_status_needs_resend.
  ///
  /// In en, this message translates to:
  /// **'Resend needed'**
  String get invite_status_needs_resend;

  /// No description provided for @invite_status_cannot_send.
  ///
  /// In en, this message translates to:
  /// **'Cannot send'**
  String get invite_status_cannot_send;

  /// No description provided for @invite_status_joined.
  ///
  /// In en, this message translates to:
  /// **'Joined'**
  String get invite_status_joined;

  /// No description provided for @invite_status_unknown.
  ///
  /// In en, this message translates to:
  /// **'Invite unknown'**
  String get invite_status_unknown;

  /// No description provided for @invite_cannot_send_missing_secure_key_detail.
  ///
  /// In en, this message translates to:
  /// **'We don\'t have the secure info needed to invite this friend. Ask them to open or reinstall the app, then try again.'**
  String get invite_cannot_send_missing_secure_key_detail;

  /// No description provided for @invite_cannot_send_group_key_missing_detail.
  ///
  /// In en, this message translates to:
  /// **'This group is missing the secure invite key. Reopen the app and try again.'**
  String get invite_cannot_send_group_key_missing_detail;

  /// No description provided for @invite_cannot_send_invalid_payload_detail.
  ///
  /// In en, this message translates to:
  /// **'This invite could not be prepared. Reopen the app and try again.'**
  String get invite_cannot_send_invalid_payload_detail;

  /// No description provided for @invite_cannot_send_generic_detail.
  ///
  /// In en, this message translates to:
  /// **'We could not prepare a secure invite for this friend. They may need to open or reinstall the app before you can invite them.'**
  String get invite_cannot_send_generic_detail;

  /// No description provided for @invite_cannot_send_missing_secure_key_snackbar.
  ///
  /// In en, this message translates to:
  /// **'Cannot send: we don\'t have the secure info needed to invite this friend.'**
  String get invite_cannot_send_missing_secure_key_snackbar;

  /// No description provided for @invite_cannot_send_group_key_missing_snackbar.
  ///
  /// In en, this message translates to:
  /// **'Cannot send: this group is missing the secure invite key.'**
  String get invite_cannot_send_group_key_missing_snackbar;

  /// No description provided for @invite_cannot_send_invalid_payload_snackbar.
  ///
  /// In en, this message translates to:
  /// **'Cannot send: this invite could not be prepared.'**
  String get invite_cannot_send_invalid_payload_snackbar;

  /// No description provided for @invite_cannot_send_generic_snackbar.
  ///
  /// In en, this message translates to:
  /// **'Cannot send: we could not prepare a secure invite for this friend.'**
  String get invite_cannot_send_generic_snackbar;

  /// No description provided for @group_backlog_mixed_list_summary.
  ///
  /// In en, this message translates to:
  /// **'Older backlog expired after {days} days'**
  String group_backlog_mixed_list_summary(int days);

  /// No description provided for @group_backlog_mixed_banner.
  ///
  /// In en, this message translates to:
  /// **'Older missed messages expired after {days} days. Recent messages were recovered.'**
  String group_backlog_mixed_banner(int days);

  /// No description provided for @group_backlog_mixed_empty_title.
  ///
  /// In en, this message translates to:
  /// **'Recent messages recovered'**
  String get group_backlog_mixed_empty_title;

  /// No description provided for @group_backlog_mixed_empty_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Older missed messages expired after {days} days while you were away.'**
  String group_backlog_mixed_empty_subtitle(int days);

  /// No description provided for @group_backlog_expired_list_summary.
  ///
  /// In en, this message translates to:
  /// **'Missed backlog expired after {days} days'**
  String group_backlog_expired_list_summary(int days);

  /// No description provided for @group_backlog_expired_banner.
  ///
  /// In en, this message translates to:
  /// **'Missed messages older than {days} days expired while you were away.'**
  String group_backlog_expired_banner(int days);

  /// No description provided for @group_backlog_expired_empty_title.
  ///
  /// In en, this message translates to:
  /// **'Older backlog expired'**
  String get group_backlog_expired_empty_title;

  /// No description provided for @group_backlog_expired_empty_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Missed messages older than {days} days expired while you were away.'**
  String group_backlog_expired_empty_subtitle(int days);

  /// No description provided for @group_history_repair_active_banner.
  ///
  /// In en, this message translates to:
  /// **'Some missed messages are being repaired from trusted group members.'**
  String get group_history_repair_active_banner;

  /// No description provided for @group_history_repair_active_empty_title.
  ///
  /// In en, this message translates to:
  /// **'Repairing missed messages'**
  String get group_history_repair_active_empty_title;

  /// No description provided for @group_history_repair_active_empty_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Some missed messages are being verified before they appear here.'**
  String get group_history_repair_active_empty_subtitle;

  /// No description provided for @group_history_repair_failed_banner.
  ///
  /// In en, this message translates to:
  /// **'Some missed messages could not be repaired from trusted group members.'**
  String get group_history_repair_failed_banner;

  /// No description provided for @group_history_repair_failed_empty_title.
  ///
  /// In en, this message translates to:
  /// **'History repair needed'**
  String get group_history_repair_failed_empty_title;

  /// No description provided for @group_history_repair_failed_empty_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Some missed messages could not be verified from trusted members.'**
  String get group_history_repair_failed_empty_subtitle;

  /// No description provided for @group_history_repair_done_banner.
  ///
  /// In en, this message translates to:
  /// **'Missed messages were repaired and verified.'**
  String get group_history_repair_done_banner;

  /// No description provided for @group_history_repair_done_empty_title.
  ///
  /// In en, this message translates to:
  /// **'Messages repaired'**
  String get group_history_repair_done_empty_title;

  /// No description provided for @group_history_repair_done_empty_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Missed messages were verified and restored.'**
  String get group_history_repair_done_empty_subtitle;

  /// No description provided for @group_info_leave_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to leave group'**
  String get group_info_leave_failed;

  /// No description provided for @group_info_notifications_muted.
  ///
  /// In en, this message translates to:
  /// **'Notifications muted for this group'**
  String get group_info_notifications_muted;

  /// No description provided for @group_info_notifications_restored.
  ///
  /// In en, this message translates to:
  /// **'Notifications restored for this group'**
  String get group_info_notifications_restored;

  /// No description provided for @group_info_delete_local_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete group locally'**
  String get group_info_delete_local_failed;

  /// No description provided for @group_info_publish_member_removal_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to publish member removal'**
  String get group_info_publish_member_removal_failed;

  /// No description provided for @group_info_rotate_key_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to rotate group key after removal'**
  String get group_info_rotate_key_failed;

  /// No description provided for @group_info_remove_member_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to remove member'**
  String get group_info_remove_member_failed;

  /// No description provided for @group_info_no_identity.
  ///
  /// In en, this message translates to:
  /// **'No identity found'**
  String get group_info_no_identity;

  /// No description provided for @group_info_member_not_found.
  ///
  /// In en, this message translates to:
  /// **'Member not found'**
  String get group_info_member_not_found;

  /// No description provided for @group_info_upload_photo_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to upload group photo'**
  String get group_info_upload_photo_failed;

  /// No description provided for @group_info_sign_metadata_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to sign group metadata update'**
  String get group_info_sign_metadata_failed;

  /// No description provided for @groups_title.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get groups_title;

  /// No description provided for @groups_empty_title.
  ///
  /// In en, this message translates to:
  /// **'No groups yet'**
  String get groups_empty_title;

  /// No description provided for @groups_empty_desc.
  ///
  /// In en, this message translates to:
  /// **'Create a group to get started'**
  String get groups_empty_desc;

  /// No description provided for @groups_pending_invites.
  ///
  /// In en, this message translates to:
  /// **'Pending Invites'**
  String get groups_pending_invites;

  /// No description provided for @groups_joined.
  ///
  /// In en, this message translates to:
  /// **'Joined Groups'**
  String get groups_joined;

  /// No description provided for @groups_unknown_sender.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get groups_unknown_sender;

  /// No description provided for @groups_no_joined.
  ///
  /// In en, this message translates to:
  /// **'No joined groups yet. Accept an invite to add it here.'**
  String get groups_no_joined;

  /// No description provided for @group_type_discussion.
  ///
  /// In en, this message translates to:
  /// **'Discussion'**
  String get group_type_discussion;

  /// No description provided for @group_type_announce.
  ///
  /// In en, this message translates to:
  /// **'Announce'**
  String get group_type_announce;

  /// No description provided for @group_type_qa.
  ///
  /// In en, this message translates to:
  /// **'Q&A'**
  String get group_type_qa;

  /// No description provided for @group_dissolved_badge.
  ///
  /// In en, this message translates to:
  /// **'Dissolved'**
  String get group_dissolved_badge;

  /// No description provided for @pending_invite_expired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get pending_invite_expired;

  /// No description provided for @pending_invite_accept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get pending_invite_accept;

  /// No description provided for @pending_invite_decline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get pending_invite_decline;

  /// No description provided for @pending_invite_dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get pending_invite_dismiss;

  /// No description provided for @pending_invite_invited_by.
  ///
  /// In en, this message translates to:
  /// **'Invited by {username}'**
  String pending_invite_invited_by(String username);

  /// No description provided for @pending_invite_expires.
  ///
  /// In en, this message translates to:
  /// **'Expires {date}'**
  String pending_invite_expires(String date);

  /// No description provided for @group_no_contacts_available.
  ///
  /// In en, this message translates to:
  /// **'No contacts available'**
  String get group_no_contacts_available;

  /// No description provided for @settings_intro_debug_delete_row.
  ///
  /// In en, this message translates to:
  /// **'Delete Row'**
  String get settings_intro_debug_delete_row;

  /// No description provided for @settings_intro_debug_delete_pair.
  ///
  /// In en, this message translates to:
  /// **'Delete Pair'**
  String get settings_intro_debug_delete_pair;

  /// No description provided for @settings_intro_debug_deleted_row.
  ///
  /// In en, this message translates to:
  /// **'Deleted local introduction row'**
  String get settings_intro_debug_deleted_row;

  /// No description provided for @settings_intro_debug_deleted_pair.
  ///
  /// In en, this message translates to:
  /// **'Deleted local pair {pairLabel}'**
  String settings_intro_debug_deleted_pair(String pairLabel);

  /// No description provided for @settings_intro_debug_heading.
  ///
  /// In en, this message translates to:
  /// **'DEBUG INTRODUCTIONS'**
  String get settings_intro_debug_heading;

  /// No description provided for @settings_intro_debug_description.
  ///
  /// In en, this message translates to:
  /// **'Local sent intro rows on this device. Deleting a pair makes it selectable again in the picker.'**
  String get settings_intro_debug_description;

  /// No description provided for @settings_intro_debug_empty.
  ///
  /// In en, this message translates to:
  /// **'No local introduction rows for the current user.'**
  String get settings_intro_debug_empty;

  /// No description provided for @settings_intro_debug_status_line.
  ///
  /// In en, this message translates to:
  /// **'status={status}  recipient={recipientStatus}  introduced={introducedStatus}'**
  String settings_intro_debug_status_line(
    String status,
    String recipientStatus,
    String introducedStatus,
  );

  /// No description provided for @settings_intro_debug_meta_line.
  ///
  /// In en, this message translates to:
  /// **'id={id}  created={createdAt}'**
  String settings_intro_debug_meta_line(String id, String createdAt);

  /// No description provided for @group_start_chat.
  ///
  /// In en, this message translates to:
  /// **'Start group chat'**
  String get group_start_chat;

  /// No description provided for @group_reactions_title.
  ///
  /// In en, this message translates to:
  /// **'Reactions'**
  String get group_reactions_title;

  /// No description provided for @group_add_members_count.
  ///
  /// In en, this message translates to:
  /// **'Add Members ({count})'**
  String group_add_members_count(int count);

  /// No description provided for @group_loading_contacts.
  ///
  /// In en, this message translates to:
  /// **'Loading contacts...'**
  String get group_loading_contacts;

  /// No description provided for @group_send_invites.
  ///
  /// In en, this message translates to:
  /// **'Send Invites'**
  String get group_send_invites;

  /// No description provided for @group_send_permission_lost.
  ///
  /// In en, this message translates to:
  /// **'You no longer have permission to send messages in this group.'**
  String get group_send_permission_lost;

  /// No description provided for @group_unavailable_snackbar.
  ///
  /// In en, this message translates to:
  /// **'This group is no longer available.'**
  String get group_unavailable_snackbar;

  /// No description provided for @media_retry_unavailable_now.
  ///
  /// In en, this message translates to:
  /// **'Retry unavailable right now.'**
  String get media_retry_unavailable_now;

  /// No description provided for @media_unavailable_now.
  ///
  /// In en, this message translates to:
  /// **'Media unavailable right now.'**
  String get media_unavailable_now;

  /// No description provided for @media_still_unavailable.
  ///
  /// In en, this message translates to:
  /// **'Media is still unavailable.'**
  String get media_still_unavailable;

  /// No description provided for @failed_media_retry_failed.
  ///
  /// In en, this message translates to:
  /// **'Could not retry media message.'**
  String get failed_media_retry_failed;

  /// No description provided for @failed_media_delete_unavailable.
  ///
  /// In en, this message translates to:
  /// **'Delete unavailable right now.'**
  String get failed_media_delete_unavailable;

  /// No description provided for @picker_media_library.
  ///
  /// In en, this message translates to:
  /// **'Media Library'**
  String get picker_media_library;

  /// No description provided for @picker_record_video.
  ///
  /// In en, this message translates to:
  /// **'Record Video'**
  String get picker_record_video;

  /// No description provided for @perm_microphone_record.
  ///
  /// In en, this message translates to:
  /// **'Microphone permission is required to record voice messages.'**
  String get perm_microphone_record;

  /// No description provided for @group_read_only_not_active.
  ///
  /// In en, this message translates to:
  /// **'You can read this group\'s history, but you are not an active member.'**
  String get group_read_only_not_active;

  /// No description provided for @group_read_only_waiting_key.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the current group key before you can send.'**
  String get group_read_only_waiting_key;

  /// No description provided for @group_read_only_waiting_identity.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your identity before you can send.'**
  String get group_read_only_waiting_identity;

  /// No description provided for @group_media_unsupported.
  ///
  /// In en, this message translates to:
  /// **'This media type is not supported in groups.'**
  String get group_media_unsupported;

  /// No description provided for @upload_progress_title.
  ///
  /// In en, this message translates to:
  /// **'Uploading media'**
  String get upload_progress_title;

  /// No description provided for @upload_progress_keep_open.
  ///
  /// In en, this message translates to:
  /// **'Keep the app open until the upload completes'**
  String get upload_progress_keep_open;

  /// No description provided for @conversation_blocked_contact.
  ///
  /// In en, this message translates to:
  /// **'You blocked this contact.'**
  String get conversation_blocked_contact;

  /// No description provided for @conversation_unblock.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get conversation_unblock;

  /// No description provided for @conversation_empty_first_letter.
  ///
  /// In en, this message translates to:
  /// **'Write the first letter\nto start your conversation'**
  String get conversation_empty_first_letter;

  /// No description provided for @media_video_load_failed.
  ///
  /// In en, this message translates to:
  /// **'Could not load video'**
  String get media_video_load_failed;

  /// No description provided for @conversation_introduce_to_circle.
  ///
  /// In en, this message translates to:
  /// **'Introduce to your circle'**
  String get conversation_introduce_to_circle;

  /// No description provided for @conversation_block_contact.
  ///
  /// In en, this message translates to:
  /// **'Block {username}'**
  String conversation_block_contact(String username);

  /// No description provided for @conversation_unblock_contact.
  ///
  /// In en, this message translates to:
  /// **'Unblock {username}'**
  String conversation_unblock_contact(String username);

  /// No description provided for @conversation_delete_chat_action.
  ///
  /// In en, this message translates to:
  /// **'Delete chat'**
  String get conversation_delete_chat_action;

  /// No description provided for @post_pass_along_title.
  ///
  /// In en, this message translates to:
  /// **'Pass along'**
  String get post_pass_along_title;

  /// No description provided for @post_pass_along_desc.
  ///
  /// In en, this message translates to:
  /// **'Choose who should receive this one-hop pass.'**
  String get post_pass_along_desc;

  /// No description provided for @post_pass_along_no_eligible.
  ///
  /// In en, this message translates to:
  /// **'No eligible friends available right now.'**
  String get post_pass_along_no_eligible;

  /// No description provided for @comments_count.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No comments} =1{1 comment} other{{count} comments}}'**
  String comments_count(int count);

  /// No description provided for @comments_empty.
  ///
  /// In en, this message translates to:
  /// **'No comments yet'**
  String get comments_empty;

  /// No description provided for @edit_pinned_post_title.
  ///
  /// In en, this message translates to:
  /// **'Edit pinned post'**
  String get edit_pinned_post_title;

  /// No description provided for @post_passed_along_by.
  ///
  /// In en, this message translates to:
  /// **'{username} passed this along'**
  String post_passed_along_by(String username);

  /// No description provided for @home_empty_circle_title.
  ///
  /// In en, this message translates to:
  /// **'Your circle is waiting to be filled'**
  String get home_empty_circle_title;

  /// No description provided for @home_empty_circle_desc.
  ///
  /// In en, this message translates to:
  /// **'Scan a friend\'s code or share yours to connect'**
  String get home_empty_circle_desc;

  /// No description provided for @home_scan_friend_title.
  ///
  /// In en, this message translates to:
  /// **'Scan a friend\'s code'**
  String get home_scan_friend_title;

  /// No description provided for @home_scan_friend_desc.
  ///
  /// In en, this message translates to:
  /// **'Add someone to your circle'**
  String get home_scan_friend_desc;

  /// No description provided for @contact_request_message.
  ///
  /// In en, this message translates to:
  /// **'wants to connect with you'**
  String get contact_request_message;

  /// No description provided for @contact_request_decline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get contact_request_decline;

  /// No description provided for @share_caption.
  ///
  /// In en, this message translates to:
  /// **'Caption'**
  String get share_caption;

  /// No description provided for @share_title_count.
  ///
  /// In en, this message translates to:
  /// **'Share with ({count})'**
  String share_title_count(int count);

  /// No description provided for @share_title_empty.
  ///
  /// In en, this message translates to:
  /// **'Share with...'**
  String get share_title_empty;

  /// No description provided for @share_no_targets.
  ///
  /// In en, this message translates to:
  /// **'No contacts or groups yet'**
  String get share_no_targets;

  /// No description provided for @share_no_matches.
  ///
  /// In en, this message translates to:
  /// **'No matches found'**
  String get share_no_matches;

  /// No description provided for @share_contacts_section.
  ///
  /// In en, this message translates to:
  /// **'Contacts'**
  String get share_contacts_section;

  /// No description provided for @share_groups_section.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get share_groups_section;

  /// No description provided for @share_group_type_announcement.
  ///
  /// In en, this message translates to:
  /// **'Announcement'**
  String get share_group_type_announcement;

  /// No description provided for @share_group_type_chat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get share_group_type_chat;

  /// No description provided for @share_sending.
  ///
  /// In en, this message translates to:
  /// **'Sending...'**
  String get share_sending;

  /// No description provided for @share_send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get share_send;

  /// No description provided for @share_target_count.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 target} other{{count} targets}}'**
  String share_target_count(int count);

  /// No description provided for @share_summary_sent.
  ///
  /// In en, this message translates to:
  /// **'Sent to {targetCount}'**
  String share_summary_sent(String targetCount);

  /// No description provided for @share_summary_queued.
  ///
  /// In en, this message translates to:
  /// **'saved {targetCount} for retry'**
  String share_summary_queued(String targetCount);

  /// No description provided for @share_summary_failed.
  ///
  /// In en, this message translates to:
  /// **'failed for {targetCount}'**
  String share_summary_failed(String targetCount);

  /// No description provided for @share_summary_nothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing was shared.'**
  String get share_summary_nothing;

  /// No description provided for @share_summary_skipped_gifs.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Skipped 1 oversized GIF.} other{Skipped {count} oversized GIFs.}}'**
  String share_summary_skipped_gifs(int count);

  /// No description provided for @time_just_now.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get time_just_now;

  /// No description provided for @time_min_ago.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 min ago} other{{count} min ago}}'**
  String time_min_ago(int count);

  /// No description provided for @time_hour_ago.
  ///
  /// In en, this message translates to:
  /// **'{count}h ago'**
  String time_hour_ago(int count);

  /// No description provided for @time_day_ago.
  ///
  /// In en, this message translates to:
  /// **'{count}d ago'**
  String time_day_ago(int count);

  /// No description provided for @time_week_ago.
  ///
  /// In en, this message translates to:
  /// **'{count}w ago'**
  String time_week_ago(int count);

  /// No description provided for @post_expired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get post_expired;

  /// No description provided for @post_expires_days_hours.
  ///
  /// In en, this message translates to:
  /// **'Expires in {days}d {hours}h'**
  String post_expires_days_hours(int days, int hours);

  /// No description provided for @post_expires_days.
  ///
  /// In en, this message translates to:
  /// **'Expires in {days}d'**
  String post_expires_days(int days);

  /// No description provided for @post_expires_hours.
  ///
  /// In en, this message translates to:
  /// **'Expires in {hours}h'**
  String post_expires_hours(int hours);

  /// No description provided for @post_expires_minutes.
  ///
  /// In en, this message translates to:
  /// **'Expires in {minutes}m'**
  String post_expires_minutes(int minutes);

  /// No description provided for @post_expires_soon.
  ///
  /// In en, this message translates to:
  /// **'Expires soon'**
  String get post_expires_soon;

  /// No description provided for @post_photo_upload_failed.
  ///
  /// In en, this message translates to:
  /// **'Photo upload failed'**
  String get post_photo_upload_failed;

  /// No description provided for @post_photo_pending_upload.
  ///
  /// In en, this message translates to:
  /// **'Photo pending upload'**
  String get post_photo_pending_upload;

  /// No description provided for @post_photos_pending_upload.
  ///
  /// In en, this message translates to:
  /// **'Photos pending upload'**
  String get post_photos_pending_upload;

  /// No description provided for @post_video_upload_failed.
  ///
  /// In en, this message translates to:
  /// **'Video upload failed'**
  String get post_video_upload_failed;

  /// No description provided for @post_video_pending_upload.
  ///
  /// In en, this message translates to:
  /// **'Video pending upload'**
  String get post_video_pending_upload;

  /// No description provided for @post_voice_upload_failed.
  ///
  /// In en, this message translates to:
  /// **'Voice upload failed'**
  String get post_voice_upload_failed;

  /// No description provided for @post_voice_pending_upload.
  ///
  /// In en, this message translates to:
  /// **'Voice note pending upload'**
  String get post_voice_pending_upload;

  /// No description provided for @post_media_upload_failed.
  ///
  /// In en, this message translates to:
  /// **'Media upload failed'**
  String get post_media_upload_failed;

  /// No description provided for @post_media_pending_upload.
  ///
  /// In en, this message translates to:
  /// **'Media pending upload'**
  String get post_media_pending_upload;

  /// No description provided for @post_media_upload_failed_desc.
  ///
  /// In en, this message translates to:
  /// **'This post stayed local because the media upload did not finish.'**
  String get post_media_upload_failed_desc;

  /// No description provided for @post_media_pending_upload_desc.
  ///
  /// In en, this message translates to:
  /// **'Recipients will receive this after the upload finishes.'**
  String get post_media_pending_upload_desc;

  /// No description provided for @post_send_pass.
  ///
  /// In en, this message translates to:
  /// **'Send pass'**
  String get post_send_pass;

  /// No description provided for @btn_saving.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get btn_saving;

  /// No description provided for @intro_from.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get intro_from;

  /// No description provided for @intro_empty.
  ///
  /// In en, this message translates to:
  /// **'No introductions yet'**
  String get intro_empty;

  /// No description provided for @intro_tab_desc.
  ///
  /// In en, this message translates to:
  /// **'These are people your friends know well. Once you both accept, you can start chatting.'**
  String get intro_tab_desc;

  /// No description provided for @intro_banner_title.
  ///
  /// In en, this message translates to:
  /// **'Help {username} meet your circle'**
  String intro_banner_title(String username);

  /// No description provided for @intro_banner_desc.
  ///
  /// In en, this message translates to:
  /// **'Introduce them to friends who might click'**
  String get intro_banner_desc;

  /// No description provided for @intro_make_introductions.
  ///
  /// In en, this message translates to:
  /// **'Make introductions'**
  String get intro_make_introductions;

  /// No description provided for @intro_maybe_later.
  ///
  /// In en, this message translates to:
  /// **'Maybe later'**
  String get intro_maybe_later;

  /// No description provided for @introduced_by_label.
  ///
  /// In en, this message translates to:
  /// **'Introduced by'**
  String get introduced_by_label;

  /// No description provided for @intro_unavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get intro_unavailable;

  /// No description provided for @intro_waiting_for.
  ///
  /// In en, this message translates to:
  /// **'Waiting for {username}'**
  String intro_waiting_for(String username);

  /// No description provided for @intro_waiting_for_them.
  ///
  /// In en, this message translates to:
  /// **'Waiting for them'**
  String get intro_waiting_for_them;

  /// No description provided for @intro_sent_count.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 introduction sent} other{{count} introductions sent}}'**
  String intro_sent_count(int count);

  /// No description provided for @intro_back_to_conversation.
  ///
  /// In en, this message translates to:
  /// **'Back to conversation'**
  String get intro_back_to_conversation;

  /// No description provided for @identity_tagline.
  ///
  /// In en, this message translates to:
  /// **'Your identity, your control'**
  String get identity_tagline;

  /// No description provided for @startup_failed_title.
  ///
  /// In en, this message translates to:
  /// **'Failed to initialize'**
  String get startup_failed_title;

  /// No description provided for @identity_restore_action.
  ///
  /// In en, this message translates to:
  /// **'Restore identity'**
  String get identity_restore_action;

  /// No description provided for @settings_peer_id_title.
  ///
  /// In en, this message translates to:
  /// **'PEER ID'**
  String get settings_peer_id_title;

  /// No description provided for @settings_peer_id_desc.
  ///
  /// In en, this message translates to:
  /// **'Your unique identifier on the network'**
  String get settings_peer_id_desc;

  /// No description provided for @intro_and_more.
  ///
  /// In en, this message translates to:
  /// **'{names} and {count} more'**
  String intro_and_more(String names, int count);

  /// No description provided for @orbit_block_action.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get orbit_block_action;

  /// No description provided for @orbit_unblock_action.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get orbit_unblock_action;

  /// No description provided for @orbit_delete_action.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get orbit_delete_action;

  /// No description provided for @orbit_archive_action.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get orbit_archive_action;

  /// No description provided for @orbit_unarchive_action.
  ///
  /// In en, this message translates to:
  /// **'Unarchive'**
  String get orbit_unarchive_action;

  /// No description provided for @orbit_archived_empty_title.
  ///
  /// In en, this message translates to:
  /// **'No archived friends yet'**
  String get orbit_archived_empty_title;

  /// No description provided for @orbit_archived_empty_desc.
  ///
  /// In en, this message translates to:
  /// **'Swipe left on a friend to archive them.'**
  String get orbit_archived_empty_desc;

  /// No description provided for @orbit_inner_circle_badge.
  ///
  /// In en, this message translates to:
  /// **'Inner Circle'**
  String get orbit_inner_circle_badge;

  /// No description provided for @orbit_inner_circle_title.
  ///
  /// In en, this message translates to:
  /// **'YOUR INNER CIRCLE'**
  String get orbit_inner_circle_title;

  /// No description provided for @orbit_pending_items.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item pending} other{{count} items pending}}'**
  String orbit_pending_items(int count);

  /// No description provided for @orbit_pending_group_invites.
  ///
  /// In en, this message translates to:
  /// **'Pending Group Invites'**
  String get orbit_pending_group_invites;

  /// No description provided for @orbit_pending_group_intro_desc.
  ///
  /// In en, this message translates to:
  /// **'Review pending group invites here, then check introductions below. Once you accept, the group appears in Orbit and catches up from offline inbox.'**
  String get orbit_pending_group_intro_desc;

  /// No description provided for @orbit_no_friends_matching.
  ///
  /// In en, this message translates to:
  /// **'No friends matching \"{query}\"'**
  String orbit_no_friends_matching(String query);

  /// No description provided for @feed_blocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get feed_blocked;

  /// No description provided for @feed_introduced_by.
  ///
  /// In en, this message translates to:
  /// **'Introduced by {username}'**
  String feed_introduced_by(String username);

  /// No description provided for @feed_previously_seen.
  ///
  /// In en, this message translates to:
  /// **'PREVIOUSLY SEEN'**
  String get feed_previously_seen;

  /// No description provided for @feed_replying_to.
  ///
  /// In en, this message translates to:
  /// **'Replying to'**
  String get feed_replying_to;

  /// No description provided for @feed_view_earlier_messages.
  ///
  /// In en, this message translates to:
  /// **'View earlier messages'**
  String get feed_view_earlier_messages;

  /// No description provided for @feed_ready_for_user.
  ///
  /// In en, this message translates to:
  /// **'Your feed is ready, @{username}. New connections will appear here.'**
  String feed_ready_for_user(String username);

  /// No description provided for @feed_loading.
  ///
  /// In en, this message translates to:
  /// **'Loading Feed...'**
  String get feed_loading;

  /// No description provided for @feed_syncing_threads.
  ///
  /// In en, this message translates to:
  /// **'Your recent threads are still syncing.'**
  String get feed_syncing_threads;

  /// No description provided for @qr_added_to_circle.
  ///
  /// In en, this message translates to:
  /// **'Added to your circle!'**
  String get qr_added_to_circle;

  /// No description provided for @btn_ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get btn_ok;

  /// No description provided for @qr_already_in_circle.
  ///
  /// In en, this message translates to:
  /// **'Already in your circle!'**
  String get qr_already_in_circle;

  /// No description provided for @qr_contact_added_previously.
  ///
  /// In en, this message translates to:
  /// **'This contact was added previously'**
  String get qr_contact_added_previously;

  /// No description provided for @btn_got_it.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get btn_got_it;

  /// No description provided for @orbit_intro_banner_mixed.
  ///
  /// In en, this message translates to:
  /// **'{inviteCount, plural, =1{1 group invite} other{{inviteCount} group invites}} and {introCount, plural, =1{1 introduction} other{{introCount} introductions}} waiting'**
  String orbit_intro_banner_mixed(int inviteCount, int introCount);

  /// No description provided for @orbit_intro_banner_invites.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Review group invite and join from Intros} other{Review group invites and join from Intros}}'**
  String orbit_intro_banner_invites(int count);

  /// No description provided for @orbit_intro_banner_intros.
  ///
  /// In en, this message translates to:
  /// **'Review and accept introductions to start chatting'**
  String get orbit_intro_banner_intros;

  /// No description provided for @group_member_invited_count.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Member invited} other{{count} members invited}}'**
  String group_member_invited_count(int count);

  /// No description provided for @group_member_added_count.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 member added} other{{count} members added}}'**
  String group_member_added_count(int count);

  /// No description provided for @group_invite_missing_key_issue.
  ///
  /// In en, this message translates to:
  /// **'invites were not sent because the group is missing its latest key'**
  String get group_invite_missing_key_issue;

  /// No description provided for @group_invite_issues.
  ///
  /// In en, this message translates to:
  /// **'invite issues: {details}'**
  String group_invite_issues(String details);

  /// No description provided for @group_members_publish_failed_issue.
  ///
  /// In en, this message translates to:
  /// **'the add-members event could not be published'**
  String get group_members_publish_failed_issue;

  /// No description provided for @group_member_added_with_warnings.
  ///
  /// In en, this message translates to:
  /// **'{prefix}, but {issues}.'**
  String group_member_added_with_warnings(String prefix, String issues);

  /// No description provided for @group_invite_joined.
  ///
  /// In en, this message translates to:
  /// **'Joined {name}'**
  String group_invite_joined(String name);

  /// No description provided for @group_invite_no_longer_available.
  ///
  /// In en, this message translates to:
  /// **'Invite no longer available'**
  String get group_invite_no_longer_available;

  /// No description provided for @group_invite_expired.
  ///
  /// In en, this message translates to:
  /// **'Invite expired'**
  String get group_invite_expired;

  /// No description provided for @group_invite_revoked.
  ///
  /// In en, this message translates to:
  /// **'Invite was revoked'**
  String get group_invite_revoked;

  /// No description provided for @group_invite_already_used.
  ///
  /// In en, this message translates to:
  /// **'Invite already used'**
  String get group_invite_already_used;

  /// No description provided for @group_invite_wrong_identity.
  ///
  /// In en, this message translates to:
  /// **'Invite is for another identity'**
  String get group_invite_wrong_identity;

  /// No description provided for @group_invite_needs_key.
  ///
  /// In en, this message translates to:
  /// **'Invite needs fresh key material'**
  String get group_invite_needs_key;

  /// No description provided for @group_invite_invalid.
  ///
  /// In en, this message translates to:
  /// **'Invite is no longer valid'**
  String get group_invite_invalid;

  /// No description provided for @group_invite_duplicate_group.
  ///
  /// In en, this message translates to:
  /// **'Group already added'**
  String get group_invite_duplicate_group;

  /// No description provided for @group_invite_joined_recovery.
  ///
  /// In en, this message translates to:
  /// **'Joined {name}, but recovery is still catching up'**
  String group_invite_joined_recovery(String name);

  /// No description provided for @group_invite_accepted_recovery.
  ///
  /// In en, this message translates to:
  /// **'Invite accepted, but recovery is still catching up'**
  String get group_invite_accepted_recovery;

  /// No description provided for @group_invite_accept_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to accept invite'**
  String get group_invite_accept_failed;

  /// No description provided for @group_invite_declined.
  ///
  /// In en, this message translates to:
  /// **'Invite declined'**
  String get group_invite_declined;

  /// No description provided for @group_invite_decline_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to decline invite'**
  String get group_invite_decline_failed;

  /// No description provided for @post_pin_retrying.
  ///
  /// In en, this message translates to:
  /// **'Pin update will continue retrying'**
  String get post_pin_retrying;

  /// No description provided for @post_pin_queued.
  ///
  /// In en, this message translates to:
  /// **'Pin update queued for retry'**
  String get post_pin_queued;

  /// No description provided for @post_pin_failed.
  ///
  /// In en, this message translates to:
  /// **'Pin update failed'**
  String get post_pin_failed;

  /// No description provided for @post_pin_could_not.
  ///
  /// In en, this message translates to:
  /// **'Could not pin post'**
  String get post_pin_could_not;

  /// No description provided for @post_pinned_update_retrying.
  ///
  /// In en, this message translates to:
  /// **'Pinned post update will continue retrying'**
  String get post_pinned_update_retrying;

  /// No description provided for @post_pinned_update_queued.
  ///
  /// In en, this message translates to:
  /// **'Pinned post update queued for retry'**
  String get post_pinned_update_queued;

  /// No description provided for @post_pinned_update_failed.
  ///
  /// In en, this message translates to:
  /// **'Pinned post update failed'**
  String get post_pinned_update_failed;

  /// No description provided for @post_pinned_update_could_not.
  ///
  /// In en, this message translates to:
  /// **'Could not update pinned post'**
  String get post_pinned_update_could_not;

  /// No description provided for @post_pin_removal_retrying.
  ///
  /// In en, this message translates to:
  /// **'Pin removal will continue retrying'**
  String get post_pin_removal_retrying;

  /// No description provided for @post_pin_removal_queued.
  ///
  /// In en, this message translates to:
  /// **'Pin removal queued for retry'**
  String get post_pin_removal_queued;

  /// No description provided for @post_pin_removal_failed.
  ///
  /// In en, this message translates to:
  /// **'Pin removal failed'**
  String get post_pin_removal_failed;

  /// No description provided for @post_pin_remove_could_not.
  ///
  /// In en, this message translates to:
  /// **'Could not remove pin'**
  String get post_pin_remove_could_not;

  /// No description provided for @post_repost_retrying.
  ///
  /// In en, this message translates to:
  /// **'Repost will continue retrying'**
  String get post_repost_retrying;

  /// No description provided for @post_repost_queued.
  ///
  /// In en, this message translates to:
  /// **'Repost queued for retry'**
  String get post_repost_queued;

  /// No description provided for @post_repost_media_failed.
  ///
  /// In en, this message translates to:
  /// **'Could not prepare repost media'**
  String get post_repost_media_failed;

  /// No description provided for @post_repost_could_not.
  ///
  /// In en, this message translates to:
  /// **'Could not prepare repost'**
  String get post_repost_could_not;

  /// No description provided for @post_no_longer_available.
  ///
  /// In en, this message translates to:
  /// **'Post is no longer available'**
  String get post_no_longer_available;

  /// No description provided for @post_repost_not_allowed.
  ///
  /// In en, this message translates to:
  /// **'This post cannot be reposted'**
  String get post_repost_not_allowed;

  /// No description provided for @identity_generate_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to generate identity'**
  String get identity_generate_failed;

  /// No description provided for @identity_save_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save identity'**
  String get identity_save_failed;

  /// No description provided for @qr_no_identity_detail.
  ///
  /// In en, this message translates to:
  /// **'No identity found. Please create one first.'**
  String get qr_no_identity_detail;

  /// No description provided for @qr_sign_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to sign QR code. Please try again.'**
  String get qr_sign_failed;

  /// No description provided for @qr_unexpected_error.
  ///
  /// In en, this message translates to:
  /// **'An unexpected error occurred. Please try again.'**
  String get qr_unexpected_error;

  /// No description provided for @qr_invalid_title.
  ///
  /// In en, this message translates to:
  /// **'Invalid QR Code'**
  String get qr_invalid_title;

  /// No description provided for @qr_invalid_body.
  ///
  /// In en, this message translates to:
  /// **'This doesn\'t look like a valid contact QR code.'**
  String get qr_invalid_body;

  /// No description provided for @qr_incomplete_title.
  ///
  /// In en, this message translates to:
  /// **'Incomplete QR Code'**
  String get qr_incomplete_title;

  /// No description provided for @qr_incomplete_body.
  ///
  /// In en, this message translates to:
  /// **'This QR code is missing required information.'**
  String get qr_incomplete_body;

  /// No description provided for @qr_invalid_signature_title.
  ///
  /// In en, this message translates to:
  /// **'Invalid Signature'**
  String get qr_invalid_signature_title;

  /// No description provided for @qr_invalid_signature_body.
  ///
  /// In en, this message translates to:
  /// **'This QR code could not be verified.'**
  String get qr_invalid_signature_body;

  /// No description provided for @qr_expired_title.
  ///
  /// In en, this message translates to:
  /// **'Expired QR Code'**
  String get qr_expired_title;

  /// No description provided for @qr_expired_body.
  ///
  /// In en, this message translates to:
  /// **'This QR code has expired. Ask your friend for a new one.'**
  String get qr_expired_body;

  /// No description provided for @qr_self_title.
  ///
  /// In en, this message translates to:
  /// **'That\'s You!'**
  String get qr_self_title;

  /// No description provided for @qr_self_body.
  ///
  /// In en, this message translates to:
  /// **'You can\'t add yourself as a contact.'**
  String get qr_self_body;

  /// No description provided for @qr_add_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to add contact. Please try again.'**
  String get qr_add_failed;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
