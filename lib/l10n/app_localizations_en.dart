// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get nav_feed => 'Feed';

  @override
  String get nav_remember => 'Remember';

  @override
  String get nav_posts => 'Posts';

  @override
  String get nav_orbit => 'Orbit';

  @override
  String get onboarding_new_here => 'I\'m new here';

  @override
  String get onboarding_new_desc => 'Generate a fresh identity';

  @override
  String get onboarding_load_key => 'Load my key';

  @override
  String get onboarding_load_desc => 'Restore from recovery phrase';

  @override
  String get onboarding_privacy_1 => 'Only you can read your messages';

  @override
  String get onboarding_privacy_2 =>
      'Everything stays on your phone. Nobody is watching.';

  @override
  String get progress_securing => 'Securing your identity';

  @override
  String get progress_securing_desc =>
      'Saving your identity to secure storage.';

  @override
  String get progress_creating => 'Creating your secure identity';

  @override
  String get progress_creating_desc =>
      'Generating encryption keys on this device. This only happens once.';

  @override
  String get progress_keep_open => 'Please keep the app open.';

  @override
  String get progress_almost => 'Almost there.';

  @override
  String get progress_step_keys => 'Generate keys';

  @override
  String get progress_step_save => 'Save to device';

  @override
  String get mnemonic_title => 'Recovery phrase';

  @override
  String get mnemonic_error_12 => 'Please enter exactly 12 words';

  @override
  String get mnemonic_error_invalid => 'Invalid recovery phrase';

  @override
  String get mnemonic_error_generic => 'An error occurred. Please try again.';

  @override
  String get mnemonic_hint =>
      'word1 word2 word3 word4\\nword5 word6 word7 word8\\nword9 word10 word11 word12';

  @override
  String get qr_show_desc => 'Show this to someone you want in your circle...';

  @override
  String get qr_copy_hint => 'Long-press QR to copy data';

  @override
  String get qr_copied => 'QR data copied to clipboard!';

  @override
  String get qr_scan_title => 'Scan QR Code';

  @override
  String get qr_scan_instruction => 'Point your camera at a friend\'s QR code';

  @override
  String get qr_scan_subtitle => 'They\'ll be added to your circle';

  @override
  String get qr_my_code => 'My QR Code';

  @override
  String get qr_no_identity => 'No Identity';

  @override
  String get qr_error => 'Error';

  @override
  String get qr_try_again => 'Try Again';

  @override
  String get qr_paste_title => 'Paste QR Data';

  @override
  String get qr_paste_hint => 'Paste the JSON QR payload from another device:';

  @override
  String get qr_paste_button => 'Paste from Clipboard';

  @override
  String get posts_title => 'Posts';

  @override
  String posts_header_subtitle(String username) {
    return 'What\'s happening around your friends today, $username?';
  }

  @override
  String get posts_compose_button => 'Share something with your friends';

  @override
  String get posts_empty_title => 'You\'re all caught up';

  @override
  String get posts_empty_desc =>
      'Your direct-friend posts will appear here after they land or replay.';

  @override
  String get posts_empty_button => 'Create your first post';

  @override
  String get posts_caught_up => 'You\'re all caught up';

  @override
  String get posts_time_now => 'Right now';

  @override
  String get posts_time_earlier => 'Earlier today';

  @override
  String get posts_time_yesterday => 'Yesterday';

  @override
  String get compose_title => 'Create Post';

  @override
  String get compose_hint => 'What do you want to share?';

  @override
  String get compose_audience_all => 'All Friends';

  @override
  String get compose_audience_nearby => 'People Nearby';

  @override
  String get compose_audience_pick => 'Pick People';

  @override
  String get compose_radius => 'Radius';

  @override
  String get compose_radius_500 => '500m';

  @override
  String get compose_radius_1k => '1km';

  @override
  String get compose_radius_2k => '2km';

  @override
  String get compose_media => 'Media';

  @override
  String get compose_media_adding => 'Adding...';

  @override
  String get compose_voice => 'Voice';

  @override
  String get compose_voice_stop => 'Stop';

  @override
  String get compose_voice_attached => 'Voice attached';

  @override
  String compose_attachments(int count) {
    return '$count attachments';
  }

  @override
  String get compose_pick_people => 'Pick People';

  @override
  String get compose_posting => 'Posting...';

  @override
  String get compose_post => 'Post';

  @override
  String get compose_manage => 'Manage';

  @override
  String get compose_pinned_1 => 'You already have 1 active pinned post';

  @override
  String compose_pinned_n(int count) {
    return 'You already have $count active pinned posts';
  }

  @override
  String get compose_nearby_off => 'People Nearby is off in Settings';

  @override
  String get compose_nearby_ready => 'People Nearby is ready';

  @override
  String get compose_nearby_refresh => 'Refresh nearby before posting';

  @override
  String get compose_nearby_allow => 'Allow location to use People Nearby';

  @override
  String get compose_nearby_perm_off => 'Location permission is off';

  @override
  String get compose_nearby_services => 'Turn on location services';

  @override
  String get compose_nearby_off_desc =>
      'Turn it on in Settings before posting to nearby friends.';

  @override
  String get compose_nearby_ready_desc =>
      'Your nearby snapshot is fresh enough to use for posting.';

  @override
  String get compose_nearby_refresh_desc =>
      'Refresh your nearby snapshot before using this audience.';

  @override
  String get compose_nearby_allow_desc =>
      'Refresh nearby to grant location permission for nearby posts.';

  @override
  String get compose_nearby_perm_desc =>
      'Open system settings to re-enable location access.';

  @override
  String get compose_nearby_services_desc =>
      'Enable location services, then refresh nearby again.';

  @override
  String get compose_open_settings => 'Open Settings';

  @override
  String get compose_refreshing => 'Refreshing...';

  @override
  String get compose_refresh_nearby => 'Refresh nearby';

  @override
  String get post_badge_friend => 'Friend';

  @override
  String get post_uploading => 'Uploading media...';

  @override
  String get post_sending => 'Sending...';

  @override
  String get post_partial => 'Partially sent';

  @override
  String get post_upload_failed => 'Upload failed';

  @override
  String get post_send_failed => 'Send failed';

  @override
  String get pinned_title => 'Pinned posts';

  @override
  String get pinned_count_1 => '1 pinned post';

  @override
  String pinned_count_n(int count) {
    return '$count pinned posts';
  }

  @override
  String pinned_see_all(int count) {
    return 'See all $count pinned posts';
  }

  @override
  String get pinned_dismiss => 'Dismiss';

  @override
  String pinned_message(String username) {
    return 'Message $username';
  }

  @override
  String get pinned_edit => 'Edit';

  @override
  String get pinned_remove => 'Remove';

  @override
  String get edit_pinned_hint => 'Update your post';

  @override
  String get orbit_close_friends => 'Close Friends';

  @override
  String get orbit_new_group => 'New Group';

  @override
  String get orbit_new_announce => 'New Announce';

  @override
  String get orbit_my_qr => 'My QR';

  @override
  String get orbit_scan => 'Scan';

  @override
  String get orbit_qr_share => 'Share to add friends';

  @override
  String get orbit_qr_scan_desc => 'Add a friend instantly';

  @override
  String get orbit_filter_all => 'All';

  @override
  String get orbit_filter_intros => 'Intros';

  @override
  String get orbit_filter_archived => 'Archived';

  @override
  String get orbit_search => 'Search friends...';

  @override
  String orbit_block_title(String username) {
    return 'Block $username?';
  }

  @override
  String get orbit_delete_chat => 'Delete chat?';

  @override
  String get orbit_leave_group => 'Leave & delete group?';

  @override
  String get conversation_hint => 'Write something...';

  @override
  String get conversation_voice_fail => 'Failed to send voice message.';

  @override
  String conversation_block(String username) {
    return 'Block $username?';
  }

  @override
  String get conversation_delete_chat => 'Delete chat?';

  @override
  String get conversation_reply => 'Reply...';

  @override
  String get conversation_context_reply => 'Reply';

  @override
  String get conversation_context_edit => 'Edit';

  @override
  String get conversation_context_copy => 'Copy';

  @override
  String get conversation_context_delete => 'Delete';

  @override
  String get conversation_context_copied => 'Message copied to clipboard';

  @override
  String get conversation_editing_message => 'Editing message';

  @override
  String get conversation_cancel_edit => 'Cancel';

  @override
  String get conversation_edited_indicator => '(edited)';

  @override
  String get conversation_delete_message_prompt =>
      'Who would you like to delete this message for?';

  @override
  String get conversation_delete_for_me => 'Delete for Me';

  @override
  String get conversation_delete_for_everyone => 'Delete for Everyone';

  @override
  String get conversation_delete_cancel => 'Cancel';

  @override
  String get conversation_message_deleted => 'This message was deleted';

  @override
  String get conversation_delete_failed =>
      'Couldn\'t finish deleting this message.';

  @override
  String get conversation_continue => 'Continue...';

  @override
  String get comment_hint => 'Write a comment...';

  @override
  String get group_name_optional => 'Group name (optional)';

  @override
  String get group_message_hint => 'Message';

  @override
  String get group_create_failed => 'Failed to create group';

  @override
  String get group_invite_failed => 'Failed to invite members';

  @override
  String group_create_member_limit_reached(int maxMembers, int overflowCount) {
    return 'Groups can have up to $maxMembers members including you. Reduce your selection by $overflowCount and try again.';
  }

  @override
  String group_invite_member_limit_reached(int maxMembers, int overflowCount) {
    return 'Groups can have up to $maxMembers members. Reduce your selection by $overflowCount and try again.';
  }

  @override
  String picker_introduce_to(String username) {
    return 'Introduce to $username';
  }

  @override
  String get picker_search => 'Search friends...';

  @override
  String get picker_no_friends => 'No friends available to introduce';

  @override
  String picker_no_results(String query) {
    return 'No friends matching \"$query\"';
  }

  @override
  String picker_introduce_count(int count) {
    return 'Introduce ($count)';
  }

  @override
  String get picker_introduce => 'Introduce';

  @override
  String picker_sending_progress(int completed, int total) {
    return 'Sending $completed of $total';
  }

  @override
  String get picker_search_contacts => 'Search contacts...';

  @override
  String get picker_search_all => 'Search contacts & groups';

  @override
  String get settings_title => 'Settings';

  @override
  String get settings_background => 'Background';

  @override
  String get settings_background_default => 'Default';

  @override
  String get settings_background_default_desc =>
      'The current ambient background.';

  @override
  String get settings_background_cosmic => 'Cosmic';

  @override
  String get settings_background_cosmic_desc => 'A deep starfield for Feed.';

  @override
  String get settings_background_cosmic_selected => 'Cosmic selected';

  @override
  String get settings_background_cosmic_mirrored => 'Mirrored cosmic';

  @override
  String get settings_background_cosmic_mirrored_desc =>
      'The cosmic starfield with mirrored color blooms.';

  @override
  String get settings_background_cosmic_mirrored_selected =>
      'Mirrored cosmic selected';

  @override
  String get settings_background_daylight_lagoon => 'Daylight Lagoon';

  @override
  String get settings_background_daylight_lagoon_desc =>
      'A bright lagoon sky with soft pastel blooms.';

  @override
  String get settings_background_daylight_lagoon_selected =>
      'Daylight Lagoon selected';

  @override
  String get settings_background_save_fail =>
      'Background choice could not be saved';

  @override
  String get settings_background_semantics => 'App background setting';

  @override
  String get settings_background_default_selected => 'Default selected';

  @override
  String get settings_video_quality => 'Video Quality';

  @override
  String get settings_compressed => 'Compressed';

  @override
  String get settings_original => 'Original';

  @override
  String get settings_original_desc =>
      'Full quality, larger file size. Metadata is always removed.';

  @override
  String get settings_compressed_desc =>
      'Smaller file size, faster sending. Metadata is always removed.';

  @override
  String get settings_photo_fail => 'Failed to upload profile picture';

  @override
  String get picker_take_photo => 'Take Photo';

  @override
  String get picker_gallery => 'Choose from Gallery';

  @override
  String get notif_new_intro => 'New Introduction';

  @override
  String get notif_new_connection => 'New Connection';

  @override
  String get startup_checking => 'Preparing your space...';

  @override
  String get startup_checking_desc => 'Checking identity and startup state';

  @override
  String get startup_feed => 'Opening Feed...';

  @override
  String get startup_feed_desc => 'Handing off to your conversations';

  @override
  String get startup_setup => 'Opening setup...';

  @override
  String get startup_setup_desc => 'Getting your first-time experience ready';

  @override
  String get startup_onboarding => 'Opening onboarding...';

  @override
  String get startup_onboarding_desc => 'Let\'s get your identity ready';

  @override
  String get btn_retry => 'Retry';

  @override
  String get btn_cancel => 'Cancel';

  @override
  String get btn_submit => 'Submit';

  @override
  String get error_add_contact => 'Failed to add contact. Please try again.';

  @override
  String get error_send_message => 'Message failed to send. Try again.';

  @override
  String error_update_photo(String error) {
    return 'Failed to update photo: $error';
  }

  @override
  String get error_update_username =>
      'Failed to update username. Please try again.';

  @override
  String error_generic(String error) {
    return 'Error: $error';
  }

  @override
  String get status_processing_video => 'Processing video...';

  @override
  String get perm_camera =>
      'This app needs camera access to scan QR codes and take photos';

  @override
  String get perm_photos =>
      'This app needs access to your photo library to share images';

  @override
  String get perm_microphone =>
      'This app needs microphone access to record voice messages';

  @override
  String get perm_location =>
      'This app needs location access to share nearby posts with your direct friends';

  @override
  String get perm_local_network =>
      'mknoon looks for your friends on the same WiFi to send messages directly to their phone. It\'s faster, more private, and we never collect your data.';

  @override
  String get perm_notifications =>
      'This app needs notification access to alert you of incoming messages';

  @override
  String connected_date(String date) {
    return 'Connected $date';
  }

  @override
  String get date_today => 'Today';

  @override
  String get date_yesterday => 'Yesterday';

  @override
  String get feed_collapse => 'Collapse';

  @override
  String get feed_tap_expand => 'Tap to expand';

  @override
  String get feed_you => 'You';

  @override
  String feed_you_replied(String time) {
    return 'You replied $time';
  }

  @override
  String get settings_photo_quality => 'Photo Quality';

  @override
  String get settings_share_nearby => 'Share People Nearby';

  @override
  String get settings_share_nearby_on => 'On';

  @override
  String get settings_share_nearby_off => 'Off';

  @override
  String get settings_share_nearby_desc =>
      'Shares only an approximate location with direct friends. No live maps, and never strangers.';

  @override
  String get settings_recovery_title => 'RECOVERY PHRASE';

  @override
  String get settings_recovery_warning =>
      'Never share this phrase with anyone. It grants full access to your account.';

  @override
  String get settings_recovery_tap => 'Tap to reveal';

  @override
  String get settings_recovery_copied => 'Copied!';

  @override
  String get settings_recovery_copy => 'Copy to clipboard';

  @override
  String get settings_recovery_hide => 'Hide';

  @override
  String get connected_title => 'Connected!';

  @override
  String get send_message => 'Send Message';

  @override
  String introduced_by(String username) {
    return 'Introduced by $username';
  }
}
