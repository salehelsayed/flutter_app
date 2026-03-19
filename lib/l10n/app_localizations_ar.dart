// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get nav_feed => 'الخلاصة';

  @override
  String get nav_remember => 'الذكريات';

  @override
  String get nav_posts => 'المنشورات';

  @override
  String get nav_orbit => 'الدائرة';

  @override
  String get onboarding_new_here => 'أنا جديد هنا';

  @override
  String get onboarding_new_desc => 'أنشئ هوية جديدة';

  @override
  String get onboarding_load_key => 'استرجاع مفتاحي';

  @override
  String get onboarding_load_desc => 'استعدها باستخدام عبارة الاسترداد';

  @override
  String get onboarding_privacy_1 => 'أنت وحدك من يمكنه قراءة رسائلك';

  @override
  String get onboarding_privacy_2 => 'كل شيء يبقى على هاتفك. لا أحد يراقبك.';

  @override
  String get progress_securing => 'جارٍ تأمين هويتك';

  @override
  String get progress_securing_desc => 'جارٍ حفظ هويتك في مساحة تخزين آمنة.';

  @override
  String get progress_creating => 'جارٍ إنشاء هويتك الآمنة';

  @override
  String get progress_creating_desc =>
      'جارٍ إنشاء مفاتيح التشفير على هذا الجهاز. يحدث هذا مرة واحدة فقط.';

  @override
  String get progress_keep_open => 'يرجى إبقاء التطبيق مفتوحًا.';

  @override
  String get progress_almost => 'أوشكنا على الانتهاء.';

  @override
  String get progress_step_keys => 'إنشاء المفاتيح';

  @override
  String get progress_step_save => 'الحفظ على الجهاز';

  @override
  String get mnemonic_title => 'عبارة الاسترداد';

  @override
  String get mnemonic_error_12 => 'يرجى إدخال 12 كلمة بالضبط';

  @override
  String get mnemonic_error_invalid => 'عبارة الاسترداد غير صحيحة';

  @override
  String get mnemonic_error_generic => 'حدث خطأ. يرجى المحاولة مرة أخرى.';

  @override
  String get mnemonic_hint =>
      'word1 word2 word3 word4\nword5 word6 word7 word8\nword9 word10 word11 word12';

  @override
  String get qr_show_desc => 'اعرض هذا على شخص تريد ضمّه إلى دائرتك...';

  @override
  String get qr_copy_hint => 'اضغط مطولًا على رمز QR لنسخ البيانات';

  @override
  String get qr_copied => 'تم نسخ بيانات QR إلى الحافظة!';

  @override
  String get qr_scan_title => 'امسح رمز QR';

  @override
  String get qr_scan_instruction => 'وجّه الكاميرا إلى رمز QR الخاص بصديق';

  @override
  String get qr_scan_subtitle => 'سيتم إضافته إلى دائرتك';

  @override
  String get qr_my_code => 'رمز QR الخاص بي';

  @override
  String get qr_no_identity => 'لا توجد هوية';

  @override
  String get qr_error => 'خطأ';

  @override
  String get qr_try_again => 'حاول مرة أخرى';

  @override
  String get qr_paste_title => 'لصق بيانات QR';

  @override
  String get qr_paste_hint => 'ألصق بيانات JSON الخاصة برمز QR من جهاز آخر:';

  @override
  String get qr_paste_button => 'لصق من الحافظة';

  @override
  String get qr_debug_paste => 'تصحيح: لصق بيانات QR';

  @override
  String get posts_title => 'المنشورات';

  @override
  String posts_header_subtitle(String username) {
    return 'ما الذي يحدث اليوم بين أصدقائك يا $username؟';
  }

  @override
  String get posts_compose_button => 'شارك شيئًا مع أصدقائك';

  @override
  String get posts_empty_title => 'أنت مطّلع على كل جديد';

  @override
  String get posts_empty_desc =>
      'ستظهر هنا منشورات أصدقائك المباشرين عندما تصل أو تُعاد مزامنتها.';

  @override
  String get posts_empty_button => 'أنشئ أول منشور لك';

  @override
  String get posts_caught_up => 'أنت مطّلع على كل جديد';

  @override
  String get posts_time_now => 'الآن';

  @override
  String get posts_time_earlier => 'في وقت سابق اليوم';

  @override
  String get posts_time_yesterday => 'أمس';

  @override
  String get compose_title => 'إنشاء منشور';

  @override
  String get compose_hint => 'ماذا تريد أن تشارك؟';

  @override
  String get compose_audience_all => 'كل الأصدقاء';

  @override
  String get compose_audience_nearby => 'القريبون منك';

  @override
  String get compose_audience_pick => 'اختر أشخاصًا';

  @override
  String get compose_radius => 'المسافة';

  @override
  String get compose_radius_500 => '500م';

  @override
  String get compose_radius_1k => '1كم';

  @override
  String get compose_radius_2k => '2كم';

  @override
  String get compose_media => 'وسائط';

  @override
  String get compose_media_adding => 'جارٍ الإضافة...';

  @override
  String get compose_voice => 'رسالة صوتية';

  @override
  String get compose_voice_stop => 'إيقاف';

  @override
  String get compose_voice_attached => 'تم إرفاق رسالة صوتية';

  @override
  String compose_attachments(int count) {
    return '$count مرفقات';
  }

  @override
  String get compose_pick_people => 'اختر أشخاصًا';

  @override
  String get compose_posting => 'جارٍ النشر...';

  @override
  String get compose_post => 'نشر';

  @override
  String get compose_manage => 'إدارة';

  @override
  String get compose_pinned_1 => 'لديك بالفعل منشور مثبّت نشط واحد';

  @override
  String compose_pinned_n(int count) {
    return 'لديك بالفعل $count منشورات مثبّتة نشطة';
  }

  @override
  String get compose_nearby_off => 'ميزة القريبين منك معطّلة في الإعدادات';

  @override
  String get compose_nearby_ready => 'ميزة القريبين منك جاهزة';

  @override
  String get compose_nearby_refresh => 'حدّث القريبين منك قبل النشر';

  @override
  String get compose_nearby_allow => 'اسمح بالموقع لاستخدام ميزة القريبين منك';

  @override
  String get compose_nearby_perm_off => 'إذن الموقع معطّل';

  @override
  String get compose_nearby_services => 'فعّل خدمات الموقع';

  @override
  String get compose_nearby_off_desc =>
      'فعّلها من الإعدادات قبل النشر للأصدقاء القريبين منك.';

  @override
  String get compose_nearby_ready_desc =>
      'بيانات القريبين منك محدثة بما يكفي للنشر.';

  @override
  String get compose_nearby_refresh_desc =>
      'حدّث بيانات القريبين منك قبل استخدام هذه الفئة.';

  @override
  String get compose_nearby_allow_desc =>
      'حدّث القريبين منك لتفعيل الوصول إلى الموقع لهذا النوع من المنشورات.';

  @override
  String get compose_nearby_perm_desc =>
      'افتح إعدادات النظام لإعادة تفعيل الوصول إلى الموقع.';

  @override
  String get compose_nearby_services_desc =>
      'فعّل خدمات الموقع ثم حدّث القريبين منك مرة أخرى.';

  @override
  String get compose_open_settings => 'افتح الإعدادات';

  @override
  String get compose_refreshing => 'جارٍ التحديث...';

  @override
  String get compose_refresh_nearby => 'حدّث القريبين منك';

  @override
  String get post_badge_friend => 'صديق';

  @override
  String get post_uploading => 'جارٍ رفع الوسائط...';

  @override
  String get post_sending => 'جارٍ الإرسال...';

  @override
  String get post_partial => 'تم الإرسال جزئيًا';

  @override
  String get post_upload_failed => 'فشل رفع الملف';

  @override
  String get post_send_failed => 'فشل الإرسال';

  @override
  String get pinned_title => 'المنشورات المثبّتة';

  @override
  String get pinned_count_1 => 'منشور مثبّت واحد';

  @override
  String pinned_count_n(int count) {
    return '$count منشورات مثبّتة';
  }

  @override
  String pinned_see_all(int count) {
    return 'عرض كل المنشورات المثبّتة ($count)';
  }

  @override
  String get pinned_dismiss => 'إخفاء';

  @override
  String pinned_message(String username) {
    return 'راسل $username';
  }

  @override
  String get pinned_edit => 'تعديل';

  @override
  String get pinned_remove => 'إزالة';

  @override
  String get edit_pinned_hint => 'حدّث منشورك';

  @override
  String get orbit_close_friends => 'الأصدقاء المقرّبون';

  @override
  String get orbit_new_group => 'مجموعة جديدة';

  @override
  String get orbit_new_announce => 'إعلان جديد';

  @override
  String get orbit_my_qr => 'رمزي';

  @override
  String get orbit_scan => 'مسح';

  @override
  String get orbit_qr_share => 'شارك لإضافة أصدقاء';

  @override
  String get orbit_qr_scan_desc => 'أضف صديقًا فورًا';

  @override
  String get orbit_filter_all => 'الكل';

  @override
  String get orbit_filter_intros => 'التعارف';

  @override
  String get orbit_filter_archived => 'المؤرشفة';

  @override
  String get orbit_search => 'ابحث عن الأصدقاء...';

  @override
  String orbit_block_title(String username) {
    return 'حظر $username؟';
  }

  @override
  String get orbit_delete_chat => 'حذف المحادثة؟';

  @override
  String get orbit_leave_group => 'مغادرة المجموعة وحذفها؟';

  @override
  String get conversation_hint => 'اكتب شيئًا...';

  @override
  String get conversation_voice_fail => 'فشل إرسال الرسالة الصوتية.';

  @override
  String conversation_block(String username) {
    return 'حظر $username؟';
  }

  @override
  String get conversation_delete_chat => 'حذف المحادثة؟';

  @override
  String get conversation_reply => 'رد...';

  @override
  String get conversation_continue => 'متابعة...';

  @override
  String get comment_hint => 'اكتب تعليقًا...';

  @override
  String get group_create_title => 'إنشاء مجموعة';

  @override
  String get group_name_hint => 'أدخل اسم المجموعة';

  @override
  String get group_desc_hint => 'عن ماذا تتحدث هذه المجموعة؟';

  @override
  String get group_name_optional => 'اسم المجموعة (اختياري)';

  @override
  String get group_message_hint => 'رسالة';

  @override
  String get group_create_failed => 'فشل إنشاء المجموعة';

  @override
  String get group_invite_failed => 'فشل دعوة الأعضاء';

  @override
  String picker_introduce_to(String username) {
    return 'تعريفهم إلى $username';
  }

  @override
  String get picker_search => 'ابحث عن الأصدقاء...';

  @override
  String get picker_no_friends => 'لا يوجد أصدقاء متاحون للتعريف بهم';

  @override
  String picker_no_results(String query) {
    return 'لا يوجد أصدقاء يطابقون \"$query\"';
  }

  @override
  String picker_introduce_count(int count) {
    return 'عرّف ($count)';
  }

  @override
  String get picker_introduce => 'عرّف';

  @override
  String get picker_search_contacts => 'ابحث في جهات الاتصال...';

  @override
  String get picker_search_all => 'ابحث في جهات الاتصال والمجموعات';

  @override
  String get settings_title => 'الإعدادات';

  @override
  String get settings_video_quality => 'جودة الفيديو';

  @override
  String get settings_compressed => 'مضغوط';

  @override
  String get settings_original => 'أصلي';

  @override
  String get settings_original_desc =>
      'جودة كاملة وحجم ملف أكبر. تتم إزالة البيانات الوصفية دائمًا.';

  @override
  String get settings_compressed_desc =>
      'حجم ملف أصغر وإرسال أسرع. تتم إزالة البيانات الوصفية دائمًا.';

  @override
  String get settings_photo_fail => 'فشل رفع الصورة الشخصية';

  @override
  String get picker_take_photo => 'التقاط صورة';

  @override
  String get picker_gallery => 'اختر من المعرض';

  @override
  String get notif_new_intro => 'تعارف جديد';

  @override
  String get notif_new_connection => 'اتصال جديد';

  @override
  String get startup_checking => 'جارٍ تجهيز مساحتك...';

  @override
  String get startup_checking_desc => 'جارٍ التحقق من الهوية وحالة البدء';

  @override
  String get startup_feed => 'جارٍ فتح الخلاصة...';

  @override
  String get startup_feed_desc => 'جارٍ نقلك إلى محادثاتك';

  @override
  String get startup_setup => 'جارٍ فتح الإعداد...';

  @override
  String get startup_setup_desc => 'نجهّز لك تجربة البداية الأولى';

  @override
  String get startup_onboarding => 'جارٍ فتح التهيئة الأولى...';

  @override
  String get startup_onboarding_desc => 'لنجهّز هويتك';

  @override
  String get btn_retry => 'أعد المحاولة';

  @override
  String get btn_cancel => 'إلغاء';

  @override
  String get btn_submit => 'إرسال';

  @override
  String get error_add_contact =>
      'فشل إضافة جهة الاتصال. يرجى المحاولة مرة أخرى.';

  @override
  String get error_send_message => 'فشل إرسال الرسالة. حاول مرة أخرى.';

  @override
  String error_update_photo(String error) {
    return 'فشل تحديث الصورة: $error';
  }

  @override
  String get error_update_username =>
      'فشل تحديث اسم المستخدم. يرجى المحاولة مرة أخرى.';

  @override
  String error_generic(String error) {
    return 'خطأ: $error';
  }

  @override
  String get status_processing_video => 'جارٍ معالجة الفيديو...';

  @override
  String get perm_camera =>
      'يحتاج هذا التطبيق إلى الوصول إلى الكاميرا لمسح رموز QR والتقاط الصور';

  @override
  String get perm_photos =>
      'يحتاج هذا التطبيق إلى الوصول إلى مكتبة الصور لمشاركة الصور';

  @override
  String get perm_microphone =>
      'يحتاج هذا التطبيق إلى الوصول إلى الميكروفون لتسجيل الرسائل الصوتية';

  @override
  String get perm_location =>
      'يحتاج هذا التطبيق إلى الوصول إلى الموقع لمشاركة المنشورات القريبة مع أصدقائك المباشرين';

  @override
  String get perm_local_network =>
      'يبحث mknoon عن أصدقائك على نفس شبكة Wi‑Fi لإرسال الرسائل مباشرة إلى هواتفهم. هذا أسرع وأكثر خصوصية، ونحن لا نجمع بياناتك أبدًا.';

  @override
  String get perm_notifications =>
      'يحتاج هذا التطبيق إلى الوصول إلى الإشعارات لتنبيهك عند وصول رسائل جديدة';

  @override
  String connected_date(String date) {
    return 'تم الاتصال $date';
  }

  @override
  String get date_today => 'اليوم';

  @override
  String get date_yesterday => 'أمس';

  @override
  String get feed_collapse => 'طي';

  @override
  String get feed_tap_expand => 'اضغط للتوسيع';

  @override
  String get feed_you => 'أنت';

  @override
  String feed_you_replied(String time) {
    return 'رددت $time';
  }

  @override
  String get settings_photo_quality => 'جودة الصورة';

  @override
  String get settings_share_nearby => 'مشاركة القريبين منك';

  @override
  String get settings_share_nearby_on => 'مفعّل';

  @override
  String get settings_share_nearby_off => 'معطّل';

  @override
  String get settings_share_nearby_desc =>
      'يشارك موقعًا تقريبيًا فقط مع الأصدقاء المباشرين. لا خرائط مباشرة، ولا غرباء أبدًا.';

  @override
  String get settings_recovery_title => 'عبارة الاسترداد';

  @override
  String get settings_recovery_warning =>
      'لا تشارك هذه العبارة مع أي شخص. تمنح الوصول الكامل إلى حسابك.';

  @override
  String get settings_recovery_tap => 'اضغط للكشف';

  @override
  String get settings_recovery_copied => 'تم النسخ!';

  @override
  String get settings_recovery_copy => 'نسخ إلى الحافظة';

  @override
  String get settings_recovery_hide => 'إخفاء';

  @override
  String get connected_title => '!تم الاتصال';

  @override
  String get send_message => 'إرسال رسالة';

  @override
  String introduced_by(String username) {
    return 'تم التعريف بواسطة $username';
  }
}
