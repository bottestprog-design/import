#!/usr/bin/env python3
"""LocalAI Studio: loopback-only status dashboard and direct Ollama smoke test."""
from __future__ import annotations
import json, logging, threading, urllib.error, urllib.request, webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

HOST, PORT = "127.0.0.1", 8090
OLLAMA, WEBUI = "http://127.0.0.1:11434", "http://127.0.0.1:8080"
ROOT = Path(__file__).resolve().parent
(ROOT / "Logs").mkdir(parents=True, exist_ok=True)
logging.basicConfig(filename=str(ROOT / "Logs" / "dashboard.log"), level=logging.INFO,
                    encoding="utf-8", format="%(asctime)s %(levelname)s %(message)s")

PAGE = r'''<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><meta name="theme-color" content="#0b1423">
<title>LocalAI Studio | مركز التحكم</title><style>
:root{color-scheme:dark;--bg:#0b1423;--panel:#142238;--line:#2c405a;--txt:#edf4ff;--muted:#9db1ca;--blue:#65aaff;--teal:#64d5d0;--green:#58d99e;--red:#ff7a83}
*{box-sizing:border-box}body{margin:0;background:radial-gradient(850px 440px at 5% -12%,#204c77 0,transparent 65%),var(--bg);color:var(--txt);font-family:Tahoma,"Segoe UI",Arial,sans-serif}
.shell{display:grid;grid-template-columns:230px 1fr;min-height:100vh}aside{background:#091321df;border-left:1px solid var(--line);padding:24px 16px;display:flex;flex-direction:column;gap:24px}
.brand{display:flex;align-items:center;gap:11px}.logo{width:42px;height:42px;border-radius:14px;background:linear-gradient(135deg,#2879c7,#48b9bd);display:grid;place-items:center;font-weight:900}.brand h1{font-size:16px;margin:0}.brand p{font-size:10px;color:var(--muted);margin:5px 0 0}nav{display:grid;gap:8px}.nav{padding:11px;border-radius:10px;color:#c5d4e8;text-decoration:none;font-size:12px}.nav:hover,.nav:first-child{background:#1a2e48;border:1px solid #355271}.side{margin-top:auto;padding:13px;background:#122238;border:1px solid var(--line);border-radius:12px;color:var(--muted);font-size:10px;line-height:1.8}
main{max-width:1450px;width:100%;margin:auto;padding:30px clamp(15px,4vw,50px)}.top{display:flex;justify-content:space-between;align-items:center;gap:12px;margin-bottom:23px}.eyebrow{font-size:10px;letter-spacing:.1em;color:var(--teal);font-weight:800}.top h2{font-size:25px;margin:7px 0 0}.actions{display:flex;gap:8px;flex-wrap:wrap}
.btn{border:1px solid #38536e;border-radius:10px;padding:10px 14px;background:#1b3049;color:white;font-size:11px;font-weight:bold;cursor:pointer}.btn:hover{border-color:var(--blue)}.primary{border:0;background:linear-gradient(135deg,#2b78c1,#299da9)}.btn:disabled{opacity:.6;cursor:wait}
.hero{padding:25px 27px;border:1px solid #315777;border-radius:17px;background:linear-gradient(110deg,#1e4c76bb,#18334ae0 60%,#17444abb);display:flex;justify-content:space-between;align-items:center;gap:15px}.hero h3{font-size:21px;margin:0 0 8px}.hero p{font-size:12px;color:#c8d7e8;line-height:1.9;margin:0;max-width:760px}.tag,.pill{border:1px solid #405873;background:#1c3049;border-radius:30px;padding:6px 10px;font-size:10px;white-space:nowrap}.tag{color:#aaf0e6}
.head{margin:25px 0 12px;display:flex;justify-content:space-between;align-items:end}.head h3{font-size:15px;margin:0}.head p{font-size:10px;color:var(--muted);margin:5px 0 0}
.cards{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:11px}.card,.panel{background:linear-gradient(150deg,#172941,#111d2e);border:1px solid var(--line);border-radius:14px}.card{padding:15px;min-height:110px}.cap{color:var(--muted);font-size:10px;display:flex;justify-content:space-between}.ico{background:#263f5d;border-radius:8px;padding:6px;color:#acd7ff}.metric{font-size:20px;font-weight:800;margin:14px 0 5px}.sub{font-size:10px;color:var(--muted)}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:12px}.panel{padding:16px}.panel h3{font-size:14px;margin:0}.paneltop{display:flex;justify-content:space-between;align-items:center;margin-bottom:12px}.items{display:grid;gap:8px}.item{padding:10px;border:1px solid #2d425d;background:#14243a;border-radius:10px;display:flex;justify-content:space-between;align-items:center;gap:10px}.item b{font-size:11px;overflow-wrap:anywhere}.item small{display:block;color:var(--muted);font-size:10px;margin-top:4px}.size{white-space:nowrap;color:var(--muted);font-size:10px}
.note{margin-top:10px;background:#192d45;border:1px solid #354f6b;border-radius:10px;padding:11px;color:#c8d7e8;font-size:10px;line-height:1.9}.note strong{color:white}
form{display:grid;gap:10px}label{color:var(--muted);font-size:10px}select,textarea{width:100%;background:#0d192a;border:1px solid #354b66;border-radius:9px;color:white;padding:11px;font:inherit;font-size:11px}textarea{min-height:90px;line-height:1.8;resize:vertical}.answer{margin-top:10px;min-height:60px;padding:11px;background:#0d1929;border:1px solid #304760;border-radius:10px;white-space:pre-wrap;overflow-wrap:anywhere;line-height:1.9;font-size:11px}.footer{text-align:center;color:var(--muted);font-size:9px;margin:22px 0}
@media(max-width:950px){.cards{grid-template-columns:repeat(2,1fr)}.grid{grid-template-columns:1fr}}
@media(max-width:680px){.shell{grid-template-columns:1fr}aside{padding:12px;border:0;border-bottom:1px solid var(--line);gap:10px}nav{grid-template-columns:repeat(3,1fr)}.nav{text-align:center;padding:9px 4px}.side{display:none}main{padding:18px 12px}.top{align-items:flex-start;flex-direction:column}.top h2{font-size:21px}.hero{align-items:flex-start;flex-direction:column;padding:19px}.hero h3{font-size:18px}.cards{gap:8px}.card{padding:11px}.metric{font-size:17px}}
</style></head><body><div class="shell"><aside>
<div class="brand"><div class="logo">AI</div><div><h1>LocalAI Studio</h1><p>مركز التحكم المحلي</p></div></div>
<nav><a class="nav" href="#home">نظرة عامة</a><a class="nav" href="#models">النماذج</a><a class="nav" href="#test">اختبار النموذج</a></nav>
<div class="side">لوحة محلية لا ترسل بياناتها إلى خدمات خارجية.<br>مقيّدة على 127.0.0.1 فقط.</div></aside><main id="home">
<div class="top"><div><div class="eyebrow">LOCAL INTELLIGENCE WORKSPACE</div><h2>مركز التحكم في الذكاء الاصطناعي</h2></div>
<div class="actions"><span class="pill" id="overall">جارٍ الفحص...</span><button class="btn" onclick="refresh()">تحديث ↻</button><button class="btn primary" onclick="window.open('http://127.0.0.1:8080','_blank','noopener')">فتح المحادثة</button></div></div>
<section class="hero"><div><h3>كل خدمات الذكاء الاصطناعي المحلي في مكان واحد</h3><p>راقب المحرك والواجهة، اعرض النماذج الموجودة بالفعل، واختبر Qwen مباشرة دون حفظ محادثة أو تنزيل نموذج جديد.</p></div><span class="tag">● تشغيل محلي · Loopback</span></section>
<div class="head"><div><h3>حالة النظام</h3><p id="updated">لم يتم التحديث بعد</p></div></div>
<div class="cards">
<div class="card"><div class="cap">محرك Ollama <span class="ico">◉</span></div><div class="metric" id="ollama">—</div><div class="sub" id="ollamaSub">فحص الاتصال</div></div>
<div class="card"><div class="cap">Open WebUI <span class="ico">▣</span></div><div class="metric" id="webui">—</div><div class="sub" id="webSub">المنفذ 8080</div></div>
<div class="card"><div class="cap">النماذج المحلية <span class="ico">◇</span></div><div class="metric" id="count">—</div><div class="sub">حسب قائمة Ollama الفعلية</div></div>
<div class="card"><div class="cap">الذاكرة RAM <span class="ico">▤</span></div><div class="metric" id="ram">—</div><div class="sub" id="ramSub">معلومات الجهاز</div></div></div>
<div class="head" id="models"><div><h3>النماذج المثبتة</h3><p>لا تظهر نماذج افتراضية أو غير موجودة على الجهاز.</p></div></div>
<div class="grid"><section class="panel"><div class="paneltop"><h3>مكتبة النماذج</h3><span class="pill" id="modelBadge">0 نموذج</span></div><div class="items" id="list">يتم جلب قائمة النماذج...</div>
<div class="note"><strong>توصية:</strong> اترك Qwen 3.5 9B للمهام الصعبة. يمكن إضافة Qwen 3.5 4B اختياريًا من ADD-FAST-MODEL.bat بعد الموافقة، ولا يتم تنزيله تلقائيًا.</div></section>
<section class="panel" id="test"><div class="paneltop"><h3>اختبار مباشر للنموذج</h3><span class="pill">غير محفوظ</span></div>
<form id="testForm"><div><label for="model">النموذج</label><select id="model" required><option value="">لا توجد نماذج</option></select></div>
<div><label for="prompt">سؤال الاختبار</label><textarea id="prompt" maxlength="1500" required placeholder="مثال: اشرح قانون نيوتن الثاني مع مثال بالعربية."></textarea></div>
<button class="btn primary" id="testBtn">اختبار الاستجابة</button></form><div class="answer" id="answer">ستظهر الإجابة هنا. هذا اختبار واحد لا ينشئ محادثة محفوظة.</div></section></div>
<div class="footer">LocalAI Studio · لوحة تحكم محلية · المحادثة الكاملة عبر Open WebUI</div></main></div>
<script>
function gb(x){return (Number(x)/1073741824).toFixed(2)+" GB"}
function renderModels(ms){const l=document.getElementById("list"),s=document.getElementById("model");l.replaceChildren();s.replaceChildren();document.getElementById("count").textContent=ms.length;document.getElementById("modelBadge").textContent=ms.length+" نموذج";
if(!ms.length){l.textContent="لا توجد نماذج ظاهرة في Ollama. لم يتم تنزيل شيء.";s.add(new Option("لا توجد نماذج",""));return}
ms.forEach(m=>{const r=document.createElement("div");r.className="item";const b=document.createElement("div");const n=document.createElement("b");n.textContent=m.name;const d=document.createElement("small");d.textContent=[m.details?.parameter_size,m.details?.quantization_level].filter(Boolean).join(" · ")||"محلي";b.append(n,d);const z=document.createElement("span");z.className="size";z.textContent=m.size?gb(m.size):"—";r.append(b,z);l.append(r);s.add(new Option(m.name+" ("+(m.size?gb(m.size):"unknown")+")",m.name))});
const p=ms.find(m=>m.name.startsWith("local-qwen35"))||ms.find(m=>m.name.startsWith("qwen3.5:9b"));if(p)s.value=p.name}
async function refresh(){document.getElementById("updated").textContent="جارٍ التحديث...";
try{const d=await(await fetch("/api/status",{cache:"no-store"})).json(),o=d.ollama.ok,w=d.webui.ok;
document.getElementById("ollama").textContent=o?"متصل":"غير متصل";document.getElementById("ollamaSub").textContent=o?"الإصدار "+d.ollama.version:"شغّل Ollama";
document.getElementById("webui").textContent=w?"جاهز":"متوقف";document.getElementById("webSub").textContent=w?"127.0.0.1:8080":"شغّل START-CHAT.bat";
document.getElementById("ram").textContent=d.memory?.total_gb?d.memory.used_gb+" / "+d.memory.total_gb+" GB":"غير متاح";document.getElementById("ramSub").textContent=d.memory?.percent!=null?"الاستخدام "+d.memory.percent+"%":"غير متاح";
const p=document.getElementById("overall");p.textContent=o&&w?"الخدمات جاهزة":o?"Ollama يعمل · WebUI متوقف":"تحقق من Ollama";p.style.color=o&&w?"#58d99e":"#ff7a83";renderModels(d.models||[]);document.getElementById("updated").textContent="آخر تحديث: "+new Date().toLocaleTimeString("ar")
}catch(e){document.getElementById("updated").textContent="تعذر التحديث: "+e.message}}
document.getElementById("testForm").addEventListener("submit",async e=>{e.preventDefault();const b=document.getElementById("testBtn"),a=document.getElementById("answer"),model=document.getElementById("model").value,prompt=document.getElementById("prompt").value.trim();if(!model||!prompt){a.textContent="اختر نموذجًا واكتب سؤالًا.";return}b.disabled=true;b.textContent="النموذج يعمل...";a.textContent="يتم إرسال طلب مباشر إلى Ollama. قد يستغرق ذلك وقتًا على CPU.";
try{const r=await fetch("/api/test-model",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({model,prompt})}),d=await r.json();if(!r.ok)throw Error(d.error||"فشل الاختبار");a.textContent=d.response||"لا توجد إجابة نهائية"}catch(x){a.textContent="تعذر الاختبار: "+x.message}finally{b.disabled=false;b.textContent="اختبار الاستجابة"}});
refresh();setInterval(refresh,15000);
</script></body></html>'''

