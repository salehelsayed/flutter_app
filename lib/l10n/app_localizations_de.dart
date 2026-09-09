// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get nav_feed => 'Feed';

  @override
  String get nav_remember => 'Erinnerungen';

  @override
  String get nav_posts => 'Beiträge';

  @override
  String get nav_orbit => 'Kreis';

  @override
  String get onboarding_new_here => 'Ich bin neu hier';

  @override
  String get onboarding_new_desc => 'Neue Identität erstellen';

  @override
  String get onboarding_load_key => 'Schlüssel wiederherstellen';

  @override
  String get onboarding_load_desc =>
      'Mit deiner Wiederherstellungsphrase wiederherstellen';

  @override
  String get onboarding_move_from_old_phone => 'Vom alten Handy umziehen';

  @override
  String get onboarding_move_desc =>
      'Bring dein bestehendes Konto auf dieses Gerät';

  @override
  String get onboarding_privacy_1 => 'Nur du kannst deine Nachrichten lesen';

  @override
  String get onboarding_privacy_2 =>
      'Alles bleibt auf deinem Handy. Niemand schaut mit.';

  @override
  String get progress_securing => 'Deine Identität wird gesichert';

  @override
  String get progress_securing_desc =>
      'Deine Identität wird sicher gespeichert.';

  @override
  String get progress_creating => 'Deine sichere Identität wird erstellt';

  @override
  String get progress_creating_desc =>
      'Auf diesem Gerät werden Verschlüsselungsschlüssel erstellt. Das passiert nur einmal.';

  @override
  String get progress_keep_open => 'Bitte lass die App geöffnet.';

  @override
  String get progress_almost => 'Fast geschafft.';

  @override
  String get progress_step_keys => 'Schlüssel erstellen';

  @override
  String get progress_step_save => 'Auf dem Gerät speichern';

  @override
  String get mnemonic_title => 'Wiederherstellungsphrase';

  @override
  String get mnemonic_error_12 => 'Bitte gib genau 12 Wörter ein';

  @override
  String get mnemonic_error_invalid => 'Ungültige Wiederherstellungsphrase';

  @override
  String get mnemonic_error_generic =>
      'Es ist ein Fehler aufgetreten. Bitte versuche es erneut.';

  @override
  String get mnemonic_hint =>
      'word1 word2 word3 word4\nword5 word6 word7 word8\nword9 word10 word11 word12';

  @override
  String get qr_show_desc =>
      'Zeig das jemandem, den du in deinen Kreis aufnehmen willst...';

  @override
  String get qr_copy_hint =>
      'QR-Code gedrückt halten, um die Daten zu kopieren';

  @override
  String get qr_copied => 'QR-Daten in die Zwischenablage kopiert!';

  @override
  String get qr_scan_title => 'QR-Code scannen';

  @override
  String get qr_scan_instruction =>
      'Richte deine Kamera auf den QR-Code eines Freundes';

  @override
  String get qr_scan_subtitle => 'Die Person wird deinem Kreis hinzugefügt';

  @override
  String get account_migration_scan_title => 'Migrations-QR scannen';

  @override
  String get account_migration_scan_instruction =>
      'Richte deine Kamera auf den Move-Account-QR auf deinem neuen Handy';

  @override
  String get account_migration_scan_subtitle =>
      'Hier werden nur Move-Account-QR-Codes akzeptiert';

  @override
  String get qr_my_code => 'Mein QR-Code';

  @override
  String get qr_no_identity => 'Keine Identität vorhanden';

  @override
  String get qr_error => 'Fehler';

  @override
  String get qr_try_again => 'Erneut versuchen';

  @override
  String get qr_paste_title => 'QR-Daten einfügen';

  @override
  String get qr_paste_hint =>
      'Füge die JSON-Daten des QR-Codes von einem anderen Gerät ein:';

  @override
  String get qr_paste_button => 'Aus Zwischenablage einfügen';

  @override
  String get account_migration_paste_title => 'Migrations-QR einfügen';

  @override
  String get account_migration_paste_hint =>
      'Füge die Move-Account-QR-Daten ein, die auf deinem neuen Handy angezeigt werden:';

  @override
  String get account_migration_paste_button =>
      'Migrations-QR aus Zwischenablage einfügen';

  @override
  String get account_migration_paste_payload_hint =>
      'kind: account_migration_pairing, version: 1, sessionId: ...';

  @override
  String get posts_title => 'Beiträge';

  @override
  String posts_header_subtitle(String username) {
    return 'Was ist heute bei deinen Freunden los, $username?';
  }

  @override
  String get posts_compose_button => 'Teile etwas mit deinen Freunden';

  @override
  String get posts_empty_title => 'Du bist auf dem neuesten Stand';

  @override
  String get posts_empty_desc =>
      'Beiträge von deinen direkten Freunden erscheinen hier, sobald sie ankommen oder nachträglich synchronisiert werden.';

  @override
  String get posts_empty_button => 'Ersten Beitrag erstellen';

  @override
  String get posts_caught_up => 'Du bist auf dem neuesten Stand';

  @override
  String get posts_time_now => 'Gerade eben';

  @override
  String get posts_time_earlier => 'Früher heute';

  @override
  String get posts_time_yesterday => 'Gestern';

  @override
  String get compose_title => 'Beitrag erstellen';

  @override
  String get compose_hint => 'Was möchtest du teilen?';

  @override
  String get compose_audience_all => 'Alle Freunde';

  @override
  String get compose_audience_nearby => 'Leute in deiner Nähe';

  @override
  String get compose_audience_pick => 'Personen auswählen';

  @override
  String get compose_radius => 'Radius';

  @override
  String get compose_radius_500 => '500m';

  @override
  String get compose_radius_1k => '1km';

  @override
  String get compose_radius_2k => '2km';

  @override
  String get compose_media => 'Medien';

  @override
  String get compose_media_adding => 'Wird hinzugefügt...';

  @override
  String get compose_voice => 'Sprachnachricht';

  @override
  String get compose_voice_stop => 'Stopp';

  @override
  String get compose_voice_attached => 'Sprachnachricht angehängt';

  @override
  String compose_attachments(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Anhänge',
      one: '1 Anhang',
      zero: 'Keine Anhänge',
    );
    return '$_temp0';
  }

  @override
  String get orbit_preview_voice_message => 'Sprachnachricht';

  @override
  String get orbit_preview_gif => 'GIF';

  @override
  String orbit_preview_photo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Fotos',
      one: 'Foto',
    );
    return '$_temp0';
  }

  @override
  String orbit_preview_video(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Videos',
      one: 'Video',
    );
    return '$_temp0';
  }

  @override
  String orbit_preview_file(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Dateien',
      one: 'Datei',
    );
    return '$_temp0';
  }

  @override
  String orbit_preview_attachment(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Anhänge',
      one: 'Anhang',
    );
    return '$_temp0';
  }

  @override
  String get compose_pick_people => 'Personen auswählen';

  @override
  String get compose_posting => 'Wird gepostet...';

  @override
  String get compose_post => 'Posten';

  @override
  String get compose_manage => 'Verwalten';

  @override
  String get compose_pinned_1 =>
      'Du hast bereits einen aktiven angepinnten Beitrag';

  @override
  String compose_pinned_n(int count) {
    return 'Du hast bereits $count aktive angepinnte Beiträge';
  }

  @override
  String get compose_nearby_off =>
      '„Leute in deiner Nähe“ ist in den Einstellungen deaktiviert';

  @override
  String get compose_nearby_ready => '„Leute in deiner Nähe“ ist einsatzbereit';

  @override
  String get compose_nearby_refresh => 'Nähe vor dem Posten aktualisieren';

  @override
  String get compose_nearby_allow =>
      'Standort erlauben, um Leute in deiner Nähe zu nutzen';

  @override
  String get compose_nearby_perm_off => 'Standortberechtigung ist deaktiviert';

  @override
  String get compose_nearby_services => 'Ortungsdienste einschalten';

  @override
  String get compose_nearby_off_desc =>
      'Aktiviere es in den Einstellungen, bevor du an Freunde in deiner Nähe postest.';

  @override
  String get compose_nearby_ready_desc =>
      'Deine Daten zu Personen in deiner Nähe sind aktuell genug zum Posten.';

  @override
  String get compose_nearby_refresh_desc =>
      'Aktualisiere deine Daten zu Personen in deiner Nähe, bevor du diese Zielgruppe nutzt.';

  @override
  String get compose_nearby_allow_desc =>
      'Aktualisiere die Nähe-Funktion, um den Standortzugriff für Beiträge in deiner Nähe zu erlauben.';

  @override
  String get compose_nearby_perm_desc =>
      'Öffne die Systemeinstellungen, um den Standortzugriff wieder zu aktivieren.';

  @override
  String get compose_nearby_services_desc =>
      'Aktiviere die Ortungsdienste und aktualisiere Nearby erneut.';

  @override
  String get compose_open_settings => 'Einstellungen öffnen';

  @override
  String get compose_refreshing => 'Wird aktualisiert...';

  @override
  String get compose_refresh_nearby => 'Nähe aktualisieren';

  @override
  String get post_badge_friend => 'Freund';

  @override
  String get post_uploading => 'Medien werden hochgeladen...';

  @override
  String get post_sending => 'Wird gesendet...';

  @override
  String get post_partial => 'Teilweise gesendet';

  @override
  String get post_upload_failed => 'Upload fehlgeschlagen';

  @override
  String get post_send_failed => 'Senden fehlgeschlagen';

  @override
  String get pinned_title => 'Angepinnte Beiträge';

  @override
  String get pinned_count_1 => '1 angepinnter Beitrag';

  @override
  String pinned_count_n(int count) {
    return '$count angepinnte Beiträge';
  }

  @override
  String pinned_see_all(int count) {
    return 'Alle $count angepinnten Beiträge ansehen';
  }

  @override
  String get pinned_dismiss => 'Ausblenden';

  @override
  String pinned_message(String username) {
    return 'Nachricht an $username';
  }

  @override
  String get pinned_edit => 'Bearbeiten';

  @override
  String get pinned_remove => 'Entfernen';

  @override
  String get edit_pinned_hint => 'Deinen Beitrag aktualisieren';

  @override
  String get orbit_view_toggle_to_list => 'Alle Chats anzeigen';

  @override
  String get orbit_view_toggle_to_circle => 'Engsten Kreis anzeigen';

  @override
  String get orbit_inner_circle_empty_hint =>
      'Füge Freunde hinzu, um deinen engsten Kreis zu sehen';

  @override
  String orbit_overflow_badge_open(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count weitere Personen – zum Öffnen tippen',
      one: '1 weitere Person – zum Öffnen tippen',
    );
    return '$_temp0';
  }

  @override
  String get orbit_overflow_badge_collapse => 'Weitere Personen ausblenden';

  @override
  String get orbit_edit_banner => 'ZUM BEENDEN DANEBEN TIPPEN';

  @override
  String get orbit_edit_reset => 'Zurücksetzen';

  @override
  String get orbit_handle_ring_spacing => 'Ringabstand';

  @override
  String get orbit_handle_avatar_size => 'Avatar-Größe';

  @override
  String get orbit_handle_arc_wrap => 'Bogenkrümmung';

  @override
  String get orbit_handle_max_per_arc => 'Max. pro Bogen';

  @override
  String get orbit_handle_orbit_gap => 'Orbit-Abstand';

  @override
  String orbit_edit_step_increase(String name) {
    return '$name erhöhen';
  }

  @override
  String orbit_edit_step_decrease(String name) {
    return '$name verringern';
  }

  @override
  String get orbit_find_placeholder => 'Jemanden finden…';

  @override
  String get orbit_find_pill_semantics => 'Jemanden in deinem Kreis finden';

  @override
  String get orbit_find_close => 'Suche schließen';

  @override
  String get orbit_open_settings => 'Einstellungen öffnen';

  @override
  String get orbit_search_trigger_semantics => 'Chats durchsuchen';

  @override
  String orbit_chip_provenance_ring(int ring) {
    return 'Ring $ring';
  }

  @override
  String orbit_chip_provenance_arc(int arc) {
    return 'Bogen $arc';
  }

  @override
  String orbit_chip_open(String name) {
    return '$name öffnen';
  }

  @override
  String orbit_node_unread_open_chat(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Chat mit $name öffnen, $count ungelesene Nachrichten',
      one: 'Chat mit $name öffnen, 1 ungelesene Nachricht',
    );
    return '$_temp0';
  }

  @override
  String orbit_node_open_group(String name) {
    return 'Gruppe $name öffnen';
  }

  @override
  String orbit_node_unread_open_group(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Gruppe $name öffnen, $count ungelesene Nachrichten',
      one: 'Gruppe $name öffnen, 1 ungelesene Nachricht',
    );
    return '$_temp0';
  }

  @override
  String get orbit_new_group => 'Neue Gruppe';

  @override
  String get orbit_new_announce => 'Neue Ankündigung';

  @override
  String get orbit_my_qr => 'Mein QR';

  @override
  String get orbit_scan => 'Scannen';

  @override
  String get orbit_qr_share => 'Teilen, um Freunde hinzuzufügen';

  @override
  String get orbit_qr_scan_desc => 'Freund sofort hinzufügen';

  @override
  String get orbit_filter_all => 'Alle';

  @override
  String get orbit_filter_intros => 'Vorstellungen';

  @override
  String get orbit_filter_archived => 'Archiviert';

  @override
  String get orbit_search => 'Freunde suchen...';

  @override
  String orbit_block_title(String username) {
    return '$username blockieren?';
  }

  @override
  String get orbit_delete_chat => 'Chat löschen?';

  @override
  String get orbit_leave_group => 'Gruppe verlassen und löschen?';

  @override
  String get orbit_leave_action => 'Verlassen';

  @override
  String get orbit_leave_group_body =>
      'Beim Verlassen werden diese Gruppe und ihr Verlauf von diesem Gerät entfernt. Dies kann nicht rückgängig gemacht werden.';

  @override
  String get orbit_leave_group_action => 'Verlassen & löschen';

  @override
  String get group_exit_only_admin_title => 'Du bist der einzige Admin';

  @override
  String group_exit_only_admin_body(String groupName) {
    return 'Eine Gruppe benötigt mindestens einen Admin, bevor du sie verlassen kannst. Wähle, was mit $groupName geschehen soll.';
  }

  @override
  String get group_exit_choose_admin => 'Anderen Admin auswählen';

  @override
  String get group_exit_choose_admin_body =>
      'Danach kannst du die Gruppe verlassen und von diesem Gerät entfernen.';

  @override
  String get group_exit_dissolve_for_everyone => 'Für alle auflösen';

  @override
  String get group_exit_keep_group => 'Gruppe behalten';

  @override
  String get group_exit_keep_and_close_semantics =>
      'Gruppe behalten und schließen';

  @override
  String get group_exit_no_eligible_successor =>
      'Warte, bis jemand beitritt, oder löse die Gruppe auf.';

  @override
  String get group_exit_choose_member => 'Mitglied auswählen';

  @override
  String get group_exit_continue_to_leave => 'Weiter zum Verlassen';

  @override
  String get group_exit_stay_in_group => 'In der Gruppe bleiben';

  @override
  String get group_exit_admin_sync_pending_title =>
      'Die Admin-Änderung wird noch synchronisiert';

  @override
  String get group_exit_admin_sync_pending_body =>
      'Warte, bis die signierte Admin-Änderung synchronisiert ist, bevor du die Gruppe verlässt.';

  @override
  String get group_exit_sync_finishing_title =>
      'Eine Rollenänderung wird abgeschlossen';

  @override
  String get group_exit_sync_finishing_body =>
      'Du kannst diesen Bildschirm verlassen. Wir verlassen die Gruppe, sobald die Rollenänderung sicher übermittelt wurde.';

  @override
  String get group_exit_leave_when_sync_completes =>
      'Verlassen, sobald die Synchronisierung abgeschlossen ist';

  @override
  String get group_exit_try_again => 'Erneut versuchen';

  @override
  String get group_exit_cancel_queued_leave => 'Geplantes Verlassen abbrechen';

  @override
  String get group_exit_cancel_queued_leave_body =>
      'Dadurch wird das automatische Verlassen abgebrochen. Die Rollenänderung wird weiter synchronisiert.';

  @override
  String get group_exit_leaving_status => 'Wird verlassen…';

  @override
  String get group_exit_leaving_read_only =>
      'Diese Gruppe ist schreibgeschützt, während das Verlassen abgeschlossen wird.';

  @override
  String get group_exit_cancel_too_late =>
      'Das Verlassen wurde bereits gestartet und kann nicht mehr abgebrochen werden.';

  @override
  String get group_exit_leave_uncertain =>
      'Die Anfrage zum Verlassen wurde möglicherweise abgeschlossen. Aktualisiere die Gruppe, bevor du es erneut versuchst.';

  @override
  String get group_exit_cleanup_incomplete =>
      'Du hast die Gruppe verlassen, aber ihr lokaler Verlauf konnte nicht vollständig entfernt werden.';

  @override
  String get group_removed_delete_title =>
      'Diese Gruppe von diesem Gerät löschen?';

  @override
  String get group_removed_delete_body =>
      'Dadurch werden die gespeicherten Nachrichten nur von diesem Gerät gelöscht. Du verlässt die Gruppe nicht und niemand darin wird benachrichtigt.';

  @override
  String get group_removed_delete_action => 'Vom Gerät löschen';

  @override
  String get group_removed_delete_failed =>
      'Die Gruppe konnte nicht von diesem Gerät gelöscht werden. Versuche es erneut.';

  @override
  String get conversation_hint => 'Schreib etwas...';

  @override
  String get conversation_voice_fail =>
      'Sprachnachricht konnte nicht gesendet werden.';

  @override
  String get conversation_voice_limit_reached =>
      'Die Aufnahme hat das 5-Minuten-Limit erreicht.';

  @override
  String conversation_block(String username) {
    return '$username blockieren?';
  }

  @override
  String get conversation_delete_chat => 'Chat löschen?';

  @override
  String get conversation_reply => 'Antworten...';

  @override
  String get conversation_context_reply => 'Antworten';

  @override
  String get announcement_private_reply_action => 'Absender anschreiben';

  @override
  String get announcement_private_reply_unavailable =>
      'Der Absender kann nicht angeschrieben werden.';

  @override
  String get announcement_private_reply_open_failed =>
      'Die Unterhaltung konnte nicht geöffnet werden.';

  @override
  String get conversation_context_edit => 'Bearbeiten';

  @override
  String get conversation_context_copy => 'Kopieren';

  @override
  String get conversation_context_delete => 'Löschen';

  @override
  String get conversation_context_save => 'Speichern';

  @override
  String get conversation_context_share => 'Teilen';

  @override
  String get conversation_context_info => 'Info';

  @override
  String get conversation_context_copied =>
      'Nachricht in die Zwischenablage kopiert';

  @override
  String get conversation_forwarded_marker => 'Weitergeleitet';

  @override
  String get conversation_editing_message => 'Nachricht bearbeiten';

  @override
  String get conversation_cancel_edit => 'Abbrechen';

  @override
  String get conversation_edited_indicator => '(bearbeitet)';

  @override
  String get conversation_delete_message_prompt =>
      'Für wen möchtest du diese Nachricht löschen?';

  @override
  String get conversation_delete_media_message_prompt =>
      'Diese Nachricht löschen? Die Nachricht und alle ihre Anhänge werden von diesem Gerät entfernt.';

  @override
  String get conversation_delete_for_me => 'Für mich löschen';

  @override
  String get conversation_delete_for_everyone => 'Für alle löschen';

  @override
  String get conversation_delete_cancel => 'Abbrechen';

  @override
  String get conversation_message_deleted => 'Diese Nachricht wurde gelöscht';

  @override
  String get conversation_delete_failed =>
      'Diese Nachricht konnte nicht vollständig gelöscht werden.';

  @override
  String get conversation_continue => 'Weiter...';

  @override
  String get conversation_catching_up => 'Wird synchronisiert...';

  @override
  String get comment_hint => 'Schreib einen Kommentar...';

  @override
  String get group_name_optional => 'Gruppenname (optional)';

  @override
  String get group_message_hint => 'Nachricht';

  @override
  String get notification_group_reaction_target_message => 'Nachricht';

  @override
  String get notification_group_reaction_target_photo => 'Foto';

  @override
  String get notification_group_reaction_target_video => 'Video';

  @override
  String get notification_group_reaction_target_voice_message =>
      'Sprachnachricht';

  @override
  String get notification_group_reaction_target_file => 'Datei';

  @override
  String get notification_group_reaction_target_media => 'Medien';

  @override
  String notification_group_reaction_actor(
    String actorName,
    String targetKind,
  ) {
    return '$actorName hat darauf reagiert: $targetKind';
  }

  @override
  String notification_group_reaction_someone(String targetKind) {
    return 'Jemand hat darauf reagiert: $targetKind';
  }

  @override
  String get group_create_failed => 'Gruppe konnte nicht erstellt werden';

  @override
  String get group_invite_failed =>
      'Mitglieder konnten nicht eingeladen werden';

  @override
  String group_create_member_limit_reached(int maxMembers, int overflowCount) {
    return 'Gruppen können bis zu $maxMembers Mitglieder einschließlich dir haben. Verringere deine Auswahl um $overflowCount und versuche es erneut.';
  }

  @override
  String group_invite_member_limit_reached(int maxMembers, int overflowCount) {
    return 'Gruppen können bis zu $maxMembers Mitglieder haben. Verringere deine Auswahl um $overflowCount und versuche es erneut.';
  }

  @override
  String picker_introduce_to(String username) {
    return '$username vorstellen';
  }

  @override
  String get picker_search => 'Freunde suchen...';

  @override
  String get picker_no_friends =>
      'Keine Freunde verfügbar, die du vorstellen kannst';

  @override
  String picker_no_results(String query) {
    return 'Keine Freunde passend zu „$query“';
  }

  @override
  String picker_introduce_count(int count) {
    return 'Vorstellen ($count)';
  }

  @override
  String get picker_introduce => 'Vorstellen';

  @override
  String picker_sending_progress(int completed, int total) {
    return 'Sende $completed von $total';
  }

  @override
  String get picker_search_contacts => 'Kontakte suchen...';

  @override
  String get picker_search_all => 'Kontakte & Gruppen durchsuchen';

  @override
  String get settings_title => 'Einstellungen';

  @override
  String get settings_section_identity => 'IDENTITÄT';

  @override
  String get settings_section_preferences => 'PRÄFERENZEN';

  @override
  String get settings_group_exit_diagnostics_section => 'SUPPORT';

  @override
  String get settings_group_exit_diagnostics_title => 'Gruppenaustrittsverlauf';

  @override
  String settings_group_exit_diagnostics_count(int count) {
    return '$count gespeicherte Einträge';
  }

  @override
  String get settings_group_exit_diagnostics_unavailable =>
      'Der Gruppenaustrittsverlauf ist nicht verfügbar.';

  @override
  String get settings_group_exit_diagnostics_unavailable_hint =>
      'Tippe, um es erneut zu versuchen.';

  @override
  String get settings_group_exit_diagnostics_empty =>
      'Keine gespeicherten Gruppenaustrittseinträge.';

  @override
  String get settings_group_exit_diagnostics_reload => 'Neu laden';

  @override
  String get settings_group_exit_diagnostics_clear => 'Verlauf löschen';

  @override
  String get settings_group_exit_diagnostics_reloaded =>
      'Der Gruppenaustrittsverlauf wurde neu geladen.';

  @override
  String get settings_group_exit_diagnostics_cleared =>
      'Der Gruppenaustrittsverlauf wurde gelöscht.';

  @override
  String get settings_group_exit_diagnostics_reload_failed =>
      'Der Gruppenaustrittsverlauf konnte nicht neu geladen werden. Vorhandene Einträge bleiben unverändert.';

  @override
  String get settings_group_exit_diagnostics_clear_failed =>
      'Der Gruppenaustrittsverlauf konnte nicht gelöscht werden. Vorhandene Einträge bleiben unverändert.';

  @override
  String get settings_group_exit_diagnostics_close =>
      'Gruppenaustrittsverlauf schließen';

  @override
  String settings_group_exit_diagnostics_group_reference(String groupRef) {
    return 'Gruppenreferenz $groupRef';
  }

  @override
  String get settings_group_exit_diagnostic_ex01 =>
      'Die Berechtigung zum Austritt konnte nicht bestätigt werden.';

  @override
  String get settings_group_exit_diagnostic_ex02 =>
      'Aktualisierungen der Mitgliederrollen konnten nicht abgeschlossen werden.';

  @override
  String get settings_group_exit_diagnostic_ex03 =>
      'Die Austrittsmitteilung konnte nicht vorbereitet werden.';

  @override
  String get settings_group_exit_diagnostic_ex04 =>
      'Die Gruppen-Engine ist nicht verfügbar.';

  @override
  String get settings_group_exit_diagnostic_ex05 =>
      'Die Gruppen-Engine hat den Austritt abgelehnt.';

  @override
  String get settings_group_exit_diagnostic_ex06 =>
      'Das Ergebnis des Austritts konnte nicht bestätigt werden.';

  @override
  String get settings_group_exit_diagnostic_ex07 =>
      'Die Gruppe wurde verlassen, aber die lokale Bereinigung ist unvollständig.';

  @override
  String get settings_group_exit_diagnostic_ex08 =>
      'Die Austrittsmitteilung konnte nicht alle Mitglieder erreichen.';

  @override
  String get settings_group_exit_diagnostic_ex09 =>
      'Die Rotation des Gruppenschlüssels wurde aufgeschoben.';

  @override
  String get settings_group_exit_diagnostic_ex10 =>
      'Das lokale Löschen der Gruppe ist unvollständig.';

  @override
  String get settings_group_exit_diagnostic_ex99 =>
      'Beim Gruppenaustritt ist ein unerwartetes Ergebnis aufgetreten.';

  @override
  String get settings_background => 'Hintergrund';

  @override
  String get settings_background_default => 'Standard';

  @override
  String get settings_background_default_desc =>
      'Gespiegelter kosmischer Drift mit weichen Farblichten.';

  @override
  String get settings_background_cosmic => 'Kosmisch';

  @override
  String get settings_background_cosmic_desc =>
      'Ein tiefes Sternenfeld für den Feed.';

  @override
  String get settings_background_cosmic_selected => 'Kosmisch ausgewählt';

  @override
  String get settings_background_aurora => 'Aurora';

  @override
  String get settings_background_aurora_desc =>
      'Das ursprüngliche Umgebungsleuchten.';

  @override
  String get settings_background_aurora_selected => 'Aurora ausgewählt';

  @override
  String get settings_background_daylight_lagoon => 'Signal';

  @override
  String get settings_background_daylight_lagoon_desc =>
      'Ein warmer mineralischer Himmel mit sanftem violettem und salbeigrünem Licht.';

  @override
  String get settings_background_daylight_lagoon_selected =>
      'Signal ausgewählt';

  @override
  String get settings_background_save_fail =>
      'Speichern fehlgeschlagen. Versuch es erneut.';

  @override
  String get settings_background_semantics => 'App-Hintergrundeinstellung';

  @override
  String get settings_background_default_selected => 'Standard ausgewählt';

  @override
  String get settings_video_quality => 'Videoqualität';

  @override
  String get settings_compressed => 'Komprimiert';

  @override
  String get settings_original => 'Original';

  @override
  String get settings_original_desc =>
      'Volle Qualität, größere Datei. Metadaten werden immer entfernt.';

  @override
  String get settings_compressed_desc =>
      'Kleinere Datei, schnelleres Senden. Metadaten werden immer entfernt.';

  @override
  String get settings_photo_fail =>
      'Profilbild konnte nicht hochgeladen werden';

  @override
  String get picker_take_photo => 'Foto aufnehmen';

  @override
  String get picker_gallery => 'Aus Galerie wählen';

  @override
  String get notif_new_intro => 'Neue Vorstellung';

  @override
  String get notif_new_connection => 'Neue Verbindung';

  @override
  String get startup_checking => 'Dein Bereich wird vorbereitet...';

  @override
  String get startup_checking_desc =>
      'Identität und Startzustand werden geprüft';

  @override
  String get startup_feed => 'Feed wird geöffnet...';

  @override
  String get startup_feed_desc => 'Wir wechseln zu deinen Unterhaltungen';

  @override
  String get startup_setup => 'Einrichtung wird geöffnet...';

  @override
  String get startup_setup_desc => 'Dein erster Start wird vorbereitet';

  @override
  String get startup_onboarding => 'Onboarding wird geöffnet...';

  @override
  String get startup_onboarding_desc => 'Wir richten deine Identität ein';

  @override
  String get btn_retry => 'Erneut versuchen';

  @override
  String get btn_cancel => 'Abbrechen';

  @override
  String get btn_submit => 'Absenden';

  @override
  String get error_add_contact =>
      'Kontakt konnte nicht hinzugefügt werden. Bitte versuche es erneut.';

  @override
  String get error_send_message =>
      'Nachricht konnte nicht gesendet werden. Bitte versuche es erneut.';

  @override
  String error_update_photo(String error) {
    return 'Foto konnte nicht aktualisiert werden: $error';
  }

  @override
  String get error_update_username =>
      'Benutzername konnte nicht aktualisiert werden. Bitte versuche es erneut.';

  @override
  String error_generic(String error) {
    return 'Fehler: $error';
  }

  @override
  String get status_processing_video => 'Video wird verarbeitet...';

  @override
  String get perm_camera =>
      'Diese App benötigt Kamerazugriff, um QR-Codes zu scannen und Fotos aufzunehmen';

  @override
  String get perm_photos =>
      'Diese App benötigt Zugriff auf deine Fotomediathek, um Bilder zu teilen';

  @override
  String get perm_microphone =>
      'Diese App benötigt Mikrofonzugriff, um Sprachnachrichten aufzunehmen';

  @override
  String get perm_location =>
      'Diese App benötigt Standortzugriff, damit du Beiträge mit direkten Freunden in deiner Nähe teilen kannst';

  @override
  String get perm_local_network =>
      'mknoon sucht deine Freunde im selben WLAN, um Nachrichten direkt an ihr Handy zu senden. Das ist schneller, privater und wir sammeln niemals deine Daten.';

  @override
  String get perm_notifications =>
      'Diese App benötigt Mitteilungszugriff, um dich über eingehende Nachrichten zu informieren';

  @override
  String connected_date(String date) {
    return 'Verbunden am $date';
  }

  @override
  String get date_today => 'Heute';

  @override
  String get date_yesterday => 'Gestern';

  @override
  String get feed_collapse => 'Einklappen';

  @override
  String get feed_tap_expand => 'Zum Öffnen tippen';

  @override
  String get feed_you => 'Du';

  @override
  String get settings_photo_quality => 'Fotoqualität';

  @override
  String get settings_share_nearby => 'Mit Leuten in der Nähe teilen';

  @override
  String get settings_share_nearby_on => 'An';

  @override
  String get settings_share_nearby_off => 'Aus';

  @override
  String get settings_share_nearby_desc =>
      'Teilt nur einen ungefähren Standort mit direkten Freunden. Keine Live-Karte und nie mit Fremden.';

  @override
  String get settings_move_account_title => 'Konto auf neues Handy umziehen';

  @override
  String get settings_recovery_title => 'WIEDERHERSTELLUNGSPHRASE';

  @override
  String get settings_recovery_warning =>
      'Teile diese Phrase niemals mit jemandem. Sie gewährt vollen Zugriff auf dein Konto.';

  @override
  String get settings_recovery_tap => 'Zum Anzeigen tippen';

  @override
  String get settings_recovery_copied => 'Kopiert!';

  @override
  String get settings_recovery_copy => 'In die Zwischenablage kopieren';

  @override
  String get settings_recovery_hide => 'Verbergen';

  @override
  String get connected_title => 'Verbunden!';

  @override
  String get send_message => 'Nachricht senden';

  @override
  String introduced_by(String username) {
    return 'Vorgestellt von $username';
  }

  @override
  String get load_retry_hint =>
      'Prüfe deine Verbindung und versuche es erneut.';

  @override
  String get upload_leave_title => 'Unterhaltung verlassen?';

  @override
  String get upload_leave_body =>
      'Ein Upload läuft gerade. Wenn du gehst, kann er unterbrochen werden. Bist du sicher?';

  @override
  String get upload_leave_stay => 'Bleiben';

  @override
  String get upload_leave_confirm => 'Verlassen';

  @override
  String get upload_cancelled => 'Upload abgebrochen.';

  @override
  String get media_too_large_title => 'Medien zu groß';

  @override
  String media_too_large_prompt(String totalSize, String limitSize) {
    return 'Die angehängten Medien sind $totalSize groß und überschreiten das Limit von $limitSize. Möchtest du sie komprimieren und senden oder abbrechen?';
  }

  @override
  String get media_compress => 'Komprimieren';

  @override
  String get media_too_large_after_compress =>
      'Die Medien sind auch nach der Komprimierung zu groß.';

  @override
  String get media_gif_too_large =>
      'GIF-Dateien größer als 25 MB können nicht hinzugefügt werden.';

  @override
  String get media_too_large_chip => 'Zu groß';

  @override
  String get media_gif_too_large_chip => 'GIF zu groß';

  @override
  String get media_attachments_too_large_note =>
      'Anhänge zu groß – entfernen Sie einige zum Senden.';

  @override
  String get media_unavailable => 'Medien nicht verfügbar';

  @override
  String get media_could_not_verify =>
      'Diese Medien konnten nicht verifiziert werden';

  @override
  String get settings_media_storage => 'Medien & Speicher';

  @override
  String get settings_media_auto_download => 'Automatische Downloads';

  @override
  String get settings_media_auto_download_desc =>
      'Wähle, welche empfangenen Medien in jedem Netz automatisch geladen werden.';

  @override
  String get settings_media_lane_direct => 'Direktchats';

  @override
  String get settings_media_lane_discussions => 'Diskussionen';

  @override
  String get settings_media_lane_announcements => 'Ankündigungen';

  @override
  String get settings_media_type_image => 'Fotos';

  @override
  String get settings_media_type_video => 'Videos';

  @override
  String get settings_media_type_audio => 'Audio';

  @override
  String get settings_media_type_file => 'Dateien';

  @override
  String get settings_media_network_off => 'Aus';

  @override
  String get settings_media_network_wifi => 'WLAN';

  @override
  String get settings_media_network_all => 'WLAN + Mobilfunk';

  @override
  String get settings_media_save_fail =>
      'Speichern fehlgeschlagen. Versuch es erneut.';

  @override
  String get settings_media_storage_usage => 'Speichernutzung';

  @override
  String get settings_media_storage_compute => 'Nutzung anzeigen';

  @override
  String get settings_media_storage_clear_type => 'Leeren';

  @override
  String get settings_media_storage_empty =>
      'Keine heruntergeladenen Medienkopien';

  @override
  String get media_local_copy_removed => 'Lokale Kopie entfernt';

  @override
  String get media_retry_unavailable => 'Nicht verfügbare Medien erneut laden';

  @override
  String get edit_save_failed => 'Änderung konnte nicht gespeichert werden.';

  @override
  String get sending_taking_longer => 'Senden dauert länger…';

  @override
  String get intro_pass => 'Weitergeben';

  @override
  String get intro_accept => 'Annehmen';

  @override
  String get intro_accepting => 'Wird angenommen...';

  @override
  String get failed_message_retry_semantics =>
      'Fehlgeschlagene Nachricht erneut senden';

  @override
  String get failed_media_retry_semantics =>
      'Fehlgeschlagene Mediennachricht erneut senden';

  @override
  String get failed_media_delete_semantics =>
      'Fehlgeschlagene Mediennachricht löschen';

  @override
  String message_status_semantics(String status) {
    return 'Nachrichtenstatus: $status';
  }

  @override
  String get message_status_delivered => 'zugestellt';

  @override
  String get message_status_failed => 'fehlgeschlagen';

  @override
  String get message_status_sending => 'wird gesendet';

  @override
  String get message_status_sent => 'gesendet';

  @override
  String get message_status_pending_inbox =>
      'ausstehende Zustellung über Posteingang';

  @override
  String get message_status_inbox => 'im Posteingang zugestellt';

  @override
  String get message_sent_via_relay => 'Über Mobilfunk-Relay gesendet';

  @override
  String get message_sent_via_direct => 'Über Direktverbindung gesendet';

  @override
  String get message_sent_via_wifi => 'Über WLAN gesendet';

  @override
  String get message_sent_via_inbox => 'An Posteingang gesendet';

  @override
  String get message_received_via_relay => 'Über Mobilfunk-Relay empfangen';

  @override
  String get message_received_via_direct => 'Über Direktverbindung empfangen';

  @override
  String get message_received_via_wifi => 'Über WLAN empfangen';

  @override
  String get message_received_via_inbox => 'Über Posteingang empfangen';

  @override
  String get message_sent_via_upgraded => 'Auf Direktverbindung hochgestuft';

  @override
  String get message_received_via_upgraded =>
      'Über hochgestufte Direktverbindung empfangen';

  @override
  String get share_send_failed =>
      'Konnte nicht an die ausgewählten Ziele teilen.';

  @override
  String get group_info_title => 'Gruppeninfo';

  @override
  String get group_edit_details => 'Details bearbeiten';

  @override
  String group_member_count(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Mitglieder',
      one: '1 Mitglied',
    );
    return '$_temp0';
  }

  @override
  String get group_security_title => 'Sicherheit';

  @override
  String get group_security_key_change_visible => 'Schlüsseländerung sichtbar';

  @override
  String get group_security_verification_warning => 'Verifizierungswarnung';

  @override
  String group_security_identity_warning_detail(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count Identitäten haben sich geändert. Prüfe die Sicherheitsnummern unten.',
      one: '1 Identität hat sich geändert. Prüfe die Sicherheitsnummern unten.',
    );
    return '$_temp0';
  }

  @override
  String get group_dissolved => 'Gruppe aufgelöst';

  @override
  String get group_dissolved_read_only_desc =>
      'Diese Unterhaltung ist jetzt schreibgeschützt. Frühere Nachrichten bleiben als Referenz verfügbar.';

  @override
  String get group_mute_notifications => 'Mitteilungen stummschalten';

  @override
  String get group_mute_on_desc =>
      'Neue Nachrichten kommen weiterhin an, aber diese Gruppe bleibt stumm.';

  @override
  String get group_mute_off_desc =>
      'Du wirst benachrichtigt, wenn neue Nachrichten in dieser Gruppe ankommen.';

  @override
  String get group_members_title => 'Mitglieder';

  @override
  String get group_add_member => 'Mitglied hinzufügen';

  @override
  String get group_leave => 'Gruppe verlassen';

  @override
  String get group_dissolve => 'Gruppe auflösen';

  @override
  String get group_delete_from_device => 'Von diesem Gerät löschen';

  @override
  String get group_delete_local_desc =>
      'Behalte diesen aufgelösten Verlauf so lange du möchtest oder entferne ihn nur von diesem Gerät. Das betrifft niemand anderen.';

  @override
  String get group_delete_locally => 'Gruppe lokal löschen';

  @override
  String get group_no_messages => 'Noch keine Nachrichten';

  @override
  String get group_empty_dissolved_desc =>
      'Diese Gruppe wurde aufgelöst. Neue Nachrichten sind deaktiviert.';

  @override
  String get group_empty_start =>
      'Sende eine Nachricht, um die Unterhaltung zu starten';

  @override
  String get group_empty_waiting => 'Warte auf Nachrichten';

  @override
  String get group_recovery_banner =>
      'Verpasste Nachrichten werden nachgeholt. Neue Nachrichten erscheinen weiterhin hier.';

  @override
  String get group_read_only_dissolved =>
      'Diese Gruppe wurde aufgelöst. Der Verlauf bleibt verfügbar, aber neue Nachrichten sind deaktiviert.';

  @override
  String get group_read_only_admin_only =>
      'Nur Admins können in dieser Gruppe Nachrichten senden';

  @override
  String get group_read_only_unavailable =>
      'Diese Gruppe ist nicht mehr verfügbar.';

  @override
  String get group_send_failed_dissolved =>
      'Senden fehlgeschlagen — diese Gruppe wurde aufgelöst';

  @override
  String get group_send_failed_removed =>
      'Senden fehlgeschlagen — du bist nicht mehr in dieser Gruppe';

  @override
  String get group_send_failed_unavailable =>
      'Senden fehlgeschlagen — diese Gruppe ist nicht verfügbar';

  @override
  String get group_removed_snackbar => 'Du wurdest aus dieser Gruppe entfernt.';

  @override
  String get group_dissolved_snackbar => 'Diese Gruppe wurde aufgelöst';

  @override
  String get group_info_mute_update_failed =>
      'Stummschaltung konnte nicht aktualisiert werden';

  @override
  String get group_info_dissolve_title => 'Diese Gruppe für alle auflösen?';

  @override
  String get group_info_dissolve_body =>
      'Damit endet die Gruppe für alle Mitglieder. Der Verlauf bleibt sichtbar, aber nach der Auflösung kann niemand mehr neue Nachrichten senden.';

  @override
  String get group_info_dissolve_action => 'Auflösen';

  @override
  String get group_info_dissolved_recovery =>
      'Gruppe aufgelöst. Einige Mitglieder müssen sie möglicherweise wiederherstellen, um das zu sehen.';

  @override
  String get group_info_already_dissolved => 'Gruppe ist bereits aufgelöst';

  @override
  String get group_info_admins_only_dissolve =>
      'Nur Admins können Gruppen auflösen';

  @override
  String get group_info_not_found => 'Gruppe existiert nicht mehr';

  @override
  String get group_info_dissolve_failed =>
      'Gruppe konnte nicht aufgelöst werden';

  @override
  String get group_info_delete_local_title =>
      'Diese aufgelöste Gruppe von diesem Gerät löschen?';

  @override
  String get group_info_delete_local_body =>
      'Dadurch wird der aufgelöste Verlauf nur von diesem Gerät entfernt. Andere Personen sind nicht betroffen und es wird kein neues Verlassen-Ereignis gesendet.';

  @override
  String get group_info_delete_local_action => 'Lokal löschen';

  @override
  String group_info_remove_member_title(String username) {
    return '$username aus der Gruppe entfernen?';
  }

  @override
  String get group_info_remove_member_body =>
      'Diese Person erhält keine neuen Nachrichten aus dieser Gruppe mehr.';

  @override
  String get group_info_remove_action => 'Entfernen';

  @override
  String group_info_revoke_invite_title(String username) {
    return 'Einladung für $username zurückziehen?';
  }

  @override
  String get group_info_revoke_invite_body =>
      'Sie können der Gruppe mit dieser Einladung nicht mehr beitreten.';

  @override
  String get group_info_revoke_invite_action => 'Zurückziehen';

  @override
  String get group_info_member_fallback => 'Mitglied';

  @override
  String group_info_make_admin_title(String username) {
    return '$username zum Admin machen?';
  }

  @override
  String group_info_remove_admin_title(String username) {
    return 'Admin-Zugriff von $username entfernen?';
  }

  @override
  String get group_info_make_admin_body =>
      'Diese Person kann Mitglieder hinzufügen, entfernen und verwalten.';

  @override
  String get group_info_remove_admin_body =>
      'Diese Person verliert Admin-Aktionen, sobald die Änderung synchronisiert ist.';

  @override
  String get group_info_make_admin_action => 'Zum Admin machen';

  @override
  String get group_info_remove_admin_action => 'Admin entfernen';

  @override
  String group_info_admin_added(String username) {
    return '$username ist jetzt Admin';
  }

  @override
  String group_info_admin_removed(String username) {
    return '$username ist nicht mehr Admin';
  }

  @override
  String get group_info_member_role_update_failed =>
      'Mitgliedsrolle konnte nicht aktualisiert werden';

  @override
  String get group_info_details_updated => 'Gruppendetails aktualisiert';

  @override
  String get group_info_details_update_failed =>
      'Gruppendetails konnten nicht aktualisiert werden';

  @override
  String get group_info_details_update_queued =>
      'Gespeichert – erneuter Sendeversuch bei erneuter Verbindung';

  @override
  String get group_info_invite_resend_failed =>
      'Einladung konnte nicht erneut gesendet werden';

  @override
  String group_info_invite_revoked(String username) {
    return 'Einladung an $username widerrufen';
  }

  @override
  String get group_info_invite_revoke_failed =>
      'Einladung konnte nicht widerrufen werden';

  @override
  String group_info_invite_sent(String username) {
    return 'Einladung an $username gesendet';
  }

  @override
  String group_info_invite_queued(String username) {
    return 'Einladung liegt im Posteingang von $username';
  }

  @override
  String get group_info_invite_needs_resend =>
      'Einladung muss noch einmal gesendet werden';

  @override
  String group_info_invite_joined(String username) {
    return '$username ist bereits beigetreten';
  }

  @override
  String get group_info_invite_unknown => 'Einladungsstatus unbekannt';

  @override
  String get group_edit_photo_pick_failed =>
      'Gruppenfoto konnte nicht ausgewählt werden';

  @override
  String get group_edit_details_title => 'Gruppendetails bearbeiten';

  @override
  String get group_edit_change_photo => 'Foto ändern';

  @override
  String get group_edit_add_photo => 'Foto hinzufügen';

  @override
  String get group_edit_remove_photo => 'Foto entfernen';

  @override
  String get group_edit_name => 'Gruppenname';

  @override
  String get group_edit_description => 'Beschreibung';

  @override
  String get group_edit_recovery_waiting =>
      'Bitte warten, während dieses Gerät aufholt.';

  @override
  String group_edit_recovery_waiting_elapsed(int seconds) {
    return 'Wartet seit $seconds s';
  }

  @override
  String get btn_save => 'Speichern';

  @override
  String get group_member_sending => 'Wird gesendet...';

  @override
  String get group_member_resend => 'Erneut senden';

  @override
  String get group_member_revoke => 'Widerrufen';

  @override
  String get group_member_revoking => 'Wird widerrufen...';

  @override
  String get group_member_manage_role => 'Rolle verwalten';

  @override
  String get group_role_admin => 'Admin';

  @override
  String get group_role_writer => 'Schreibberechtigt';

  @override
  String get group_role_reader => 'Lesend';

  @override
  String get group_identity_changed => 'Identität geändert';

  @override
  String get group_current_safety => 'Aktuelle Sicherheit';

  @override
  String get group_saved_safety => 'Gespeicherte Sicherheit';

  @override
  String get group_security_encrypted => 'Ende-zu-Ende verschlüsselt';

  @override
  String get group_security_pending => 'Verschlüsselung ausstehend';

  @override
  String get group_security_no_key => 'Kein Gruppenschlüssel auf diesem Gerät';

  @override
  String group_security_key_changed(int keyEpoch) {
    return 'Gruppenschlüssel auf Epoche $keyEpoch geändert';
  }

  @override
  String group_security_current_key_epoch(int keyEpoch) {
    return 'Aktuelle Schlüsselepoche $keyEpoch';
  }

  @override
  String get group_security_no_members => 'Keine Mitglieder zum Verifizieren';

  @override
  String group_security_all_members_verified(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Alle $count Mitglieder verifiziert',
      one: '1 Mitglied verifiziert',
    );
    return '$_temp0';
  }

  @override
  String group_security_members_verified(int verifiedCount, int memberCount) {
    return '$verifiedCount von $memberCount Mitgliedern verifiziert';
  }

  @override
  String group_security_members_need_review(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Mitglieder benötigen eine Verifizierungsprüfung',
      one: '1 Mitglied benötigt eine Verifizierungsprüfung',
    );
    return '$_temp0';
  }

  @override
  String group_security_members_unverified(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count Mitglieder nicht anhand gespeicherter Kontakte verifiziert',
      one: '1 Mitglied nicht anhand gespeicherter Kontakte verifiziert',
    );
    return '$_temp0';
  }

  @override
  String get group_security_no_warnings => 'Keine Verifizierungswarnungen';

  @override
  String group_security_compact_encrypted_epoch(int keyEpoch) {
    return 'Verschlüsselt - Schlüsselepoche $keyEpoch';
  }

  @override
  String get invite_status_sent => 'Einladung gesendet';

  @override
  String get invite_status_queued => 'Im Posteingang';

  @override
  String get invite_status_needs_resend => 'Erneutes Senden nötig';

  @override
  String get invite_status_cannot_send => 'Senden nicht möglich';

  @override
  String get invite_status_joined => 'Beigetreten';

  @override
  String get invite_status_revoked => 'Widerrufen';

  @override
  String get invite_status_declined => 'Abgelehnt';

  @override
  String get invite_status_unknown => 'Einladung unbekannt';

  @override
  String get invite_cannot_send_missing_secure_key_detail =>
      'Uns fehlen die sicheren Informationen, um diesen Freund einzuladen. Bitte ihn, die App zu öffnen oder neu zu installieren, und versuche es erneut.';

  @override
  String get invite_cannot_send_group_key_missing_detail =>
      'Dieser Gruppe fehlt der sichere Einladungsschlüssel. Öffne die App erneut und versuche es noch einmal.';

  @override
  String get invite_cannot_send_invalid_payload_detail =>
      'Diese Einladung konnte nicht vorbereitet werden. Öffne die App erneut und versuche es noch einmal.';

  @override
  String get invite_cannot_send_generic_detail =>
      'Wir konnten keine sichere Einladung für diesen Freund vorbereiten. Er muss möglicherweise die App öffnen oder neu installieren, bevor du ihn einladen kannst.';

  @override
  String get invite_cannot_send_missing_secure_key_snackbar =>
      'Senden nicht möglich: Uns fehlen die sicheren Informationen, um diesen Freund einzuladen.';

  @override
  String get invite_cannot_send_group_key_missing_snackbar =>
      'Senden nicht möglich: Dieser Gruppe fehlt der sichere Einladungsschlüssel.';

  @override
  String get invite_cannot_send_invalid_payload_snackbar =>
      'Senden nicht möglich: Diese Einladung konnte nicht vorbereitet werden.';

  @override
  String get invite_cannot_send_generic_snackbar =>
      'Senden nicht möglich: Wir konnten keine sichere Einladung für diesen Freund vorbereiten.';

  @override
  String group_backlog_mixed_banner(int days) {
    return 'Ältere verpasste Nachrichten sind nach $days Tagen abgelaufen. Aktuelle Nachrichten wurden wiederhergestellt.';
  }

  @override
  String get group_backlog_mixed_empty_title =>
      'Aktuelle Nachrichten wiederhergestellt';

  @override
  String group_backlog_mixed_empty_subtitle(int days) {
    return 'Ältere verpasste Nachrichten sind nach $days Tagen während deiner Abwesenheit abgelaufen.';
  }

  @override
  String group_backlog_expired_banner(int days) {
    return 'Verpasste Nachrichten, die älter als $days Tage sind, sind während deiner Abwesenheit abgelaufen.';
  }

  @override
  String get group_backlog_expired_empty_title =>
      'Älterer Rückstand abgelaufen';

  @override
  String group_backlog_expired_empty_subtitle(int days) {
    return 'Verpasste Nachrichten, die älter als $days Tage sind, sind während deiner Abwesenheit abgelaufen.';
  }

  @override
  String get group_history_repair_active_banner =>
      'Einige verpasste Nachrichten werden von vertrauenswürdigen Gruppenmitgliedern repariert.';

  @override
  String get group_history_repair_active_empty_title =>
      'Verpasste Nachrichten werden repariert';

  @override
  String get group_history_repair_active_empty_subtitle =>
      'Einige verpasste Nachrichten werden verifiziert, bevor sie hier erscheinen.';

  @override
  String get group_history_repair_failed_banner =>
      'Einige verpasste Nachrichten konnten nicht von vertrauenswürdigen Gruppenmitgliedern repariert werden.';

  @override
  String get group_history_repair_failed_empty_title =>
      'Verlaufsreparatur nötig';

  @override
  String get group_history_repair_failed_empty_subtitle =>
      'Einige verpasste Nachrichten konnten nicht von vertrauenswürdigen Mitgliedern verifiziert werden.';

  @override
  String get group_history_repair_done_banner =>
      'Verpasste Nachrichten wurden repariert und verifiziert.';

  @override
  String get group_history_repair_done_empty_title => 'Nachrichten repariert';

  @override
  String get group_history_repair_done_empty_subtitle =>
      'Verpasste Nachrichten wurden verifiziert und wiederhergestellt.';

  @override
  String get group_info_leave_failed => 'Gruppe konnte nicht verlassen werden';

  @override
  String get group_info_notifications_muted =>
      'Mitteilungen für diese Gruppe stummgeschaltet';

  @override
  String get group_info_notifications_restored =>
      'Mitteilungen für diese Gruppe wieder aktiviert';

  @override
  String get group_notification_catching_up =>
      'Diese Gruppe wird noch synchronisiert – versuche es gleich erneut.';

  @override
  String get restore_groups_device_local_notice =>
      'Deine Gruppen erscheinen wieder, sobald dieses Gerät erneut zugelassen wird. Gruppenverlauf aus der Zeit vor diesem Gerät kann nicht wiederhergestellt werden.';

  @override
  String get group_info_delete_local_failed =>
      'Gruppe konnte lokal nicht gelöscht werden';

  @override
  String get group_info_publish_member_removal_failed =>
      'Entfernen des Mitglieds konnte nicht veröffentlicht werden';

  @override
  String get group_info_rotate_key_failed =>
      'Gruppenschlüssel konnte nach dem Entfernen nicht rotiert werden';

  @override
  String get group_info_remove_member_partial_distribution =>
      'Mitglied entfernt. Einige Mitglieder erhalten den neuen Schlüssel, sobald sie wieder verbunden sind.';

  @override
  String get group_info_remove_member_failed =>
      'Mitglied konnte nicht entfernt werden';

  @override
  String get group_info_no_identity => 'Keine Identität gefunden';

  @override
  String get group_info_member_not_found => 'Mitglied nicht gefunden';

  @override
  String get group_info_upload_photo_failed =>
      'Gruppenfoto konnte nicht hochgeladen werden';

  @override
  String get group_info_sign_metadata_failed =>
      'Aktualisierung der Gruppendaten konnte nicht signiert werden';

  @override
  String get group_type_discussion => 'Diskussion';

  @override
  String get group_type_announce => 'Ankündigung';

  @override
  String get group_type_qa => 'Fragen';

  @override
  String get group_dissolved_badge => 'Aufgelöst';

  @override
  String get pending_invite_expired => 'Abgelaufen';

  @override
  String get pending_invite_accept => 'Annehmen';

  @override
  String get pending_invite_decline => 'Ablehnen';

  @override
  String get pending_invite_dismiss => 'Ausblenden';

  @override
  String pending_invite_invited_by(String username) {
    return 'Eingeladen von $username';
  }

  @override
  String pending_invite_expires(String date) {
    return 'Läuft ab $date';
  }

  @override
  String get group_no_contacts_available => 'Keine Kontakte verfügbar';

  @override
  String get settings_intro_debug_delete_row => 'Zeile löschen';

  @override
  String get settings_intro_debug_delete_pair => 'Paar löschen';

  @override
  String get settings_intro_debug_deleted_row =>
      'Lokale Einführungszeile gelöscht';

  @override
  String settings_intro_debug_deleted_pair(String pairLabel) {
    return 'Lokales Paar $pairLabel gelöscht';
  }

  @override
  String get settings_intro_debug_heading => 'DEBUG-EINFÜHRUNGEN';

  @override
  String get settings_intro_debug_description =>
      'Lokal gesendete Einführungszeilen auf diesem Gerät. Wenn du ein Paar löschst, ist es in der Auswahl wieder verfügbar.';

  @override
  String get settings_intro_debug_empty =>
      'Keine lokalen Einführungszeilen für den aktuellen Benutzer.';

  @override
  String settings_intro_debug_status_line(
    String status,
    String recipientStatus,
    String introducedStatus,
  ) {
    return 'Status=$status  Empfänger=$recipientStatus  Vorgestellt=$introducedStatus';
  }

  @override
  String settings_intro_debug_meta_line(String id, String createdAt) {
    return 'ID=$id  erstellt=$createdAt';
  }

  @override
  String get group_start_chat => 'Gruppenchat starten';

  @override
  String get group_reactions_title => 'Reaktionen';

  @override
  String group_add_members_count(int count) {
    return 'Mitglieder hinzufügen ($count)';
  }

  @override
  String get group_loading_contacts => 'Kontakte werden geladen...';

  @override
  String get group_send_invites => 'Einladungen senden';

  @override
  String get group_send_permission_lost =>
      'Du hast keine Berechtigung mehr, Nachrichten in dieser Gruppe zu senden.';

  @override
  String get group_unavailable_snackbar =>
      'Diese Gruppe ist nicht mehr verfügbar.';

  @override
  String get media_retry_unavailable_now =>
      'Erneut versuchen ist gerade nicht verfügbar.';

  @override
  String get media_unavailable_now => 'Medien sind gerade nicht verfügbar.';

  @override
  String get media_still_unavailable =>
      'Medien sind weiterhin nicht verfügbar.';

  @override
  String get failed_media_retry_failed =>
      'Mediennachricht konnte nicht erneut versucht werden.';

  @override
  String get failed_message_retry_failed =>
      'Nachricht konnte nicht erneut versucht werden.';

  @override
  String get failed_media_upload_pending_retry =>
      'Medienupload wird noch abgeschlossen. Er wird bald erneut versucht.';

  @override
  String get failed_media_delete_unavailable =>
      'Löschen ist gerade nicht verfügbar.';

  @override
  String get picker_media_library => 'Medienbibliothek';

  @override
  String get picker_record_video => 'Video aufnehmen';

  @override
  String get perm_microphone_record =>
      'Die Mikrofonberechtigung ist erforderlich, um Sprachnachrichten aufzunehmen.';

  @override
  String get mic_perm_dialog_title => 'Mikrofonzugriff erlauben';

  @override
  String get mic_perm_dialog_body =>
      'Um Sprachnachrichten aufzunehmen, aktiviere ihn in den Einstellungen deines Telefons.';

  @override
  String get mic_perm_not_now => 'Nicht jetzt';

  @override
  String get group_read_only_not_active =>
      'Du wurdest aus dieser Gruppe entfernt. Du kannst frühere Nachrichten weiterhin lesen.';

  @override
  String get group_read_only_waiting_key =>
      'Warte auf den aktuellen Gruppenschlüssel, bevor du senden kannst.';

  @override
  String get group_read_only_waiting_identity =>
      'Warte auf deine Identität, bevor du senden kannst.';

  @override
  String get group_media_unsupported =>
      'Dieser Medientyp wird in Gruppen nicht unterstützt.';

  @override
  String get upload_progress_title => 'Medien werden hochgeladen';

  @override
  String get upload_progress_keep_open =>
      'Lass die App geöffnet, bis der Upload abgeschlossen ist';

  @override
  String get conversation_blocked_contact =>
      'Du hast diesen Kontakt blockiert.';

  @override
  String get conversation_unblock => 'Entsperren';

  @override
  String conversation_undelivered_banner(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Nachrichten konnten nicht angezeigt werden',
      one: '1 Nachricht konnte nicht angezeigt werden',
    );
    return '$_temp0';
  }

  @override
  String get conversation_undelivered_retry => 'Erneut versuchen';

  @override
  String get conversation_empty_first_letter =>
      'Schreib den ersten Brief,\num eure Unterhaltung zu beginnen';

  @override
  String get media_video_load_failed => 'Video konnte nicht geladen werden';

  @override
  String get media_viewer_action_save => 'Speichern';

  @override
  String get media_viewer_action_save_image => 'Bild speichern';

  @override
  String get media_viewer_more_actions => 'Weitere Aktionen';

  @override
  String get media_viewer_action_share => 'Teilen';

  @override
  String get media_viewer_action_forward => 'Weiterleiten';

  @override
  String get media_viewer_action_delete => 'Löschen';

  @override
  String get media_viewer_action_bookmark => 'Lesezeichen';

  @override
  String get media_viewer_action_info => 'Info';

  @override
  String get media_viewer_action_reply => 'Antworten';

  @override
  String get media_viewer_action_picture_in_picture => 'Bild-in-Bild';

  @override
  String get media_viewer_picture_in_picture_start_failed =>
      'Bild-in-Bild konnte nicht gestartet werden';

  @override
  String get media_save_destination_prompt => 'Speichern in …';

  @override
  String get media_save_destination_photos => 'In Fotos speichern';

  @override
  String get media_save_destination_files => 'In Dateien speichern';

  @override
  String get media_egress_result_saved => 'Gespeichert';

  @override
  String get media_egress_result_shared => 'Geteilt';

  @override
  String get media_egress_result_cancelled => 'Abgebrochen';

  @override
  String get media_egress_result_permission_denied =>
      'Berechtigung erforderlich, um diese Aktion abzuschließen';

  @override
  String get media_egress_result_missing =>
      'Diese Mediendatei fehlt auf diesem Gerät';

  @override
  String get media_egress_result_failed =>
      'Aktion konnte nicht abgeschlossen werden';

  @override
  String get media_egress_result_unavailable =>
      'Diese Medien stehen zum Speichern oder Teilen nicht mehr zur Verfügung';

  @override
  String get media_info_title => 'Medieninfo';

  @override
  String get media_info_sender => 'Von';

  @override
  String get media_info_direction => 'Richtung';

  @override
  String get media_info_direction_incoming => 'Empfangen';

  @override
  String get media_info_direction_outgoing => 'Gesendet';

  @override
  String get media_info_date => 'Datum';

  @override
  String get media_info_type => 'Typ';

  @override
  String get media_info_size => 'Größe';

  @override
  String get media_info_dimensions => 'Abmessungen';

  @override
  String get media_info_duration => 'Dauer';

  @override
  String get media_info_state => 'Status';

  @override
  String get media_info_state_downloaded => 'Heruntergeladen';

  @override
  String get media_info_state_not_downloaded => 'Nicht heruntergeladen';

  @override
  String get media_info_state_unverified => 'Konnte nicht überprüft werden';

  @override
  String get group_media_info_title => 'Medieninfo';

  @override
  String get group_media_info_kind => 'Typ';

  @override
  String get group_media_info_kind_image => 'Bild';

  @override
  String get group_media_info_kind_video => 'Video';

  @override
  String get group_media_info_sender => 'Von';

  @override
  String get group_media_info_sent_time => 'Gesendet';

  @override
  String get group_media_info_size => 'Größe';

  @override
  String get group_media_info_state => 'Status';

  @override
  String get group_media_info_caption => 'Bildunterschrift';

  @override
  String get group_media_info_state_available =>
      'Heruntergeladen und verifiziert';

  @override
  String get group_media_info_state_pending => 'Noch nicht heruntergeladen';

  @override
  String get group_media_info_state_unavailable => 'Nicht verfügbar';

  @override
  String get group_media_delete_for_me_title => 'Für mich löschen?';

  @override
  String get group_media_delete_for_me_body =>
      'Dies entfernt die Nachricht und ihre Medien nur von diesem Gerät. Andere Mitglieder behalten ihre Kopie.';

  @override
  String get group_media_delete_for_me_confirm => 'Für mich löschen';

  @override
  String get group_media_delete_for_me_cancel => 'Abbrechen';

  @override
  String get group_media_saved_confirm => 'Gespeichert';

  @override
  String get media_viewer_play => 'Abspielen';

  @override
  String get media_viewer_pause => 'Pause';

  @override
  String get media_viewer_skip_back => '10 Sekunden zurück';

  @override
  String get media_viewer_skip_forward => '10 Sekunden vor';

  @override
  String get media_viewer_mute => 'Stummschalten';

  @override
  String get media_viewer_unmute => 'Ton ein';

  @override
  String get conversation_introduce_to_circle => 'Deinem Kreis vorstellen';

  @override
  String get conversation_shared_media => 'Geteilte Medien';

  @override
  String get shared_media_title => 'Geteilte Medien';

  @override
  String get shared_media_filter_all => 'Alle';

  @override
  String get shared_media_filter_photos => 'Fotos';

  @override
  String get shared_media_filter_videos => 'Videos';

  @override
  String get shared_media_filter_bookmarked => 'Gemerkt';

  @override
  String get shared_media_empty => 'Noch keine geteilten Medien';

  @override
  String get shared_media_load_failed =>
      'Geteilte Medien konnten nicht geladen werden';

  @override
  String get shared_media_kind_photo => 'Foto';

  @override
  String get shared_media_kind_video => 'Video';

  @override
  String get shared_media_state_missing => 'Datei fehlt';

  @override
  String get shared_media_state_evicted => 'Lokale Kopie entfernt';

  @override
  String get shared_media_state_not_downloaded => 'Nicht heruntergeladen';

  @override
  String get shared_media_state_unverified => 'Konnte nicht überprüft werden';

  @override
  String shared_media_selection_count(int count) {
    return '$count ausgewählt';
  }

  @override
  String shared_media_selection_limit(int max) {
    return 'Du kannst bis zu $max Elemente auswählen';
  }

  @override
  String get shared_media_action_save => 'Speichern';

  @override
  String get shared_media_action_share => 'Teilen';

  @override
  String get shared_media_action_delete => 'Löschen';

  @override
  String get shared_media_action_go_to_message => 'Zur Nachricht';

  @override
  String shared_media_delete_title(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Nachrichten',
      one: '1 Nachricht',
    );
    return '$_temp0 löschen?';
  }

  @override
  String get shared_media_delete_body =>
      'Dies entfernt die gesamte Nachricht jedes ausgewählten Elements, einschließlich aller Anhänge, nur von diesem Gerät. Außerhalb dieser App gespeicherte oder geteilte Kopien sind nicht betroffen.';

  @override
  String get shared_media_delete_confirm => 'Für mich löschen';

  @override
  String get shared_media_delete_cancel => 'Abbrechen';

  @override
  String shared_media_batch_partial_failure(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Elemente konnten',
      one: '1 Element konnte',
    );
    return '$_temp0 nicht abgeschlossen werden und bleiben ausgewählt';
  }

  @override
  String get shared_media_go_to_message_missing =>
      'Diese Nachricht ist nicht mehr in der Unterhaltung';

  @override
  String get shared_media_bookmark_add => 'Merken';

  @override
  String get shared_media_bookmark_remove => 'Merken aufheben';

  @override
  String conversation_block_contact(String username) {
    return '$username blockieren';
  }

  @override
  String conversation_unblock_contact(String username) {
    return '$username entsperren';
  }

  @override
  String get conversation_delete_chat_action => 'Chat löschen';

  @override
  String get post_pass_along_title => 'Weitergeben';

  @override
  String get post_pass_along_desc =>
      'Wähle aus, wer diese Weitergabe über einen Hop erhalten soll.';

  @override
  String get post_pass_along_no_eligible =>
      'Aktuell sind keine berechtigten Freunde verfügbar.';

  @override
  String comments_count(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Kommentare',
      one: '1 Kommentar',
      zero: 'Keine Kommentare',
    );
    return '$_temp0';
  }

  @override
  String get comments_empty => 'Noch keine Kommentare';

  @override
  String get edit_pinned_post_title => 'Angepinnten Beitrag bearbeiten';

  @override
  String post_passed_along_by(String username) {
    return '$username hat dies weitergegeben';
  }

  @override
  String get home_empty_circle_title =>
      'Dein Kreis wartet darauf, gefüllt zu werden';

  @override
  String get home_empty_circle_desc =>
      'Scanne den Code eines Freundes oder teile deinen, um dich zu verbinden';

  @override
  String get home_scan_friend_title => 'Code eines Freundes scannen';

  @override
  String get home_scan_friend_desc => 'Füge jemanden zu deinem Kreis hinzu';

  @override
  String get contact_request_message => 'möchte sich mit dir verbinden';

  @override
  String get contact_request_decline => 'Ablehnen';

  @override
  String get share_caption => 'Beschriftung';

  @override
  String share_title_count(int count) {
    return 'Teilen mit ($count)';
  }

  @override
  String get share_title_empty => 'Teilen mit...';

  @override
  String get share_no_targets => 'Noch keine Kontakte oder Gruppen';

  @override
  String get share_no_matches => 'Keine Treffer gefunden';

  @override
  String get share_contacts_section => 'Kontakte';

  @override
  String get share_groups_section => 'Gruppen';

  @override
  String get share_group_type_announcement => 'Ankündigung';

  @override
  String get share_group_type_chat => 'Chat';

  @override
  String get share_sending => 'Wird gesendet...';

  @override
  String get share_send => 'Senden';

  @override
  String share_target_count(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Ziele',
      one: '1 Ziel',
    );
    return '$_temp0';
  }

  @override
  String share_summary_sent(String targetCount) {
    return 'Gesendet an $targetCount';
  }

  @override
  String share_summary_queued(String targetCount) {
    return '$targetCount für erneuten Versuch gespeichert';
  }

  @override
  String share_summary_failed(String targetCount) {
    return 'fehlgeschlagen für $targetCount';
  }

  @override
  String get share_summary_nothing => 'Es wurde nichts geteilt.';

  @override
  String share_summary_skipped_gifs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count zu große Anhänge übersprungen.',
      one: '1 zu großen Anhang übersprungen.',
    );
    return '$_temp0';
  }

  @override
  String get time_just_now => 'gerade eben';

  @override
  String time_min_ago(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'vor $count Min.',
      one: 'vor 1 Min.',
    );
    return '$_temp0';
  }

  @override
  String time_hour_ago(int count) {
    return 'vor $count Std.';
  }

  @override
  String time_day_ago(int count) {
    return 'vor $count T.';
  }

  @override
  String time_week_ago(int count) {
    return 'vor $count Wo.';
  }

  @override
  String get post_expired => 'Abgelaufen';

  @override
  String post_expires_days_hours(int days, int hours) {
    return 'Läuft in $days T. $hours Std. ab';
  }

  @override
  String post_expires_days(int days) {
    return 'Läuft in $days T. ab';
  }

  @override
  String post_expires_hours(int hours) {
    return 'Läuft in $hours Std. ab';
  }

  @override
  String post_expires_minutes(int minutes) {
    return 'Läuft in $minutes Min. ab';
  }

  @override
  String get post_expires_soon => 'Läuft bald ab';

  @override
  String get post_photo_upload_failed => 'Foto-Upload fehlgeschlagen';

  @override
  String get post_photo_pending_upload => 'Foto wartet auf Upload';

  @override
  String get post_photos_pending_upload => 'Fotos warten auf Upload';

  @override
  String get post_video_upload_failed => 'Video-Upload fehlgeschlagen';

  @override
  String get post_video_pending_upload => 'Video wartet auf Upload';

  @override
  String get post_voice_upload_failed => 'Sprach-Upload fehlgeschlagen';

  @override
  String get post_voice_pending_upload => 'Sprachnotiz wartet auf Upload';

  @override
  String get post_media_upload_failed => 'Medien-Upload fehlgeschlagen';

  @override
  String get post_media_pending_upload => 'Medien warten auf Upload';

  @override
  String get post_media_upload_failed_desc =>
      'Dieser Beitrag blieb lokal, weil der Medien-Upload nicht abgeschlossen wurde.';

  @override
  String get post_media_pending_upload_desc =>
      'Empfänger erhalten dies, sobald der Upload abgeschlossen ist.';

  @override
  String get post_send_pass => 'Weitergabe senden';

  @override
  String get btn_saving => 'Wird gespeichert...';

  @override
  String get intro_from => 'Von';

  @override
  String get intro_empty => 'Noch keine Einführungen';

  @override
  String get intro_tab_desc =>
      'Das sind Menschen, die deine Freunde gut kennen. Sobald ihr beide annehmt, könnt ihr chatten.';

  @override
  String intro_banner_title(String username) {
    return 'Hilf $username, deinen Kreis kennenzulernen';
  }

  @override
  String get intro_banner_desc =>
      'Stelle diese Person Freunden vor, mit denen es passen könnte';

  @override
  String get intro_make_introductions => 'Einführungen machen';

  @override
  String get intro_maybe_later => 'Vielleicht später';

  @override
  String get introduced_by_label => 'Vorgestellt von';

  @override
  String get intro_unavailable => 'Nicht verfügbar';

  @override
  String intro_waiting_for(String username) {
    return 'Warte auf $username';
  }

  @override
  String get intro_waiting_for_them => 'Warte auf die andere Person';

  @override
  String intro_sent_count(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Einführungen gesendet',
      one: '1 Einführung gesendet',
    );
    return '$_temp0';
  }

  @override
  String get intro_back_to_conversation => 'Zurück zur Unterhaltung';

  @override
  String get identity_tagline => 'Deine Identität, deine Kontrolle';

  @override
  String get startup_failed_title => 'Initialisierung fehlgeschlagen';

  @override
  String get identity_restore_action => 'Identität wiederherstellen';

  @override
  String get settings_peer_id_title => 'PEER-ID';

  @override
  String intro_and_more(String names, int count) {
    return '$names und $count weitere';
  }

  @override
  String get orbit_block_action => 'Blockieren';

  @override
  String get orbit_unblock_action => 'Entsperren';

  @override
  String get orbit_delete_action => 'Löschen';

  @override
  String get orbit_archive_action => 'Archivieren';

  @override
  String get orbit_unarchive_action => 'Aus Archiv holen';

  @override
  String get orbit_archived_empty_title => 'Noch keine archivierten Freunde';

  @override
  String get orbit_archived_empty_desc =>
      'Wische bei einem Freund nach links, um ihn zu archivieren.';

  @override
  String get orbit_inner_circle_badge => 'Innerer Kreis';

  @override
  String orbit_pending_items(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Elemente ausstehend',
      one: '1 Element ausstehend',
    );
    return '$_temp0';
  }

  @override
  String get orbit_pending_group_invites => 'Ausstehende Gruppeneinladungen';

  @override
  String get orbit_pending_group_intro_desc =>
      'Prüfe hier ausstehende Gruppeneinladungen und dann die Einführungen darunter. Nach dem Annehmen erscheint die Gruppe in Orbit und holt Nachrichten aus dem Offline-Postfach nach.';

  @override
  String orbit_no_friends_matching(String query) {
    return 'Keine Freunde passend zu \"$query\"';
  }

  @override
  String get feed_blocked => 'Blockiert';

  @override
  String feed_introduced_by(String username) {
    return 'Vorgestellt von $username';
  }

  @override
  String get feed_replying_to => 'Antwort auf';

  @override
  String feed_ready_for_user(String username) {
    return 'Dein Feed ist bereit, @$username. Neue Verbindungen erscheinen hier.';
  }

  @override
  String get feed_all_caught_up => 'Du bist auf dem neuesten Stand';

  @override
  String get feed_loading => 'Feed wird geladen...';

  @override
  String get feed_syncing_threads =>
      'Deine letzten Threads werden noch synchronisiert.';

  @override
  String feed_reply_to_name(String name) {
    return 'Antworte an $name…';
  }

  @override
  String feed_message_name(String name) {
    return 'Nachricht an $name…';
  }

  @override
  String get feed_add_another => 'Weitere senden…';

  @override
  String get feed_open_full_conversation => 'Vollständige Unterhaltung öffnen';

  @override
  String get feed_tap_to_retry => 'zum Wiederholen tippen';

  @override
  String feed_removed_undo(String name) {
    return '$name entfernt';
  }

  @override
  String get feed_undo => 'Rückgängig';

  @override
  String get feed_tap_to_say_hi => 'tippen, um Hallo zu sagen';

  @override
  String get feed_connected => 'Verbunden';

  @override
  String get qr_added_to_circle => 'Zu deinem Kreis hinzugefügt!';

  @override
  String get btn_ok => 'OK';

  @override
  String get qr_already_in_circle => 'Bereits in deinem Kreis!';

  @override
  String get qr_contact_added_previously =>
      'Dieser Kontakt wurde schon hinzugefügt';

  @override
  String get btn_got_it => 'Verstanden';

  @override
  String orbit_intro_banner_mixed(int inviteCount, int introCount) {
    String _temp0 = intl.Intl.pluralLogic(
      inviteCount,
      locale: localeName,
      other: '$inviteCount Gruppeneinladungen',
      one: '1 Gruppeneinladung',
    );
    String _temp1 = intl.Intl.pluralLogic(
      introCount,
      locale: localeName,
      other: '$introCount Einführungen',
      one: '1 Einführung',
    );
    return '$_temp0 und $_temp1 warten';
  }

  @override
  String orbit_intro_banner_invites(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Gruppeneinladungen prüfen und über Intros beitreten',
      one: 'Gruppeneinladung prüfen und über Intros beitreten',
    );
    return '$_temp0';
  }

  @override
  String get orbit_intro_banner_intros =>
      'Prüfe und akzeptiere Einführungen, um zu chatten';

  @override
  String orbit_intro_dock_label(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count neu',
      one: '1 neu',
    );
    return '$_temp0';
  }

  @override
  String orbit_intro_dock_semantics(int count) {
    return 'Überprüfung der Einführungen öffnen, $count neu';
  }

  @override
  String get orbit_intro_remnant_semantics =>
      'Überprüfung der Einführungen öffnen';

  @override
  String group_member_invited_count(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Mitglieder eingeladen',
      one: 'Mitglied eingeladen',
    );
    return '$_temp0';
  }

  @override
  String group_member_added_count(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Mitglieder hinzugefügt',
      one: '1 Mitglied hinzugefügt',
    );
    return '$_temp0';
  }

  @override
  String get group_invite_missing_key_issue =>
      'Einladungen wurden nicht gesendet, weil der Gruppe der neueste Schlüssel fehlt';

  @override
  String group_invite_issues(String details) {
    return 'Einladungsprobleme: $details';
  }

  @override
  String get group_members_publish_failed_issue =>
      'Das Ereignis zum Hinzufügen von Mitgliedern konnte nicht veröffentlicht werden';

  @override
  String group_member_added_with_warnings(String prefix, String issues) {
    return '$prefix, aber $issues.';
  }

  @override
  String get group_invite_no_longer_available =>
      'Einladung nicht mehr verfügbar';

  @override
  String get group_invite_expired => 'Einladung abgelaufen';

  @override
  String get group_invite_expired_ask_resend =>
      'Diese Einladung ist abgelaufen. Bitte den Gruppen-Admin um eine neue.';

  @override
  String get group_joining_in_progress => 'Beitreten…';

  @override
  String get group_join_failed_retry =>
      'Beitritt fehlgeschlagen — erneut versuchen';

  @override
  String get group_invite_revoked => 'Einladung wurde widerrufen';

  @override
  String get group_invite_already_used => 'Einladung bereits verwendet';

  @override
  String get group_invite_wrong_identity =>
      'Einladung gehört zu einer anderen Identität';

  @override
  String get group_invite_needs_key =>
      'Einladung benötigt frisches Schlüsselmaterial';

  @override
  String get group_invite_waiting_for_key => 'Warte auf Schlüssel';

  @override
  String get group_invite_invalid => 'Einladung ist nicht mehr gültig';

  @override
  String get group_invite_duplicate_group => 'Gruppe bereits hinzugefügt';

  @override
  String get group_invite_accepted_recovery =>
      'Einladung angenommen, aber die Wiederherstellung holt noch auf';

  @override
  String get group_invite_accept_failed =>
      'Einladung konnte nicht angenommen werden';

  @override
  String get group_invite_declined => 'Einladung abgelehnt';

  @override
  String get group_invite_decline_failed =>
      'Einladung konnte nicht abgelehnt werden';

  @override
  String get post_pin_retrying => 'Pin-Aktualisierung wird weiter versucht';

  @override
  String get post_pin_queued =>
      'Pin-Aktualisierung zum erneuten Versuch eingereiht';

  @override
  String get post_pin_failed => 'Pin-Aktualisierung fehlgeschlagen';

  @override
  String get post_pin_could_not => 'Beitrag konnte nicht angepinnt werden';

  @override
  String get post_pinned_update_retrying =>
      'Aktualisierung des angepinnten Beitrags wird weiter versucht';

  @override
  String get post_pinned_update_queued =>
      'Aktualisierung des angepinnten Beitrags zum erneuten Versuch eingereiht';

  @override
  String get post_pinned_update_failed =>
      'Aktualisierung des angepinnten Beitrags fehlgeschlagen';

  @override
  String get post_pinned_update_could_not =>
      'Angepinnter Beitrag konnte nicht aktualisiert werden';

  @override
  String get post_pin_removal_retrying =>
      'Entfernen des Pins wird weiter versucht';

  @override
  String get post_pin_removal_queued =>
      'Entfernen des Pins zum erneuten Versuch eingereiht';

  @override
  String get post_pin_removal_failed => 'Entfernen des Pins fehlgeschlagen';

  @override
  String get post_pin_remove_could_not => 'Pin konnte nicht entfernt werden';

  @override
  String get post_repost_retrying => 'Repost wird weiter versucht';

  @override
  String get post_repost_queued => 'Repost zum erneuten Versuch eingereiht';

  @override
  String get post_repost_media_failed =>
      'Repost-Medien konnten nicht vorbereitet werden';

  @override
  String get post_repost_could_not => 'Repost konnte nicht vorbereitet werden';

  @override
  String get post_no_longer_available => 'Beitrag ist nicht mehr verfügbar';

  @override
  String get post_repost_not_allowed =>
      'Dieser Beitrag kann nicht erneut gepostet werden';

  @override
  String get identity_generate_failed =>
      'Identität konnte nicht erstellt werden';

  @override
  String get identity_save_failed =>
      'Identität konnte nicht gespeichert werden';

  @override
  String get qr_no_identity_detail =>
      'Keine Identität gefunden. Bitte erstelle zuerst eine.';

  @override
  String get qr_sign_failed =>
      'QR-Code konnte nicht signiert werden. Bitte versuche es erneut.';

  @override
  String get qr_unexpected_error =>
      'Ein unerwarteter Fehler ist aufgetreten. Bitte versuche es erneut.';

  @override
  String get qr_invalid_title => 'Ungültiger QR-Code';

  @override
  String get qr_invalid_body =>
      'Das sieht nicht wie ein gültiger Kontakt-QR-Code aus.';

  @override
  String get qr_incomplete_title => 'Unvollständiger QR-Code';

  @override
  String get qr_incomplete_body =>
      'Diesem QR-Code fehlen erforderliche Informationen.';

  @override
  String get qr_invalid_signature_title => 'Ungültige Signatur';

  @override
  String get qr_invalid_signature_body =>
      'Dieser QR-Code konnte nicht verifiziert werden.';

  @override
  String get qr_expired_title => 'QR-Code abgelaufen';

  @override
  String get qr_expired_body =>
      'Dieser QR-Code ist abgelaufen. Bitte deinen Freund um einen neuen.';

  @override
  String get qr_self_title => 'Das bist du!';

  @override
  String get qr_self_body =>
      'Du kannst dich nicht selbst als Kontakt hinzufügen.';

  @override
  String get qr_add_failed =>
      'Kontakt konnte nicht hinzugefügt werden. Bitte versuche es erneut.';

  @override
  String sibling_device_new_device_title(String member) {
    return 'Neues Gerät für $member';
  }

  @override
  String get sibling_device_verify_prompt =>
      'Ein neues Gerät möchte diesem Konto beitreten. Überprüfe, ob die Sicherheitsnummer mit dem neuen Gerät übereinstimmt, bevor du es genehmigst.';

  @override
  String get sibling_device_reject => 'Ablehnen';

  @override
  String get sibling_device_verify_approve => 'Überprüfen & genehmigen';

  @override
  String get contact_profile_linked_devices => 'Verknüpfte Geräte';

  @override
  String get contact_profile_linked_device_revoke => 'Widerrufen';

  @override
  String get contact_profile_linked_device_verify => 'Überprüfen';

  @override
  String get linked_device_setup_title => 'Dieses Gerät verknüpfen';

  @override
  String get linked_device_setup_recovery_phrase_instruction =>
      'Gib die aus 12 Wörtern bestehende Wiederherstellungsphrase des Kontos ein, dem dieses Smartphone als zusätzliches Gerät beitreten soll.';

  @override
  String get linked_group_status_title => 'Gruppen (schreibgeschützt)';

  @override
  String get linked_group_status_refresh => 'Gruppenstatus aktualisieren';

  @override
  String get linked_group_status_waiting =>
      'Warten auf eine Gruppeneinrichtung von deinem primären Gerät.';

  @override
  String get group_info_link_device_action =>
      'Diese Gruppe mit einem anderen Gerät verknüpfen';

  @override
  String get linked_group_confirm_title => 'Diese Gruppe verknüpfen?';

  @override
  String linked_group_confirm_body(String groupName) {
    return '„$groupName“ mit dem gescannten verknüpften Gerät teilen. Keine anderen Gruppen oder Unterhaltungen werden geteilt.';
  }

  @override
  String get linked_group_confirm_action => 'Gruppe verknüpfen';

  @override
  String get linked_device_media_unavailable =>
      'Medien sind auf diesem verknüpften Gerät noch nicht verfügbar';

  @override
  String get linked_device_voice_unavailable =>
      'Sprachnachrichten sind auf diesem verknüpften Gerät noch nicht verfügbar';

  @override
  String get transport_diagnostics_title => 'TRANSPORT-DIAGNOSE (SITZUNG)';

  @override
  String get transport_diagnostics_census =>
      'Sitzungsbezogene, rein aggregierte Transportübersicht. Keine Kennungen verlassen das Gerät.';

  @override
  String get transport_diagnostics_lan_discovery => 'Erkennung';

  @override
  String get transport_diagnostics_lan_peers => 'Peers';

  @override
  String get transport_diagnostics_lan_permission => 'Berechtigung';

  @override
  String get transport_diagnostics_refresh => 'Aktualisieren';

  @override
  String get account_migration_back => 'Zurück';

  @override
  String get account_migration_qr_heading => 'Konto-Umzugs-QR';

  @override
  String get account_migration_qr_confirm_label =>
      'Bestätige diesen Code nach dem Scannen';

  @override
  String account_migration_qr_expires_at(String time) {
    return 'Läuft ab um $time';
  }

  @override
  String get account_migration_scan_action => 'Umzugs-QR scannen';

  @override
  String get account_migration_start_transfer => 'Übertragung starten';

  @override
  String get account_migration_cancel_transfer => 'Übertragung abbrechen';

  @override
  String get account_migration_retry => 'Erneut versuchen';

  @override
  String get account_migration_erase_confirm_title => 'Dieses Gerät löschen?';

  @override
  String get account_migration_erase_confirm_body =>
      'Dies löscht nur die lokalen Kontodaten auf diesem Telefon, nachdem das Konto umgezogen ist. Es wird nichts zurückbewegt.';

  @override
  String get account_migration_cancel => 'Abbrechen';

  @override
  String get account_migration_erase_local_data => 'Lokale Daten löschen';

  @override
  String get account_migration_erased_snackbar => 'Lokale Kontodaten gelöscht';

  @override
  String account_migration_erase_failed(String error) {
    return 'Lokale Kontodaten konnten nicht gelöscht werden: $error';
  }

  @override
  String get account_migration_blocked_title =>
      'Konto auf ein anderes Telefon umgezogen';

  @override
  String get account_migration_blocked_message =>
      'Dieses Telefon ist nach der Migration für das Öffnen des Kontos gesperrt. Lösche die lokale Kopie erst, wenn du sicher bist, dass das neue Telefon funktioniert.';

  @override
  String get account_migration_unfinished_move_title =>
      'Kontoumzug nicht abgeschlossen';

  @override
  String get account_migration_unfinished_move_message =>
      'Dieses Telefon hat dein Konto importiert, aber die endgültige Übergabe mit dem alten Telefon wurde nicht abgeschlossen. Behalte beide Telefone und lösche keine der beiden Kopien.';

  @override
  String get contact_profile_verified_peer => 'Verifizierter Kontakt';

  @override
  String get contact_profile_blocked => 'Blockiert';

  @override
  String get contact_profile_archived => 'Archiviert';

  @override
  String get contact_profile_peer_id_label => 'Peer-ID';

  @override
  String get contact_profile_peer_id_copied => 'Peer-ID kopiert';

  @override
  String get contact_profile_tap_to_copy => 'Zum Kopieren tippen';

  @override
  String get contact_profile_safety_number_label => 'Sicherheitsnummer';

  @override
  String get contact_profile_safety_number_hint =>
      'Vergleiche diese Nummer persönlich, um zu bestätigen, dass deine Verbindung sicher ist.';

  @override
  String get contact_profile_copied => 'In die Zwischenablage kopiert';

  @override
  String get contact_profile_connected_since_label => 'Verbunden seit';

  @override
  String get contact_profile_introduced_by_label => 'Vorgestellt von';

  @override
  String get contact_profile_message_button => 'Nachricht';

  @override
  String get private_media_selector_label => 'Private Medien';

  @override
  String get private_media_ordinary => 'Im Chat behalten';

  @override
  String get private_media_protected => 'Geschützte Ansicht';

  @override
  String get private_media_ordinary_detail =>
      'Kann gespeichert oder geteilt werden.';

  @override
  String get private_media_protected_detail =>
      'Kann erneut angesehen, aber nicht gespeichert oder geteilt werden.';

  @override
  String get private_media_view_once => 'Einmal ansehen';

  @override
  String get private_media_disappearing_1h => 'Verschwindet nach 1 Stunde';

  @override
  String get private_media_disappearing_1d => 'Verschwindet nach 1 Tag';

  @override
  String get private_media_disappearing_7d => 'Verschwindet nach 7 Tagen';

  @override
  String get private_media_invalid_shape =>
      'Private Medien benötigen ein Foto oder Video ohne Bildunterschrift.';

  @override
  String get private_media_notification_body => 'Private Medien';

  @override
  String get group_private_media_notification_body => 'Neue private Medien';

  @override
  String get private_media_expiry_device_local =>
      'Wird nach dieser Zeit von ihrem Gerät gelöscht.';

  @override
  String get private_media_view_once_copy =>
      'Verschwindet, nachdem es einmal geöffnet wurde.';

  @override
  String private_media_protected_body_received(String name) {
    return 'Du kannst es erneut ansehen. $name erlaubt kein Speichern oder Teilen.';
  }

  @override
  String private_media_protected_body_received_compact(String name) {
    return '$name erlaubt kein Speichern oder Teilen.';
  }

  @override
  String get private_media_view_once_body_received =>
      'Du kannst dies nur einmal ansehen.';

  @override
  String private_media_outgoing_body(String name) {
    return 'Nur $name kann es ansehen und weder speichern noch teilen.';
  }

  @override
  String get private_media_open => 'Private Medien öffnen';

  @override
  String get private_media_opening => 'Private Medien werden geöffnet…';

  @override
  String get private_media_consumed => 'Auf diesem Gerät bereits angesehen';

  @override
  String get private_media_expired => 'Auf diesem Gerät abgelaufen';

  @override
  String get private_media_unsupported =>
      'Aktualisiere Mknoon, um diese privaten Medien anzusehen, oder lösche sie';

  @override
  String get private_media_android_capture_limit =>
      'Screenshots und Bildschirmaufnahmen werden nur blockiert, solange diese private Ansicht geöffnet ist';

  @override
  String get private_media_ios_capture_limit =>
      'iOS kann Screenshots nicht zuverlässig verhindern; Aufnahmen werden erkannt und private Medien werden verdeckt bzw. geschlossen';

  @override
  String get private_media_ios_image_capture_limit =>
      'Dieses geschützte Bild wird in Screenshots und Bildschirmaufnahmen ausgeblendet, solange es geöffnet ist.';

  @override
  String get private_media_general_capture_limit =>
      'Ein anderes Gerät oder eine Kamera kann den Bildschirm weiterhin fotografieren';

  @override
  String private_media_sheet_title_photo(String name) {
    return 'Wie soll $name dieses Foto sehen?';
  }

  @override
  String private_media_sheet_title_video(String name) {
    return 'Wie soll $name dieses Video sehen?';
  }

  @override
  String private_media_sheet_title_gif(String name) {
    return 'Wie soll $name dieses GIF sehen?';
  }

  @override
  String get group_private_media_sheet_title =>
      'Wie sollen Mitglieder dieses Foto sehen?';

  @override
  String get private_media_set_expiry => 'Ablaufzeit festlegen';

  @override
  String private_media_expiry_choose_detail(String name) {
    return 'Verschwindet nach einer von dir gewählten Zeit von ${name}s Gerät.';
  }

  @override
  String get private_media_delete_after => 'Löschen nach';

  @override
  String get private_media_duration_1h => '1 Stunde';

  @override
  String get private_media_duration_1d => '1 Tag';

  @override
  String get private_media_duration_7d => '7 Tage';

  @override
  String private_media_use_mode_cta(String mode) {
    return '$mode verwenden';
  }

  @override
  String get private_media_summary_change => 'Ändern';

  @override
  String get private_media_summary_ordinary_detail =>
      'Normales Foto · kann gespeichert oder geteilt werden';

  @override
  String get private_media_summary_protected_detail =>
      'Erneut ansehbar · kein Speichern oder Teilen';

  @override
  String private_media_summary_view_once_detail(String name) {
    return 'Eine Ansicht für $name';
  }

  @override
  String private_media_summary_expiry_detail(String duration) {
    return 'Kein Speichern oder Teilen · wird nach $duration gelöscht';
  }

  @override
  String private_media_disclosure_protected(String name) {
    return 'Nur $name kann die Datei öffnen. Speichern und Teilen sind deaktiviert.';
  }

  @override
  String private_media_disclosure_view_once(String name) {
    return '$name kann die Datei einmal öffnen, danach ist sie weg. Speichern und Teilen sind deaktiviert.';
  }

  @override
  String private_media_disclosure_expiry(String name) {
    return 'Nur $name kann die Datei bis zum Ablauf öffnen. Speichern und Teilen sind deaktiviert.';
  }

  @override
  String get private_media_disclosure_reopen =>
      'Du kannst sie nach dem Senden hier noch einmal öffnen.';

  @override
  String get private_media_disclosure_reopen_protected =>
      'Du kannst sie hier jederzeit erneut öffnen.';

  @override
  String get private_media_card_title_protected_photo => 'Geschütztes Foto';

  @override
  String get private_media_card_title_protected_video => 'Geschütztes Video';

  @override
  String get private_media_card_title_view_once_photo => 'Einmal-Foto';

  @override
  String get private_media_card_title_view_once_video => 'Einmal-Video';

  @override
  String private_media_card_title_expiry_photo(String duration) {
    return 'Foto · verschwindet nach $duration';
  }

  @override
  String private_media_card_title_expiry_video(String duration) {
    return 'Video · verschwindet nach $duration';
  }

  @override
  String get private_media_open_photo => 'Foto öffnen';

  @override
  String get private_media_open_video => 'Video öffnen';

  @override
  String get private_media_view_photo => 'Foto ansehen';

  @override
  String get private_media_view_video => 'Video ansehen';

  @override
  String get private_media_sender_consumed =>
      'Du hast deinen einen zusätzlichen Blick genutzt';

  @override
  String get offline_send_promise =>
      'Wird gesendet, sobald du wieder online bist';

  @override
  String get offline_retry_delayed =>
      'Zustellung verzögert — erneuter Versuch läuft automatisch';

  @override
  String get share_stored_offline_promise =>
      'Gespeichert — wird gesendet, sobald du wieder online bist.';

  @override
  String get offline_banner_title => 'Du bist offline';

  @override
  String get offline_banner_body =>
      'Nachrichten und Medien werden gesendet, sobald du wieder online bist.';

  @override
  String get media_sending_automatically => 'Wird automatisch gesendet…';

  @override
  String media_uploading_percent(int percent) {
    return 'Foto wird hochgeladen · $percent%';
  }

  @override
  String get media_uploading => 'Foto wird hochgeladen…';

  @override
  String get media_view_once_not_viewed => 'Noch nicht angesehen.';

  @override
  String get media_missing_terminal_title_photo =>
      'Das Foto ist nicht mehr auf diesem Gerät';

  @override
  String get media_missing_terminal_title_video =>
      'Das Video ist nicht mehr auf diesem Gerät';

  @override
  String get media_missing_terminal_body =>
      'Wähle es erneut aus, um es zu senden.';

  @override
  String get media_remove => 'Entfernen';

  @override
  String get private_media_open_failed_title_photo =>
      'Dieses Foto konnte nicht geöffnet werden';

  @override
  String get private_media_open_failed_title_video =>
      'Dieses Video konnte nicht geöffnet werden';

  @override
  String get private_media_open_failed_view_safe =>
      'Deine einmalige Ansicht ist noch verfügbar.';

  @override
  String get private_media_open_failed_reopen_safe =>
      'Dein einer zusätzlicher Blick ist noch verfügbar.';

  @override
  String get private_media_sender_local_missing_body =>
      'Deine gesendeten Medien können auf diesem Gerät nicht erneut geöffnet werden.';

  @override
  String get private_media_try_again => 'Erneut versuchen';

  @override
  String get group_invite_ask_new => 'Um eine neue Einladung bitten';

  @override
  String group_invite_request_new_draft(String groupName) {
    return 'Kannst du mir eine neue Einladung zu $groupName senden?';
  }

  @override
  String get group_invite_contact_unavailable =>
      'Dieser Kontakt ist nicht mehr verfügbar.';

  @override
  String get shared_media_action_forward => 'Mehrfach weiterleiten';

  @override
  String get direct_batch_forward_title => 'Mehrfach weiterleiten';

  @override
  String direct_batch_forward_item_count(int count) {
    return '$count ausgewählte Elemente';
  }

  @override
  String direct_batch_forward_source_label(int index, int count) {
    return 'Quelle $index von $count';
  }

  @override
  String direct_batch_forward_caption_label(int index, int count) {
    return 'Bildunterschrift für Quelle $index von $count';
  }

  @override
  String get direct_batch_forward_contacts_title => 'Direkte Kontakte';

  @override
  String get direct_batch_forward_no_contacts =>
      'Keine aktiven direkten Kontakte';

  @override
  String get direct_batch_forward_send => 'Senden';

  @override
  String get direct_batch_forward_retry_failed =>
      'Fehlgeschlagene erneut versuchen';

  @override
  String direct_batch_forward_progress(String phase, int completed, int total) {
    return '$phase: $completed von $total';
  }

  @override
  String get direct_batch_forward_source_unavailable =>
      'Die ausgewählten Medien sind nicht mehr verfügbar';

  @override
  String get direct_batch_forward_status_sent => 'Gesendet';

  @override
  String get direct_batch_forward_status_queued => 'Warteschlange';

  @override
  String get direct_batch_forward_status_failed => 'Fehlgeschlagen';

  @override
  String direct_batch_forward_summary(int sent, int queued, int failed) {
    return 'Gesendet $sent, Warteschlange $queued, fehlgeschlagen $failed';
  }

  @override
  String get direct_batch_forward_phase_uploading => 'Wird hochgeladen';

  @override
  String get direct_batch_forward_phase_sending => 'Wird gesendet';

  @override
  String get direct_batch_forward_close => 'Schließen';

  @override
  String get push_registration_health_warning_title =>
      'Benachrichtigungen prüfen';

  @override
  String get push_registration_health_permission_denied =>
      'Benachrichtigungen für Mknoon sind auf diesem Gerät deaktiviert.';

  @override
  String get push_registration_health_no_token =>
      'Dieses Gerät hat noch kein Benachrichtigungs-Token erhalten.';

  @override
  String get push_registration_health_registration_failed =>
      'Mknoon konnte dieses Gerät nicht für Benachrichtigungen registrieren.';

  @override
  String get push_registration_health_temporary_problem =>
      'Beim Einrichten der Benachrichtigungen ist ein vorübergehendes Problem aufgetreten.';

  @override
  String get push_registration_health_retry => 'Erneut versuchen';

  @override
  String get push_registration_health_open_notification_settings =>
      'Benachrichtigungseinstellungen öffnen';

  @override
  String get call_row_voice_call => 'Sprachanruf';

  @override
  String get call_row_missed => 'Verpasster Sprachanruf';

  @override
  String get call_row_no_answer => 'Keine Antwort';

  @override
  String get call_row_you_declined => 'Du hast abgelehnt';

  @override
  String get call_row_declined => 'Anruf abgelehnt';

  @override
  String get call_row_busy => 'Kontakt war besetzt';

  @override
  String get call_row_cancelled => 'Abgebrochen';

  @override
  String get call_row_failed => 'Anruf fehlgeschlagen';

  @override
  String call_row_with_duration(String label, String duration) {
    return '$label · $duration';
  }

  @override
  String get missed_call_notification_unknown_caller => 'Jemand';

  @override
  String get call_ended => 'Anruf beendet';

  @override
  String get call_dismiss_status => 'Anrufstatus schließen';

  @override
  String get call_cancel => 'Anruf abbrechen';

  @override
  String get call_answer => 'Annehmen';

  @override
  String get call_answer_unavailable => 'Annehmen nicht verfügbar';

  @override
  String get call_decline_unavailable => 'Ablehnen nicht verfügbar';

  @override
  String get call_controls => 'Anrufsteuerung';

  @override
  String call_audio_output(String route) {
    return 'Audioausgabe: $route';
  }

  @override
  String get call_speaker => 'Lautsprecher';

  @override
  String get call_speaker_off => 'Lautsprecher ausschalten';

  @override
  String get call_end => 'Anruf beenden';

  @override
  String get call_end_action => 'Beenden';

  @override
  String get call_audio_route_system_default => 'Systemstandard';

  @override
  String get call_audio_route_earpiece => 'Hörmuschel';

  @override
  String get call_audio_route_wired_headset => 'Kabelgebundenes Headset';

  @override
  String get call_audio_route_bluetooth => 'Bluetooth';

  @override
  String get settings_diagnostics_section => 'SUPPORT';

  @override
  String get settings_call_diagnostics_title => 'Anrufdiagnose';

  @override
  String get settings_call_diagnostics_switch => 'Anrufdiagnosedaten teilen';

  @override
  String get settings_call_diagnostics_summary =>
      'Hilf dabei, erfolgreiche und fehlgeschlagene Anrufe zu untersuchen. Wenn die Funktion aktiviert ist, werden Berichte automatisch gesendet, sobald dieses Gerät online ist.';

  @override
  String get settings_call_diagnostics_details =>
      'Enthält Anrufphasen, Fehlerursachen, Zeitangaben, die App-Version sowie den Verbindungsstatus und den Status der Paketübertragung. Keine Audiodaten, Nachrichten, Kontakt- oder Gerätekennungen, Tokens oder Netzwerkadressen.';

  @override
  String get settings_app_diagnostics_title => 'App-Diagnose';

  @override
  String get settings_app_diagnostics_switch => 'App-Diagnosedaten teilen';

  @override
  String get settings_app_diagnostics_summary =>
      'Hilf dabei, Probleme mit Nachrichten, privaten Medien, Benachrichtigungen und dem App-Start zu erkennen. Berichte werden automatisch hochgeladen, sobald dieses Gerät online ist.';

  @override
  String get settings_app_diagnostics_details =>
      'Enthält Vorgangsphasen, festgelegte Fehlerkategorien, Zeitangaben, die App-Version, Berichte über Abstürze und Einfrieren sowie den Zustand der Berichterstattung. Keine Nachrichten, Bilder, Audiodaten, Schlüssel, Kontakt- oder Gerätekennungen, Tokens oder Netzwerkadressen. Kopiere einen Supportcode, damit wir das Problem finden können.';

  @override
  String get settings_diagnostics_sharing_on => 'Teilen aktiviert';

  @override
  String get settings_diagnostics_off => 'Aus';

  @override
  String get settings_diagnostics_status_unavailable =>
      'Der Diagnosestatus ist vorübergehend nicht verfügbar.';

  @override
  String get settings_diagnostics_storage_failed =>
      'Berichte können auf diesem Gerät nicht gespeichert werden. Versuche, das Teilen aus- und wieder einzuschalten.';

  @override
  String get settings_diagnostics_setup_pending =>
      'Die Einrichtung zum Teilen steht noch aus. Berichte werden hochgeladen, sobald sie abgeschlossen ist.';

  @override
  String get settings_diagnostics_disable_pending =>
      'Das Teilen ist auf diesem Gerät ausgeschaltet. Die Aktualisierung auf dem Server steht noch aus.';

  @override
  String get settings_diagnostics_ready => 'Das Teilen ist bereit.';

  @override
  String get settings_diagnostics_disabled => 'Das Teilen ist ausgeschaltet.';

  @override
  String settings_diagnostics_queued_events(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Ereignisse warten auf die Übertragung',
      one: '1 Ereignis wartet auf die Übertragung',
    );
    return '$_temp0';
  }

  @override
  String settings_diagnostics_last_upload(DateTime date, DateTime time) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMd(localeName);
    final String dateString = dateDateFormat.format(date);
    final intl.DateFormat timeDateFormat = intl.DateFormat.jm(localeName);
    final String timeString = timeDateFormat.format(time);

    return 'Letzte Übertragung: $dateString um $timeString';
  }

  @override
  String settings_diagnostics_dropped_events(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count Ereignisse wurden verworfen. Berichte sind möglicherweise unvollständig.',
      one:
          '1 Ereignis wurde verworfen. Berichte sind möglicherweise unvollständig.',
    );
    return '$_temp0';
  }

  @override
  String get settings_diagnostics_retry_pending =>
      'Die Übertragung wartet auf einen erneuten Versuch.';

  @override
  String get settings_diagnostics_update_failed =>
      'Die Diagnoseeinstellungen konnten nicht aktualisiert werden. Bitte versuche es erneut.';

  @override
  String settings_diagnostics_retention(int localDays, int serverDays) {
    return 'Berichte bleiben bis zu $localDays Tage auf diesem Gerät und bis zu $serverDays Tage auf dem Server gespeichert. Das Teilen ist standardmäßig aktiviert. Du kannst es jederzeit ausschalten.';
  }

  @override
  String get settings_diagnostics_support_code_copied =>
      'Supportcode kopiert. Gib ihn bei einer Problemmeldung an.';

  @override
  String get settings_diagnostics_copy_support_code => 'Supportcode kopieren';

  @override
  String get settings_diagnostics_preview_report => 'Supportbericht ansehen';

  @override
  String get settings_diagnostics_report_copied => 'Supportbericht kopiert';

  @override
  String get settings_diagnostics_copy_report => 'Supportbericht kopieren';

  @override
  String get settings_diagnostics_cleared =>
      'Das Teilen ist ausgeschaltet und lokale Berichte wurden gelöscht';

  @override
  String get settings_diagnostics_disable_and_clear =>
      'Ausschalten und Berichte löschen';

  @override
  String get settings_safety_support_title => 'Sicherheit & Hilfe';

  @override
  String get settings_safety_support_description =>
      'Melde Missbrauch oder Bedenken zur Sicherheit von Kindern an den Entwickler von mknoon. Nutze die folgende Adresse oder öffne deine E-Mail-App, um eine Meldung zu schreiben.';

  @override
  String get settings_safety_support_email => 'E-Mail schreiben';

  @override
  String get settings_safety_support_copy_email => 'E-Mail-Adresse kopieren';

  @override
  String get settings_safety_support_copied => 'E-Mail-Adresse kopiert.';

  @override
  String get settings_safety_support_copy_failed =>
      'Die Adresse konnte nicht kopiert werden. Du kannst sie oben auswählen und manuell kopieren.';

  @override
  String get settings_safety_support_email_unavailable =>
      'Es konnte keine E-Mail-App geöffnet werden. Kopiere die Adresse und kontaktiere uns über deinen bevorzugten E-Mail-Dienst.';

  @override
  String get settings_safety_support_browser_unavailable =>
      'Es konnte kein Browser geöffnet werden. Du kannst den Link zur Richtlinie unten kopieren und selbst öffnen.';

  @override
  String get settings_safety_support_guidance =>
      'Beschreibe dein Anliegen. Sende kein mutmaßliches Material über sexuellen Kindesmissbrauch, keine privaten Schlüssel und keine Wiederherstellungsphrasen.';

  @override
  String get settings_safety_support_standards =>
      'Standards zum Schutz von Kindern';
}
