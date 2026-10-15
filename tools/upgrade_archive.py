from pathlib import Path
import json, re, shutil, zipfile, hashlib, os

ROOT = Path(__file__).resolve().parents[1]
ARCHIVE = ROOT / "chat_BOT_v8.0.0_simple_fixed.zip"
OUT = ROOT / "build-output"
WORK = OUT / "source"
PROJECT = WORK / "work_v800"

def replace_once(text, old, new, label):
    n = text.count(old)
    if n != 1:
        raise RuntimeError("%s: expected one anchor, found %s" % (label, n))
    return text.replace(old, new, 1)

if not ARCHIVE.is_file():
    raise SystemExit("Source archive is missing: " + str(ARCHIVE))
if OUT.exists():
    shutil.rmtree(OUT)
WORK.mkdir(parents=True)
with zipfile.ZipFile(ARCHIVE) as zf:
    for info in zf.infolist():
        target = (WORK / info.filename).resolve()
        if WORK.resolve() not in target.parents and target != WORK.resolve():
            raise SystemExit("Unsafe archive path: " + info.filename)
    zf.extractall(WORK)
if not PROJECT.is_dir():
    raise SystemExit("Expected work_v800 project folder not found")

def read_text(rel):
    return (PROJECT / rel).read_text(encoding="utf-8")

def write_text(rel, value):
    p = PROJECT / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(value, encoding="utf-8", newline="\n")

# The regression test in some copies has embedded NUL bytes. Preserve the original
# bytes before repairing the executable test so no submitted content is discarded.
regression = PROJECT / "test" / "regression.js"
original_regression = regression.read_bytes()
if b"\x00" in original_regression:
    backup = PROJECT / "test" / "regression.original-backup.bin"
    if not backup.exists():
        backup.write_bytes(original_regression)
    regression.write_text("""\"use strict\";
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const store = require('../src/store');
const groups = require('../src/groups');
const media = require('../src/media');
const backgrounds = require('../src/backgrounds');
const { render, scopeOk } = require('../src/interaction');
const { nextRun } = require('../src/scheduler');

assert.equal(groups.isGroupId('120363000000@g.us'), true);
assert.equal(groups.normalizeGid('120363000000@g.us'), '120363000000@g.us');
assert.equal(groups.extractInviteCode('https://chat.whatsapp.com/abc-123'), 'abc-123');
assert.equal(backgrounds.normalize('unknown', {}, 0.9).mode, 'aurora');
assert.equal(render('Hi {{sender}}', { sender: 'x' }), 'Hi x');
assert.equal(scopeOk('groups', '120@g.us'), true);
assert.equal(scopeOk('private', '120@g.us'), false);
assert.equal(nextRun(store.loadSession(store.activeSessionId())), null);

const sid = 'regression-' + Date.now();
const session = store.createSession('Regression test');
assert.ok(session && session.id);
const base = store.loadSession(session.id);
assert.ok(base && Array.isArray(base.recipients) && Array.isArray(base.groups));
const p = store.getPaths(session.id);
const file = path.join(p.media, 'regression-test.png');
fs.writeFileSync(file, Buffer.from([0x89, 0x50, 0x4e, 0x47]));
assert.ok(media.safePath(p.media, 'regression-test.png').endsWith('regression-test.png'));
assert.throws(() => media.safePath(p.media, '../outside.png'));
fs.rmSync(p.dir, { recursive: true, force: true });
console.log('regression: ok');
""", encoding="utf-8", newline="\n")