def _get_json(url: str, timeout: float = 5) -> dict[str, Any]:
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as response:
        result = json.loads(response.read(4_000_000).decode("utf-8"))
    return result if isinstance(result, dict) else {}

def _status() -> dict[str, Any]:
    data: dict[str, Any] = {"ollama": {"ok": False, "version": None},
                            "webui": {"ok": False}, "models": [], "memory": None}
    try:
        import psutil
        vm = psutil.virtual_memory()
        data["memory"] = {"total_gb": round(vm.total / 2**30, 1),
                          "used_gb": round((vm.total - vm.available) / 2**30, 1),
                          "percent": int(vm.percent)}
    except Exception:
        pass
    try:
        version = _get_json(OLLAMA + "/api/version")
        tags = _get_json(OLLAMA + "/api/tags", 10)
        data["ollama"] = {"ok": True, "version": str(version.get("version", "available"))}
        data["models"] = [
            {"name": str(item["name"]), "size": int(item.get("size", 0) or 0),
             "details": item.get("details") if isinstance(item.get("details"), dict) else {}}
            for item in tags.get("models", []) if isinstance(item, dict) and item.get("name")
        ]
    except Exception as exc:
        logging.info("Ollama status unavailable: %s", type(exc).__name__)
    try:
        with urllib.request.urlopen(WEBUI + "/ready", timeout=3) as response:
            data["webui"] = {"ok": 200 <= response.status < 300}
    except Exception:
        pass
    return data

