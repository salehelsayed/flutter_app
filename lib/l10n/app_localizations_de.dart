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
  String get settings_background => 'Hintergrund';

  @override
  String get settings_background_default => 'Standard';

  @override
  String get settings_background_default_desc =>
      'Der aktuelle Umgebungs-Hintergrund.';

  @override
  String get settings_background_cosmic => 'Kosmisch';

  @override
  String get settings_background_cosmic_desc =>
      'Ein tiefes Sternenfeld für den Feed.';

  @override
  String get settings_background_cosmic_selected => 'Kosmisch ausgewählt';

  @override
  String get settings_background_cosmic_mirrored => 'Kosmisch gespiegelt';

  @override
  String get settings_background_cosmic_mirrored_desc =>
      'Das kosmische Sternenfeld mit gespiegelten Farblichtern.';

  @override
  String get settings_background_cosmic_mirrored_selected =>
      'Kosmisch gespiegelt ausgewählt';

  @override
  String get settings_background_daylight_lagoon => 'Tageslicht-Lagune';

  @override
  String get settings_background_daylight_lagoon_desc =>
      'Ein heller Lagunenhimmel mit sanften Pastelllichtern.';

  @override
  String get settings_background_daylight_lagoon_selected =>
      'Tageslicht-Lagune ausgewählt';

  @override
  String get settings_background_save_fail =>
      'Hintergrundauswahl konnte nicht gespeichert werden';

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
  String feed_you_replied(String time) {
    return 'Du hast $time geantwortet';
  }

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
  String get media_unavailable => 'Medien nicht verfügbar';

  @override
  String get media_retry_unavailable => 'Nicht verfügbare Medien erneut laden';

  @override
  String get edit_save_failed => 'Änderung konnte nicht gespeichert werden.';

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
  String get group_info_invite_resend_failed =>
      'Einladung konnte nicht erneut gesendet werden';

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
  String get btn_save => 'Speichern';

  @override
  String get group_member_sending => 'Wird gesendet...';

  @override
  String get group_member_resend => 'Erneut senden';

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
  String get group_card_no_messages => 'Noch keine Nachrichten';

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
  String group_backlog_mixed_list_summary(int days) {
    return 'Älterer Rückstand nach $days Tagen abgelaufen';
  }

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
  String group_backlog_expired_list_summary(int days) {
    return 'Verpasster Rückstand nach $days Tagen abgelaufen';
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
  String get group_info_delete_local_failed =>
      'Gruppe konnte lokal nicht gelöscht werden';

  @override
  String get group_info_publish_member_removal_failed =>
      'Entfernen des Mitglieds konnte nicht veröffentlicht werden';

  @override
  String get group_info_rotate_key_failed =>
      'Gruppenschlüssel konnte nach dem Entfernen nicht rotiert werden';

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
  String get groups_title => 'Gruppen';

  @override
  String get groups_empty_title => 'Noch keine Gruppen';

  @override
  String get groups_empty_desc => 'Erstelle eine Gruppe, um loszulegen';

  @override
  String get groups_pending_invites => 'Ausstehende Einladungen';

  @override
  String get groups_joined => 'Beigetretene Gruppen';

  @override
  String get groups_unknown_sender => 'Unbekannt';

  @override
  String get groups_no_joined =>
      'Noch keine beigetretenen Gruppen. Nimm eine Einladung an, um sie hier hinzuzufügen.';

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
  String get group_read_only_not_active =>
      'Du kannst den Verlauf dieser Gruppe lesen, bist aber kein aktives Mitglied.';

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
  String get conversation_empty_first_letter =>
      'Schreib den ersten Brief,\num eure Unterhaltung zu beginnen';

  @override
  String get media_video_load_failed => 'Video konnte nicht geladen werden';

  @override
  String get conversation_introduce_to_circle => 'Deinem Kreis vorstellen';

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
      other: '$count zu große GIFs übersprungen.',
      one: '1 zu großes GIF übersprungen.',
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
  String get settings_peer_id_desc => 'Deine eindeutige Kennung im Netzwerk';

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
  String get orbit_inner_circle_title => 'DEIN INNERER KREIS';

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
  String get feed_previously_seen => 'BEREITS GESEHEN';

  @override
  String get feed_replying_to => 'Antwort auf';

  @override
  String get feed_view_earlier_messages => 'Frühere Nachrichten anzeigen';

  @override
  String feed_ready_for_user(String username) {
    return 'Dein Feed ist bereit, @$username. Neue Verbindungen erscheinen hier.';
  }

  @override
  String get feed_loading => 'Feed wird geladen...';

  @override
  String get feed_syncing_threads =>
      'Deine letzten Threads werden noch synchronisiert.';

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
  String group_invite_joined(String name) {
    return '$name beigetreten';
  }

  @override
  String get group_invite_no_longer_available =>
      'Einladung nicht mehr verfügbar';

  @override
  String get group_invite_expired => 'Einladung abgelaufen';

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
  String get group_invite_invalid => 'Einladung ist nicht mehr gültig';

  @override
  String get group_invite_duplicate_group => 'Gruppe bereits hinzugefügt';

  @override
  String group_invite_joined_recovery(String name) {
    return '$name beigetreten, aber die Wiederherstellung holt noch auf';
  }

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
}