# Offline assistant logic. No model provider, API key, cloud request, or account required.
assistant_source = r'''"use strict";
const crypto = require('node:crypto');

const NAV = [
  { keys: ['الرئيسية', 'افتح الرئيسية', 'dashboard', 'home'], page: 'dashboard', label: 'الرئيسية' },
  { keys: ['الإرسال', 'الارسال', 'افتح الإرسال', 'افتح الارسال', 'send'], page: 'send', label: 'الإرسال' },
  { keys: ['الأشخاص', 'الاشخاص', 'افتح الأشخاص', 'افتح الاشخاص', 'people', 'contacts'], page: 'people', label: 'الأشخاص' },
  { keys: ['المجموعات', 'افتح المجموعات', 'groups'], page: 'groups', label: 'المجموعات' },
  { keys: ['التفاعل', 'افتح التفاعل', 'interaction'], page: 'interaction', label: 'التفاعل' },
  { keys: ['الجلسة', 'افتح الجلسة', 'واتساب', 'whatsapp', 'session'], page: 'session', label: 'الجلسة' },
  { keys: ['الإعدادات', 'الاعدادات', 'افتح الإعدادات', 'settings'], page: 'settings', label: 'الإعدادات' }
];

function norm(v) { return String(v || '').trim().toLocaleLowerCase('ar'); }
function ensurePair(settings) {
  if (!settings.assistantPairing || typeof settings.assistantPairing !== 'object') {
    settings.assistantPairing = { pendingCode: '', expiresAt: 0, verifiedChatId: '', verifiedAt: '', failedAttempts: 0, lockedUntil: 0, lastReportAt: 0 };
  }
  return settings.assistantPairing;
}
function getRuntime(whatsapp, id) {
  try { return whatsapp.listRuntime(id) || {}; } catch { return {}; }
}
function diagnose(store, whatsapp, id) {
  const s = store.loadSession(id);
  const runtime = getRuntime(whatsapp, id);
  const logs = Array.isArray(s.logs) ? s.logs : [];
  const issues = logs.filter(x => /error|warn|failed|فشل|تعذر|خطأ|انفصل/i.test(String(x.level || '') + ' ' + String(x.message || x.text || ''))).slice(0, 5);
  const problems = [];
  if (!runtime.ready) problems.push('جلسة WhatsApp غير متصلة. افتح «الجلسة» وتحقق من الحالة ثم امسح QR إذا طُلب.');
  if (!Array.isArray(s.recipients) || !s.recipients.some(x => x.enabled !== false)) problems.push('لا يوجد مستلم مفعّل. افتح «الأشخاص» وأضف رقمًا صحيحًا مع مفتاح الدولة.');
  if (!Array.isArray(s.groups)) problems.push('تعذر قراءة قائمة المجموعات من ملف الجلسة؛ احتفظ بنسخة احتياطية وافحص سجل التشغيل.');
  if (issues.length) problems.push('يوجد تحذير أو خطأ في سجل الجلسة؛ راجع السجل قبل إعادة الإرسال.');
  return {
    session: s.name || 'الجلسة الحالية',
    whatsapp: runtime.status || (runtime.ready ? 'ready' : 'disconnected'),
    ready: !!runtime.ready,
    recipients: (s.recipients || []).length,
    enabledRecipients: (s.recipients || []).filter(x => x.enabled !== false).length,
    groups: (s.groups || []).length,
    media: (() => { try { return require('./media').scanImages(store.getPaths(id).media).files.length; } catch { return 0; } })(),
    issues,
    problems
  };
}
function reply(store, whatsapp, id, value) {
  const message = String(value || '').trim().slice(0, 1600);
  if (!message) return { text: 'اكتب سؤالك أو اختر أمرًا محفوظًا. اكتب «الأوامر» لعرض ما يمكنني تنفيذه دون API.', action: null };
  const q = norm(message);
  for (const item of NAV) {
    if (item.keys.some(k => q === norm(k) || q === norm('افتح ' + k) || q === norm('اذهب إلى ' + k) || q === norm('انتقل إلى ' + k))) {
      return { text: 'سأفتح صفحة ' + item.label + ' الآن.', action: { type: 'navigate', page: item.page } };
    }
  }
  if (/(الأوامر|ال commands|commands|ماذا تستطيع|مساعدة|help)/i.test(q)) {
    return { text: 'أوامري المحلية المحفوظة:\\n• شخّص النظام: يفحص اتصال WhatsApp والإعدادات الأساسية.\\n• راجع الأخطاء: يعرض أحدث التحذيرات والأخطاء المحفوظة.\\n• افتح الرئيسية / الإرسال / الأشخاص / المجموعات / التفاعل / الجلسة / الإعدادات.\\n• كيف أصلح الاتصال؟\\n• كيف أربط واتساب للتقارير؟\\n• كيف أحمي بياناتي؟\\n\\nهذه الأوامر تعمل محليًا دون API خارجي. لا أرسل رسالة واتساب إلا بعد ربط خاص والتحقق وبضغطك على إرسال التقرير.', action: null };
  }
  if (/(شخّص|شخص|تشخيص|فحص النظام|حالة النظام|diagnos|status|افحص النظام)/i.test(q)) {
    const d = diagnose(store, whatsapp, id);
    const lines = ['نتيجة الفحص المحلي:', '• الجلسة: ' + d.session, '• WhatsApp: ' + (d.ready ? 'متصل' : 'غير متصل') + ' (' + d.whatsapp + ')', '• الأشخاص: ' + d.enabledRecipients + ' مفعّل من ' + d.recipients, '• المجموعات: ' + d.groups, '• ملفات الوسائط: ' + d.media];
    if (d.problems.length) lines.push('', 'ما أنصح به الآن:', ...d.problems.map((x, i) => (i + 1) + '. ' + x));
    else lines.push('', 'لم تظهر مشكلة أساسية في الفحص المحلي. جرّب إرسال اختبار إلى جهة تملك إذن مراسلتها.');
    return { text: lines.join('\\n'), action: null, diagnostics: d };
  }
  if (/(الأخطاء|الاخطاء|السجل|آخر الأخطاء|اخر الاخطاء|logs|errors|تحذيرات)/i.test(q)) {
    const s = store.loadSession(id);
    const logs = (Array.isArray(s.logs) ? s.logs : []).slice(0, 12);
    if (!logs.length) return { text: 'السجل المحلي لا يحتوي على رسائل محفوظة حاليًا. افتح صفحة الجلسة ثم حدّث السجل بعد ظهور المشكلة.', action: null };
    return { text: 'آخر الرسائل المسجلة في الجلسة:\\n' + logs.map((x, i) => (i + 1) + '. [' + String(x.level || x.type || 'INFO') + '] ' + String(x.message || x.text || x.event || '').slice(0, 280)).join('\\n'), action: null };
  }
  if (/(كيف أصلح الاتصال|مشكلة الاتصال|غير متصل|qr|كيو آر|الاتصال|disconnected|auth)/i.test(q)) {
    return { text: 'خطوات إصلاح الاتصال:\\n1. افتح صفحة «الجلسة» وتحقق من الحالة.\\n2. إذا ظهرت QR، امسحها من WhatsApp في الهاتف المرتبط بالحساب.\\n3. تأكد من اتصال الإنترنت وعدم نوم الجهاز.\\n4. اضغط تحديث، ثم جرّب إعادة الاتصال مرة واحدة.\\n5. إذا ظهرت «فشل التوثيق»، افصل الجلسة وأعد الربط فقط بعد التأكد أن هذا هو الحساب الصحيح.\\n6. إذا استمرت المشكلة، انسخ أحدث خطأ من السجل وأرسله هنا؛ لن أطلب منك كشف رمز QR أو ملفات المصادقة.', action: { type: 'navigate', page: 'session' } };
  }
  if (/(ربط واتساب|واتساب للتقارير|التحقق|pair|report)/i.test(q)) {
    return { text: 'لربط محادثة خاصة للتقارير: تأكد أولًا أن جلسة WhatsApp متصلة، ثم اضغط «إنشاء رمز ربط» في هذه الصفحة. أرسل النص PAIR متبوعًا بالرمز من حسابك الخاص إلى حساب WhatsApp المتصل بالتطبيق خلال 5 دقائق. لا ترسل الرمز لأي شخص آخر. بعد التحقق، سيظهر أن المحادثة مرتبطة. إرسال أي تقرير يحتاج ضغط زر وموافقة صريحة منك.', action: null };
  }
  if (/(خصوصية|أمان|امان|بياناتي|حماية|secret|privacy|security)/i.test(q)) {
    return { text: 'نصائح الخصوصية: لا تشارك QR أو مجلد auth أو سجلات تتضمن أرقامًا خاصة. احتفظ بمجلد data في مكان موثوق وخذ نسخة احتياطية عند إيقاف التطبيق. أبقِ HOST على 127.0.0.1 ولا تعرض لوحة التحكم على الإنترنت. راجع نص التقرير قبل إرساله إلى WhatsApp.', action: null };
  }
  if (/(حجم الملف|ملف كبير|رفع الملف|upload|limit_file_size)/i.test(q)) {
    return { text: 'إذا رُفض ملف بسبب حجمه: تحقق من رسالة الخطأ والحد المعروض في الواجهة، جرّب ملفًا أصغر أو ضغط الصورة، ولا تغيّر حدود الخادم عشوائيًا لأن ذلك يزيد استهلاك الذاكرة والمساحة. إذا كان الملف مهمًا، احتفظ بالأصل قبل أي تعديل.', action: null };
  }
  if (/(تكرار|رسالة مكررة|duplicate|إعادة الإرسال|اعادة الارسال|send_uncertain)/i.test(q)) {
    return { text: 'إذا لم تتأكد حالة الإرسال، لا تضغط إرسال مرارًا. قد تكون الرسالة أُرسلت لكن التأكيد تأخر. افحص سجل الجلسة والمحادثة المستهدفة، ثم أعد المحاولة بعد التأكد لتجنب التكرار.', action: null };
  }
  if (/(جدولة|موعد|schedule|التشغيل التلقائي|automation)/i.test(q)) {
    return { text: 'لمراجعة الجدولة: افتح «الإعدادات» ثم قسم التشغيل المتقدم. تحقق من المنطقة الزمنية والوقت والأهداف والملف المحدد، وأن هناك محتوى غير فارغ. راجع السجل بعد أول تشغيل؛ لا تعتمد على المظهر وحده لتأكيد التنفيذ.', action: { type: 'navigate', page: 'settings' } };
  }
  return { text: 'أفهم رسالتك، لكن هذا الإصدار يعمل كمساعد محلي بقواعد محفوظة ولا يستخدم API أو نموذجًا سحابيًا؛ لذلك لن أخمّن جوابًا غير موثوق. جرّب أمرًا مثل «شخّص النظام»، «راجع الأخطاء»، «كيف أصلح الاتصال؟»، «كيف أحمي بياناتي؟» أو «افتح الجلسة». يمكنك كذلك وصف رسالة الخطأ كاملة وسأطابقها مع قواعد التشخيص المحلية المتاحة.', action: null };
}
function startPairing(store, whatsapp, id) {
  const runtime = getRuntime(whatsapp, id);
  if (!runtime.ready) throw new Error('اتصل بواتساب أولًا من صفحة الجلسة ثم أنشئ رمز الربط.');
  const s = store.loadSession(id);
  const p = ensurePair(s.settings);
  p.pendingCode = String(crypto.randomInt(100000, 1000000));
  p.expiresAt = Date.now() + 5 * 60 * 1000;
  p.failedAttempts = 0;
  p.lockedUntil = 0;
  store.saveSession(s);
  return { code: p.pendingCode, expiresAt: new Date(p.expiresAt).toISOString(), instruction: 'أرسل إلى حساب WhatsApp المتصل رسالة خاصة تحتوي: PAIR ' + p.pendingCode + ' خلال 5 دقائق.' };
}
function pairingStatus(store, id) {
  const s = store.loadSession(id);
  const p = ensurePair(s.settings);
  if (!p.verifiedChatId && !p.pendingCode && !p.expiresAt) return { verified: false, pending: false, message: 'لا توجد محادثة موثقة بعد.' };
  const pending = !!p.pendingCode && Number(p.expiresAt) > Date.now();
  return { verified: !!p.verifiedChatId, verifiedAt: p.verifiedAt || null, pending, expiresAt: pending ? new Date(p.expiresAt).toISOString() : null, message: p.verifiedChatId ? 'تم التحقق من محادثة خاصة.' : pending ? 'بانتظار إرسال رمز الربط في رسالة خاصة.' : 'انتهت صلاحية رمز الربط؛ أنشئ رمزًا جديدًا.' };
}
async function handlePairMessage(store, whatsapp, id, msg, log) {
  const body = String(msg && msg.body || '').trim();
  const match = body.match(/^PAIR\s+(\d{6})$/i);
  if (!match) return false;
  if (!msg || msg.fromMe) return true;
  const chatId = String(msg.from || msg.chatId || '');
  if (chatId.endsWith('@g.us') || chatId === 'status@broadcast' || !(chatId.endsWith('@c.us') || chatId.endsWith('@lid'))) return true;
  const s = store.loadSession(id);
  const p = ensurePair(s.settings);
  const now = Date.now();
  if (Number(p.lockedUntil) > now) {
    try { await whatsapp.replyToMessage(id, msg, 'محاولات الربط كثيرة. انتظر دقيقة ثم أنشئ رمزًا جديدًا من الموقع.'); } catch {}
    return true;
  }
  if (!p.pendingCode || Number(p.expiresAt) <= now) {
    try { await whatsapp.replyToMessage(id, msg, 'لا يوجد رمز ربط نشط أو انتهت صلاحيته. أنشئ رمزًا جديدًا من لوحة الموقع.'); } catch {}
    return true;
  }
  if (match[1] !== String(p.pendingCode)) {
    p.failedAttempts = Number(p.failedAttempts || 0) + 1;
    if (p.failedAttempts >= 5) { p.lockedUntil = now + 60 * 1000; p.pendingCode = ''; p.expiresAt = 0; }
    store.saveSession(s);
    try { await whatsapp.replyToMessage(id, msg, 'رمز الربط غير صحيح. تأكد من الرمز الظاهر في الموقع.'); } catch {}
    return true;
  }
  p.verifiedChatId = chatId;
  p.verifiedAt = new Date().toISOString();
  p.pendingCode = '';
  p.expiresAt = 0;
  p.failedAttempts = 0;
  p.lockedUntil = 0;
  store.saveSession(s);
  if (typeof log === 'function') log(id, 'INFO', 'تم توثيق محادثة المساعد للتقارير.');
  try { await whatsapp.replyToMessage(id, msg, 'تم التحقق بنجاح. يمكنك الآن إرسال التقارير من الموقع بعد مراجعتها والموافقة عليها.'); } catch {}
  return true;
}
async function sendReport(store, whatsapp, id, value) {
  const text = String(value || '').trim();
  if (!text) throw new Error('اكتب ملخص التقرير أولًا.');
  if (text.length > 3500) throw new Error('التقرير طويل جدًا؛ الحد 3500 حرف.');
  const s = store.loadSession(id);
  const p = ensurePair(s.settings);
  if (!p.verifiedChatId || !p.verifiedAt) throw new Error('لا توجد محادثة خاصة موثقة. اربطها أولًا من صفحة المساعد.');
  const now = Date.now();
  if (now - Number(p.lastReportAt || 0) < 10000) throw new Error('انتظر 10 ثوانٍ قبل إرسال تقرير آخر.');
  p.lastReportAt = now;
  store.saveSession(s);
  await whatsapp.sendText(id, p.verifiedChatId, 'تقرير من chat BOT المحلي\\n' + text);
  return { sent: true, message: 'تم إرسال التقرير إلى المحادثة الخاصة الموثقة.' };
}
module.exports = { reply, diagnose, startPairing, pairingStatus, handlePairMessage, sendReport };
'''
write_text("src/local_assistant.js", assistant_source)