class Handler(BaseHTTPRequestHandler):
    server_version = "LocalAIStudio/2.3"
    def log_message(self, fmt: str, *args: Any) -> None:
        logging.info("%s - %s", self.address_string(), fmt % args)
    def _is_local(self) -> bool:
        host = (self.headers.get("Host") or "").split(":")[0].strip("[]").lower()
        return host in ("127.0.0.1", "localhost")
    def _reply(self, code: int, content: bytes, mime: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(content)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(content)
    def _json(self, code: int, item: dict[str, Any]) -> None:
        self._reply(code, json.dumps(item, ensure_ascii=False).encode("utf-8"),
                    "application/json; charset=utf-8")
    def do_GET(self) -> None:
        if not self._is_local():
            return self._json(403, {"error": "Loopback access only"})
        route = self.path.split("?", 1)[0]
        if route == "/":
            return self._reply(200, PAGE.encode("utf-8"), "text/html; charset=utf-8")
        if route == "/api/status":
            return self._json(200, _status())
        if route == "/healthz":
            return self._json(200, {"ok": True, "host": HOST, "port": PORT})
        return self._json(404, {"error": "Not found"})
    def do_POST(self) -> None:
        if not self._is_local():
            return self._json(403, {"error": "Loopback access only"})
        if self.path.split("?", 1)[0] != "/api/test-model":
            return self._json(404, {"error": "Not found"})
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if size < 2 or size > 8192:
                raise ValueError("حجم الطلب غير صالح.")
            request_data = json.loads(self.rfile.read(size).decode("utf-8"))
            model = str(request_data.get("model", "")).strip()
            prompt = str(request_data.get("prompt", "")).strip()
            if not prompt or len(prompt) > 1500:
                raise ValueError("اكتب سؤالًا من 1 إلى 1500 حرف.")
            tags = _get_json(OLLAMA + "/api/tags", 10)
            available = {str(x.get("name")) for x in tags.get("models", []) if isinstance(x, dict)}
            if model not in available:
                raise ValueError("النموذج غير مثبت حاليًا؛ لم يتم تنزيل أي نموذج.")
            payload = {"model": model, "messages": [{"role": "user", "content": prompt}],
                       "think": False, "stream": False, "keep_alive": "0",
                       "options": {"num_ctx": 4096, "num_predict": 512, "temperature": 0.2}}
            request = urllib.request.Request(
                OLLAMA + "/api/chat",
                data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
                headers={"Content-Type": "application/json", "Accept": "application/json"},
                method="POST")
            with urllib.request.urlopen(request, timeout=600) as response:
                result = json.loads(response.read(2_000_000).decode("utf-8"))
            message = result.get("message", {})
            answer = message.get("content", "") if isinstance(message, dict) else ""
            if not isinstance(answer, str) or not answer.strip():
                raise RuntimeError("لم يرجع النموذج إجابة نهائية؛ راجع سجل Ollama.")
            return self._json(200, {"ok": True, "model": model, "response": answer.strip()})
        except ValueError as exc:
            return self._json(400, {"error": str(exc)})
        except urllib.error.HTTPError as exc:
            detail = exc.read(700).decode("utf-8", "replace")
            return self._json(502, {"error": "رفض Ollama طلب الاختبار: " + detail[:300]})
        except Exception as exc:
            logging.exception("Model test failed")
            return self._json(504, {"error": "تعذر اختبار النموذج: " + str(exc)[:250]})

def main() -> int:
    try:
        server = ThreadingHTTPServer((HOST, PORT), Handler)
    except OSError as exc:
        print("تعذر تشغيل لوحة التحكم على 127.0.0.1:8090:", exc)
        print("إذا كانت اللوحة تعمل بالفعل افتح http://127.0.0.1:8090")
        return 2
    server.daemon_threads = True
    url = f"http://{HOST}:{PORT}"
    print("LocalAI Studio:", url, "| Loopback only | Ctrl+C stops dashboard only")
    threading.Timer(1, lambda: webbrowser.open(url)).start()
    try:
        server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        print("\nDashboard stopped.")
    finally:
        server.server_close()
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
