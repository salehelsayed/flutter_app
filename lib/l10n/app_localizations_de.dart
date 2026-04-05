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
      'Beiträge von deinen direkten Freunden erscheinen hier, sobald sie ankommen oder erneut geladen werden.';

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
    return '$count Anhänge';
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
      'Du hast bereits 1 aktiven angepinnten Beitrag';

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
  String get compose_nearby_refresh => 'Nearby vor dem Posten aktualisieren';

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
      'Deine Nearby-Daten sind aktuell genug zum Posten.';

  @override
  String get compose_nearby_refresh_desc =>
      'Aktualisiere deine Nearby-Daten, bevor du diese Zielgruppe nutzt.';

  @override
  String get compose_nearby_allow_desc =>
      'Aktualisiere Nearby, um den Standortzugriff für diese Beiträge freizugeben.';

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
  String get compose_refresh_nearby => 'Nearby aktualisieren';

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
  String get orbit_close_friends => 'Enge Freunde';

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
  String get conversation_hint => 'Schreib etwas...';

  @override
  String get conversation_voice_fail =>
      'Sprachnachricht konnte nicht gesendet werden.';

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
  String get conversation_context_edit => 'Bearbeiten';

  @override
  String get conversation_context_copy => 'Kopieren';

  @override
  String get conversation_context_delete => 'Löschen';

  @override
  String get conversation_context_copied =>
      'Nachricht in die Zwischenablage kopiert';

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
  String get comment_hint => 'Schreib einen Kommentar...';

  @override
  String get group_create_title => 'Gruppe erstellen';

  @override
  String get group_name_hint => 'Gruppenname eingeben';

  @override
  String get group_desc_hint => 'Worum geht es in dieser Gruppe?';

  @override
  String get group_name_optional => 'Gruppenname (optional)';

  @override
  String get group_message_hint => 'Nachricht';

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
    return 'An $username vorstellen';
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
  String get btn_submit => 'Senden';

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
    return 'Verbunden $date';
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
  String feed_you_replied(String time) {
    return 'Du hast geantwortet $time';
  }

  @override
  String get settings_photo_quality => 'Fotoqualität';

  @override
  String get settings_share_nearby => 'Leute in der Nähe teilen';

  @override
  String get settings_share_nearby_on => 'An';

  @override
  String get settings_share_nearby_off => 'Aus';

  @override
  String get settings_share_nearby_desc =>
      'Teilt nur einen ungefähren Standort mit direkten Freunden. Keine Live-Karten und niemals Fremde.';

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
}