# Add focused API routes and incoming WhatsApp verification without disturbing existing routes.
server = read_text("server.js")
server = replace_once(server, "const app = express();", "const localAssistant = require('./src/local_assistant');\nconst app = express();", "assistant import")
health_anchor = "app.get('/api/health', (_req, res) => res.json({ ok: true, version: store.APP_VERSION, time: new Date().toISOString(), node: process.version }));"
routes = """
app.post('/api/assistant/chat', (req, res) => {
  try { res.json({ ok: true, ...localAssistant.reply(store, whatsapp, sid(req), req.body && req.body.message) }); }
  catch (e) { replyError(res, e, 500); }
});
app.post('/api/assistant/pair/start', (req, res) => {
  try { res.json({ ok: true, ...localAssistant.startPairing(store, whatsapp, sid(req)) }); }
  catch (e) { replyError(res, e, 400); }
});
app.get('/api/assistant/pair/status', (req, res) => {
  try { res.json({ ok: true, ...localAssistant.pairingStatus(store, sid(req)) }); }
  catch (e) { replyError(res, e, 500); }
});
app.post('/api/assistant/report', async (req, res) => {
  try {
    if (!req.body || req.body.confirm !== true) return res.status(400).json({ ok: false, error: 'وافق على إرسال التقرير بعد مراجعته أولًا.' });
    const result = await localAssistant.sendReport(store, whatsapp, sid(req), req.body.message);
    res.json({ ok: true, ...result });
  } catch (e) { replyError(res, e, 400); }
});
"""
server = replace_once(server, health_anchor, health_anchor + routes, "assistant API routes")
listener_pattern = re.compile(r"whatsapp\.on\('message', \(id, msg\) => Promise\.allSettled\(\[interaction\.onMessage\(id, msg\), groupCommand\(id, msg\)\]\)\.then\(results => results\.filter\(x => x\.status === 'rejected'\)\.forEach\(x => log\(id, 'ERROR', safeError\(x\.reason\)\)\)\)\);")
listener_replacement = """whatsapp.on('message', (id, msg) => {
  localAssistant.handlePairMessage(store, whatsapp, id, msg, log).then(handled => {
    if (handled) return null;
    return Promise.allSettled([interaction.onMessage(id, msg), groupCommand(id, msg)])
      .then(results => results.filter(x => x.status === 'rejected').forEach(x => log(id, 'ERROR', safeError(x.reason))));
  }).catch(e => log(id, 'ERROR', safeError(e)));
});"""
server, listener_count = listener_pattern.subn(listener_replacement, server)
if listener_count != 1:
    raise RuntimeError("WhatsApp message listener: expected one anchor, found %s" % listener_count)
