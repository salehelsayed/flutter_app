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
  String get onboarding_move_from_old_phone => 'Move from old phone';

  @override
  String get onboarding_move_desc =>
      'Bring your existing account to this device';

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
  String get account_migration_scan_title => 'Scan migration QR';

  @override
  String get account_migration_scan_instruction =>
      'Point your camera at the Move Account QR on your new phone';

  @override
  String get account_migration_scan_subtitle =>
      'Only Move Account QR codes are accepted here';

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
  String get account_migration_paste_title => 'Paste migration QR';

  @override
  String get account_migration_paste_hint =>
      'Paste the Move Account QR payload shown on your new phone:';

  @override
  String get account_migration_paste_button =>
      'Paste migration QR from Clipboard';

  @override
  String get account_migration_paste_payload_hint =>
      'kind: account_migration_pairing, version: 1, sessionId: ...';

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
  String get orbit_preview_voice_message => 'Voice message';

  @override
  String get orbit_preview_gif => 'GIF';

  @override
  String orbit_preview_photo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count photos',
      one: 'Photo',
    );
    return '$_temp0';
  }

  @override
  String orbit_preview_video(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count videos',
      one: 'Video',
    );
    return '$_temp0';
  }

  @override
  String orbit_preview_file(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: 'File',
    );
    return '$_temp0';
  }

  @override
  String orbit_preview_attachment(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count attachments',
      one: 'Attachment',
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
  String get orbit_view_toggle_to_list => 'Show all chats';

  @override
  String get orbit_view_toggle_to_circle => 'Show inner circle';

  @override
  String get orbit_inner_circle_empty_hint =>
      'Add friends to see your inner circle';

  @override
  String orbit_overflow_badge_open(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more people — tap to open',
      one: '1 more person — tap to open',
    );
    return '$_temp0';
  }

  @override
  String get orbit_overflow_badge_collapse => 'Hide extra people';

  @override
  String get orbit_edit_banner => 'TAP AWAY TO FINISH';

  @override
  String get orbit_edit_reset => 'Reset';

  @override
  String get orbit_handle_ring_spacing => 'Ring spacing';

  @override
  String get orbit_handle_avatar_size => 'Avatar size';

  @override
  String get orbit_handle_arc_wrap => 'Arc wrap';

  @override
  String get orbit_handle_max_per_arc => 'Max per arc';

  @override
  String get orbit_handle_orbit_gap => 'Orbit gap';

  @override
  String orbit_edit_step_increase(String name) {
    return 'Increase $name';
  }

  @override
  String orbit_edit_step_decrease(String name) {
    return 'Decrease $name';
  }

  @override
  String get orbit_find_placeholder => 'Find someone…';

  @override
  String get orbit_find_pill_semantics => 'Find someone in your circle';

  @override
  String get orbit_find_close => 'Close search';

  @override
  String get orbit_open_settings => 'Open settings';

  @override
  String get orbit_search_trigger_semantics => 'Search chats';

  @override
  String orbit_chip_provenance_ring(int ring) {
    return 'Ring $ring';
  }

  @override
  String orbit_chip_provenance_arc(int arc) {
    return 'Arc $arc';
  }

  @override
  String orbit_chip_open(String name) {
    return 'Open $name';
  }

  @override
  String orbit_node_unread_open_chat(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Open chat with $name, $count unread messages',
      one: 'Open chat with $name, 1 unread message',
    );
    return '$_temp0';
  }

  @override
  String orbit_node_open_group(String name) {
    return 'Open group $name';
  }

  @override
  String orbit_node_unread_open_group(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Open group $name, $count unread messages',
      one: 'Open group $name, 1 unread message',
    );
    return '$_temp0';
  }

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
  String get orbit_leave_action => 'Leave';

  @override
  String get orbit_leave_group_body =>
      'Leaving removes this group and its history from this device. This cannot be undone.';

  @override
  String get orbit_leave_group_action => 'Leave & Delete';

  @override
  String get group_exit_only_admin_title => 'You’re the only admin';

  @override
  String group_exit_only_admin_body(String groupName) {
    return 'A group needs at least one admin before you can leave. Choose what should happen to $groupName.';
  }

  @override
  String get group_exit_choose_admin => 'Choose another admin';

  @override
  String get group_exit_choose_admin_body =>
      'Then you can leave and remove this group from this device.';

  @override
  String get group_exit_dissolve_for_everyone => 'Dissolve for everyone';

  @override
  String get group_exit_keep_group => 'Keep group';

  @override
  String get group_exit_keep_and_close_semantics => 'Keep group and close';

  @override
  String get group_exit_no_eligible_successor =>
      'Wait for someone to join, or dissolve the group.';

  @override
  String get group_exit_choose_member => 'Choose a member';

  @override
  String get group_exit_continue_to_leave => 'Continue to leave';

  @override
  String get group_exit_stay_in_group => 'Stay in group';

  @override
  String get group_exit_admin_sync_pending_title =>
      'Admin change is still syncing';

  @override
  String get group_exit_admin_sync_pending_body =>
      'Wait for the signed admin change to finish syncing before you leave.';

  @override
  String get group_exit_sync_finishing_title => 'Finishing a role change';

  @override
  String get group_exit_sync_finishing_body =>
      'You can leave this screen. We’ll leave the group as soon as the role update is safely delivered.';

  @override
  String get group_exit_leave_when_sync_completes =>
      'Leave when sync completes';

  @override
  String get group_exit_try_again => 'Try again';

  @override
  String get group_exit_cancel_queued_leave => 'Cancel queued leave';

  @override
  String get group_exit_cancel_queued_leave_body =>
      'This cancels automatic leave. The role change will keep syncing.';

  @override
  String get group_exit_leaving_status => 'Leaving…';

  @override
  String get group_exit_leaving_read_only =>
      'This group is read-only while we finish leaving.';

  @override
  String get group_exit_cancel_too_late =>
      'Leaving has already started and can’t be cancelled.';

  @override
  String get group_exit_leave_uncertain =>
      'The leave request may have completed. Refresh the group before trying again.';

  @override
  String get group_exit_cleanup_incomplete =>
      'You left the group, but its local history could not be fully removed.';

  @override
  String get group_removed_delete_title =>
      'Delete this group from this device?';

  @override
  String get group_removed_delete_body =>
      'This deletes the retained messages from this device only. You will not leave or notify the group.';

  @override
  String get group_removed_delete_action => 'Delete from Device';

  @override
  String get group_removed_delete_failed =>
      'Couldn’t delete this group from this device. Try again.';

  @override
  String get conversation_hint => 'Write something...';

  @override
  String get conversation_voice_fail => 'Failed to send voice message.';

  @override
  String get conversation_voice_limit_reached =>
      'Recording reached the 5-minute limit.';

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
  String get announcement_private_reply_action => 'Message sender';

  @override
  String get announcement_private_reply_unavailable =>
      'Message sender is unavailable.';

  @override
  String get announcement_private_reply_open_failed =>
      'Couldn’t open the conversation.';

  @override
  String get conversation_context_edit => 'Edit';

  @override
  String get conversation_context_copy => 'Copy';

  @override
  String get conversation_context_delete => 'Delete';

  @override
  String get conversation_context_save => 'Save';

  @override
  String get conversation_context_share => 'Share';

  @override
  String get conversation_context_info => 'Info';

  @override
  String get conversation_context_copied => 'Message copied to clipboard';

  @override
  String get conversation_forwarded_marker => 'Forwarded';

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
  String get conversation_delete_media_message_prompt =>
      'Delete this message? The message and all of its attachments will be removed from this device.';

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
  String get conversation_catching_up => 'Catching up...';

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
  String get settings_section_identity => 'IDENTITY';

  @override
  String get settings_section_preferences => 'PREFERENCES';

  @override
  String get settings_group_exit_diagnostics_section => 'SUPPORT';

  @override
  String get settings_group_exit_diagnostics_title => 'Group exit history';

  @override
  String settings_group_exit_diagnostics_count(int count) {
    return '$count saved records';
  }

  @override
  String get settings_group_exit_diagnostics_unavailable =>
      'Group exit history is unavailable.';

  @override
  String get settings_group_exit_diagnostics_unavailable_hint =>
      'Tap to try again.';

  @override
  String get settings_group_exit_diagnostics_empty =>
      'No saved group exit records.';

  @override
  String get settings_group_exit_diagnostics_reload => 'Reload';

  @override
  String get settings_group_exit_diagnostics_clear => 'Clear history';

  @override
  String get settings_group_exit_diagnostics_reloaded =>
      'Group exit history reloaded.';

  @override
  String get settings_group_exit_diagnostics_cleared =>
      'Group exit history cleared.';

  @override
  String get settings_group_exit_diagnostics_reload_failed =>
      'Couldn’t reload group exit history. Existing records are unchanged.';

  @override
  String get settings_group_exit_diagnostics_clear_failed =>
      'Couldn’t clear group exit history. Existing records are unchanged.';

  @override
  String get settings_group_exit_diagnostics_close =>
      'Close group exit history';

  @override
  String settings_group_exit_diagnostics_group_reference(String groupRef) {
    return 'Group reference $groupRef';
  }

  @override
  String get settings_group_exit_diagnostic_ex01 =>
      'Exit authority could not be established.';

  @override
  String get settings_group_exit_diagnostic_ex02 =>
      'Membership-role updates could not finish.';

  @override
  String get settings_group_exit_diagnostic_ex03 =>
      'The leave notice could not be prepared.';

  @override
  String get settings_group_exit_diagnostic_ex04 =>
      'The group engine is unavailable.';

  @override
  String get settings_group_exit_diagnostic_ex05 =>
      'The group engine rejected the leave request.';

  @override
  String get settings_group_exit_diagnostic_ex06 =>
      'The leave result could not be confirmed.';

  @override
  String get settings_group_exit_diagnostic_ex07 =>
      'The group was left, but local cleanup is incomplete.';

  @override
  String get settings_group_exit_diagnostic_ex08 =>
      'The leave notice could not reach every member.';

  @override
  String get settings_group_exit_diagnostic_ex09 =>
      'Group-key rotation is deferred.';

  @override
  String get settings_group_exit_diagnostic_ex10 =>
      'Local group deletion is incomplete.';

  @override
  String get settings_group_exit_diagnostic_ex99 =>
      'An unexpected group-exit result occurred.';

  @override
  String get settings_background => 'Background';

  @override
  String get settings_background_default => 'Default';

  @override
  String get settings_background_default_desc =>
      'Mirrored cosmic drift with soft color blooms.';

  @override
  String get settings_background_cosmic => 'Cosmic';

  @override
  String get settings_background_cosmic_desc => 'A deep starfield for Feed.';

  @override
  String get settings_background_cosmic_selected => 'Cosmic selected';

  @override
  String get settings_background_aurora => 'Aurora';

  @override
  String get settings_background_aurora_desc => 'The original ambient glow.';

  @override
  String get settings_background_aurora_selected => 'Aurora selected';

  @override
  String get settings_background_daylight_lagoon => 'Signal';

  @override
  String get settings_background_daylight_lagoon_desc =>
      'A warm mineral sky with soft violet and sage light.';

  @override
  String get settings_background_daylight_lagoon_selected => 'Signal selected';

  @override
  String get settings_background_save_fail => 'Couldn\'t save. Try again.';

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
  String get settings_move_account_title => 'Move account to new phone';

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
  String get media_too_large_chip => 'Too large';

  @override
  String get media_gif_too_large_chip => 'GIF too big';

  @override
  String get media_attachments_too_large_note =>
      'Attachments too large — remove some to send.';

  @override
  String get media_unavailable => 'Media unavailable';

  @override
  String get media_could_not_verify => 'Couldn\'t verify this media';

  @override
  String get settings_media_storage => 'Media & storage';

  @override
  String get settings_media_auto_download => 'Automatic downloads';

  @override
  String get settings_media_auto_download_desc =>
      'Choose which received media downloads automatically on each network.';

  @override
  String get settings_media_lane_direct => 'Direct chats';

  @override
  String get settings_media_lane_discussions => 'Discussions';

  @override
  String get settings_media_lane_announcements => 'Announcements';

  @override
  String get settings_media_type_image => 'Photos';

  @override
  String get settings_media_type_video => 'Videos';

  @override
  String get settings_media_type_audio => 'Audio';

  @override
  String get settings_media_type_file => 'Files';

  @override
  String get settings_media_network_off => 'Off';

  @override
  String get settings_media_network_wifi => 'Wi-Fi';

  @override
  String get settings_media_network_all => 'Wi-Fi + cellular';

  @override
  String get settings_media_save_fail => 'Couldn\'t save. Try again.';

  @override
  String get settings_media_storage_usage => 'Storage usage';

  @override
  String get settings_media_storage_compute => 'Show usage';

  @override
  String get settings_media_storage_clear_type => 'Clear';

  @override
  String get settings_media_storage_empty => 'No downloaded media copies';

  @override
  String get media_local_copy_removed => 'Local copy removed';

  @override
  String get media_retry_unavailable => 'Retry unavailable media';

  @override
  String get edit_save_failed => 'Failed to save edit.';

  @override
  String get sending_taking_longer => 'Sending is taking longer…';

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
  String get message_status_inbox => 'delivered to inbox';

  @override
  String get message_sent_via_relay => 'Sent via cellular relay';

  @override
  String get message_sent_via_direct => 'Sent via direct connection';

  @override
  String get message_sent_via_wifi => 'Sent via Wi-Fi';

  @override
  String get message_sent_via_inbox => 'Sent to inbox';

  @override
  String get message_received_via_relay => 'Received via cellular relay';

  @override
  String get message_received_via_direct => 'Received via direct connection';

  @override
  String get message_received_via_wifi => 'Received via Wi-Fi';

  @override
  String get message_received_via_inbox => 'Received via inbox';

  @override
  String get message_sent_via_upgraded => 'Upgraded to direct connection';

  @override
  String get message_received_via_upgraded =>
      'Received via upgraded direct connection';

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
  String get group_read_only_unavailable =>
      'This group is no longer available.';

  @override
  String get group_send_failed_dissolved =>
      'Couldn\'t send — this group was dissolved';

  @override
  String get group_send_failed_removed =>
      'Couldn\'t send — you\'re no longer in this group';

  @override
  String get group_send_failed_unavailable =>
      'Couldn\'t send — this group is unavailable';

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
  String group_info_revoke_invite_title(String username) {
    return 'Revoke invite for $username?';
  }

  @override
  String get group_info_revoke_invite_body =>
      'They will no longer be able to join the group with this invite.';

  @override
  String get group_info_revoke_invite_action => 'Revoke';

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
  String get group_info_details_update_queued =>
      'Saved — will retry sending when reconnected';

  @override
  String get group_info_invite_resend_failed => 'Failed to resend invite';

  @override
  String group_info_invite_revoked(String username) {
    return 'Invite to $username revoked';
  }

  @override
  String get group_info_invite_revoke_failed => 'Failed to revoke invite';

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
  String get group_edit_recovery_waiting =>
      'Please wait while this device catches up.';

  @override
  String group_edit_recovery_waiting_elapsed(int seconds) {
    return 'Waiting ${seconds}s';
  }

  @override
  String get btn_save => 'Save';

  @override
  String get group_member_sending => 'Sending...';

  @override
  String get group_member_resend => 'Resend';

  @override
  String get group_member_revoke => 'Revoke';

  @override
  String get group_member_revoking => 'Revoking...';

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
  String get invite_status_revoked => 'Revoked';

  @override
  String get invite_status_declined => 'Declined';

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
  String get group_notification_catching_up =>
      'This group is still catching up — try again in a moment.';

  @override
  String get restore_groups_device_local_notice =>
      'Your groups will reappear when this device is re-admitted. Group history from before this device existed can\'t be recovered.';

  @override
  String get group_info_delete_local_failed => 'Failed to delete group locally';

  @override
  String get group_info_publish_member_removal_failed =>
      'Failed to publish member removal';

  @override
  String get group_info_rotate_key_failed =>
      'Failed to rotate group key after removal';

  @override
  String get group_info_remove_member_partial_distribution =>
      'Member removed. Some members will receive the new key when they reconnect.';

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
  String get failed_message_retry_failed => 'Could not retry message.';

  @override
  String get failed_media_upload_pending_retry =>
      'Media upload is still finishing. It will retry soon.';

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
  String get mic_perm_dialog_title => 'Allow microphone access';

  @override
  String get mic_perm_dialog_body =>
      'To record voice messages, turn it on in your phone\'s settings.';

  @override
  String get mic_perm_not_now => 'Not now';

  @override
  String get group_read_only_not_active =>
      'You were removed from this group. You can still read past messages.';

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
  String conversation_undelivered_banner(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Couldn\'t display $count messages',
      one: 'Couldn\'t display 1 message',
    );
    return '$_temp0';
  }

  @override
  String get conversation_undelivered_retry => 'Retry';

  @override
  String get conversation_empty_first_letter =>
      'Write the first letter\nto start your conversation';

  @override
  String get media_video_load_failed => 'Could not load video';

  @override
  String get media_viewer_action_save => 'Save';

  @override
  String get media_viewer_action_share => 'Share';

  @override
  String get media_viewer_action_forward => 'Forward';

  @override
  String get media_viewer_action_delete => 'Delete';

  @override
  String get media_viewer_action_bookmark => 'Bookmark';

  @override
  String get media_viewer_action_info => 'Info';

  @override
  String get media_viewer_action_reply => 'Reply';

  @override
  String get media_viewer_action_picture_in_picture => 'Picture in Picture';

  @override
  String get media_viewer_picture_in_picture_start_failed =>
      'Couldn\'t start Picture in Picture';

  @override
  String get media_save_destination_prompt => 'Save to…';

  @override
  String get media_save_destination_photos => 'Save to Photos';

  @override
  String get media_save_destination_files => 'Save to Files';

  @override
  String get media_egress_result_saved => 'Saved';

  @override
  String get media_egress_result_shared => 'Shared';

  @override
  String get media_egress_result_cancelled => 'Cancelled';

  @override
  String get media_egress_result_permission_denied =>
      'Permission needed to finish this action';

  @override
  String get media_egress_result_missing =>
      'This media file is missing from this device';

  @override
  String get media_egress_result_failed => 'Couldn\'t complete this action';

  @override
  String get media_egress_result_unavailable =>
      'This media is no longer available for saving or sharing';

  @override
  String get media_info_title => 'Media info';

  @override
  String get media_info_sender => 'From';

  @override
  String get media_info_direction => 'Direction';

  @override
  String get media_info_direction_incoming => 'Received';

  @override
  String get media_info_direction_outgoing => 'Sent';

  @override
  String get media_info_date => 'Date';

  @override
  String get media_info_type => 'Type';

  @override
  String get media_info_size => 'Size';

  @override
  String get media_info_dimensions => 'Dimensions';

  @override
  String get media_info_duration => 'Duration';

  @override
  String get media_info_state => 'Status';

  @override
  String get media_info_state_downloaded => 'Downloaded';

  @override
  String get media_info_state_not_downloaded => 'Not downloaded';

  @override
  String get media_info_state_unverified => 'Couldn\'t verify';

  @override
  String get group_media_info_title => 'Media info';

  @override
  String get group_media_info_kind => 'Type';

  @override
  String get group_media_info_kind_image => 'Image';

  @override
  String get group_media_info_kind_video => 'Video';

  @override
  String get group_media_info_sender => 'From';

  @override
  String get group_media_info_sent_time => 'Sent';

  @override
  String get group_media_info_size => 'Size';

  @override
  String get group_media_info_state => 'Status';

  @override
  String get group_media_info_caption => 'Caption';

  @override
  String get group_media_info_state_available => 'Downloaded and verified';

  @override
  String get group_media_info_state_pending => 'Not downloaded yet';

  @override
  String get group_media_info_state_unavailable => 'Unavailable';

  @override
  String get group_media_delete_for_me_title => 'Delete for me?';

  @override
  String get group_media_delete_for_me_body =>
      'This removes the message and its media from this device only. Other members keep their copy.';

  @override
  String get group_media_delete_for_me_confirm => 'Delete for me';

  @override
  String get group_media_delete_for_me_cancel => 'Cancel';

  @override
  String get group_media_saved_confirm => 'Saved';

  @override
  String get media_viewer_play => 'Play';

  @override
  String get media_viewer_pause => 'Pause';

  @override
  String get media_viewer_skip_back => 'Back 10 seconds';

  @override
  String get media_viewer_skip_forward => 'Forward 10 seconds';

  @override
  String get media_viewer_mute => 'Mute';

  @override
  String get media_viewer_unmute => 'Unmute';

  @override
  String get conversation_introduce_to_circle => 'Introduce to your circle';

  @override
  String get conversation_shared_media => 'Shared media';

  @override
  String get shared_media_title => 'Shared media';

  @override
  String get shared_media_filter_all => 'All';

  @override
  String get shared_media_filter_photos => 'Photos';

  @override
  String get shared_media_filter_videos => 'Videos';

  @override
  String get shared_media_filter_bookmarked => 'Bookmarked';

  @override
  String get shared_media_empty => 'No shared media yet';

  @override
  String get shared_media_load_failed => 'Couldn\'t load shared media';

  @override
  String get shared_media_kind_photo => 'Photo';

  @override
  String get shared_media_kind_video => 'Video';

  @override
  String get shared_media_state_missing => 'File missing';

  @override
  String get shared_media_state_evicted => 'Local copy removed';

  @override
  String get shared_media_state_not_downloaded => 'Not downloaded';

  @override
  String get shared_media_state_unverified => 'Couldn\'t verify';

  @override
  String shared_media_selection_count(int count) {
    return '$count selected';
  }

  @override
  String shared_media_selection_limit(int max) {
    return 'You can select up to $max items';
  }

  @override
  String get shared_media_action_save => 'Save';

  @override
  String get shared_media_action_share => 'Share';

  @override
  String get shared_media_action_delete => 'Delete';

  @override
  String get shared_media_action_go_to_message => 'Go to message';

  @override
  String shared_media_delete_title(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages',
      one: '1 message',
    );
    return 'Delete $_temp0?';
  }

  @override
  String get shared_media_delete_body =>
      'This removes each selected item\'s entire message, including all of its attachments, from this device only. Copies saved or shared outside this app are not affected.';

  @override
  String get shared_media_delete_confirm => 'Delete for me';

  @override
  String get shared_media_delete_cancel => 'Cancel';

  @override
  String shared_media_batch_partial_failure(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0 couldn\'t be completed and stay selected';
  }

  @override
  String get shared_media_go_to_message_missing =>
      'This message is no longer in the conversation';

  @override
  String get shared_media_bookmark_add => 'Bookmark';

  @override
  String get shared_media_bookmark_remove => 'Remove bookmark';

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
      other: 'Skipped $count oversized attachments.',
      one: 'Skipped 1 oversized attachment.',
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
  String get feed_replying_to => 'Replying to';

  @override
  String feed_ready_for_user(String username) {
    return 'Your feed is ready, @$username. New connections will appear here.';
  }

  @override
  String get feed_all_caught_up => 'You\'re all caught up';

  @override
  String get feed_loading => 'Loading Feed...';

  @override
  String get feed_syncing_threads => 'Your recent threads are still syncing.';

  @override
  String feed_reply_to_name(String name) {
    return 'Reply to $name…';
  }

  @override
  String feed_message_name(String name) {
    return 'Message $name…';
  }

  @override
  String get feed_add_another => 'Add another…';

  @override
  String get feed_open_full_conversation => 'Open full conversation';

  @override
  String get feed_tap_to_retry => 'tap to retry';

  @override
  String feed_removed_undo(String name) {
    return 'Removed $name';
  }

  @override
  String get feed_undo => 'Undo';

  @override
  String get feed_tap_to_say_hi => 'tap to say hi';

  @override
  String get feed_connected => 'Connected';

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
  String orbit_intro_dock_label(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count new',
      one: '1 new',
    );
    return '$_temp0';
  }

  @override
  String orbit_intro_dock_semantics(int count) {
    return 'Open introductions review, $count new';
  }

  @override
  String get orbit_intro_remnant_semantics => 'Open introductions review';

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
  String get group_invite_no_longer_available => 'Invite no longer available';

  @override
  String get group_invite_expired => 'Invite expired';

  @override
  String get group_invite_expired_ask_resend =>
      'This invite has expired. Ask the group admin to send a fresh one.';

  @override
  String get group_joining_in_progress => 'Joining…';

  @override
  String get group_join_failed_retry => 'Couldn\'t join — retry';

  @override
  String get group_invite_revoked => 'Invite was revoked';

  @override
  String get group_invite_already_used => 'Invite already used';

  @override
  String get group_invite_wrong_identity => 'Invite is for another identity';

  @override
  String get group_invite_needs_key => 'Invite needs fresh key material';

  @override
  String get group_invite_waiting_for_key => 'Waiting for key';

  @override
  String get group_invite_invalid => 'Invite is no longer valid';

  @override
  String get group_invite_duplicate_group => 'Group already added';

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

  @override
  String sibling_device_new_device_title(String member) {
    return 'New device for $member';
  }

  @override
  String get sibling_device_verify_prompt =>
      'A new device wants to join this account. Verify its safety number matches the new device before approving.';

  @override
  String get sibling_device_reject => 'Reject';

  @override
  String get sibling_device_verify_approve => 'Verify & approve';

  @override
  String get transport_diagnostics_title => 'TRANSPORT DIAGNOSTICS (SESSION)';

  @override
  String get transport_diagnostics_census =>
      'Session-scoped, aggregate-only transport census. No identifiers leave the device.';

  @override
  String get transport_diagnostics_lan_discovery => 'discovery';

  @override
  String get transport_diagnostics_lan_peers => 'peers';

  @override
  String get transport_diagnostics_lan_permission => 'permission';

  @override
  String get transport_diagnostics_refresh => 'Refresh';

  @override
  String get account_migration_back => 'Back';

  @override
  String get account_migration_qr_heading => 'Move Account QR';

  @override
  String get account_migration_qr_confirm_label =>
      'Confirm this code after scanning';

  @override
  String account_migration_qr_expires_at(String time) {
    return 'Expires at $time';
  }

  @override
  String get account_migration_scan_action => 'Scan migration QR';

  @override
  String get account_migration_start_transfer => 'Start transfer';

  @override
  String get account_migration_cancel_transfer => 'Cancel transfer';

  @override
  String get account_migration_retry => 'Retry';

  @override
  String get account_migration_erase_confirm_title => 'Erase this device?';

  @override
  String get account_migration_erase_confirm_body =>
      'This only clears local account data on this phone after the account has moved. It will not move anything back.';

  @override
  String get account_migration_cancel => 'Cancel';

  @override
  String get account_migration_erase_local_data => 'Erase local data';

  @override
  String get account_migration_erased_snackbar => 'Local account data erased';

  @override
  String account_migration_erase_failed(String error) {
    return 'Could not erase local account data: $error';
  }

  @override
  String get account_migration_blocked_title =>
      'Account moved to another phone';

  @override
  String get account_migration_blocked_message =>
      'This phone is blocked from opening the account after migration. Erase the local copy only when you are sure the new phone works.';

  @override
  String get contact_profile_verified_peer => 'Verified peer';

  @override
  String get contact_profile_blocked => 'Blocked';

  @override
  String get contact_profile_archived => 'Archived';

  @override
  String get contact_profile_peer_id_label => 'Peer ID';

  @override
  String get contact_profile_peer_id_copied => 'Peer ID copied';

  @override
  String get contact_profile_tap_to_copy => 'Tap to copy';

  @override
  String get contact_profile_safety_number_label => 'Safety number';

  @override
  String get contact_profile_safety_number_hint =>
      'Compare this number in person to confirm your connection is secure.';

  @override
  String get contact_profile_copied => 'Copied to clipboard';

  @override
  String get contact_profile_connected_since_label => 'Connected since';

  @override
  String get contact_profile_introduced_by_label => 'Introduced by';

  @override
  String get contact_profile_message_button => 'Message';

  @override
  String get private_media_selector_label => 'Private media';

  @override
  String get private_media_ordinary => 'Keep in chat';

  @override
  String get private_media_protected => 'Protected view';

  @override
  String get private_media_ordinary_detail => 'They can save or share it.';

  @override
  String get private_media_protected_detail =>
      'They can view it again, but not save or share it.';

  @override
  String get private_media_view_once => 'View once';

  @override
  String get private_media_disappearing_1h => 'Disappears after 1 hour';

  @override
  String get private_media_disappearing_1d => 'Disappears after 1 day';

  @override
  String get private_media_disappearing_7d => 'Disappears after 7 days';

  @override
  String get private_media_invalid_shape =>
      'Private media needs one photo or video with no caption.';

  @override
  String get private_media_notification_body => 'Private media';

  @override
  String get group_private_media_notification_body => 'New private media';

  @override
  String get private_media_expiry_device_local =>
      'Deleted from their device after this time.';

  @override
  String get private_media_view_once_copy =>
      'Disappears after they open it once.';

  @override
  String private_media_protected_body_received(String name) {
    return 'You can view it again. $name doesn\'t allow saving or sharing.';
  }

  @override
  String private_media_protected_body_received_compact(String name) {
    return '$name doesn\'t allow saving or sharing.';
  }

  @override
  String get private_media_view_once_body_received =>
      'You can only view this once.';

  @override
  String private_media_outgoing_body(String name) {
    return 'Only $name can view it. They can\'t save or share it.';
  }

  @override
  String get private_media_open => 'Open private media';

  @override
  String get private_media_opening => 'Opening private media…';

  @override
  String get private_media_consumed => 'Already viewed on this device';

  @override
  String get private_media_expired => 'Expired on this device';

  @override
  String get private_media_unsupported =>
      'Update Mknoon to view this private media, or delete it';

  @override
  String get private_media_android_capture_limit =>
      'Screenshots and screen recording are blocked only while this private route is open';

  @override
  String get private_media_ios_capture_limit =>
      'iOS cannot reliably prevent screenshots; capture is detected and private media is covered/dismissed';

  @override
  String get private_media_ios_image_capture_limit =>
      'This protected image is hidden in screenshots and screen recordings while open';

  @override
  String get private_media_general_capture_limit =>
      'Another device or camera can still photograph the screen';

  @override
  String private_media_sheet_title_photo(String name) {
    return 'How should $name see this photo?';
  }

  @override
  String private_media_sheet_title_video(String name) {
    return 'How should $name see this video?';
  }

  @override
  String private_media_sheet_title_gif(String name) {
    return 'How should $name see this GIF?';
  }

  @override
  String get group_private_media_sheet_title =>
      'How should members see this photo?';

  @override
  String get private_media_set_expiry => 'Set an expiry';

  @override
  String private_media_expiry_choose_detail(String name) {
    return 'Disappears from $name\'s phone after a time you choose.';
  }

  @override
  String get private_media_delete_after => 'Delete after';

  @override
  String get private_media_duration_1h => '1 hour';

  @override
  String get private_media_duration_1d => '1 day';

  @override
  String get private_media_duration_7d => '7 days';

  @override
  String private_media_use_mode_cta(String mode) {
    return 'Use $mode';
  }

  @override
  String get private_media_summary_change => 'Change';

  @override
  String get private_media_summary_ordinary_detail =>
      'Normal photo · can be saved or shared';

  @override
  String get private_media_summary_protected_detail =>
      'Viewable again · no saving or sharing';

  @override
  String private_media_summary_view_once_detail(String name) {
    return 'One view for $name';
  }

  @override
  String private_media_summary_expiry_detail(String duration) {
    return 'No saving or sharing · deleted after $duration';
  }

  @override
  String private_media_disclosure_protected(String name) {
    return 'Only $name can open it. Saving and sharing are disabled.';
  }

  @override
  String private_media_disclosure_view_once(String name) {
    return '$name can open it once, then it\'s gone. Saving and sharing are disabled.';
  }

  @override
  String private_media_disclosure_expiry(String name) {
    return 'Only $name can open it until it expires. Saving and sharing are disabled.';
  }

  @override
  String get private_media_disclosure_reopen =>
      'You can reopen it once here after sending.';

  @override
  String get private_media_card_title_protected_photo => 'Protected photo';

  @override
  String get private_media_card_title_protected_video => 'Protected video';

  @override
  String get private_media_card_title_view_once_photo => 'View-once photo';

  @override
  String get private_media_card_title_view_once_video => 'View-once video';

  @override
  String private_media_card_title_expiry_photo(String duration) {
    return 'Photo · disappears after $duration';
  }

  @override
  String private_media_card_title_expiry_video(String duration) {
    return 'Video · disappears after $duration';
  }

  @override
  String get private_media_open_photo => 'Open photo';

  @override
  String get private_media_open_video => 'Open video';

  @override
  String get private_media_view_photo => 'View photo';

  @override
  String get private_media_view_video => 'View video';

  @override
  String get private_media_sender_consumed => 'You\'ve used your one more look';

  @override
  String get offline_send_promise => 'Will send when you\'re back online';

  @override
  String get offline_retry_delayed =>
      'Delivery delayed — retrying automatically';

  @override
  String get share_stored_offline_promise =>
      'Stored — will send when you\'re back online.';

  @override
  String get offline_banner_title => 'You\'re offline';

  @override
  String get offline_banner_body =>
      'Messages and media will send when you\'re back online.';

  @override
  String get media_sending_automatically => 'Sending automatically…';

  @override
  String media_uploading_percent(int percent) {
    return 'Uploading photo · $percent%';
  }

  @override
  String get media_uploading => 'Uploading photo…';

  @override
  String get media_view_once_not_viewed => 'Not viewed yet.';

  @override
  String get media_missing_terminal_title_photo =>
      'Photo is no longer on this phone';

  @override
  String get media_missing_terminal_title_video =>
      'Video is no longer on this phone';

  @override
  String get media_missing_terminal_body => 'Choose it again to send.';

  @override
  String get media_remove => 'Remove';

  @override
  String get private_media_open_failed_title_photo =>
      'Couldn\'t open this photo';

  @override
  String get private_media_open_failed_title_video =>
      'Couldn\'t open this video';

  @override
  String get private_media_open_failed_view_safe =>
      'Your one view is still available.';

  @override
  String get private_media_open_failed_reopen_safe =>
      'Your one more look is still available.';

  @override
  String get private_media_sender_local_missing_body =>
      'Your sent media can\'t be reopened on this phone.';

  @override
  String get private_media_try_again => 'Try again';

  @override
  String get group_invite_ask_new => 'Ask for a new invite';

  @override
  String group_invite_request_new_draft(String groupName) {
    return 'Could you send me a new invite to $groupName?';
  }

  @override
  String get group_invite_contact_unavailable =>
      'This contact is no longer available.';

  @override
  String get shared_media_action_forward => 'Batch Forward';

  @override
  String get direct_batch_forward_title => 'Batch Forward';

  @override
  String direct_batch_forward_item_count(int count) {
    return '$count selected items';
  }

  @override
  String direct_batch_forward_source_label(int index, int count) {
    return 'Source $index of $count';
  }

  @override
  String direct_batch_forward_caption_label(int index, int count) {
    return 'Caption for source $index of $count';
  }

  @override
  String get direct_batch_forward_contacts_title => 'Direct contacts';

  @override
  String get direct_batch_forward_no_contacts => 'No active direct contacts';

  @override
  String get direct_batch_forward_send => 'Send';

  @override
  String get direct_batch_forward_retry_failed => 'Retry failed';

  @override
  String direct_batch_forward_progress(String phase, int completed, int total) {
    return '$phase: $completed of $total';
  }

  @override
  String get direct_batch_forward_source_unavailable =>
      'Selected media is no longer available';

  @override
  String get direct_batch_forward_status_sent => 'Sent';

  @override
  String get direct_batch_forward_status_queued => 'Queued';

  @override
  String get direct_batch_forward_status_failed => 'Failed';

  @override
  String direct_batch_forward_summary(int sent, int queued, int failed) {
    return 'Sent $sent, queued $queued, failed $failed';
  }

  @override
  String get direct_batch_forward_phase_uploading => 'Uploading';

  @override
  String get direct_batch_forward_phase_sending => 'Sending';

  @override
  String get direct_batch_forward_close => 'Close';
}
