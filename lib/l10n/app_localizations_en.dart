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
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count attachments',
      one: '1 attachment',
      zero: 'No attachments',
    );
    return '$_temp0';
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

  @override
  String get load_retry_hint => 'Check your connection and try again.';

  @override
  String get upload_leave_title => 'Leave conversation?';

  @override
  String get upload_leave_body =>
      'An upload is in progress. Leaving may interrupt it. Are you sure?';

  @override
  String get upload_leave_stay => 'Stay';

  @override
  String get upload_leave_confirm => 'Leave';

  @override
  String get upload_cancelled => 'Upload cancelled.';

  @override
  String get media_too_large_title => 'Media Too Large';

  @override
  String media_too_large_prompt(String totalSize, String limitSize) {
    return 'The attached media is $totalSize and exceeds the $limitSize limit. Would you like to compress and send, or cancel?';
  }

  @override
  String get media_compress => 'Compress';

  @override
  String get media_too_large_after_compress =>
      'The media is too large even after compression.';

  @override
  String get media_gif_too_large =>
      'GIF files larger than 25 MB cannot be added.';

  @override
  String get media_unavailable => 'Media unavailable';

  @override
  String get media_retry_unavailable => 'Retry unavailable media';

  @override
  String get edit_save_failed => 'Failed to save edit.';

  @override
  String get intro_pass => 'Pass';

  @override
  String get intro_accept => 'Accept';

  @override
  String get intro_accepting => 'Accepting...';

  @override
  String get failed_message_retry_semantics => 'Retry failed message';

  @override
  String get failed_media_retry_semantics => 'Retry failed media message';

  @override
  String get failed_media_delete_semantics => 'Delete failed media message';

  @override
  String message_status_semantics(String status) {
    return 'Message status: $status';
  }

  @override
  String get message_status_delivered => 'delivered';

  @override
  String get message_status_failed => 'failed';

  @override
  String get message_status_sending => 'sending';

  @override
  String get message_status_sent => 'sent';

  @override
  String get message_status_pending_inbox => 'pending delivery via inbox';

  @override
  String get share_send_failed => 'Could not share to the selected targets.';

  @override
  String get group_info_title => 'Group Info';

  @override
  String get group_edit_details => 'Edit Details';

  @override
  String group_member_count(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members',
      one: '1 member',
    );
    return '$_temp0';
  }

  @override
  String get group_security_title => 'Security';

  @override
  String get group_security_key_change_visible => 'Key change visible';

  @override
  String get group_security_verification_warning => 'Verification warning';

  @override
  String group_security_identity_warning_detail(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count identities have changed. Review safety numbers below.',
      one: '1 identity has changed. Review safety numbers below.',
    );
    return '$_temp0';
  }

  @override
  String get group_dissolved => 'Group dissolved';

  @override
  String get group_dissolved_read_only_desc =>
      'This conversation is now read-only. Previous messages stay available for reference.';

  @override
  String get group_mute_notifications => 'Mute Notifications';

  @override
  String get group_mute_on_desc =>
      'New messages still arrive, but this group stays quiet.';

  @override
  String get group_mute_off_desc =>
      'Get notified when new messages arrive in this group.';

  @override
  String get group_members_title => 'Members';

  @override
  String get group_add_member => 'Add Member';

  @override
  String get group_leave => 'Leave Group';

  @override
  String get group_dissolve => 'Dissolve Group';

  @override
  String get group_delete_from_device => 'Delete from this device';

  @override
  String get group_delete_local_desc =>
      'Keep this dissolved history as long as you want, or remove it from this device only. This will not affect anyone else.';

  @override
  String get group_delete_locally => 'Delete Group Locally';

  @override
  String get group_no_messages => 'No messages yet';

  @override
  String get group_empty_dissolved_desc =>
      'This group has been dissolved. New messages are disabled.';

  @override
  String get group_empty_start => 'Send a message to start the conversation';

  @override
  String get group_empty_waiting => 'Waiting for messages';

  @override
  String get group_recovery_banner =>
      'Catching up missed messages. New messages will still appear here.';

  @override
  String get group_read_only_dissolved =>
      'This group has been dissolved. History stays available, but new messages are disabled.';

  @override
  String get group_read_only_admin_only =>
      'Only admins can send messages in this group';

  @override
  String get group_removed_snackbar => 'You were removed from this group.';

  @override
  String get group_dissolved_snackbar => 'This group has been dissolved';

  @override
  String get group_info_mute_update_failed => 'Failed to update mute';

  @override
  String get group_info_dissolve_title => 'Dissolve this group for everyone?';

  @override
  String get group_info_dissolve_body =>
      'This ends the group for all members. History stays visible, but no one can send new messages after it is dissolved.';

  @override
  String get group_info_dissolve_action => 'Dissolve';

  @override
  String get group_info_dissolved_recovery =>
      'Group dissolved. Some members may need recovery to see it.';

  @override
  String get group_info_already_dissolved => 'Group already dissolved';

  @override
  String get group_info_admins_only_dissolve =>
      'Only admins can dissolve groups';

  @override
  String get group_info_not_found => 'Group no longer exists';

  @override
  String get group_info_dissolve_failed => 'Failed to dissolve group';

  @override
  String get group_info_delete_local_title =>
      'Delete this dissolved group from this device?';

  @override
  String get group_info_delete_local_body =>
      'This removes the dissolved history from this device only. It will not affect anyone else or send a new leave event.';

  @override
  String get group_info_delete_local_action => 'Delete Locally';

  @override
  String group_info_remove_member_title(String username) {
    return 'Remove $username from the group?';
  }

  @override
  String get group_info_remove_member_body =>
      'They will stop receiving new messages from this group.';

  @override
  String get group_info_remove_action => 'Remove';

  @override
  String get group_info_member_fallback => 'member';

  @override
  String group_info_make_admin_title(String username) {
    return 'Make $username an admin?';
  }

  @override
  String group_info_remove_admin_title(String username) {
    return 'Remove admin access from $username?';
  }

  @override
  String get group_info_make_admin_body =>
      'They will be able to add, remove, and manage members.';

  @override
  String get group_info_remove_admin_body =>
      'They will lose admin-only actions after the change syncs.';

  @override
  String get group_info_make_admin_action => 'Make Admin';

  @override
  String get group_info_remove_admin_action => 'Remove Admin';

  @override
  String group_info_admin_added(String username) {
    return '$username is now an admin';
  }

  @override
  String group_info_admin_removed(String username) {
    return '$username is no longer an admin';
  }

  @override
  String get group_info_member_role_update_failed =>
      'Failed to update member role';

  @override
  String get group_info_details_updated => 'Group details updated';

  @override
  String get group_info_details_update_failed =>
      'Failed to update group details';

  @override
  String get group_info_invite_resend_failed => 'Failed to resend invite';

  @override
  String group_info_invite_sent(String username) {
    return 'Invite sent to $username';
  }

  @override
  String group_info_invite_queued(String username) {
    return 'Invite is in $username\'s inbox';
  }

  @override
  String get group_info_invite_needs_resend =>
      'Invite still needs to be resent';

  @override
  String group_info_invite_joined(String username) {
    return '$username already joined';
  }

  @override
  String get group_info_invite_unknown => 'Invite status unknown';

  @override
  String get group_edit_photo_pick_failed => 'Failed to pick group photo';

  @override
  String get group_edit_details_title => 'Edit Group Details';

  @override
  String get group_edit_change_photo => 'Change Photo';

  @override
  String get group_edit_add_photo => 'Add Photo';

  @override
  String get group_edit_remove_photo => 'Remove Photo';

  @override
  String get group_edit_name => 'Group Name';

  @override
  String get group_edit_description => 'Description';

  @override
  String get btn_save => 'Save';

  @override
  String get group_member_sending => 'Sending...';

  @override
  String get group_member_resend => 'Resend';

  @override
  String get group_member_manage_role => 'Manage role';

  @override
  String get group_role_admin => 'admin';

  @override
  String get group_role_writer => 'writer';

  @override
  String get group_role_reader => 'reader';

  @override
  String get group_identity_changed => 'Identity changed';

  @override
  String get group_current_safety => 'Current safety';

  @override
  String get group_saved_safety => 'Saved safety';

  @override
  String get group_card_no_messages => 'No messages yet';

  @override
  String get group_security_encrypted => 'End-to-end encrypted';

  @override
  String get group_security_pending => 'Encryption pending';

  @override
  String get group_security_no_key => 'No group key on this device';

  @override
  String group_security_key_changed(int keyEpoch) {
    return 'Group key changed to epoch $keyEpoch';
  }

  @override
  String group_security_current_key_epoch(int keyEpoch) {
    return 'Current key epoch $keyEpoch';
  }

  @override
  String get group_security_no_members => 'No members to verify';

  @override
  String group_security_all_members_verified(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'All $count members verified',
      one: 'All 1 member verified',
    );
    return '$_temp0';
  }

  @override
  String group_security_members_verified(int verifiedCount, int memberCount) {
    return '$verifiedCount of $memberCount members verified';
  }

  @override
  String group_security_members_need_review(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members need verification review',
      one: '1 member needs verification review',
    );
    return '$_temp0';
  }

  @override
  String group_security_members_unverified(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members not verified from saved contacts',
      one: '1 member not verified from saved contacts',
    );
    return '$_temp0';
  }

  @override
  String get group_security_no_warnings => 'No verification warnings';

  @override
  String group_security_compact_encrypted_epoch(int keyEpoch) {
    return 'Encrypted - key epoch $keyEpoch';
  }

  @override
  String get invite_status_sent => 'Invite sent';

  @override
  String get invite_status_queued => 'In their inbox';

  @override
  String get invite_status_needs_resend => 'Resend needed';

  @override
  String get invite_status_cannot_send => 'Cannot send';

  @override
  String get invite_status_joined => 'Joined';

  @override
  String get invite_status_unknown => 'Invite unknown';

  @override
  String get invite_cannot_send_missing_secure_key_detail =>
      'We don\'t have the secure info needed to invite this friend. Ask them to open or reinstall the app, then try again.';

  @override
  String get invite_cannot_send_group_key_missing_detail =>
      'This group is missing the secure invite key. Reopen the app and try again.';

  @override
  String get invite_cannot_send_invalid_payload_detail =>
      'This invite could not be prepared. Reopen the app and try again.';

  @override
  String get invite_cannot_send_generic_detail =>
      'We could not prepare a secure invite for this friend. They may need to open or reinstall the app before you can invite them.';

  @override
  String get invite_cannot_send_missing_secure_key_snackbar =>
      'Cannot send: we don\'t have the secure info needed to invite this friend.';

  @override
  String get invite_cannot_send_group_key_missing_snackbar =>
      'Cannot send: this group is missing the secure invite key.';

  @override
  String get invite_cannot_send_invalid_payload_snackbar =>
      'Cannot send: this invite could not be prepared.';

  @override
  String get invite_cannot_send_generic_snackbar =>
      'Cannot send: we could not prepare a secure invite for this friend.';

  @override
  String group_backlog_mixed_list_summary(int days) {
    return 'Older backlog expired after $days days';
  }

  @override
  String group_backlog_mixed_banner(int days) {
    return 'Older missed messages expired after $days days. Recent messages were recovered.';
  }

  @override
  String get group_backlog_mixed_empty_title => 'Recent messages recovered';

  @override
  String group_backlog_mixed_empty_subtitle(int days) {
    return 'Older missed messages expired after $days days while you were away.';
  }

  @override
  String group_backlog_expired_list_summary(int days) {
    return 'Missed backlog expired after $days days';
  }

  @override
  String group_backlog_expired_banner(int days) {
    return 'Missed messages older than $days days expired while you were away.';
  }

  @override
  String get group_backlog_expired_empty_title => 'Older backlog expired';

  @override
  String group_backlog_expired_empty_subtitle(int days) {
    return 'Missed messages older than $days days expired while you were away.';
  }

  @override
  String get group_history_repair_active_banner =>
      'Some missed messages are being repaired from trusted group members.';

  @override
  String get group_history_repair_active_empty_title =>
      'Repairing missed messages';

  @override
  String get group_history_repair_active_empty_subtitle =>
      'Some missed messages are being verified before they appear here.';

  @override
  String get group_history_repair_failed_banner =>
      'Some missed messages could not be repaired from trusted group members.';

  @override
  String get group_history_repair_failed_empty_title => 'History repair needed';

  @override
  String get group_history_repair_failed_empty_subtitle =>
      'Some missed messages could not be verified from trusted members.';

  @override
  String get group_history_repair_done_banner =>
      'Missed messages were repaired and verified.';

  @override
  String get group_history_repair_done_empty_title => 'Messages repaired';

  @override
  String get group_history_repair_done_empty_subtitle =>
      'Missed messages were verified and restored.';

  @override
  String get group_info_leave_failed => 'Failed to leave group';

  @override
  String get group_info_notifications_muted =>
      'Notifications muted for this group';

  @override
  String get group_info_notifications_restored =>
      'Notifications restored for this group';

  @override
  String get group_info_delete_local_failed => 'Failed to delete group locally';

  @override
  String get group_info_publish_member_removal_failed =>
      'Failed to publish member removal';

  @override
  String get group_info_rotate_key_failed =>
      'Failed to rotate group key after removal';

  @override
  String get group_info_remove_member_failed => 'Failed to remove member';

  @override
  String get group_info_no_identity => 'No identity found';

  @override
  String get group_info_member_not_found => 'Member not found';

  @override
  String get group_info_upload_photo_failed => 'Failed to upload group photo';

  @override
  String get group_info_sign_metadata_failed =>
      'Failed to sign group metadata update';

  @override
  String get groups_title => 'Groups';

  @override
  String get groups_empty_title => 'No groups yet';

  @override
  String get groups_empty_desc => 'Create a group to get started';

  @override
  String get groups_pending_invites => 'Pending Invites';

  @override
  String get groups_joined => 'Joined Groups';

  @override
  String get groups_unknown_sender => 'Unknown';

  @override
  String get groups_no_joined =>
      'No joined groups yet. Accept an invite to add it here.';

  @override
  String get group_type_discussion => 'Discussion';

  @override
  String get group_type_announce => 'Announce';

  @override
  String get group_type_qa => 'Q&A';

  @override
  String get group_dissolved_badge => 'Dissolved';

  @override
  String get pending_invite_expired => 'Expired';

  @override
  String get pending_invite_accept => 'Accept';

  @override
  String get pending_invite_decline => 'Decline';

  @override
  String get pending_invite_dismiss => 'Dismiss';

  @override
  String pending_invite_invited_by(String username) {
    return 'Invited by $username';
  }

  @override
  String pending_invite_expires(String date) {
    return 'Expires $date';
  }

  @override
  String get group_no_contacts_available => 'No contacts available';

  @override
  String get settings_intro_debug_delete_row => 'Delete Row';

  @override
  String get settings_intro_debug_delete_pair => 'Delete Pair';

  @override
  String get settings_intro_debug_deleted_row =>
      'Deleted local introduction row';

  @override
  String settings_intro_debug_deleted_pair(String pairLabel) {
    return 'Deleted local pair $pairLabel';
  }

  @override
  String get settings_intro_debug_heading => 'DEBUG INTRODUCTIONS';

  @override
  String get settings_intro_debug_description =>
      'Local sent intro rows on this device. Deleting a pair makes it selectable again in the picker.';

  @override
  String get settings_intro_debug_empty =>
      'No local introduction rows for the current user.';

  @override
  String settings_intro_debug_status_line(
    String status,
    String recipientStatus,
    String introducedStatus,
  ) {
    return 'status=$status  recipient=$recipientStatus  introduced=$introducedStatus';
  }

  @override
  String settings_intro_debug_meta_line(String id, String createdAt) {
    return 'id=$id  created=$createdAt';
  }

  @override
  String get group_start_chat => 'Start group chat';

  @override
  String get group_reactions_title => 'Reactions';

  @override
  String group_add_members_count(int count) {
    return 'Add Members ($count)';
  }

  @override
  String get group_loading_contacts => 'Loading contacts...';

  @override
  String get group_send_invites => 'Send Invites';

  @override
  String get group_send_permission_lost =>
      'You no longer have permission to send messages in this group.';

  @override
  String get group_unavailable_snackbar => 'This group is no longer available.';

  @override
  String get media_retry_unavailable_now => 'Retry unavailable right now.';

  @override
  String get media_unavailable_now => 'Media unavailable right now.';

  @override
  String get media_still_unavailable => 'Media is still unavailable.';

  @override
  String get failed_media_retry_failed => 'Could not retry media message.';

  @override
  String get failed_media_delete_unavailable => 'Delete unavailable right now.';

  @override
  String get picker_media_library => 'Media Library';

  @override
  String get picker_record_video => 'Record Video';

  @override
  String get perm_microphone_record =>
      'Microphone permission is required to record voice messages.';

  @override
  String get group_read_only_not_active =>
      'You can read this group\'s history, but you are not an active member.';

  @override
  String get group_read_only_waiting_key =>
      'Waiting for the current group key before you can send.';

  @override
  String get group_read_only_waiting_identity =>
      'Waiting for your identity before you can send.';

  @override
  String get group_media_unsupported =>
      'This media type is not supported in groups.';

  @override
  String get upload_progress_title => 'Uploading media';

  @override
  String get upload_progress_keep_open =>
      'Keep the app open until the upload completes';

  @override
  String get conversation_blocked_contact => 'You blocked this contact.';

  @override
  String get conversation_unblock => 'Unblock';

  @override
  String get conversation_empty_first_letter =>
      'Write the first letter\nto start your conversation';

  @override
  String get media_video_load_failed => 'Could not load video';

  @override
  String get conversation_introduce_to_circle => 'Introduce to your circle';

  @override
  String conversation_block_contact(String username) {
    return 'Block $username';
  }

  @override
  String conversation_unblock_contact(String username) {
    return 'Unblock $username';
  }

  @override
  String get conversation_delete_chat_action => 'Delete chat';

  @override
  String get post_pass_along_title => 'Pass along';

  @override
  String get post_pass_along_desc =>
      'Choose who should receive this one-hop pass.';

  @override
  String get post_pass_along_no_eligible =>
      'No eligible friends available right now.';

  @override
  String comments_count(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count comments',
      one: '1 comment',
      zero: 'No comments',
    );
    return '$_temp0';
  }

  @override
  String get comments_empty => 'No comments yet';

  @override
  String get edit_pinned_post_title => 'Edit pinned post';

  @override
  String post_passed_along_by(String username) {
    return '$username passed this along';
  }

  @override
  String get home_empty_circle_title => 'Your circle is waiting to be filled';

  @override
  String get home_empty_circle_desc =>
      'Scan a friend\'s code or share yours to connect';

  @override
  String get home_scan_friend_title => 'Scan a friend\'s code';

  @override
  String get home_scan_friend_desc => 'Add someone to your circle';

  @override
  String get contact_request_message => 'wants to connect with you';

  @override
  String get contact_request_decline => 'Decline';

  @override
  String get share_caption => 'Caption';

  @override
  String share_title_count(int count) {
    return 'Share with ($count)';
  }

  @override
  String get share_title_empty => 'Share with...';

  @override
  String get share_no_targets => 'No contacts or groups yet';

  @override
  String get share_no_matches => 'No matches found';

  @override
  String get share_contacts_section => 'Contacts';

  @override
  String get share_groups_section => 'Groups';

  @override
  String get share_group_type_announcement => 'Announcement';

  @override
  String get share_group_type_chat => 'Chat';

  @override
  String get share_sending => 'Sending...';

  @override
  String get share_send => 'Send';

  @override
  String share_target_count(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count targets',
      one: '1 target',
    );
    return '$_temp0';
  }

  @override
  String share_summary_sent(String targetCount) {
    return 'Sent to $targetCount';
  }

  @override
  String share_summary_queued(String targetCount) {
    return 'saved $targetCount for retry';
  }

  @override
  String share_summary_failed(String targetCount) {
    return 'failed for $targetCount';
  }

  @override
  String get share_summary_nothing => 'Nothing was shared.';

  @override
  String share_summary_skipped_gifs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Skipped $count oversized GIFs.',
      one: 'Skipped 1 oversized GIF.',
    );
    return '$_temp0';
  }

  @override
  String get time_just_now => 'just now';

  @override
  String time_min_ago(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count min ago',
      one: '1 min ago',
    );
    return '$_temp0';
  }

  @override
  String time_hour_ago(int count) {
    return '${count}h ago';
  }

  @override
  String time_day_ago(int count) {
    return '${count}d ago';
  }

  @override
  String time_week_ago(int count) {
    return '${count}w ago';
  }

  @override
  String get post_expired => 'Expired';

  @override
  String post_expires_days_hours(int days, int hours) {
    return 'Expires in ${days}d ${hours}h';
  }

  @override
  String post_expires_days(int days) {
    return 'Expires in ${days}d';
  }

  @override
  String post_expires_hours(int hours) {
    return 'Expires in ${hours}h';
  }

  @override
  String post_expires_minutes(int minutes) {
    return 'Expires in ${minutes}m';
  }

  @override
  String get post_expires_soon => 'Expires soon';

  @override
  String get post_photo_upload_failed => 'Photo upload failed';

  @override
  String get post_photo_pending_upload => 'Photo pending upload';

  @override
  String get post_photos_pending_upload => 'Photos pending upload';

  @override
  String get post_video_upload_failed => 'Video upload failed';

  @override
  String get post_video_pending_upload => 'Video pending upload';

  @override
  String get post_voice_upload_failed => 'Voice upload failed';

  @override
  String get post_voice_pending_upload => 'Voice note pending upload';

  @override
  String get post_media_upload_failed => 'Media upload failed';

  @override
  String get post_media_pending_upload => 'Media pending upload';

  @override
  String get post_media_upload_failed_desc =>
      'This post stayed local because the media upload did not finish.';

  @override
  String get post_media_pending_upload_desc =>
      'Recipients will receive this after the upload finishes.';

  @override
  String get post_send_pass => 'Send pass';

  @override
  String get btn_saving => 'Saving...';

  @override
  String get intro_from => 'From';

  @override
  String get intro_empty => 'No introductions yet';

  @override
  String get intro_tab_desc =>
      'These are people your friends know well. Once you both accept, you can start chatting.';

  @override
  String intro_banner_title(String username) {
    return 'Help $username meet your circle';
  }

  @override
  String get intro_banner_desc => 'Introduce them to friends who might click';

  @override
  String get intro_make_introductions => 'Make introductions';

  @override
  String get intro_maybe_later => 'Maybe later';

  @override
  String get introduced_by_label => 'Introduced by';

  @override
  String get intro_unavailable => 'Unavailable';

  @override
  String intro_waiting_for(String username) {
    return 'Waiting for $username';
  }

  @override
  String get intro_waiting_for_them => 'Waiting for them';

  @override
  String intro_sent_count(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count introductions sent',
      one: '1 introduction sent',
    );
    return '$_temp0';
  }

  @override
  String get intro_back_to_conversation => 'Back to conversation';

  @override
  String get identity_tagline => 'Your identity, your control';

  @override
  String get startup_failed_title => 'Failed to initialize';

  @override
  String get identity_restore_action => 'Restore identity';

  @override
  String get settings_peer_id_title => 'PEER ID';

  @override
  String get settings_peer_id_desc => 'Your unique identifier on the network';

  @override
  String intro_and_more(String names, int count) {
    return '$names and $count more';
  }

  @override
  String get orbit_block_action => 'Block';

  @override
  String get orbit_unblock_action => 'Unblock';

  @override
  String get orbit_delete_action => 'Delete';

  @override
  String get orbit_archive_action => 'Archive';

  @override
  String get orbit_unarchive_action => 'Unarchive';

  @override
  String get orbit_archived_empty_title => 'No archived friends yet';

  @override
  String get orbit_archived_empty_desc =>
      'Swipe left on a friend to archive them.';

  @override
  String get orbit_inner_circle_badge => 'Inner Circle';

  @override
  String get orbit_inner_circle_title => 'YOUR INNER CIRCLE';

  @override
  String orbit_pending_items(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items pending',
      one: '1 item pending',
    );
    return '$_temp0';
  }

  @override
  String get orbit_pending_group_invites => 'Pending Group Invites';

  @override
  String get orbit_pending_group_intro_desc =>
      'Review pending group invites here, then check introductions below. Once you accept, the group appears in Orbit and catches up from offline inbox.';

  @override
  String orbit_no_friends_matching(String query) {
    return 'No friends matching \"$query\"';
  }

  @override
  String get feed_blocked => 'Blocked';

  @override
  String feed_introduced_by(String username) {
    return 'Introduced by $username';
  }

  @override
  String get feed_previously_seen => 'PREVIOUSLY SEEN';

  @override
  String get feed_replying_to => 'Replying to';

  @override
  String get feed_view_earlier_messages => 'View earlier messages';

  @override
  String feed_ready_for_user(String username) {
    return 'Your feed is ready, @$username. New connections will appear here.';
  }

  @override
  String get feed_loading => 'Loading Feed...';

  @override
  String get feed_syncing_threads => 'Your recent threads are still syncing.';

  @override
  String get qr_added_to_circle => 'Added to your circle!';

  @override
  String get btn_ok => 'OK';

  @override
  String get qr_already_in_circle => 'Already in your circle!';

  @override
  String get qr_contact_added_previously => 'This contact was added previously';

  @override
  String get btn_got_it => 'Got it';

  @override
  String orbit_intro_banner_mixed(int inviteCount, int introCount) {
    String _temp0 = intl.Intl.pluralLogic(
      inviteCount,
      locale: localeName,
      other: '$inviteCount group invites',
      one: '1 group invite',
    );
    String _temp1 = intl.Intl.pluralLogic(
      introCount,
      locale: localeName,
      other: '$introCount introductions',
      one: '1 introduction',
    );
    return '$_temp0 and $_temp1 waiting';
  }

  @override
  String orbit_intro_banner_invites(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Review group invites and join from Intros',
      one: 'Review group invite and join from Intros',
    );
    return '$_temp0';
  }

  @override
  String get orbit_intro_banner_intros =>
      'Review and accept introductions to start chatting';

  @override
  String group_member_invited_count(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members invited',
      one: 'Member invited',
    );
    return '$_temp0';
  }

  @override
  String group_member_added_count(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members added',
      one: '1 member added',
    );
    return '$_temp0';
  }

  @override
  String get group_invite_missing_key_issue =>
      'invites were not sent because the group is missing its latest key';

  @override
  String group_invite_issues(String details) {
    return 'invite issues: $details';
  }

  @override
  String get group_members_publish_failed_issue =>
      'the add-members event could not be published';

  @override
  String group_member_added_with_warnings(String prefix, String issues) {
    return '$prefix, but $issues.';
  }

  @override
  String group_invite_joined(String name) {
    return 'Joined $name';
  }

  @override
  String get group_invite_no_longer_available => 'Invite no longer available';

  @override
  String get group_invite_expired => 'Invite expired';

  @override
  String get group_invite_revoked => 'Invite was revoked';

  @override
  String get group_invite_already_used => 'Invite already used';

  @override
  String get group_invite_wrong_identity => 'Invite is for another identity';

  @override
  String get group_invite_needs_key => 'Invite needs fresh key material';

  @override
  String get group_invite_invalid => 'Invite is no longer valid';

  @override
  String get group_invite_duplicate_group => 'Group already added';

  @override
  String group_invite_joined_recovery(String name) {
    return 'Joined $name, but recovery is still catching up';
  }

  @override
  String get group_invite_accepted_recovery =>
      'Invite accepted, but recovery is still catching up';

  @override
  String get group_invite_accept_failed => 'Failed to accept invite';

  @override
  String get group_invite_declined => 'Invite declined';

  @override
  String get group_invite_decline_failed => 'Failed to decline invite';

  @override
  String get post_pin_retrying => 'Pin update will continue retrying';

  @override
  String get post_pin_queued => 'Pin update queued for retry';

  @override
  String get post_pin_failed => 'Pin update failed';

  @override
  String get post_pin_could_not => 'Could not pin post';

  @override
  String get post_pinned_update_retrying =>
      'Pinned post update will continue retrying';

  @override
  String get post_pinned_update_queued => 'Pinned post update queued for retry';

  @override
  String get post_pinned_update_failed => 'Pinned post update failed';

  @override
  String get post_pinned_update_could_not => 'Could not update pinned post';

  @override
  String get post_pin_removal_retrying => 'Pin removal will continue retrying';

  @override
  String get post_pin_removal_queued => 'Pin removal queued for retry';

  @override
  String get post_pin_removal_failed => 'Pin removal failed';

  @override
  String get post_pin_remove_could_not => 'Could not remove pin';

  @override
  String get post_repost_retrying => 'Repost will continue retrying';

  @override
  String get post_repost_queued => 'Repost queued for retry';

  @override
  String get post_repost_media_failed => 'Could not prepare repost media';

  @override
  String get post_repost_could_not => 'Could not prepare repost';

  @override
  String get post_no_longer_available => 'Post is no longer available';

  @override
  String get post_repost_not_allowed => 'This post cannot be reposted';

  @override
  String get identity_generate_failed => 'Failed to generate identity';

  @override
  String get identity_save_failed => 'Failed to save identity';

  @override
  String get qr_no_identity_detail =>
      'No identity found. Please create one first.';

  @override
  String get qr_sign_failed => 'Failed to sign QR code. Please try again.';

  @override
  String get qr_unexpected_error =>
      'An unexpected error occurred. Please try again.';

  @override
  String get qr_invalid_title => 'Invalid QR Code';

  @override
  String get qr_invalid_body =>
      'This doesn\'t look like a valid contact QR code.';

  @override
  String get qr_incomplete_title => 'Incomplete QR Code';

  @override
  String get qr_incomplete_body =>
      'This QR code is missing required information.';

  @override
  String get qr_invalid_signature_title => 'Invalid Signature';

  @override
  String get qr_invalid_signature_body => 'This QR code could not be verified.';

  @override
  String get qr_expired_title => 'Expired QR Code';

  @override
  String get qr_expired_body =>
      'This QR code has expired. Ask your friend for a new one.';

  @override
  String get qr_self_title => 'That\'s You!';

  @override
  String get qr_self_body => 'You can\'t add yourself as a contact.';

  @override
  String get qr_add_failed => 'Failed to add contact. Please try again.';
}