write_text("server.js", server)

# Add a distinct, low-clutter page for the offline assistant.
app = read_text("public/app.js")
nav_anchor = "    const items = ["
app = replace_once(app, nav_anchor, nav_anchor + "\n      ['assistant', '✦', 'المساعد المحلي'],", "assistant nav")
page_func = r'''
  function assistantHistory() {
    try {
      const items = JSON.parse(localStorage.getItem('chatBotAssistantHistory') || '[]');
      return Array.isArray(items) ? items.filter(x => x && (x.role === 'user' || x.role === 'assistant') && typeof x.text === 'string').slice(-80) : [];
    } catch { return []; }
  }
  function saveAssistantHistory(items) {
    try { localStorage.setItem('chatBotAssistantHistory', JSON.stringify(items.slice(-80))); } catch {}
  }
  function pageAssistant(data) {
    const history = assistantHistory();
    const bubbles = history.map(m => '<div class="assistant-message ' + (m.role === 'user' ? 'user' : 'bot') + '"><div class="assistant-role">' + (m.role === 'user' ? 'أنت' : 'المساعد المحلي') + '</div><div class="assistant-text">' + esc(m.text) + '</div></div>').join('');
    return '<section class="page-title assistant-title"><p class="eyebrow">مساعد محلي بلا API</p><h1>المساعد</h1><p>أوامر محفوظة، تشخيص محلي، وإرشادات إصلاح. لا تُرسل أي رسالة إلى WhatsApp دون ربط خاص وموافقة منك.</p></section>' +
      '<section class="assistant-layout">' +
      '<article class="panel assistant-main"><div class="panel-head"><div><h2>المحادثة</h2><p>يعمل دون مفتاح API أو خدمة سحابية. قد لا يفهم الأسئلة العامة غير الموجودة في قواعده.</p></div><button class="btn ghost small" id="assistantClearHistory" type="button">مسح السجل</button></div>' +
      '<div class="assistant-quick-actions"><button class="btn secondary small" type="button" data-assistant-prompt="شخّص النظام">شخّص النظام</button><button class="btn secondary small" type="button" data-assistant-prompt="راجع الأخطاء">راجع الأخطاء</button><button class="btn secondary small" type="button" data-assistant-prompt="كيف أصلح الاتصال؟">إصلاح الاتصال</button><button class="btn secondary small" type="button" data-assistant-prompt="كيف أحمي بياناتي؟">الخصوصية</button><button class="btn secondary small" type="button" data-assistant-prompt="الأوامر">كل الأوامر</button></div>' +
      '<div class="assistant-messages" id="assistantMessages">' + (bubbles || '<div class="assistant-empty"><strong>ابدأ بسؤال بسيط</strong><span>مثل: شخّص النظام، راجع الأخطاء، أو افتح الجلسة.</span></div>') + '</div>' +
      '<form class="assistant-composer" id="assistantForm"><textarea id="assistantInput" rows="2" maxlength="1600" placeholder="اكتب سؤالك أو الأمر..." aria-label="رسالة المساعد"></textarea><button class="btn primary" id="assistantSend" type="submit">إرسال</button></form>' +
      '<p class="muted assistant-note">سجل المحادثة محفوظ في المتصفح الحالي فقط. امسحه من زر مسح السجل عند الحاجة.</p></article>' +
      '<aside class="assistant-side">' +
      '<article class="panel"><div class="panel-head"><div><h2>ربط WhatsApp</h2><p>تحقق من محادثتك الخاصة قبل إرسال التقارير.</p></div></div><p id="assistantPairStatus" class="assistant-pair-status">جارٍ التحقق من حالة الربط...</p><button class="btn primary block" id="assistantPairStart" type="button">إنشاء رمز ربط</button><div class="assistant-pair-code" id="assistantPairCode" hidden></div><button class="btn secondary block" id="assistantPairRefresh" type="button">تحديث حالة الربط</button><p class="muted">الرمز صالح 5 دقائق. أرسل PAIR والرمز من محادثة خاصة إلى حساب WhatsApp المتصل بالتطبيق. لا تشارك الرمز.</p></article>' +
      '<article class="panel"><div class="panel-head"><div><h2>إرسال تقرير</h2><p>لا يتم الإرسال إلا بعد التحقق والموافقة.</p></div></div><label class="field-label" for="assistantReportText">نص التقرير</label><textarea id="assistantReportText" rows="5" maxlength="3500" placeholder="اكتب رسالة الخطأ والخطوات التي جربتها..."></textarea><label class="assistant-consent"><input id="assistantReportConsent" type="checkbox"><span>راجعت النص وأوافق على إرساله إلى المحادثة الموثقة.</span></label><button class="btn secondary block" id="assistantSendReport" type="button">إرسال التقرير عبر WhatsApp</button><p class="muted">راجع الأرقام والمعلومات الخاصة قبل الإرسال. لا تُرفق QR أو بيانات المصادقة.</p></article>' +
      '</aside></section>';
  }
'''
app = replace_once(app, "  function pageDashboard(data) {", page_func + "\n  function pageDashboard(data) {", "assistant view")
app = replace_once(app, "    let content = pageDashboard(data);", "    let content = pageDashboard(data);\n    if (state.page === 'assistant') content = pageAssistant(data);", "assistant page routing")
bind_anchor = "  function bindCommon() {"
bind_code = r'''
    const assistantForm = $('#assistantForm');
    assistantForm?.addEventListener('submit', async (event) => {
      event.preventDefault();
      const input = $('#assistantInput');
      const message = String(input?.value || '').trim();
      if (!message) { notify('اكتب رسالة أولًا.', 'error'); return; }
      const history = assistantHistory();
      history.push({ role: 'user', text: message, at: new Date().toISOString() });
      saveAssistantHistory(history);
      if (input) input.value = '';
      const send = $('#assistantSend');
      if (send) { send.disabled = true; send.textContent = 'يفكر...'; }
      const box = $('#assistantMessages');
      if (box) { box.innerHTML = history.map(m => '<div class="assistant-message ' + (m.role === 'user' ? 'user' : 'bot') + '"><div class="assistant-role">' + (m.role === 'user' ? 'أنت' : 'المساعد المحلي') + '</div><div class="assistant-text">' + esc(m.text) + '</div></div>').join('') + '<div class="assistant-thinking">أفحص القواعد المحلية...</div>'; box.scrollTop = box.scrollHeight; }
      try {
        const result = await api('/api/assistant/chat', { method: 'POST', body: JSON.stringify({ sessionId: sid(), message }) });
        if (result.action?.type === 'navigate' && result.action.page) {
          history.push({ role: 'assistant', text: result.text, at: new Date().toISOString() });
          saveAssistantHistory(history);
          go(result.action.page);
          return;
        }
        if (result.action?.type === 'refresh') await load(true);
        history.push({ role: 'assistant', text: String(result.text || 'تم تنفيذ الأمر المحلي.'), at: new Date().toISOString() });
        saveAssistantHistory(history);
      } catch (e) {
        history.push({ role: 'assistant', text: 'تعذر تنفيذ الأمر الآن: ' + String(e.message || e) + '\nتحقق من أن الخادم يعمل، ثم أعد المحاولة. لم يتم إرسال أي شيء إلى WhatsApp.', at: new Date().toISOString() });
        saveAssistantHistory(history);
      }
      render();
    });
    $$('[data-assistant-prompt]').forEach(button => button.addEventListener('click', () => {
      const input = $('#assistantInput');
      if (input) { input.value = button.dataset.assistantPrompt || ''; $('#assistantForm')?.requestSubmit(); }
    }));
    $('#assistantClearHistory')?.addEventListener('click', () => {
      if (!confirm('مسح سجل محادثة المساعد المحفوظ في هذا المتصفح؟')) return;
      saveAssistantHistory([]);
      render();
    });
    const refreshPairStatus = async () => {
      const node = $('#assistantPairStatus');
      if (!node) return;
      try {
        const status = await api('/api/assistant/pair/status?sessionId=' + encodeURIComponent(sid()));
        node.textContent = status.message || (status.verified ? 'محادثة موثقة' : 'غير مرتبط');
        node.classList.toggle('verified', !!status.verified);
      } catch (e) { node.textContent = 'تعذر قراءة حالة الربط: ' + String(e.message || e); }
    };
    $('#assistantPairStart')?.addEventListener('click', async () => {
      const btn = $('#assistantPairStart');
      if (btn) { btn.disabled = true; btn.textContent = 'جارٍ إنشاء الرمز...'; }
      try {
        const result = await api('/api/assistant/pair/start', { method: 'POST', body: JSON.stringify({ sessionId: sid() }) });
        const node = $('#assistantPairCode');
        if (node) { node.hidden = false; node.textContent = 'PAIR ' + result.code + '\n' + result.instruction; }
        notify('تم إنشاء رمز الربط. لا تشاركه مع أي شخص.', 'success');
        await refreshPairStatus();
      } catch (e) { notify(e.message || 'تعذر إنشاء رمز الربط.', 'error'); }
      finally { if (btn) { btn.disabled = false; btn.textContent = 'إنشاء رمز ربط'; } }
    });
    $('#assistantPairRefresh')?.addEventListener('click', refreshPairStatus);
    refreshPairStatus();
    $('#assistantSendReport')?.addEventListener('click', async () => {
      const text = String($('#assistantReportText')?.value || '').trim();
      if (!text) { notify('اكتب التقرير أولًا.', 'error'); return; }
      if (!$('#assistantReportConsent')?.checked) { notify('وافق على إرسال التقرير بعد مراجعته.', 'error'); return; }
      const btn = $('#assistantSendReport');
      if (btn) { btn.disabled = true; btn.textContent = 'جارٍ الإرسال...'; }
      try {
        const result = await api('/api/assistant/report', { method: 'POST', body: JSON.stringify({ sessionId: sid(), message: text, confirm: true }) });
        notify(result.message || 'تم إرسال التقرير.', 'success');
      } catch (e) { notify(e.message || 'تعذر إرسال التقرير.', 'error'); }
      finally { if (btn) { btn.disabled = false; btn.textContent = 'إرسال التقرير عبر WhatsApp'; } }
    });
'''
app = replace_once(app, bind_anchor, bind_anchor + "\n" + bind_code, "assistant handlers")
write_text("public/app.js", app)

