from pathlib import Path
import importlib.util, sys
path = Path(__file__).resolve().parent / "DASHBOARD-SERVER.py"
compile(path.read_text(encoding="utf-8"), str(path), "exec")
spec = importlib.util.spec_from_file_location("localai_dashboard_test", path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)
assert module.HOST == "127.0.0.1" and module.PORT == 8090
assert 'lang="ar" dir="rtl"' in module.PAGE
assert "/api/status" in module.PAGE and "/api/test-model" in module.PAGE
assert "LocalAI Studio" in module.PAGE
print("[PASS] Dashboard source compiles")
print("[PASS] Loopback-only binding")
print("[PASS] Arabic RTL page and status/inference endpoints")
print("DASHBOARD_TESTS: SUCCESS")
