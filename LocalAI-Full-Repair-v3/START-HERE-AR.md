# Local AI — الحزمة الكاملة V3

إذا كان Ollama مثبتًا وتنزيل النموذج غير مكتمل، شغّل `RECOVER-MODEL.bat` من هذه الحزمة، ولا تشغّل `INSTALL-ALL.bat` مجددًا. تأكد من ظهور عنوان V3 الكامل.

بعد نجاح استعادة النموذج فقط، شغّل `02-LocalAI-Chat-Integration\INSTALL-CHAT-PLATFORM.bat` إذا لم تكن المنصة مثبتة.

إذا كانت هذه أول عملية تثبيت، شغّل `VERIFY-INTEGRITY.bat` ثم `INSTALL-ALL.bat`.

مجلد النماذج الفعلي يحدده خادم Ollama عند بدء التشغيل. قد يتقدم خيار Settings > Model location في تطبيق Windows على `OLLAMA_MODELS`. لا تغيّر مسارًا ولا تنقل blobs قبل التشخيص.

بعد اكتمال المحرك والمنصة: `D:\LocalAI\Platform\START-CHAT.bat`. بعد إنشاء حساب الإدارة: `D:\LocalAI\Platform\IMPORT-FILTERS.bat`.

لم يُختبر تثبيت PowerShell على جهاز Windows فعلي من بيئة الإنشاء؛ لا تعتبر التثبيت ناجحًا إلا بعد اختبارات الحالة المحلية.
