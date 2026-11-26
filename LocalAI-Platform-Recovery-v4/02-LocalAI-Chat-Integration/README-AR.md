# الحزمة 02 — منصة المحادثة والصوت والفلاتر (نسخة مصححة)

## المتطلبات
- إكمال الحزمة 01 ووجود `D:\LocalAI\ENGINE-STATUS.txt` بحالة SUCCESS.
- Windows 11 64-bit، اتصال إنترنت للتثبيت الأول، ويفضل مساحة إضافية 8–12GB على D:.
- WinGet / Microsoft App Installer.

## ما الذي تثبّته؟
- Python 3.11 الموجود على جهازك (أو 3.12 إذا كان مثبتاً) داخل بيئة افتراضية معزولة؛ لا يعيد تثبيت Python إن كان 3.11 صالحاً.
- FFmpeg static full build من WinGet (`Gyan.FFmpeg`) (ضروري لمعالجة الصوت وتقطيع التسجيلات الطويلة).
- Open WebUI مثبت بإصدار ثابت `0.13.4` بدل تثبيت إصدار غير محدد قد يتغير.
- اتصال Ollama على `http://127.0.0.1:11434` والنموذج `local-qwen35:latest` (الاسم المختصر في الأوامر هو `local-qwen35`).
- إعداد Whisper المحلي: `base` متعدد اللغات، `int8`، وVAD مفعّل. المثبت ينزّل أوزان Whisper Base مسبقًا ويختبر تحميلها؛ أول تفريغ صوتي هو اختبار الاستخدام الفعلي.
- ثلاثة فلاتر Python مصححة، مع أداة استيراد محلية تستخدم API Key للمسؤول وتفعّلها تلقائيًا بعد إنشاء الحساب الأول. يتم فحص الصياغة وتشغيل اختبارات سلوكية لها داخل بيئة Open WebUI قبل إكمال التثبيت.
- بحث ويب عبر DDGS المدمج في Open WebUI، دون مفتاح API، مع نافذة موافقة قبل إرسال استعلام خارجي.
- أداة `IMPORT-FILTERS.bat` لاستيراد الفلاتر الثلاثة آليًا عبر API Key محلي يُدخل بشكل مخفي ولا يُحفظ.
- تثبيت `av==14.0.1` لضمان توافق تحويل الصوت مع Whisper في تثبيت pip على Windows.

## التثبيت
1. فك ضغط ZIP كاملًا.
2. شغّل `INSTALL-CHAT-PLATFORM.bat`.
3. انتظر حتى يظهر `SUCCESS`.
4. اقرأ `D:\LocalAI\Platform\PLATFORM-STATUS.txt`.
5. شغّل `D:\LocalAI\Platform\START-CHAT.bat`.
6. افتح `http://127.0.0.1:8080` وأنشئ حساب المسؤول الأول.
7. بعد إنشاء حساب المسؤول الأول، افتح Settings → Account وأنشئ API Key، ثم شغّل `D:\LocalAI\Platform\IMPORT-FILTERS.bat` والصق المفتاح في مطالبة الإدخال المخفية. المستورد يضيف/يحدّث الفلاتر ويجعلها Active وGlobal، وينشئ نسخة احتياطية قبل تحديث أي فلتر موجود. لا يحفظ المفتاح.
8. في Admin Panel → Models افتح `local-qwen35:latest`، وتأكد من تفعيل Web Search / Built-in Tools وأن Function Calling على Native. في المحادثة استخدم زر البحث عند الحاجة؛ ستظهر موافقة قبل إرسال عبارة البحث إلى مزود خارجي. في قاعدة بيانات قديمة، متغيرات ConfigVar قد لا تغيّر إعدادات محفوظة سابقًا؛ عدّلها من Admin Panel → Settings.

## البحث والتحقق من المعلومات
- يستخدم البحث DDGS المضمّن في Open WebUI؛ لا يحتاج تثبيت خدمة مستقلة أو مفتاح API.
- مشغّل التشغيل يفعّل البحث ويطلب موافقتك قبل إرسال عبارة البحث لمزود خارجي.
- من Admin Panel → Settings → Web Search تأكد من أن البحث Enabled والمحرك DDGS والـ Backend على Auto.
- من Admin Panel → Models → Edit `local-qwen35` فعّل Built-in Tools / Web Search واترك Function Calling على Native أولًا. بعد ذلك استخدم زر Web Search في المحادثة.
- إذا لم يستدعِ النموذج البحث بشكل موثوق، جرّب Legacy Function Calling من إعدادات النموذج؛ هذا مسار توافق قديم وقد لا يتيح باقي أدوات Native.
- البحث يساعد في المعلومات الحالية لكنه لا يضمن صحة النتائج؛ راجع المصادر المعروضة.

