# ابدأ من هنا — Local AI Platform Continuation

## قبل التشغيل
- النموذج Qwen موجود بالفعل في Ollama. لا تستخدم أي مثبت قديم ولا تشغّل Recovery مرة أخرى.
- شغّل تطبيق Ollama من قائمة Start وانتظر أن يعمل `http://127.0.0.1:11434`.
- صِل اللابتوب بالشاحن. المثبت ومشغل الشات يمنعان سكون النظام مؤقتًا أثناء عملهما فقط؛ يمكن للشاشة أن تنطفئ.

## التثبيت
1. فك ضغط الحزمة بالكامل في مجلد جديد.
2. شغّل `VERIFY-PACKAGE.bat`. يجب أن تظهر `PACKAGE_INTEGRITY: SUCCESS`.
3. شغّل `RUN-REPAIR.bat` واترك النافذة مفتوحة. تنزيل البرامج وملف Whisper يحتاجان اتصال إنترنت.
4. اقرأ `D:\LocalAI\Platform\PLATFORM-STATUS.txt` وسجل `D:\LocalAI\Logs` بعد انتهاء التثبيت.

## التشغيل بعد التثبيت
1. شغّل `D:\LocalAI\Platform\START-CHAT.bat`.
2. افتح `http://127.0.0.1:8080` وأنشئ حساب المسؤول الأول.
3. شغّل `D:\LocalAI\Platform\VERIFY-MODEL.bat` لاختبار رد فعلي من Qwen دون تنزيله مجددًا.
4. أنشئ Admin API Key ثم شغّل `D:\LocalAI\Platform\IMPORT-FILTERS.bat` لإضافة الفلاتر الثلاثة. المفتاح يُدخل مخفيًا ولا يُحفظ في ملفات الحزمة.

## بعد التثبيت
- `CHECK-LOCALAI.bat`: فحص المحرك والمنصة والصوت والفلاتر.
- `STOP-CHAT.bat`: يوقف خادم Open WebUI الذي بدأه المشغل فقط؛ لا يوقف Ollama.
- لا تحذف `D:\LocalAI\Models` ولا تشغّل مثبت المحرك القديم.

راجع `README-AR.md` للتفاصيل، وإعداد Whisper وDDGS والصوت والخصوصية.
