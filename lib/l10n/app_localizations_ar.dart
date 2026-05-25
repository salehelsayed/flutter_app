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
  String get onboarding_load_desc => 'استعد هويتك باستخدام عبارة الاسترداد';

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
  String get compose_radius => 'النطاق';

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
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count مرفق',
      many: '$count مرفقًا',
      few: '$count مرفقات',
      two: 'مرفقان',
      one: 'مرفق واحد',
      zero: 'لا مرفقات',
    );
    return '$_temp0';
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
  String get conversation_context_reply => 'رد';

  @override
  String get conversation_context_edit => 'تعديل';

  @override
  String get conversation_context_copy => 'نسخ';

  @override
  String get conversation_context_delete => 'حذف';

  @override
  String get conversation_context_copied => 'تم نسخ الرسالة إلى الحافظة';

  @override
  String get conversation_editing_message => 'تعديل الرسالة';

  @override
  String get conversation_cancel_edit => 'إلغاء';

  @override
  String get conversation_edited_indicator => '(تم التعديل)';

  @override
  String get conversation_delete_message_prompt => 'لمن تريد حذف هذه الرسالة؟';

  @override
  String get conversation_delete_for_me => 'الحذف لديّ';

  @override
  String get conversation_delete_for_everyone => 'الحذف للجميع';

  @override
  String get conversation_delete_cancel => 'إلغاء';

  @override
  String get conversation_message_deleted => 'تم حذف هذه الرسالة';

  @override
  String get conversation_delete_failed => 'تعذر إكمال حذف هذه الرسالة.';

  @override
  String get conversation_continue => 'متابعة...';

  @override
  String get comment_hint => 'اكتب تعليقًا...';

  @override
  String get group_name_optional => 'اسم المجموعة (اختياري)';

  @override
  String get group_message_hint => 'رسالة';

  @override
  String get group_create_failed => 'فشل إنشاء المجموعة';

  @override
  String get group_invite_failed => 'فشل دعوة الأعضاء';

  @override
  String group_create_member_limit_reached(int maxMembers, int overflowCount) {
    return 'يمكن أن تضم المجموعات حتى $maxMembers عضوًا بما فيهم أنت. قلّل اختيارك بمقدار $overflowCount ثم أعد المحاولة.';
  }

  @override
  String group_invite_member_limit_reached(int maxMembers, int overflowCount) {
    return 'يمكن أن تضم المجموعات حتى $maxMembers عضوًا. قلّل اختيارك بمقدار $overflowCount ثم أعد المحاولة.';
  }

  @override
  String picker_introduce_to(String username) {
    return 'تقديم إلى $username';
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
  String picker_sending_progress(int completed, int total) {
    return 'جارٍ إرسال $completed من $total';
  }

  @override
  String get picker_search_contacts => 'ابحث في جهات الاتصال...';

  @override
  String get picker_search_all => 'ابحث في جهات الاتصال والمجموعات';

  @override
  String get settings_title => 'الإعدادات';

  @override
  String get settings_background => 'الخلفية';

  @override
  String get settings_background_default => 'الافتراضية';

  @override
  String get settings_background_default_desc => 'الخلفية المحيطة الحالية.';

  @override
  String get settings_background_cosmic => 'كونية';

  @override
  String get settings_background_cosmic_desc => 'حقل نجوم عميق للخلاصة.';

  @override
  String get settings_background_cosmic_selected => 'تم اختيار الكونية';

  @override
  String get settings_background_cosmic_mirrored => 'كونية معكوسة';

  @override
  String get settings_background_cosmic_mirrored_desc =>
      'حقل النجوم الكوني مع توهجات لونية معكوسة.';

  @override
  String get settings_background_cosmic_mirrored_selected =>
      'تم اختيار الكونية المعكوسة';

  @override
  String get settings_background_daylight_lagoon => 'بحيرة ضوء النهار';

  @override
  String get settings_background_daylight_lagoon_desc =>
      'سماء بحيرة مشرقة بتوهجات باستيلية ناعمة.';

  @override
  String get settings_background_daylight_lagoon_selected =>
      'تم اختيار بحيرة ضوء النهار';

  @override
  String get settings_background_save_fail => 'تعذر حفظ اختيار الخلفية';

  @override
  String get settings_background_semantics => 'إعداد خلفية التطبيق';

  @override
  String get settings_background_default_selected => 'تم اختيار الافتراضية';

  @override
  String get settings_video_quality => 'جودة الفيديو';

  @override
  String get settings_compressed => 'المضغوطة';

  @override
  String get settings_original => 'الأصلية';

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
  String get notif_new_connection => 'صلة جديدة';

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
    return 'تمت الإضافة في $date';
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
      'لا تشارك هذه العبارة أبدًا مع أي شخص. فهي تمنح وصولًا كاملًا إلى حسابك.';

  @override
  String get settings_recovery_tap => 'اضغط للكشف';

  @override
  String get settings_recovery_copied => 'تم النسخ!';

  @override
  String get settings_recovery_copy => 'نسخ إلى الحافظة';

  @override
  String get settings_recovery_hide => 'إخفاء';

  @override
  String get connected_title => 'تمت الإضافة!';

  @override
  String get send_message => 'إرسال رسالة';

  @override
  String introduced_by(String username) {
    return 'تم التعريف بواسطة $username';
  }

  @override
  String get load_retry_hint => 'تحقق من اتصالك وحاول مرة أخرى.';

  @override
  String get upload_leave_title => 'مغادرة المحادثة؟';

  @override
  String get upload_leave_body =>
      'هناك رفع جارٍ. قد تؤدي المغادرة إلى مقاطعته. هل أنت متأكد؟';

  @override
  String get upload_leave_stay => 'البقاء';

  @override
  String get upload_leave_confirm => 'مغادرة';

  @override
  String get upload_cancelled => 'تم إلغاء الرفع.';

  @override
  String get media_too_large_title => 'الوسائط كبيرة جدًا';

  @override
  String media_too_large_prompt(String totalSize, String limitSize) {
    return 'حجم الوسائط المرفقة $totalSize ويتجاوز حد $limitSize. هل تريد ضغطها وإرسالها أم الإلغاء؟';
  }

  @override
  String get media_compress => 'ضغط';

  @override
  String get media_too_large_after_compress =>
      'ما زالت الوسائط كبيرة جدًا حتى بعد الضغط.';

  @override
  String get media_gif_too_large => 'لا يمكن إضافة ملفات GIF أكبر من 25 م.ب.';

  @override
  String get media_unavailable => 'الوسائط غير متاحة';

  @override
  String get media_retry_unavailable => 'إعادة تحميل الوسائط غير المتاحة';

  @override
  String get edit_save_failed => 'فشل حفظ التعديل.';

  @override
  String get intro_pass => 'تمرير';

  @override
  String get intro_accept => 'قبول';

  @override
  String get intro_accepting => 'جارٍ القبول...';

  @override
  String get failed_message_retry_semantics =>
      'إعادة محاولة إرسال الرسالة الفاشلة';

  @override
  String get failed_media_retry_semantics =>
      'إعادة محاولة رسالة الوسائط الفاشلة';

  @override
  String get failed_media_delete_semantics => 'حذف رسالة الوسائط الفاشلة';

  @override
  String message_status_semantics(String status) {
    return 'حالة الرسالة: $status';
  }

  @override
  String get message_status_delivered => 'تم التسليم';

  @override
  String get message_status_failed => 'فشل';

  @override
  String get message_status_sending => 'جارٍ الإرسال';

  @override
  String get message_status_sent => 'تم الإرسال';

  @override
  String get message_status_pending_inbox => 'تسليم معلّق عبر صندوق الوارد';

  @override
  String get share_send_failed => 'تعذرت المشاركة مع الأهداف المحددة.';

  @override
  String get group_info_title => 'معلومات المجموعة';

  @override
  String get group_edit_details => 'تعديل التفاصيل';

  @override
  String group_member_count(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عضو',
      many: '$count عضوًا',
      few: '$count أعضاء',
      two: 'عضوان',
      one: 'عضو واحد',
    );
    return '$_temp0';
  }

  @override
  String get group_security_title => 'الأمان';

  @override
  String get group_security_key_change_visible => 'تغيير المفتاح ظاهر';

  @override
  String get group_security_verification_warning => 'تحذير التحقق';

  @override
  String group_security_identity_warning_detail(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تغيّرت $count هوية. راجع أرقام الأمان أدناه.',
      many: 'تغيّرت $count هوية. راجع أرقام الأمان أدناه.',
      few: 'تغيّرت $count هويات. راجع أرقام الأمان أدناه.',
      two: 'تغيّرت هويتان. راجع أرقام الأمان أدناه.',
      one: 'تغيّرت هوية واحدة. راجع أرقام الأمان أدناه.',
    );
    return '$_temp0';
  }

  @override
  String get group_dissolved => 'تم حل المجموعة';

  @override
  String get group_dissolved_read_only_desc =>
      'أصبحت هذه المحادثة للقراءة فقط. تبقى الرسائل السابقة متاحة للرجوع إليها.';

  @override
  String get group_mute_notifications => 'كتم الإشعارات';

  @override
  String get group_mute_on_desc =>
      'ستظل الرسائل الجديدة تصل، لكن هذه المجموعة ستبقى صامتة.';

  @override
  String get group_mute_off_desc =>
      'ستتلقى إشعارًا عند وصول رسائل جديدة في هذه المجموعة.';

  @override
  String get group_members_title => 'الأعضاء';

  @override
  String get group_add_member => 'إضافة عضو';

  @override
  String get group_leave => 'مغادرة المجموعة';

  @override
  String get group_dissolve => 'حل المجموعة';

  @override
  String get group_delete_from_device => 'الحذف من هذا الجهاز';

  @override
  String get group_delete_local_desc =>
      'احتفظ بسجل هذه المجموعة المحلولة كما تريد، أو أزله من هذا الجهاز فقط. لن يؤثر ذلك في أي شخص آخر.';

  @override
  String get group_delete_locally => 'حذف المجموعة محليًا';

  @override
  String get group_no_messages => 'لا توجد رسائل بعد';

  @override
  String get group_empty_dissolved_desc =>
      'تم حل هذه المجموعة. تم تعطيل الرسائل الجديدة.';

  @override
  String get group_empty_start => 'أرسل رسالة لبدء المحادثة';

  @override
  String get group_empty_waiting => 'في انتظار الرسائل';

  @override
  String get group_recovery_banner =>
      'جارٍ استدراك الرسائل الفائتة. ستظل الرسائل الجديدة تظهر هنا.';

  @override
  String get group_read_only_dissolved =>
      'تم حل هذه المجموعة. يبقى السجل متاحًا، لكن الرسائل الجديدة معطّلة.';

  @override
  String get group_read_only_admin_only =>
      'يمكن للمشرفين فقط إرسال الرسائل في هذه المجموعة';

  @override
  String get group_removed_snackbar => 'تمت إزالتك من هذه المجموعة.';

  @override
  String get group_dissolved_snackbar => 'تم حل هذه المجموعة';

  @override
  String get group_info_mute_update_failed => 'فشل تحديث الكتم';

  @override
  String get group_info_dissolve_title => 'حل هذه المجموعة للجميع؟';

  @override
  String get group_info_dissolve_body =>
      'ينهي هذا المجموعة لكل الأعضاء. يبقى السجل مرئيًا، لكن لن يستطيع أحد إرسال رسائل جديدة بعد حلها.';

  @override
  String get group_info_dissolve_action => 'حل';

  @override
  String get group_info_dissolved_recovery =>
      'تم حل المجموعة. قد يحتاج بعض الأعضاء إلى الاسترداد لرؤية ذلك.';

  @override
  String get group_info_already_dissolved => 'المجموعة محلولة بالفعل';

  @override
  String get group_info_admins_only_dissolve =>
      'يمكن للمشرفين فقط حل المجموعات';

  @override
  String get group_info_not_found => 'لم تعد المجموعة موجودة';

  @override
  String get group_info_dissolve_failed => 'فشل حل المجموعة';

  @override
  String get group_info_delete_local_title =>
      'حذف هذه المجموعة المحلولة من هذا الجهاز؟';

  @override
  String get group_info_delete_local_body =>
      'يزيل هذا السجل المحلول من هذا الجهاز فقط. لن يؤثر في أي شخص آخر ولن يرسل حدث مغادرة جديدًا.';

  @override
  String get group_info_delete_local_action => 'حذف محليًا';

  @override
  String group_info_remove_member_title(String username) {
    return 'إزالة $username من المجموعة؟';
  }

  @override
  String get group_info_remove_member_body =>
      'سيتوقف هذا الشخص عن تلقي رسائل جديدة من هذه المجموعة.';

  @override
  String get group_info_remove_action => 'إزالة';

  @override
  String get group_info_member_fallback => 'عضو';

  @override
  String group_info_make_admin_title(String username) {
    return 'جعل $username مشرفًا؟';
  }

  @override
  String group_info_remove_admin_title(String username) {
    return 'إزالة صلاحية المشرف من $username؟';
  }

  @override
  String get group_info_make_admin_body =>
      'سيتمكن هذا الشخص من إضافة الأعضاء وإزالتهم وإدارتهم.';

  @override
  String get group_info_remove_admin_body =>
      'سيفقد هذا الشخص إجراءات المشرف فقط بعد مزامنة التغيير.';

  @override
  String get group_info_make_admin_action => 'جعله مشرفًا';

  @override
  String get group_info_remove_admin_action => 'إزالة المشرف';

  @override
  String group_info_admin_added(String username) {
    return 'أصبح $username مشرفًا الآن';
  }

  @override
  String group_info_admin_removed(String username) {
    return 'لم يعد $username مشرفًا';
  }

  @override
  String get group_info_member_role_update_failed => 'فشل تحديث دور العضو';

  @override
  String get group_info_details_updated => 'تم تحديث تفاصيل المجموعة';

  @override
  String get group_info_details_update_failed => 'فشل تحديث تفاصيل المجموعة';

  @override
  String get group_info_invite_resend_failed => 'فشل إعادة إرسال الدعوة';

  @override
  String group_info_invite_sent(String username) {
    return 'تم إرسال الدعوة إلى $username';
  }

  @override
  String group_info_invite_queued(String username) {
    return 'الدعوة في صندوق وارد $username';
  }

  @override
  String get group_info_invite_needs_resend =>
      'ما زالت الدعوة تحتاج إلى إعادة إرسال';

  @override
  String group_info_invite_joined(String username) {
    return 'انضم $username بالفعل';
  }

  @override
  String get group_info_invite_unknown => 'حالة الدعوة غير معروفة';

  @override
  String get group_edit_photo_pick_failed => 'فشل اختيار صورة المجموعة';

  @override
  String get group_edit_details_title => 'تعديل تفاصيل المجموعة';

  @override
  String get group_edit_change_photo => 'تغيير الصورة';

  @override
  String get group_edit_add_photo => 'إضافة صورة';

  @override
  String get group_edit_remove_photo => 'إزالة الصورة';

  @override
  String get group_edit_name => 'اسم المجموعة';

  @override
  String get group_edit_description => 'الوصف';

  @override
  String get btn_save => 'حفظ';

  @override
  String get group_member_sending => 'جارٍ الإرسال...';

  @override
  String get group_member_resend => 'إعادة الإرسال';

  @override
  String get group_member_manage_role => 'إدارة الدور';

  @override
  String get group_role_admin => 'مشرف';

  @override
  String get group_role_writer => 'كاتب';

  @override
  String get group_role_reader => 'قارئ';

  @override
  String get group_identity_changed => 'تغيّرت الهوية';

  @override
  String get group_current_safety => 'الأمان الحالي';

  @override
  String get group_saved_safety => 'الأمان المحفوظ';

  @override
  String get group_card_no_messages => 'لا توجد رسائل بعد';

  @override
  String get group_security_encrypted => 'مشفّر من الطرف إلى الطرف';

  @override
  String get group_security_pending => 'التشفير معلّق';

  @override
  String get group_security_no_key => 'لا يوجد مفتاح مجموعة على هذا الجهاز';

  @override
  String group_security_key_changed(int keyEpoch) {
    return 'تغيّر مفتاح المجموعة إلى الحقبة $keyEpoch';
  }

  @override
  String group_security_current_key_epoch(int keyEpoch) {
    return 'حقبة المفتاح الحالية $keyEpoch';
  }

  @override
  String get group_security_no_members => 'لا يوجد أعضاء للتحقق منهم';

  @override
  String group_security_all_members_verified(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم التحقق من $count عضو',
      many: 'تم التحقق من $count عضوًا',
      few: 'تم التحقق من $count أعضاء',
      two: 'تم التحقق من عضوين',
      one: 'تم التحقق من عضو واحد',
    );
    return '$_temp0';
  }

  @override
  String group_security_members_verified(int verifiedCount, int memberCount) {
    return 'تم التحقق من $verifiedCount من أصل $memberCount عضو';
  }

  @override
  String group_security_members_need_review(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عضو يحتاج إلى مراجعة التحقق',
      many: '$count عضوًا يحتاجون إلى مراجعة التحقق',
      few: '$count أعضاء يحتاجون إلى مراجعة التحقق',
      two: 'عضوان يحتاجان إلى مراجعة التحقق',
      one: 'عضو واحد يحتاج إلى مراجعة التحقق',
    );
    return '$_temp0';
  }

  @override
  String group_security_members_unverified(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عضو غير متحقق منه من جهات الاتصال المحفوظة',
      many: '$count عضوًا غير متحقق منهم من جهات الاتصال المحفوظة',
      few: '$count أعضاء غير متحقق منهم من جهات الاتصال المحفوظة',
      two: 'عضوان غير متحقق منهما من جهات الاتصال المحفوظة',
      one: 'عضو واحد غير متحقق منه من جهات الاتصال المحفوظة',
    );
    return '$_temp0';
  }

  @override
  String get group_security_no_warnings => 'لا توجد تحذيرات تحقق';

  @override
  String group_security_compact_encrypted_epoch(int keyEpoch) {
    return 'مشفّر - حقبة المفتاح $keyEpoch';
  }

  @override
  String get invite_status_sent => 'تم إرسال الدعوة';

  @override
  String get invite_status_queued => 'في صندوق الوارد لديهم';

  @override
  String get invite_status_needs_resend => 'تحتاج إلى إعادة إرسال';

  @override
  String get invite_status_cannot_send => 'تعذر الإرسال';

  @override
  String get invite_status_joined => 'انضم';

  @override
  String get invite_status_unknown => 'الدعوة غير معروفة';

  @override
  String get invite_cannot_send_missing_secure_key_detail =>
      'لا نملك المعلومات الآمنة المطلوبة لدعوة هذا الصديق. اطلب منه فتح التطبيق أو إعادة تثبيته، ثم حاول مرة أخرى.';

  @override
  String get invite_cannot_send_group_key_missing_detail =>
      'تفتقد هذه المجموعة مفتاح الدعوة الآمن. أعد فتح التطبيق وحاول مرة أخرى.';

  @override
  String get invite_cannot_send_invalid_payload_detail =>
      'تعذر تجهيز هذه الدعوة. أعد فتح التطبيق وحاول مرة أخرى.';

  @override
  String get invite_cannot_send_generic_detail =>
      'تعذر تجهيز دعوة آمنة لهذا الصديق. قد يحتاج إلى فتح التطبيق أو إعادة تثبيته قبل أن تتمكن من دعوته.';

  @override
  String get invite_cannot_send_missing_secure_key_snackbar =>
      'تعذر الإرسال: لا نملك المعلومات الآمنة المطلوبة لدعوة هذا الصديق.';

  @override
  String get invite_cannot_send_group_key_missing_snackbar =>
      'تعذر الإرسال: تفتقد هذه المجموعة مفتاح الدعوة الآمن.';

  @override
  String get invite_cannot_send_invalid_payload_snackbar =>
      'تعذر الإرسال: تعذر تجهيز هذه الدعوة.';

  @override
  String get invite_cannot_send_generic_snackbar =>
      'تعذر الإرسال: تعذر تجهيز دعوة آمنة لهذا الصديق.';

  @override
  String group_backlog_mixed_list_summary(int days) {
    return 'انتهت صلاحية السجل الأقدم بعد $days يومًا';
  }

  @override
  String group_backlog_mixed_banner(int days) {
    return 'انتهت صلاحية الرسائل الفائتة الأقدم بعد $days يومًا. تمت استعادة الرسائل الحديثة.';
  }

  @override
  String get group_backlog_mixed_empty_title => 'تمت استعادة الرسائل الحديثة';

  @override
  String group_backlog_mixed_empty_subtitle(int days) {
    return 'انتهت صلاحية الرسائل الفائتة الأقدم بعد $days يومًا أثناء غيابك.';
  }

  @override
  String group_backlog_expired_list_summary(int days) {
    return 'انتهت صلاحية السجل الفائت بعد $days يومًا';
  }

  @override
  String group_backlog_expired_banner(int days) {
    return 'انتهت صلاحية الرسائل الفائتة الأقدم من $days يومًا أثناء غيابك.';
  }

  @override
  String get group_backlog_expired_empty_title => 'انتهت صلاحية السجل الأقدم';

  @override
  String group_backlog_expired_empty_subtitle(int days) {
    return 'انتهت صلاحية الرسائل الفائتة الأقدم من $days يومًا أثناء غيابك.';
  }

  @override
  String get group_history_repair_active_banner =>
      'يجري إصلاح بعض الرسائل الفائتة من أعضاء موثوقين في المجموعة.';

  @override
  String get group_history_repair_active_empty_title =>
      'جارٍ إصلاح الرسائل الفائتة';

  @override
  String get group_history_repair_active_empty_subtitle =>
      'يجري التحقق من بعض الرسائل الفائتة قبل أن تظهر هنا.';

  @override
  String get group_history_repair_failed_banner =>
      'تعذر إصلاح بعض الرسائل الفائتة من أعضاء موثوقين في المجموعة.';

  @override
  String get group_history_repair_failed_empty_title => 'يلزم إصلاح السجل';

  @override
  String get group_history_repair_failed_empty_subtitle =>
      'تعذر التحقق من بعض الرسائل الفائتة من أعضاء موثوقين.';

  @override
  String get group_history_repair_done_banner =>
      'تم إصلاح الرسائل الفائتة والتحقق منها.';

  @override
  String get group_history_repair_done_empty_title => 'تم إصلاح الرسائل';

  @override
  String get group_history_repair_done_empty_subtitle =>
      'تم التحقق من الرسائل الفائتة واستعادتها.';

  @override
  String get group_info_leave_failed => 'فشل مغادرة المجموعة';

  @override
  String get group_info_notifications_muted => 'تم كتم إشعارات هذه المجموعة';

  @override
  String get group_info_notifications_restored =>
      'تمت إعادة إشعارات هذه المجموعة';

  @override
  String get group_info_delete_local_failed => 'فشل حذف المجموعة محليًا';

  @override
  String get group_info_publish_member_removal_failed => 'فشل نشر إزالة العضو';

  @override
  String get group_info_rotate_key_failed =>
      'فشل تدوير مفتاح المجموعة بعد الإزالة';

  @override
  String get group_info_remove_member_failed => 'فشل إزالة العضو';

  @override
  String get group_info_no_identity => 'لم يتم العثور على هوية';

  @override
  String get group_info_member_not_found => 'لم يتم العثور على العضو';

  @override
  String get group_info_upload_photo_failed => 'فشل رفع صورة المجموعة';

  @override
  String get group_info_sign_metadata_failed =>
      'فشل توقيع تحديث بيانات المجموعة';

  @override
  String get groups_title => 'المجموعات';

  @override
  String get groups_empty_title => 'لا توجد مجموعات بعد';

  @override
  String get groups_empty_desc => 'أنشئ مجموعة للبدء';

  @override
  String get groups_pending_invites => 'الدعوات المعلقة';

  @override
  String get groups_joined => 'المجموعات المنضم إليها';

  @override
  String get groups_unknown_sender => 'غير معروف';

  @override
  String get groups_no_joined =>
      'لا توجد مجموعات منضم إليها بعد. اقبل دعوة لإضافتها هنا.';

  @override
  String get group_type_discussion => 'نقاش';

  @override
  String get group_type_announce => 'إعلان';

  @override
  String get group_type_qa => 'أسئلة';

  @override
  String get group_dissolved_badge => 'محلولة';

  @override
  String get pending_invite_expired => 'منتهية';

  @override
  String get pending_invite_accept => 'قبول';

  @override
  String get pending_invite_decline => 'رفض';

  @override
  String get pending_invite_dismiss => 'إخفاء';

  @override
  String pending_invite_invited_by(String username) {
    return 'دعوة من $username';
  }

  @override
  String pending_invite_expires(String date) {
    return 'تنتهي في $date';
  }

  @override
  String get group_no_contacts_available => 'لا توجد جهات اتصال متاحة';

  @override
  String get settings_intro_debug_delete_row => 'حذف الصف';

  @override
  String get settings_intro_debug_delete_pair => 'حذف الزوج';

  @override
  String get settings_intro_debug_deleted_row => 'تم حذف صف التعارف المحلي';

  @override
  String settings_intro_debug_deleted_pair(String pairLabel) {
    return 'تم حذف الزوج المحلي $pairLabel';
  }

  @override
  String get settings_intro_debug_heading => 'تعريفات التصحيح';

  @override
  String get settings_intro_debug_description =>
      'صفوف التعارف المرسلة محليًا على هذا الجهاز. يؤدي حذف زوج إلى إتاحته مرة أخرى في أداة الاختيار.';

  @override
  String get settings_intro_debug_empty =>
      'لا توجد صفوف تعارف محلية للمستخدم الحالي.';

  @override
  String settings_intro_debug_status_line(
    String status,
    String recipientStatus,
    String introducedStatus,
  ) {
    return 'الحالة=$status  المستلم=$recipientStatus  المُعرَّف=$introducedStatus';
  }

  @override
  String settings_intro_debug_meta_line(String id, String createdAt) {
    return 'المعرّف=$id  تم الإنشاء=$createdAt';
  }

  @override
  String get group_start_chat => 'بدء دردشة جماعية';

  @override
  String get group_reactions_title => 'التفاعلات';

  @override
  String group_add_members_count(int count) {
    return 'إضافة أعضاء ($count)';
  }

  @override
  String get group_loading_contacts => 'جارٍ تحميل جهات الاتصال...';

  @override
  String get group_send_invites => 'إرسال الدعوات';

  @override
  String get group_send_permission_lost =>
      'لم تعد تملك صلاحية إرسال الرسائل في هذه المجموعة.';

  @override
  String get group_unavailable_snackbar => 'لم تعد هذه المجموعة متاحة.';

  @override
  String get media_retry_unavailable_now => 'إعادة المحاولة غير متاحة الآن.';

  @override
  String get media_unavailable_now => 'الوسائط غير متاحة الآن.';

  @override
  String get media_still_unavailable => 'لا تزال الوسائط غير متاحة.';

  @override
  String get failed_media_retry_failed => 'تعذرت إعادة محاولة رسالة الوسائط.';

  @override
  String get failed_media_delete_unavailable => 'الحذف غير متاح الآن.';

  @override
  String get picker_media_library => 'مكتبة الوسائط';

  @override
  String get picker_record_video => 'تسجيل فيديو';

  @override
  String get perm_microphone_record =>
      'يلزم إذن الميكروفون لتسجيل الرسائل الصوتية.';

  @override
  String get group_read_only_not_active =>
      'يمكنك قراءة سجل هذه المجموعة، لكنك لست عضوًا نشطًا.';

  @override
  String get group_read_only_waiting_key =>
      'بانتظار مفتاح المجموعة الحالي قبل أن تتمكن من الإرسال.';

  @override
  String get group_read_only_waiting_identity =>
      'بانتظار هويتك قبل أن تتمكن من الإرسال.';

  @override
  String get group_media_unsupported =>
      'هذا النوع من الوسائط غير مدعوم في المجموعات.';

  @override
  String get upload_progress_title => 'جارٍ رفع الوسائط';

  @override
  String get upload_progress_keep_open =>
      'أبقِ التطبيق مفتوحًا حتى يكتمل الرفع';

  @override
  String get conversation_blocked_contact => 'لقد حظرت جهة الاتصال هذه.';

  @override
  String get conversation_unblock => 'إلغاء الحظر';

  @override
  String get conversation_empty_first_letter =>
      'اكتب الرسالة الأولى\nلبدء محادثتكما';

  @override
  String get media_video_load_failed => 'تعذر تحميل الفيديو';

  @override
  String get conversation_introduce_to_circle => 'عرّفه إلى دائرتك';

  @override
  String conversation_block_contact(String username) {
    return 'حظر $username';
  }

  @override
  String conversation_unblock_contact(String username) {
    return 'إلغاء حظر $username';
  }

  @override
  String get conversation_delete_chat_action => 'حذف المحادثة';

  @override
  String get post_pass_along_title => 'تمرير المنشور';

  @override
  String get post_pass_along_desc =>
      'اختر من يجب أن يستلم هذا التمرير بخطوة واحدة.';

  @override
  String get post_pass_along_no_eligible => 'لا يوجد أصدقاء مؤهلون الآن.';

  @override
  String comments_count(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count تعليق',
      many: '$count تعليقًا',
      few: '$count تعليقات',
      two: 'تعليقان',
      one: 'تعليق واحد',
      zero: 'لا تعليقات',
    );
    return '$_temp0';
  }

  @override
  String get comments_empty => 'لا توجد تعليقات بعد';

  @override
  String get edit_pinned_post_title => 'تعديل المنشور المثبّت';

  @override
  String post_passed_along_by(String username) {
    return 'مرّر $username هذا المنشور';
  }

  @override
  String get home_empty_circle_title => 'دائرتك تنتظر أن تمتلئ';

  @override
  String get home_empty_circle_desc => 'امسح رمز صديق أو شارك رمزك للتواصل';

  @override
  String get home_scan_friend_title => 'مسح رمز صديق';

  @override
  String get home_scan_friend_desc => 'أضف شخصًا إلى دائرتك';

  @override
  String get contact_request_message => 'يريد التواصل معك';

  @override
  String get contact_request_decline => 'رفض';

  @override
  String get share_caption => 'تعليق';

  @override
  String share_title_count(int count) {
    return 'المشاركة مع ($count)';
  }

  @override
  String get share_title_empty => 'المشاركة مع...';

  @override
  String get share_no_targets => 'لا توجد جهات اتصال أو مجموعات بعد';

  @override
  String get share_no_matches => 'لم يتم العثور على نتائج';

  @override
  String get share_contacts_section => 'جهات الاتصال';

  @override
  String get share_groups_section => 'المجموعات';

  @override
  String get share_group_type_announcement => 'إعلان';

  @override
  String get share_group_type_chat => 'دردشة';

  @override
  String get share_sending => 'جارٍ الإرسال...';

  @override
  String get share_send => 'إرسال';

  @override
  String share_target_count(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count هدف',
      many: '$count هدفًا',
      few: '$count أهداف',
      two: 'هدفان',
      one: 'هدف واحد',
    );
    return '$_temp0';
  }

  @override
  String share_summary_sent(String targetCount) {
    return 'تم الإرسال إلى $targetCount';
  }

  @override
  String share_summary_queued(String targetCount) {
    return 'تم حفظ $targetCount لإعادة المحاولة';
  }

  @override
  String share_summary_failed(String targetCount) {
    return 'فشل الإرسال إلى $targetCount';
  }

  @override
  String get share_summary_nothing => 'لم تتم مشاركة أي شيء.';

  @override
  String share_summary_skipped_gifs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم تخطي $count ملف GIF كبير.',
      many: 'تم تخطي $count ملف GIF كبيرًا.',
      few: 'تم تخطي $count ملفات GIF كبيرة.',
      two: 'تم تخطي ملفي GIF كبيرين.',
      one: 'تم تخطي ملف GIF كبير واحد.',
    );
    return '$_temp0';
  }

  @override
  String get time_just_now => 'الآن';

  @override
  String time_min_ago(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'قبل $count دقيقة',
      many: 'قبل $count دقيقة',
      few: 'قبل $count دقائق',
      two: 'قبل دقيقتين',
      one: 'قبل دقيقة',
    );
    return '$_temp0';
  }

  @override
  String time_hour_ago(int count) {
    return 'قبل $count س';
  }

  @override
  String time_day_ago(int count) {
    return 'قبل $count ي';
  }

  @override
  String time_week_ago(int count) {
    return 'قبل $count أ';
  }

  @override
  String get post_expired => 'انتهت الصلاحية';

  @override
  String post_expires_days_hours(int days, int hours) {
    return 'ينتهي خلال $days ي $hours س';
  }

  @override
  String post_expires_days(int days) {
    return 'ينتهي خلال $days ي';
  }

  @override
  String post_expires_hours(int hours) {
    return 'ينتهي خلال $hours س';
  }

  @override
  String post_expires_minutes(int minutes) {
    return 'ينتهي خلال $minutes د';
  }

  @override
  String get post_expires_soon => 'ينتهي قريبًا';

  @override
  String get post_photo_upload_failed => 'فشل رفع الصورة';

  @override
  String get post_photo_pending_upload => 'الصورة بانتظار الرفع';

  @override
  String get post_photos_pending_upload => 'الصور بانتظار الرفع';

  @override
  String get post_video_upload_failed => 'فشل رفع الفيديو';

  @override
  String get post_video_pending_upload => 'الفيديو بانتظار الرفع';

  @override
  String get post_voice_upload_failed => 'فشل رفع الصوت';

  @override
  String get post_voice_pending_upload => 'الملاحظة الصوتية بانتظار الرفع';

  @override
  String get post_media_upload_failed => 'فشل رفع الوسائط';

  @override
  String get post_media_pending_upload => 'الوسائط بانتظار الرفع';

  @override
  String get post_media_upload_failed_desc =>
      'بقي هذا المنشور محليًا لأن رفع الوسائط لم يكتمل.';

  @override
  String get post_media_pending_upload_desc =>
      'سيستلمه المستلمون بعد اكتمال الرفع.';

  @override
  String get post_send_pass => 'إرسال التمرير';

  @override
  String get btn_saving => 'جارٍ الحفظ...';

  @override
  String get intro_from => 'من';

  @override
  String get intro_empty => 'لا توجد تعارفات بعد';

  @override
  String get intro_tab_desc =>
      'هؤلاء أشخاص يعرفهم أصدقاؤك جيدًا. عندما تقبلان كلاكما، يمكنكما بدء الدردشة.';

  @override
  String intro_banner_title(String username) {
    return 'ساعد $username على التعرف إلى دائرتك';
  }

  @override
  String get intro_banner_desc => 'عرّفه إلى أصدقاء قد ينسجم معهم';

  @override
  String get intro_make_introductions => 'إنشاء تعارفات';

  @override
  String get intro_maybe_later => 'ربما لاحقًا';

  @override
  String get introduced_by_label => 'تم التعارف بواسطة';

  @override
  String get intro_unavailable => 'غير متاح';

  @override
  String intro_waiting_for(String username) {
    return 'بانتظار $username';
  }

  @override
  String get intro_waiting_for_them => 'بانتظار الطرف الآخر';

  @override
  String intro_sent_count(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم إرسال $count تعارف',
      many: 'تم إرسال $count تعارفًا',
      few: 'تم إرسال $count تعارفات',
      two: 'تم إرسال تعارفين',
      one: 'تم إرسال تعارف واحد',
    );
    return '$_temp0';
  }

  @override
  String get intro_back_to_conversation => 'العودة إلى المحادثة';

  @override
  String get identity_tagline => 'هويتك تحت سيطرتك';

  @override
  String get startup_failed_title => 'فشل التهيئة';

  @override
  String get identity_restore_action => 'استعادة الهوية';

  @override
  String get settings_peer_id_title => 'معرّف النظير';

  @override
  String get settings_peer_id_desc => 'معرّفك الفريد على الشبكة';

  @override
  String intro_and_more(String names, int count) {
    return '$names و$count آخرون';
  }

  @override
  String get orbit_block_action => 'حظر';

  @override
  String get orbit_unblock_action => 'إلغاء الحظر';

  @override
  String get orbit_delete_action => 'حذف';

  @override
  String get orbit_archive_action => 'أرشفة';

  @override
  String get orbit_unarchive_action => 'إلغاء الأرشفة';

  @override
  String get orbit_archived_empty_title => 'لا يوجد أصدقاء مؤرشفون بعد';

  @override
  String get orbit_archived_empty_desc => 'اسحب لليسار على صديق لأرشفته.';

  @override
  String get orbit_inner_circle_badge => 'الدائرة الداخلية';

  @override
  String get orbit_inner_circle_title => 'دائرتك الداخلية';

  @override
  String orbit_pending_items(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عنصر قيد الانتظار',
      many: '$count عنصرًا قيد الانتظار',
      few: '$count عناصر قيد الانتظار',
      two: 'عنصران قيد الانتظار',
      one: 'عنصر واحد قيد الانتظار',
    );
    return '$_temp0';
  }

  @override
  String get orbit_pending_group_invites => 'دعوات المجموعات المعلقة';

  @override
  String get orbit_pending_group_intro_desc =>
      'راجع دعوات المجموعات المعلقة هنا، ثم التعارفات أدناه. بعد القبول، تظهر المجموعة في Orbit وتلحق برسائل صندوق الوارد غير المتصل.';

  @override
  String orbit_no_friends_matching(String query) {
    return 'لا يوجد أصدقاء يطابقون \"$query\"';
  }

  @override
  String get feed_blocked => 'محظور';

  @override
  String feed_introduced_by(String username) {
    return 'تم التعارف بواسطة $username';
  }

  @override
  String get feed_previously_seen => 'شوهد سابقًا';

  @override
  String get feed_replying_to => 'ردًا على';

  @override
  String get feed_view_earlier_messages => 'عرض الرسائل السابقة';

  @override
  String feed_ready_for_user(String username) {
    return 'موجزك جاهز، @$username. ستظهر الاتصالات الجديدة هنا.';
  }

  @override
  String get feed_loading => 'جارٍ تحميل الموجز...';

  @override
  String get feed_syncing_threads => 'لا تزال محادثاتك الأخيرة قيد المزامنة.';

  @override
  String get qr_added_to_circle => 'تمت الإضافة إلى دائرتك!';

  @override
  String get btn_ok => 'حسنًا';

  @override
  String get qr_already_in_circle => 'موجود بالفعل في دائرتك!';

  @override
  String get qr_contact_added_previously => 'تمت إضافة جهة الاتصال هذه سابقًا';

  @override
  String get btn_got_it => 'فهمت';

  @override
  String orbit_intro_banner_mixed(int inviteCount, int introCount) {
    String _temp0 = intl.Intl.pluralLogic(
      inviteCount,
      locale: localeName,
      other: '$inviteCount دعوة مجموعة',
      many: '$inviteCount دعوة مجموعة',
      few: '$inviteCount دعوات مجموعة',
      two: 'دعوتا مجموعة',
      one: 'دعوة مجموعة واحدة',
    );
    String _temp1 = intl.Intl.pluralLogic(
      introCount,
      locale: localeName,
      other: '$introCount تعارف',
      many: '$introCount تعارفًا',
      few: '$introCount تعارفات',
      two: 'تعارفان',
      one: 'تعارف واحد',
    );
    return '$_temp0 و$_temp1 بانتظارك';
  }

  @override
  String orbit_intro_banner_invites(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'راجع دعوة المجموعة وانضم من التعارفات',
      many: 'راجع دعوات المجموعة وانضم من التعارفات',
      few: 'راجع دعوات المجموعة وانضم من التعارفات',
      two: 'راجع دعوتي المجموعة وانضم من التعارفات',
      one: 'راجع دعوة المجموعة وانضم من التعارفات',
    );
    return '$_temp0';
  }

  @override
  String get orbit_intro_banner_intros => 'راجع التعارفات واقبلها لبدء الدردشة';

  @override
  String group_member_invited_count(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تمت دعوة $count عضو',
      many: 'تمت دعوة $count عضوًا',
      few: 'تمت دعوة $count أعضاء',
      two: 'تمت دعوة عضوين',
      one: 'تمت دعوة عضو واحد',
    );
    return '$_temp0';
  }

  @override
  String group_member_added_count(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تمت إضافة $count عضو',
      many: 'تمت إضافة $count عضوًا',
      few: 'تمت إضافة $count أعضاء',
      two: 'تمت إضافة عضوين',
      one: 'تمت إضافة عضو واحد',
    );
    return '$_temp0';
  }

  @override
  String get group_invite_missing_key_issue =>
      'لم تُرسل الدعوات لأن المجموعة تفتقد أحدث مفتاح لها';

  @override
  String group_invite_issues(String details) {
    return 'مشكلات الدعوة: $details';
  }

  @override
  String get group_members_publish_failed_issue => 'تعذر نشر حدث إضافة الأعضاء';

  @override
  String group_member_added_with_warnings(String prefix, String issues) {
    return '$prefix، لكن $issues.';
  }

  @override
  String group_invite_joined(String name) {
    return 'انضممت إلى $name';
  }

  @override
  String get group_invite_no_longer_available => 'لم تعد الدعوة متاحة';

  @override
  String get group_invite_expired => 'انتهت صلاحية الدعوة';

  @override
  String get group_invite_revoked => 'تم إلغاء الدعوة';

  @override
  String get group_invite_already_used => 'تم استخدام الدعوة بالفعل';

  @override
  String get group_invite_wrong_identity => 'الدعوة لهوية أخرى';

  @override
  String get group_invite_needs_key => 'تحتاج الدعوة إلى مادة مفاتيح جديدة';

  @override
  String get group_invite_invalid => 'لم تعد الدعوة صالحة';

  @override
  String get group_invite_duplicate_group => 'تمت إضافة المجموعة بالفعل';

  @override
  String group_invite_joined_recovery(String name) {
    return 'انضممت إلى $name، لكن الاسترداد ما زال يلحق بالرسائل';
  }

  @override
  String get group_invite_accepted_recovery =>
      'تم قبول الدعوة، لكن الاسترداد ما زال يلحق بالرسائل';

  @override
  String get group_invite_accept_failed => 'فشل قبول الدعوة';

  @override
  String get group_invite_declined => 'تم رفض الدعوة';

  @override
  String get group_invite_decline_failed => 'فشل رفض الدعوة';

  @override
  String get post_pin_retrying => 'سيستمر تحديث التثبيت في إعادة المحاولة';

  @override
  String get post_pin_queued => 'تمت جدولة تحديث التثبيت لإعادة المحاولة';

  @override
  String get post_pin_failed => 'فشل تحديث التثبيت';

  @override
  String get post_pin_could_not => 'تعذر تثبيت المنشور';

  @override
  String get post_pinned_update_retrying =>
      'سيستمر تحديث المنشور المثبّت في إعادة المحاولة';

  @override
  String get post_pinned_update_queued =>
      'تمت جدولة تحديث المنشور المثبّت لإعادة المحاولة';

  @override
  String get post_pinned_update_failed => 'فشل تحديث المنشور المثبّت';

  @override
  String get post_pinned_update_could_not => 'تعذر تحديث المنشور المثبّت';

  @override
  String get post_pin_removal_retrying =>
      'سيستمر إزالة التثبيت في إعادة المحاولة';

  @override
  String get post_pin_removal_queued =>
      'تمت جدولة إزالة التثبيت لإعادة المحاولة';

  @override
  String get post_pin_removal_failed => 'فشلت إزالة التثبيت';

  @override
  String get post_pin_remove_could_not => 'تعذرت إزالة التثبيت';

  @override
  String get post_repost_retrying => 'سيستمر إعادة النشر في إعادة المحاولة';

  @override
  String get post_repost_queued => 'تمت جدولة إعادة النشر لإعادة المحاولة';

  @override
  String get post_repost_media_failed => 'تعذر تجهيز وسائط إعادة النشر';

  @override
  String get post_repost_could_not => 'تعذر تجهيز إعادة النشر';

  @override
  String get post_no_longer_available => 'لم يعد المنشور متاحًا';

  @override
  String get post_repost_not_allowed => 'لا يمكن إعادة نشر هذا المنشور';

  @override
  String get identity_generate_failed => 'فشل إنشاء الهوية';

  @override
  String get identity_save_failed => 'فشل حفظ الهوية';

  @override
  String get qr_no_identity_detail =>
      'لم يتم العثور على هوية. يُرجى إنشاء واحدة أولًا.';

  @override
  String get qr_sign_failed => 'تعذر توقيع رمز QR. يُرجى المحاولة مرة أخرى.';

  @override
  String get qr_unexpected_error =>
      'حدث خطأ غير متوقع. يُرجى المحاولة مرة أخرى.';

  @override
  String get qr_invalid_title => 'رمز QR غير صالح';

  @override
  String get qr_invalid_body => 'لا يبدو هذا كرمز QR صالح لجهة اتصال.';

  @override
  String get qr_incomplete_title => 'رمز QR غير مكتمل';

  @override
  String get qr_incomplete_body => 'يفتقد رمز QR هذا معلومات مطلوبة.';

  @override
  String get qr_invalid_signature_title => 'توقيع غير صالح';

  @override
  String get qr_invalid_signature_body => 'تعذر التحقق من رمز QR هذا.';

  @override
  String get qr_expired_title => 'انتهت صلاحية رمز QR';

  @override
  String get qr_expired_body =>
      'انتهت صلاحية رمز QR هذا. اطلب من صديقك رمزًا جديدًا.';

  @override
  String get qr_self_title => 'هذا أنت!';

  @override
  String get qr_self_body => 'لا يمكنك إضافة نفسك كجهة اتصال.';

  @override
  String get qr_add_failed =>
      'فشلت إضافة جهة الاتصال. يُرجى المحاولة مرة أخرى.';
}
