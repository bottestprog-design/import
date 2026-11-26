# ابدأ هنا — LocalAI Studio Complete v2.4.0

1. تأكد أن Ollama يعمل على http://127.0.0.1:11434 وأن نموذج Qwen الموجود ظاهر في /api/tags.
2. فك ضغط الحزمة الكاملة إلى مجلد جديد. لا تستخدم مجلد v2.3.1 الذي فشل تطبيق إصلاحه.
3. شغّل ONE-CLICK-SETUP.bat فقط.
4. سيفحص المشغّل جميع بصمات الحزمة وصياغة ملفات PowerShell، ثم يختبر قراءة رموز الخروج 0 و37 قبل التثبيت.
5. بعد اكتمال التثبيت شغّل D:\LocalAI\Platform\START-CHAT.bat.
6. افتح http://127.0.0.1:8080 وأنشئ حساب المسؤول الأول.
7. شغّل D:\LocalAI\Platform\VERIFY-MODEL.bat لاختبار رد فعلي من Qwen.
8. استورد الفلاتر عبر D:\LocalAI\Platform\IMPORT-FILTERS.bat بعد إنشاء Admin API Key.

**لا تحذف D:\LocalAI\Platform\.venv ولا D:\LocalAI\Models.** إذا كانت البيئة الحالية صالحة سيعيد المثبّت استخدامها. وإذا كانت غير صالحة فسيحتفظ بها باسم احتياطي قبل إنشاء بيئة بديلة.

استخدم DIAGNOSTICS.bat للفحص وBACKUP-LOCALAI.bat للنسخ الاحتياطي. راجع README-AR.md للتفاصيل.