## مكونات الصوت
- Whisper Base INT8 للتعرف على العربية والإنجليزية (اختير افتراضياً لتقليل الضغط على ذاكرة 16GB؛ يمكن ترقيته إلى Small لاحقاً) من الميكروفون والتسجيلات. من Settings → Audio اختر Local Whisper (اترك STT Engine على Local/Default)، ولا تختَر Web API إن كنت تريد أن تتم المعالجة على Whisper المحلي.
- `WHISPER_COMPUTE_TYPE=int8` مناسب لتشغيل CPU.
- `WHISPER_VAD_FILTER=true` لتقليل أثر الصمت قبل/أثناء التفريغ؛ VAD مدمج ضمن محرك faster-whisper ولا يتطلب تنزيل فلتر منفصل.
- إخراج الكلام (TTS) في هذه النسخة عبر Web Speech API داخل المتصفح؛ لا يتم تثبيت نموذج TTS محلي منفصل. توفر وجودة الصوت العربي تعتمدان على أصوات Windows/Edge المثبتة. يمكنك اختيار صوت عربي من Settings → Audio إذا ظهر ضمن قائمة الأصوات.
- نموذج Whisper Base يكون محفوظًا مسبقًا في `D:\LocalAI\Platform\Data\cache\whisper\models`.

## إعداد اللغة والصوت
- اجعل لغة الواجهة Arabic من Settings → General → Language إن لم تبدأ بالعربية تلقائيًا.
- للتعرف على الصوت: Settings → Audio → Speech-to-Text Engine: Local Whisper؛ اختر Arabic أو Auto في Language.
- لقراءة الرد: اختر Web API في Text-to-Speech Engine، ثم اختر صوتًا عربيًا متاحًا. إذا لم يظهر صوت عربي، أضف حزمة صوت عربية من Windows Settings → Time & language → Speech.

## تحقق وتشخيص
شغّل `D:\LocalAI\Platform\CHECK-LOCALAI.bat`؛ يفحص Ollama، اسم النموذج، Open WebUI، FFmpeg، ومجلد الفلاتر.

## التشغيل والإيقاف
- ابدأ Ollama تلقائيًا عند الحاجة من مشغل الدردشة، أو شغّل `D:\LocalAI\START-ENGINE.bat`.
- شغّل `D:\LocalAI\Platform\START-CHAT.bat` واترك نافذته مفتوحة أثناء استخدام المنصة.
- أوقف Open WebUI بإغلاق نافذة التشغيل أو Ctrl+C. Ollama يظل يعمل في الخلفية.

## لماذا تم إصلاح النسخة السابقة؟
- تثبيت إصدار Open WebUI محدد `0.13.4` متوافق مع Python 3.11/3.12.
- إزالة إعداد `think="high"` الخاطئ لـ Qwen 3.5؛ الفلتر الجديد يرسل `think=true`.
- فلتر المراجعة المحدّث يعدّل `content` و`output_text` كي تظهر النسخة المراجعة فعلًا في الواجهة.
- منع مراجعة كل جواب طويل بلا داعٍ؛ الوضع الذكي يركز على الحسابات والبرمجة وطلبات التدقيق.
- إضافة فحوصات مسبقة وبعد التثبيت، وتنزيل Whisper مسبقًا، واختبارات سلوكية للفلاتر، وسجل واضح.
- عدم تضمين ملفات `__pycache__` أو ملفات مؤقتة داخل ZIP.
- ضبط بحث DDGS على Auto لتجنّب الاعتماد على مزود واحد، مع تفعيل تأكيد المستخدم قبل كل بحث.

## الروابط الرسمية
- Open WebUI Quick Start: https://docs.openwebui.com/getting-started/quick-start/
- Open WebUI Filter Functions: https://docs.openwebui.com/features/extensibility/plugin/functions/filter/
- Open WebUI Audio: https://docs.openwebui.com/troubleshooting/audio/
- FFmpeg: https://www.gyan.dev/ffmpeg/builds/