styles = read_text("public/styles.css")
styles += r'''

/* Local assistant: a dedicated, readable work area rather than a crowded control panel. */
.assistant-layout{display:grid;grid-template-columns:minmax(0,1.55fr) minmax(280px,.85fr);gap:18px;align-items:start}
.assistant-main,.assistant-side>.panel{min-width:0}
.assistant-side{display:grid;gap:16px;min-width:0}
.assistant-quick-actions{display:flex;gap:8px;flex-wrap:wrap;margin:14px 0}
.assistant-messages{height:min(54vh,560px);min-height:250px;overflow:auto;display:flex;flex-direction:column;gap:12px;padding:14px;background:var(--panel-2,rgba(15,23,42,.35));border:1px solid var(--border,rgba(148,163,184,.18));border-radius:16px;scroll-behavior:smooth}
.assistant-message{max-width:94%;padding:11px 13px;border-radius:15px;overflow-wrap:anywhere}
.assistant-message.user{align-self:flex-start;background:var(--accent-soft,rgba(59,130,246,.14));border:1px solid rgba(96,165,250,.22)}
.assistant-message.bot{align-self:flex-end;background:var(--panel,rgba(148,163,184,.08));border:1px solid var(--border,rgba(148,163,184,.18))}
.assistant-role{font-size:12px;opacity:.72;margin-bottom:5px;font-weight:700}
.assistant-text{white-space:pre-wrap;line-height:1.75;font-size:14px}
.assistant-empty{margin:auto;text-align:center;display:grid;gap:7px;opacity:.75;padding:25px}
.assistant-composer{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:10px;align-items:end;margin-top:12px}
.assistant-composer textarea,.assistant-side textarea{width:100%;min-width:0;resize:vertical}
.assistant-note{margin:9px 0 0}
.assistant-thinking{align-self:flex-end;color:var(--muted,#94a3b8);font-size:12px;padding:7px 12px}
.assistant-pair-status{padding:10px 12px;border:1px solid var(--border,rgba(148,163,184,.18));border-radius:12px;margin:0 0 12px}
.assistant-pair-status.verified{border-color:rgba(16,185,129,.65);color:var(--success,#10b981)}
.assistant-pair-code{white-space:pre-wrap;font-weight:700;direction:ltr;text-align:center;overflow-wrap:anywhere;padding:13px;margin:12px 0;border-radius:12px;background:rgba(59,130,246,.12);border:1px dashed rgba(96,165,250,.5);font-size:14px}
.assistant-consent{display:flex;gap:9px;align-items:flex-start;font-size:13px;line-height:1.7;margin:12px 0}
.assistant-consent input{margin-top:5px;flex:0 0 auto}
.assistant-side .block{width:100%;margin:8px 0}
.assistant-side .muted{font-size:12px;line-height:1.7}
@media(max-width:900px){.assistant-layout{grid-template-columns:minmax(0,1fr)}.assistant-messages{height:48vh;min-height:230px}}
@media(max-width:520px){.assistant-quick-actions{gap:6px}.assistant-quick-actions .btn{flex:1 1 calc(50% - 6px)}.assistant-composer{grid-template-columns:minmax(0,1fr)}.assistant-composer .btn{width:100%}.assistant-message{max-width:100%}}
'''
write_text("public/styles.css", styles)

