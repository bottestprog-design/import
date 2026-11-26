# LocalAI Studio Complete v2.3.0

هذه هي حزمة الاستكمال الكاملة لمنصة LocalAI على Windows، مبنية على ملفات الإصدار 2.2 الموجودة في المستودع مع طبقة تصحيح موحدة وأدوات صيانة إضافية.

## حماية المحرك والنموذج الموجودين

حسب تقرير جهازك السابق، Ollama 0.40.18 يعمل محليًا والنموذج موجود بالاسم local-qwen35:latest / qwen3.5:9b-q4_K_M. الحزمة:

- لا تثبّت Ollama ولا تعيد تشغيله.
- لا تسحب نموذج Qwen ولا تحذف أو تنقل D:\LocalAI\Models.
- تتحقق من المحرك والنموذج عبر API المحلي قبل تثبيت منصة المحادثة.
- تحتفظ ببيانات Open WebUI في D:\LocalAI\Platform\Data.

تنبيه: ميزة تحويل الصوت تستخدم Whisper Small كملف منفصل عن Qwen، وقد يحتاج تنزيله اتصال إنترنت. عدم توفر Whisper لا يمنع المحادثة النصية.

## طريقة التشغيل

1. شغّل تطبيق Ollama وانتظر الاستجابة على http://127.0.0.1:11434/api/version.
2. فك ضغط الحزمة بالكامل إلى مجلد عادي.
3. شغّل ONE-CLICK-SETUP.bat فقط.
4. يفحص مدخل التشغيل بصمات الحزمة الأصلية، يطبّق تحسينات v2.3.0، يعيد إنشاء Manifest، ثم يشغّل Repair/Resume.
5. بعد اكتمال التثبيت شغّل D:\LocalAI\Platform\START-CHAT.bat.
6. افتح http://127.0.0.1:8080 وأنشئ حساب المسؤول الأول.
7. شغّل D:\LocalAI\Platform\VERIFY-MODEL.bat لاختبار رد فعلي من Qwen دون تنزيله.
8. استورد الفلاتر من D:\LocalAI\Platform\IMPORT-FILTERS.bat بعد إنشاء Admin API Key.

## ما تضيفه هذه النسخة

- إصلاح قراءة ExitCode في Windows PowerShell 5.1: WaitForExit() ثم Refresh()، مع رفض ExitCode غير المتاح بدل رسالة فشل فارغة.
- إزالة تفعيل Vision افتراضيًا لكل النماذج؛ تُترك قدرات الصور لتعريف النموذج الفعلي في Ollama/Open WebUI.
- توحيد تشغيل الحزمة في ملف واحد مع تحقق سلامة قبل التثبيت.
- DIAGNOSTICS.bat: فحص قراءة فقط لـ Ollama وQwen وPython وOpen WebUI والصوت والفلاتر والمساحة. يكتب تقريرًا ولا يغيّر الإعدادات.
- BACKUP-LOCALAI.bat: نسخة SQLite متسقة لقاعدة المحادثات عبر Online Backup API مع المفتاح والفلاتر والحالة. لا ينسخ نماذج Ollama أو بيئة Python أو ذاكرة Whisper.
- أدوات التشخيص والنسخ الاحتياطي تُنسخ تلقائيًا إلى D:\LocalAI\Platform.

## المكونات الأساسية

- Open WebUI 0.13.5 مثبت بإصدار محدد.
- Python 3.11 أو 3.12 وبيئة افتراضية مستقلة.
- Whisper Small متعدد اللغات وfaster-whisper وPyAV 14.0.1 عند توافر تنزيل الصوت.
- FFmpeg عبر WinGet إن توفر.
- ثلاثة فلاتر: Trusted Content Guard، Accuracy & Thinking، Selective Self Review.
- DuckDuckGo/DDGS مع تأكيد قبل البحث الخارجي.
- ربط محلي افتراضيًا على 127.0.0.1:8080.

## حدود مهمة

- المراجعة الذاتية استدعاء ثانٍ للنموذج نفسه وليست تحققًا مستقلًا أو ضمانًا للصحة.
- Qwen 9B على CPU قد يكون بطيئًا؛ لا تشغّل Whisper والمراجعة الثقيلة مع ضغط RAM.
- إعداد TTS لا يفترض توفر صوت عربي في Windows؛ اختر محركًا متاحًا داخل Open WebUI.
- لا تفتح Open WebUI على الشبكة أو الإنترنت ولا تغيّر الربط إلى 0.0.0.0.
- النسخة الاحتياطية قد تحتوي سجل المحادثات ومفتاح التوقيع؛ لا تشاركها علنًا.

## أوامر الصيانة

- D:\LocalAI\Platform\DIAGNOSTICS.bat — فحص قراءة فقط.
- D:\LocalAI\Platform\BACKUP-LOCALAI.bat — نسخ احتياطي محلي.
- D:\LocalAI\Platform\CHECK-LOCALAI.bat — فحص سريع.
- D:\LocalAI\Platform\VERIFY-MODEL.bat — اختبار الاستدلال.
- D:\LocalAI\Platform\STOP-CHAT.bat — إيقاف Open WebUI الذي بدأه المشغل فقط، دون إيقاف Ollama.

راجع README-AR.md وSTART-HERE-AR.md من الحزمة الأصلية للتفاصيل الإضافية.