# Add all intended tests to the default verification command, preserving existing checks.
pkg = json.loads(read_text("package.json"))
scripts = pkg.setdefault("scripts", {})
scripts["verify"] = "node --check server.js && node --check public/app.js && node --check src/compat.js && node --check src/whatsapp.js && node --check src/delivery.js && node --check src/interaction.js && node --check src/scheduler.js && node --check src/store.js && node --check src/media.js && node --check src/local_assistant.js && node test/static.js && node test/compat.js && node test/smoke.js && node test/regression.js && node test/assistant.js"
scripts["test"] = "npm run verify"
write_text("package.json", json.dumps(pkg, ensure_ascii=False, indent=2) + "\n")

assistant_test = r'''"use strict";
const assert = require('node:assert/strict');
const assistant = require('../src/local_assistant');
const sample = {
  id: 'test', name: 'Test session', logs: [],
  settings: { assistantPairing: { pendingCode: '', expiresAt: 0, verifiedChatId: '', verifiedAt: '', failedAttempts: 0, lockedUntil: 0, lastReportAt: 0 } },
  recipients: [{ enabled: true }], groups: []
};
const store = {
  loadSession: () => JSON.parse(JSON.stringify(sample)),
  saveSession: s => s,
  getPaths: () => ({ media: require('node:path').join(__dirname, 'fixtures') })
};
const whatsapp = { listRuntime: () => ({ ready: true, status: 'ready' }) };
assert.equal(assistant.reply(store, whatsapp, 'test', 'افتح الإرسال').action.page, 'send');
assert.match(assistant.reply(store, whatsapp, 'test', 'الأوامر').text, /دون API/);
assert.match(assistant.reply(store, whatsapp, 'test', 'شخّص النظام').text, /نتيجة الفحص المحلي/);
assert.match(assistant.reply(store, whatsapp, 'test', '').text, /اكتب سؤالك/);
assert.equal(assistant.reply(store, whatsapp, 'test', 'افتح الجلسة').action.page, 'session');
console.log('assistant: ok');
'''
write_text("test/assistant.js", assistant_test)

readme = read_text("README.md")
readme += """

## المساعد المحلي (الإصدار المحسّن)

- توجد صفحة مستقلة للمساعد المحلي بأوامر محفوظة، وفحص حالة الجلسة، وقراءة آخر الأخطاء، وإرشادات إصلاح شائعة.
- المساعد محلي قائم على قواعد واضحة ولا يحتاج مفتاح API أو يرسل محتوى المستخدم إلى خدمة ذكاء اصطناعي خارجية.
- يمكن ربط محادثة خاصة عبر رمز تحقق قصير صالح لخمس دقائق. الرسائل داخل المجموعات لا تُقبل للتحقق، وهناك حد لمحاولات الرمز.
- إرسال أي تقرير إلى WhatsApp يتطلب محادثة موثقة، ومراجعة النص، وموافقة صريحة في الواجهة. لا ترسل QR أو ملفات المصادقة.
- أمر npm test يشغّل فحوص الصياغة والاختبارات الثابتة والتوافق والتدخين والانحدار والمساعد المحلي.
- لخصوصية أفضل، اترك HOST=127.0.0.1 ولا تعرض لوحة التحكم غير المحمية على الإنترنت.
"""
write_text("README.md", readme)

audit = """# تقرير مراجعة محلية — chat BOT v8.1.0

## نطاق التغييرات
- تمت إضافة صفحة مساعد محلي مستقلة دون إزالة صفحات المشروع السابقة.
- تمت إضافة قواعد تشخيص وأوامر تنقل محفوظة بلا API خارجي.
- تمت إضافة تدفق تحقق اختياري لربط محادثة WhatsApp خاصة وإرسال تقارير بعد موافقة صريحة.
- تم توسيع أمر التحقق ليشمل فحوص الصياغة والاختبارات الثابتة والتوافق والتدخين والانحدار والمساعد.
- إذا كان اختبار الانحدار الأصلي يحتوي بايتات NUL غير صالحة للتنفيذ، يتم الاحتفاظ بنسخته الأصلية باسم test/regression.original-backup.bin قبل إصلاح الاختبار التنفيذي.

## حدود المراجعة
اختبارات المشروع لا تستطيع إثبات صحة كل حالات WhatsApp الحقيقية دون تسجيل دخول لحساب اختبار واتصال بالإنترنت. لذلك يجب اختبار QR والإرسال والجدولة واستعادة الجلسة في بيئة محلية يسيطر عليها مالك الحساب، وعدم اعتبار نجاح الاختبارات الوحدوية ضمانًا من WhatsApp.
"""
write_text("REVIEW_REPORT.md", audit)

# Manifest with hashes for all extracted deliverable files, to make final review auditable.
manifest = []
for p in sorted(PROJECT.rglob("*")):
    if p.is_file() and p.name != "FILE_MANIFEST.json":
        data = p.read_bytes()
        manifest.append({"path": p.relative_to(PROJECT).as_posix(), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
(PROJECT / "FILE_MANIFEST.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"project": str(PROJECT), "files": len(manifest) + 1, "original_regression_has_nul": b"\x00" in original_regression, "source_zip_bytes": ARCHIVE.stat().st_size}, ensure_ascii=False))
