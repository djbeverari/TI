# Agente de Diagnóstico de Computadores — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Construir um agente de diagnóstico Windows (agente Python + servidor FastAPI + dashboard HTML) que permite ao técnico de TI diagnosticar remotamente até 39 máquinas de lojas via painel web centralizado.

**Architecture:** O agente roda como Tarefa Agendada em cada máquina, faz polling no servidor a cada 10s buscando comandos pendentes, executa checks de Windows/Hardware/Rede/Performance/Linx via PowerShell/WMI e envia JSON ao servidor. O servidor FastAPI armazena resultados em SQLite e serve o dashboard HTML que exibe cards por máquina com status por categoria.

**Tech Stack:** Python 3.10+, FastAPI, SQLite (stdlib), subprocess (PowerShell), pytest, httpx (testes), HTML/CSS/JS vanilla

---

## Estrutura de Arquivos

```
diagnostic-agent/
├── server/
│   ├── main.py            # FastAPI app — todos os endpoints
│   ├── database.py        # SQLite: init, CRUD para machines/diagnostics/checks/pending
│   ├── config.json        # Porta, nomes de processo/serviço Linx
│   ├── machines.json      # Cadastro de máquinas (editado manualmente)
│   └── static/
│       └── index.html     # Dashboard completo (cards grid + modal detalhe)
├── agent/
│   ├── agent.py           # Loop de polling + orquestração dos checks
│   ├── ps_runner.py       # Wrapper para subprocess.run(['powershell', ...])
│   ├── agent_config.json  # URL do servidor
│   └── checks/
│       ├── __init__.py    # Exporta CheckResult dataclass
│       ├── windows.py     # Event Log, Update, Disco, Serviços, Boot
│       ├── hardware.py    # CPU, RAM, SMART, Temperatura
│       ├── network.py     # Ping, DNS, IP
│       ├── performance.py # Top processos, tempo de boot, fila de disco
│       └── linx.py        # Processos Linx, serviços Linx/Dtef, porta
├── tests/
│   ├── test_database.py
│   ├── test_api.py
│   └── test_checks.py
├── install_agent.ps1      # Script de instalação do agente via Task Scheduler
└── requirements.txt
```

---

## Task 1: Scaffold do Projeto

**Files:**
- Create: `diagnostic-agent/requirements.txt`
- Create: `diagnostic-agent/server/config.json`
- Create: `diagnostic-agent/server/machines.json`
- Create: `diagnostic-agent/agent/agent_config.json`
- Create: `diagnostic-agent/agent/checks/__init__.py`

- [ ] **Step 1: Criar estrutura de diretórios**

```bash
mkdir -p diagnostic-agent/server/static
mkdir -p diagnostic-agent/agent/checks
mkdir -p diagnostic-agent/tests
touch diagnostic-agent/agent/checks/__init__.py
```

- [ ] **Step 2: Criar requirements.txt**

```
fastapi==0.111.0
uvicorn==0.29.0
httpx==0.27.0
pytest==8.2.0
pytest-asyncio==0.23.0
```

- [ ] **Step 3: Criar config.json**

```json
{
  "server_port": 8000,
  "linx_process_names": ["linx", "linxpos"],
  "linx_service_keywords": ["linx", "dtef"],
  "linx_port": null
}
```

- [ ] **Step 4: Criar machines.json de exemplo**

```json
[
  { "loja": "Loja 01", "hostname": "LOJA01-PDV1", "ip": "192.168.1.10" },
  { "loja": "Loja 02", "hostname": "LOJA02-PDV1", "ip": "192.168.2.10" }
]
```

- [ ] **Step 5: Criar agent_config.json**

```json
{
  "server_url": "http://192.168.0.1:8000",
  "poll_interval_sec": 10
}
```

- [ ] **Step 6: Instalar dependências**

```bash
cd diagnostic-agent
pip install -r requirements.txt
```

- [ ] **Step 7: Commit**

```bash
git add diagnostic-agent/
git commit -m "feat: scaffold do projeto agente de diagnóstico"
```

---

## Task 2: CheckResult — Contrato entre Agent e Server

**Files:**
- Create: `diagnostic-agent/agent/checks/__init__.py`
- Create: `diagnostic-agent/tests/test_checks.py` (primeira entrada)

- [ ] **Step 1: Escrever teste para CheckResult**

`tests/test_checks.py`:
```python
from agent.checks import CheckResult

def test_check_result_fields():
    c = CheckResult(
        category="hardware",
        name="RAM Usage",
        status="AVISO",
        value="91%",
        message="7.4 GB / 8 GB utilizados"
    )
    assert c.category == "hardware"
    assert c.status == "AVISO"
    assert c.to_dict() == {
        "category": "hardware",
        "name": "RAM Usage",
        "status": "AVISO",
        "value": "91%",
        "message": "7.4 GB / 8 GB utilizados"
    }

def test_check_result_status_values():
    for s in ("OK", "AVISO", "CRÍTICO"):
        c = CheckResult("cat", "name", s, "v", "m")
        assert c.status == s
```

- [ ] **Step 2: Rodar teste — deve falhar**

```bash
cd diagnostic-agent
pytest tests/test_checks.py -v
```
Esperado: `FAILED — cannot import name 'CheckResult'`

- [ ] **Step 3: Implementar CheckResult**

`agent/checks/__init__.py`:
```python
from dataclasses import dataclass, asdict

@dataclass
class CheckResult:
    category: str
    name: str
    status: str   # 'OK' | 'AVISO' | 'CRÍTICO'
    value: str
    message: str

    def to_dict(self) -> dict:
        return asdict(self)
```

- [ ] **Step 4: Rodar teste — deve passar**

```bash
pytest tests/test_checks.py -v
```
Esperado: `2 passed`

- [ ] **Step 5: Commit**

```bash
git add agent/checks/__init__.py tests/test_checks.py
git commit -m "feat: CheckResult dataclass com contrato de check"
```

---

## Task 3: Camada de Banco de Dados

**Files:**
- Create: `diagnostic-agent/server/database.py`
- Create: `diagnostic-agent/tests/test_database.py`

- [ ] **Step 1: Escrever testes do banco**

`tests/test_database.py`:
```python
import pytest
import os
from server.database import init_db, upsert_machine, add_pending, get_pending, mark_pending_done, save_report, get_latest_diagnostic

TEST_DB = "test_diag.db"

@pytest.fixture(autouse=True)
def clean_db():
    if os.path.exists(TEST_DB):
        os.remove(TEST_DB)
    init_db(TEST_DB)
    yield
    if os.path.exists(TEST_DB):
        os.remove(TEST_DB)

def test_upsert_machine_creates_record():
    upsert_machine(TEST_DB, "LOJA01-PDV1", "192.168.1.10", "Loja 01")
    upsert_machine(TEST_DB, "LOJA01-PDV1", "192.168.1.10", "Loja 01")  # idempotente

def test_add_and_get_pending():
    upsert_machine(TEST_DB, "LOJA01-PDV1", "192.168.1.10", "Loja 01")
    add_pending(TEST_DB, "LOJA01-PDV1")
    assert get_pending(TEST_DB, "LOJA01-PDV1") is True

def test_no_pending_returns_false():
    upsert_machine(TEST_DB, "LOJA01-PDV1", "192.168.1.10", "Loja 01")
    assert get_pending(TEST_DB, "LOJA01-PDV1") is False

def test_mark_pending_done():
    upsert_machine(TEST_DB, "LOJA01-PDV1", "192.168.1.10", "Loja 01")
    add_pending(TEST_DB, "LOJA01-PDV1")
    mark_pending_done(TEST_DB, "LOJA01-PDV1")
    assert get_pending(TEST_DB, "LOJA01-PDV1") is False

def test_save_report_and_get_latest():
    upsert_machine(TEST_DB, "LOJA02-PDV1", "192.168.2.10", "Loja 02")
    checks = [
        {"category": "hardware", "name": "CPU", "status": "OK", "value": "30%", "message": ""},
        {"category": "linx", "name": "Linx POS", "status": "CRÍTICO", "value": "ausente", "message": "linx.exe não encontrado"},
    ]
    save_report(TEST_DB, "LOJA02-PDV1", "192.168.2.10", "Loja 02", "2026-05-29T10:00:00", 12, checks, [])
    result = get_latest_diagnostic(TEST_DB, "LOJA02-PDV1")
    assert result is not None
    assert result["overall_status"] == "CRÍTICO"
    assert len(result["checks"]) == 2
```

- [ ] **Step 2: Rodar testes — devem falhar**

```bash
pytest tests/test_database.py -v
```
Esperado: `FAILED — cannot import name 'init_db'`

- [ ] **Step 3: Implementar database.py**

`server/database.py`:
```python
import sqlite3
from contextlib import contextmanager

@contextmanager
def _conn(db_path: str):
    con = sqlite3.connect(db_path)
    con.row_factory = sqlite3.Row
    try:
        yield con
        con.commit()
    finally:
        con.close()

def init_db(db_path: str = "diagnostics.db"):
    with _conn(db_path) as con:
        con.executescript("""
            CREATE TABLE IF NOT EXISTS machines (
                id        INTEGER PRIMARY KEY,
                hostname  TEXT UNIQUE,
                ip        TEXT,
                loja_nome TEXT,
                last_seen TEXT
            );
            CREATE TABLE IF NOT EXISTS pending_commands (
                id         INTEGER PRIMARY KEY,
                hostname   TEXT,
                created_at TEXT,
                status     TEXT DEFAULT 'pending'
            );
            CREATE TABLE IF NOT EXISTS diagnostics (
                id             INTEGER PRIMARY KEY,
                machine_id     INTEGER REFERENCES machines(id),
                timestamp      TEXT,
                duration_sec   INTEGER,
                overall_status TEXT
            );
            CREATE TABLE IF NOT EXISTS checks (
                id            INTEGER PRIMARY KEY,
                diagnostic_id INTEGER REFERENCES diagnostics(id),
                category      TEXT,
                name          TEXT,
                status        TEXT,
                value         TEXT,
                message       TEXT
            );
        """)

def upsert_machine(db_path: str, hostname: str, ip: str, loja_nome: str):
    with _conn(db_path) as con:
        con.execute("""
            INSERT INTO machines (hostname, ip, loja_nome, last_seen)
            VALUES (?, ?, ?, datetime('now'))
            ON CONFLICT(hostname) DO UPDATE SET ip=excluded.ip, last_seen=datetime('now')
        """, (hostname, ip, loja_nome))

def add_pending(db_path: str, hostname: str):
    with _conn(db_path) as con:
        con.execute(
            "DELETE FROM pending_commands WHERE hostname=? AND status='pending'",
            (hostname,)
        )
        con.execute(
            "INSERT INTO pending_commands (hostname, created_at, status) VALUES (?, datetime('now'), 'pending')",
            (hostname,)
        )

def get_pending(db_path: str, hostname: str) -> bool:
    with _conn(db_path) as con:
        row = con.execute(
            "SELECT id FROM pending_commands WHERE hostname=? AND status='pending' LIMIT 1",
            (hostname,)
        ).fetchone()
        return row is not None

def mark_pending_done(db_path: str, hostname: str):
    with _conn(db_path) as con:
        con.execute(
            "UPDATE pending_commands SET status='done' WHERE hostname=? AND status='pending'",
            (hostname,)
        )

def _compute_overall(checks: list[dict]) -> str:
    statuses = {c["status"] for c in checks}
    if "CRÍTICO" in statuses:
        return "CRÍTICO"
    if "AVISO" in statuses:
        return "AVISO"
    return "OK"

def save_report(db_path: str, hostname: str, ip: str, loja: str,
                timestamp: str, duration_sec: int, checks: list[dict],
                linx_services_found: list[str]):
    upsert_machine(db_path, hostname, ip, loja)
    overall = _compute_overall(checks)
    with _conn(db_path) as con:
        machine_id = con.execute(
            "SELECT id FROM machines WHERE hostname=?", (hostname,)
        ).fetchone()["id"]
        cur = con.execute(
            "INSERT INTO diagnostics (machine_id, timestamp, duration_sec, overall_status) VALUES (?,?,?,?)",
            (machine_id, timestamp, duration_sec, overall)
        )
        diag_id = cur.lastrowid
        con.executemany(
            "INSERT INTO checks (diagnostic_id, category, name, status, value, message) VALUES (?,?,?,?,?,?)",
            [(diag_id, c["category"], c["name"], c["status"], c["value"], c["message"]) for c in checks]
        )
    mark_pending_done(db_path, hostname)

def get_latest_diagnostic(db_path: str, hostname: str) -> dict | None:
    with _conn(db_path) as con:
        row = con.execute("""
            SELECT d.id, d.timestamp, d.duration_sec, d.overall_status
            FROM diagnostics d
            JOIN machines m ON m.id = d.machine_id
            WHERE m.hostname=?
            ORDER BY d.id DESC LIMIT 1
        """, (hostname,)).fetchone()
        if not row:
            return None
        checks = con.execute(
            "SELECT category, name, status, value, message FROM checks WHERE diagnostic_id=?",
            (row["id"],)
        ).fetchall()
        return {
            "timestamp": row["timestamp"],
            "duration_sec": row["duration_sec"],
            "overall_status": row["overall_status"],
            "checks": [dict(c) for c in checks]
        }

def get_diagnostics_history(db_path: str, hostname: str) -> list[dict]:
    with _conn(db_path) as con:
        rows = con.execute("""
            SELECT d.id, d.timestamp, d.overall_status
            FROM diagnostics d
            JOIN machines m ON m.id = d.machine_id
            WHERE m.hostname=?
            ORDER BY d.id DESC LIMIT 30
        """, (hostname,)).fetchall()
        return [dict(r) for r in rows]
```

- [ ] **Step 4: Rodar testes — devem passar**

```bash
pytest tests/test_database.py -v
```
Esperado: `6 passed`

- [ ] **Step 5: Commit**

```bash
git add server/database.py tests/test_database.py
git commit -m "feat: camada SQLite com machines, diagnostics, checks e pending_commands"
```

---

## Task 4: Servidor FastAPI — Endpoints

**Files:**
- Create: `diagnostic-agent/server/main.py`
- Create: `diagnostic-agent/tests/test_api.py`

- [ ] **Step 1: Escrever testes da API**

`tests/test_api.py`:
```python
import pytest
import os
from fastapi.testclient import TestClient

os.environ["DIAG_DB"] = "test_api.db"
os.environ["DIAG_MACHINES"] = "server/machines.json"

from server.main import app

client = TestClient(app)

@pytest.fixture(autouse=True)
def clean():
    from server.database import init_db
    if os.path.exists("test_api.db"):
        os.remove("test_api.db")
    init_db("test_api.db")
    yield
    if os.path.exists("test_api.db"):
        os.remove("test_api.db")

def test_get_machines_returns_list():
    r = client.get("/machines")
    assert r.status_code == 200
    assert isinstance(r.json(), list)

def test_diagnose_creates_pending():
    # precisa de uma máquina no machines.json de teste — usamos o sample
    r = client.post("/diagnose/LOJA01-PDV1")
    assert r.status_code in (200, 404)  # 404 se não existe no machines.json

def test_pending_false_when_none():
    r = client.get("/pending/LOJA01-PDV1")
    assert r.status_code == 200
    assert r.json()["pending"] is False

def test_pending_true_after_diagnose(tmp_path, monkeypatch):
    from server import database
    database.upsert_machine("test_api.db", "LOJA01-PDV1", "192.168.1.10", "Loja 01")
    database.add_pending("test_api.db", "LOJA01-PDV1")
    r = client.get("/pending/LOJA01-PDV1")
    assert r.json()["pending"] is True

def test_report_saves_and_returns_200():
    payload = {
        "hostname": "LOJA01-PDV1",
        "ip": "192.168.1.10",
        "loja": "Loja 01",
        "timestamp": "2026-05-29T10:00:00",
        "duration_sec": 12,
        "linx_services_found": [],
        "checks": [
            {"category": "hardware", "name": "CPU", "status": "OK", "value": "30%", "message": ""}
        ]
    }
    r = client.post("/report", json=payload)
    assert r.status_code == 200

def test_latest_diagnostic_after_report():
    payload = {
        "hostname": "LOJA01-PDV1",
        "ip": "192.168.1.10",
        "loja": "Loja 01",
        "timestamp": "2026-05-29T10:00:00",
        "duration_sec": 12,
        "linx_services_found": ["LinxPOS"],
        "checks": [
            {"category": "linx", "name": "Linx POS", "status": "CRÍTICO", "value": "ausente", "message": ""}
        ]
    }
    client.post("/report", json=payload)
    r = client.get("/diagnostics/LOJA01-PDV1/latest")
    assert r.status_code == 200
    assert r.json()["overall_status"] == "CRÍTICO"
```

- [ ] **Step 2: Rodar testes — devem falhar**

```bash
pytest tests/test_api.py -v
```
Esperado: `FAILED — cannot import name 'app'`

- [ ] **Step 3: Implementar main.py**

`server/main.py`:
```python
import json
import os
from fastapi import FastAPI, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from pydantic import BaseModel
from server.database import (
    init_db, upsert_machine, add_pending, get_pending,
    save_report, get_latest_diagnostic, get_diagnostics_history
)

DB_PATH = os.environ.get("DIAG_DB", "diagnostics.db")
MACHINES_FILE = os.environ.get("DIAG_MACHINES", "server/machines.json")

init_db(DB_PATH)

app = FastAPI(title="Agente de Diagnóstico")
app.mount("/static", StaticFiles(directory="server/static"), name="static")

def _load_machines() -> list[dict]:
    with open(MACHINES_FILE, encoding="utf-8") as f:
        return json.load(f)

@app.get("/")
def serve_dashboard():
    return FileResponse("server/static/index.html")

@app.get("/machines")
def list_machines():
    machines = _load_machines()
    result = []
    for m in machines:
        latest = get_latest_diagnostic(DB_PATH, m["hostname"])
        result.append({
            "hostname": m["hostname"],
            "ip": m["ip"],
            "loja": m["loja"],
            "latest": latest
        })
    return result

@app.post("/diagnose/{hostname}")
def trigger_diagnose(hostname: str):
    machines = _load_machines()
    known = {m["hostname"] for m in machines}
    if hostname not in known:
        raise HTTPException(status_code=404, detail="Máquina não encontrada em machines.json")
    m = next(x for x in machines if x["hostname"] == hostname)
    upsert_machine(DB_PATH, hostname, m["ip"], m["loja"])
    add_pending(DB_PATH, hostname)
    return {"status": "pending", "hostname": hostname}

@app.get("/pending/{hostname}")
def check_pending(hostname: str):
    return {"pending": get_pending(DB_PATH, hostname)}

class CheckItem(BaseModel):
    category: str
    name: str
    status: str
    value: str
    message: str

class ReportPayload(BaseModel):
    hostname: str
    ip: str
    loja: str
    timestamp: str
    duration_sec: int
    linx_services_found: list[str] = []
    checks: list[CheckItem]

@app.post("/report")
def receive_report(payload: ReportPayload):
    save_report(
        DB_PATH,
        payload.hostname,
        payload.ip,
        payload.loja,
        payload.timestamp,
        payload.duration_sec,
        [c.model_dump() for c in payload.checks],
        payload.linx_services_found
    )
    return {"status": "saved"}

@app.get("/diagnostics/{hostname}/latest")
def latest_diagnostic(hostname: str):
    result = get_latest_diagnostic(DB_PATH, hostname)
    if not result:
        raise HTTPException(status_code=404, detail="Nenhum diagnóstico encontrado")
    return result

@app.get("/diagnostics/{hostname}")
def diagnostic_history(hostname: str):
    return get_diagnostics_history(DB_PATH, hostname)
```

- [ ] **Step 4: Rodar testes — devem passar**

```bash
pytest tests/test_api.py -v
```
Esperado: `7 passed`

- [ ] **Step 5: Commit**

```bash
git add server/main.py tests/test_api.py
git commit -m "feat: servidor FastAPI com todos os endpoints"
```

---

## Task 5: Agent — PowerShell Runner

**Files:**
- Create: `diagnostic-agent/agent/ps_runner.py`
- Modify: `diagnostic-agent/tests/test_checks.py`

- [ ] **Step 1: Adicionar teste para ps_runner**

Adicionar em `tests/test_checks.py`:
```python
from unittest.mock import patch, MagicMock
from agent.ps_runner import run_ps

def test_run_ps_returns_stdout():
    mock_result = MagicMock()
    mock_result.stdout = "42\n"
    mock_result.returncode = 0
    with patch("agent.ps_runner.subprocess.run", return_value=mock_result):
        output = run_ps("Write-Output 42")
    assert output == "42"

def test_run_ps_returns_empty_on_error():
    mock_result = MagicMock()
    mock_result.stdout = ""
    mock_result.returncode = 1
    with patch("agent.ps_runner.subprocess.run", return_value=mock_result):
        output = run_ps("Get-Something")
    assert output == ""
```

- [ ] **Step 2: Rodar testes — devem falhar**

```bash
pytest tests/test_checks.py -v -k "test_run_ps"
```
Esperado: `FAILED — cannot import name 'run_ps'`

- [ ] **Step 3: Implementar ps_runner.py**

`agent/ps_runner.py`:
```python
import subprocess

def run_ps(command: str, timeout: int = 30) -> str:
    try:
        result = subprocess.run(
            ["powershell", "-NoProfile", "-NonInteractive", "-Command", command],
            capture_output=True, text=True, timeout=timeout
        )
        return result.stdout.strip()
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return ""
```

- [ ] **Step 4: Rodar testes — devem passar**

```bash
pytest tests/test_checks.py -v -k "test_run_ps"
```
Esperado: `2 passed`

- [ ] **Step 5: Commit**

```bash
git add agent/ps_runner.py tests/test_checks.py
git commit -m "feat: ps_runner wrapper para subprocess PowerShell"
```

---

## Task 6: Agent — Checks de Windows e Hardware

**Files:**
- Create: `diagnostic-agent/agent/checks/windows.py`
- Create: `diagnostic-agent/agent/checks/hardware.py`
- Modify: `diagnostic-agent/tests/test_checks.py`

- [ ] **Step 1: Escrever testes para checks Windows**

Adicionar em `tests/test_checks.py`:
```python
from unittest.mock import patch
from agent.checks.windows import check_windows

def _mock_ps(outputs: dict):
    def side_effect(cmd, **kwargs):
        for key, val in outputs.items():
            if key in cmd:
                return val
        return ""
    return side_effect

def test_windows_disk_critico():
    with patch("agent.checks.windows.run_ps") as m:
        m.side_effect = _mock_ps({
            "FreeSpace": "5",        # 5 GB — abaixo de 10
            "Get-EventLog": "3",
            "LastBootUpTime": "1",
            "QuickFixEngineering": "2026-05-01",
            "Spooler": "Running\nRunning\nRunning",
        })
        results = check_windows()
    disk = next(r for r in results if r.name == "Disco C:")
    assert disk.status == "CRÍTICO"

def test_windows_services_critico():
    with patch("agent.checks.windows.run_ps") as m:
        m.side_effect = _mock_ps({
            "FreeSpace": "50",
            "Get-EventLog": "2",
            "LastBootUpTime": "1",
            "QuickFixEngineering": "2026-05-15",
            "Spooler": "Stopped\nRunning\nRunning",
        })
        results = check_windows()
    svc = next(r for r in results if r.name == "Serviços Críticos")
    assert svc.status == "CRÍTICO"
```

- [ ] **Step 2: Rodar testes — devem falhar**

```bash
pytest tests/test_checks.py -v -k "test_windows"
```
Esperado: `FAILED — cannot import name 'check_windows'`

- [ ] **Step 3: Implementar windows.py**

`agent/checks/windows.py`:
```python
from agent.checks import CheckResult
from agent.ps_runner import run_ps

def check_windows() -> list[CheckResult]:
    results = []

    # Event Log
    count_str = run_ps(
        "try { (Get-EventLog -LogName System -EntryType Error "
        "-After (Get-Date).AddHours(-24) -ErrorAction Stop).Count } catch { '0' }"
    )
    count = int(count_str) if count_str.isdigit() else 0
    results.append(CheckResult(
        "windows", "Event Log (24h)",
        "AVISO" if count > 10 else "OK",
        f"{count} erros",
        f"{count} erros críticos no System Log" if count > 10 else ""
    ))

    # Espaço em disco C:
    free_str = run_ps(
        "[Math]::Round((Get-WmiObject Win32_LogicalDisk -Filter \"DeviceID='C:'\").FreeSpace / 1GB, 1)"
    )
    try:
        free_gb = float(free_str)
        status = "CRÍTICO" if free_gb < 10 else ("AVISO" if free_gb < 20 else "OK")
        results.append(CheckResult("windows", "Disco C:", status, f"{free_gb} GB livres",
                                   f"Apenas {free_gb} GB livres" if status != "OK" else ""))
    except ValueError:
        results.append(CheckResult("windows", "Disco C:", "AVISO", "N/D", "Não foi possível ler"))

    # Serviços críticos
    svc_out = run_ps(
        "(Get-Service -Name Spooler,Winmgmt,RpcSs -ErrorAction SilentlyContinue).Status -join ','"
    )
    if "Stopped" in svc_out:
        results.append(CheckResult("windows", "Serviços Críticos", "CRÍTICO", svc_out,
                                   "Um ou mais serviços críticos estão parados"))
    else:
        results.append(CheckResult("windows", "Serviços Críticos", "OK", "Todos rodando", ""))

    # Uptime
    days_str = run_ps(
        "$b=(Get-WmiObject Win32_OperatingSystem).ConvertToDateTime("
        "(Get-WmiObject Win32_OperatingSystem).LastBootUpTime);"
        "[Math]::Round(((Get-Date)-$b).TotalDays,1)"
    )
    try:
        days = float(days_str)
        status = "AVISO" if days > 7 else "OK"
        results.append(CheckResult("windows", "Uptime", status, f"{days} dias",
                                   f"Sem reiniciar há {days} dias" if status != "OK" else ""))
    except ValueError:
        results.append(CheckResult("windows", "Uptime", "OK", "N/D", ""))

    # Windows Update
    last_update = run_ps(
        "(Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 1).InstalledOn"
    )
    results.append(CheckResult("windows", "Windows Update", "OK", last_update or "N/D", ""))

    return results
```

- [ ] **Step 4: Escrever testes para checks Hardware**

Adicionar em `tests/test_checks.py`:
```python
from agent.checks.hardware import check_hardware

def test_hardware_ram_aviso():
    with patch("agent.checks.hardware.run_ps") as m:
        m.side_effect = _mock_ps({
            "LoadPercentage": "40",
            "TotalVisibleMemorySize": "8000000",
            "FreePhysicalMemory": "700000",   # ~91% usado
            "Get-PhysicalDisk": "Healthy",
            "MSAcpi_ThermalZoneTemperature": "",
        })
        results = check_hardware()
    ram = next(r for r in results if r.name == "RAM")
    assert ram.status == "AVISO"

def test_hardware_disk_critico():
    with patch("agent.checks.hardware.run_ps") as m:
        m.side_effect = _mock_ps({
            "LoadPercentage": "30",
            "TotalVisibleMemorySize": "8000000",
            "FreePhysicalMemory": "4000000",
            "Get-PhysicalDisk": "Unhealthy",
            "MSAcpi_ThermalZoneTemperature": "",
        })
        results = check_hardware()
    disk = next(r for r in results if r.name == "SMART Disco")
    assert disk.status == "CRÍTICO"

def test_hardware_temp_nd():
    with patch("agent.checks.hardware.run_ps") as m:
        m.side_effect = _mock_ps({
            "LoadPercentage": "30",
            "TotalVisibleMemorySize": "8000000",
            "FreePhysicalMemory": "4000000",
            "Get-PhysicalDisk": "Healthy",
            "MSAcpi_ThermalZoneTemperature": "",
        })
        results = check_hardware()
    temp = next(r for r in results if r.name == "Temperatura CPU")
    assert temp.status == "OK"
    assert temp.value == "N/D"
```

- [ ] **Step 5: Rodar testes hardware — devem falhar**

```bash
pytest tests/test_checks.py -v -k "test_hardware"
```
Esperado: `FAILED — cannot import name 'check_hardware'`

- [ ] **Step 6: Implementar hardware.py**

`agent/checks/hardware.py`:
```python
from agent.checks import CheckResult
from agent.ps_runner import run_ps

def check_hardware() -> list[CheckResult]:
    results = []

    # CPU
    cpu_str = run_ps("(Get-WmiObject Win32_Processor).LoadPercentage")
    try:
        cpu = int(cpu_str)
        status = "AVISO" if cpu > 85 else "OK"
        results.append(CheckResult("hardware", "CPU", status, f"{cpu}%",
                                   f"CPU em {cpu}%" if status != "OK" else ""))
    except ValueError:
        results.append(CheckResult("hardware", "CPU", "OK", "N/D", ""))

    # RAM
    total_str = run_ps("(Get-WmiObject Win32_OperatingSystem).TotalVisibleMemorySize")
    free_str = run_ps("(Get-WmiObject Win32_OperatingSystem).FreePhysicalMemory")
    try:
        total = int(total_str)
        free = int(free_str)
        pct = round((total - free) / total * 100, 1)
        status = "AVISO" if pct > 90 else "OK"
        total_gb = round(total / 1024 / 1024, 1)
        used_gb = round((total - free) / 1024 / 1024, 1)
        results.append(CheckResult("hardware", "RAM", status, f"{pct}%",
                                   f"{used_gb} GB / {total_gb} GB" if status != "OK" else ""))
    except ValueError:
        results.append(CheckResult("hardware", "RAM", "OK", "N/D", ""))

    # SMART
    smart = run_ps("(Get-PhysicalDisk -ErrorAction SilentlyContinue).HealthStatus")
    if smart and "Healthy" not in smart:
        results.append(CheckResult("hardware", "SMART Disco", "CRÍTICO", smart,
                                   f"Disco reporta: {smart}"))
    else:
        results.append(CheckResult("hardware", "SMART Disco", "OK", smart or "Healthy", ""))

    # Temperatura
    temp_raw = run_ps(
        "try { (Get-WmiObject -Namespace root/wmi -Class MSAcpi_ThermalZoneTemperature "
        "-ErrorAction Stop).CurrentTemperature | ForEach-Object { [Math]::Round($_ / 10 - 273.15, 1) } | "
        "Select-Object -First 1 } catch { '' }"
    )
    if temp_raw:
        try:
            temp = float(temp_raw)
            status = "AVISO" if temp > 85 else "OK"
            results.append(CheckResult("hardware", "Temperatura CPU", status, f"{temp}°C",
                                       f"Temperatura alta: {temp}°C" if status != "OK" else ""))
        except ValueError:
            results.append(CheckResult("hardware", "Temperatura CPU", "OK", "N/D", ""))
    else:
        results.append(CheckResult("hardware", "Temperatura CPU", "OK", "N/D", ""))

    return results
```

- [ ] **Step 7: Rodar todos os testes — devem passar**

```bash
pytest tests/test_checks.py -v
```
Esperado: todos passando

- [ ] **Step 8: Commit**

```bash
git add agent/checks/windows.py agent/checks/hardware.py tests/test_checks.py
git commit -m "feat: checks de Windows e Hardware com testes"
```

---

## Task 7: Agent — Checks de Rede, Performance e Linx

**Files:**
- Create: `diagnostic-agent/agent/checks/network.py`
- Create: `diagnostic-agent/agent/checks/performance.py`
- Create: `diagnostic-agent/agent/checks/linx.py`
- Modify: `diagnostic-agent/tests/test_checks.py`

- [ ] **Step 1: Escrever testes de rede, performance e Linx**

Adicionar em `tests/test_checks.py`:
```python
from agent.checks.network import check_network
from agent.checks.performance import check_performance
from agent.checks.linx import check_linx

def test_network_apipa_critico():
    with patch("agent.checks.network.run_ps") as m:
        m.side_effect = _mock_ps({
            "NextHop": "192.168.1.1",
            "Test-Connection": "True",
            "Resolve-DnsName": "1.2.3.4",
            "Get-NetIPAddress": "169.254.1.1",
        })
        results = check_network()
    ip = next(r for r in results if r.name == "Configuração IP")
    assert ip.status == "CRÍTICO"

def test_network_ping_internet_critico():
    with patch("agent.checks.network.run_ps") as m:
        m.side_effect = _mock_ps({
            "NextHop": "192.168.1.1",
            "8.8.8.8": "",           # ping falha
            "Resolve-DnsName": "1.2.3.4",
            "Get-NetIPAddress": "192.168.1.10",
        })
        results = check_network()
    inet = next(r for r in results if r.name == "Ping Internet")
    assert inet.status == "CRÍTICO"

def test_linx_processo_critico():
    with patch("agent.checks.linx.run_ps") as m:
        m.side_effect = _mock_ps({
            "Get-Process": "",         # nenhum processo encontrado
            "Get-Service": "Running",
            "Test-NetConnection": "",
        })
        results = check_linx(
            process_names=["linx", "linxpos"],
            service_keywords=["linx", "dtef"],
            port=None
        )
    proc = next(r for r in results if r.name == "Processo Linx")
    assert proc.status == "CRÍTICO"

def test_linx_porta_skip_quando_none():
    with patch("agent.checks.linx.run_ps") as m:
        m.side_effect = _mock_ps({
            "Get-Process": "linx",
            "Get-Service": "Running",
        })
        results = check_linx(
            process_names=["linx", "linxpos"],
            service_keywords=["linx", "dtef"],
            port=None
        )
    porta = next((r for r in results if r.name == "Porta Linx"), None)
    assert porta is None or porta.status == "OK"
```

- [ ] **Step 2: Rodar testes — devem falhar**

```bash
pytest tests/test_checks.py -v -k "test_network or test_linx"
```
Esperado: `FAILED — cannot import`

- [ ] **Step 3: Implementar network.py**

`agent/checks/network.py`:
```python
from agent.checks import CheckResult
from agent.ps_runner import run_ps

def check_network() -> list[CheckResult]:
    results = []

    # Gateway
    gw = run_ps("(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue).NextHop | Select-Object -First 1")
    if gw:
        ping_gw = run_ps(f"(Test-Connection -ComputerName {gw} -Count 1 -ErrorAction SilentlyContinue).ResponseTime")
        try:
            latency = int(ping_gw)
            status = "AVISO" if latency > 50 else "OK"
            results.append(CheckResult("rede", "Ping Gateway", status, f"{latency}ms",
                                       f"Latência alta: {latency}ms" if status != "OK" else ""))
        except ValueError:
            results.append(CheckResult("rede", "Ping Gateway", "AVISO", "timeout", "Gateway não responde"))
    else:
        results.append(CheckResult("rede", "Ping Gateway", "AVISO", "N/D", "Gateway não encontrado"))

    # Internet
    ping_inet = run_ps("(Test-Connection -ComputerName 8.8.8.8 -Count 1 -ErrorAction SilentlyContinue).ResponseTime")
    if ping_inet and ping_inet.isdigit():
        results.append(CheckResult("rede", "Ping Internet", "OK", f"{ping_inet}ms", ""))
    else:
        results.append(CheckResult("rede", "Ping Internet", "CRÍTICO", "falhou", "Sem acesso à internet"))

    # DNS
    dns = run_ps("(Resolve-DnsName google.com -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress")
    if dns:
        results.append(CheckResult("rede", "DNS", "OK", dns, ""))
    else:
        results.append(CheckResult("rede", "DNS", "CRÍTICO", "falhou", "Resolução DNS falhou"))

    # IP
    ip = run_ps(
        "(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | "
        "Where-Object { $_.IPAddress -notlike '127.*' } | Select-Object -First 1).IPAddress"
    )
    if ip and ip.startswith("169.254"):
        results.append(CheckResult("rede", "Configuração IP", "CRÍTICO", ip, "IP APIPA — sem DHCP"))
    elif ip:
        results.append(CheckResult("rede", "Configuração IP", "OK", ip, ""))
    else:
        results.append(CheckResult("rede", "Configuração IP", "AVISO", "N/D", "IP não encontrado"))

    return results
```

- [ ] **Step 4: Implementar performance.py**

`agent/checks/performance.py`:
```python
from agent.checks import CheckResult
from agent.ps_runner import run_ps

def check_performance() -> list[CheckResult]:
    results = []

    # Top processos por CPU
    top = run_ps(
        "Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 | "
        "ForEach-Object { $_.Name + ':' + [Math]::Round($_.CPU,1) } | Out-String"
    )
    high = [l for l in top.splitlines() if l.strip()]
    results.append(CheckResult("performance", "Top Processos CPU", "OK", "; ".join(high[:3]) or "N/D", ""))

    # Tempo de boot (Event ID 100 no Microsoft-Windows-Diagnostics-Performance)
    boot_ms = run_ps(
        "try { (Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Diagnostics-Performance/Operational';"
        "Id=100} -MaxEvents 1 -ErrorAction Stop).Message -replace '.*Boot Duration: (\\d+)ms.*','$1' } catch { '' }"
    )
    if boot_ms.isdigit():
        secs = int(boot_ms) / 1000
        status = "AVISO" if secs > 180 else "OK"
        results.append(CheckResult("performance", "Tempo de Boot", status, f"{round(secs)}s",
                                   f"Boot lento: {round(secs)}s" if status != "OK" else ""))
    else:
        results.append(CheckResult("performance", "Tempo de Boot", "OK", "N/D", ""))

    # Fila de disco
    queue_str = run_ps(
        "try { (Get-Counter '\\PhysicalDisk(_Total)\\Avg. Disk Queue Length' "
        "-SampleInterval 1 -MaxSamples 1 -ErrorAction Stop).CounterSamples.CookedValue } catch { '0' }"
    )
    try:
        queue = float(queue_str)
        status = "AVISO" if queue > 2 else "OK"
        results.append(CheckResult("performance", "Fila de Disco", status, f"{round(queue,1)}",
                                   f"Fila alta: {round(queue,1)}" if status != "OK" else ""))
    except ValueError:
        results.append(CheckResult("performance", "Fila de Disco", "OK", "N/D", ""))

    return results
```

- [ ] **Step 5: Implementar linx.py**

`agent/checks/linx.py`:
```python
from agent.checks import CheckResult
from agent.ps_runner import run_ps

def check_linx(process_names: list[str], service_keywords: list[str], port: int | None) -> list[CheckResult]:
    results = []

    # Processos Linx
    names_filter = ",".join(f'"{n}"' for n in process_names)
    procs = run_ps(f"(Get-Process -Name {names_filter} -ErrorAction SilentlyContinue).Name -join ','")
    if procs:
        results.append(CheckResult("linx", "Processo Linx", "OK", procs, ""))
    else:
        results.append(CheckResult("linx", "Processo Linx", "CRÍTICO", "não encontrado",
                                   f"Nenhum de {', '.join(process_names)} está rodando"))

    # Serviços Linx/Dtef — descobre e verifica
    keyword_filter = " -or ".join(f'$_.Name -like "*{k}*"' for k in service_keywords)
    svc_out = run_ps(
        f"(Get-Service | Where-Object {{ {keyword_filter} }}) | "
        "ForEach-Object { $_.Name + ':' + $_.Status } | Out-String"
    )
    svc_lines = [l.strip() for l in svc_out.splitlines() if l.strip()]
    if svc_lines:
        stopped = [l for l in svc_lines if "Stopped" in l]
        status = "CRÍTICO" if stopped else "OK"
        results.append(CheckResult("linx", "Serviços Linx/Dtef", status,
                                   "; ".join(svc_lines),
                                   f"Parados: {', '.join(stopped)}" if stopped else ""))
    else:
        results.append(CheckResult("linx", "Serviços Linx/Dtef", "AVISO", "nenhum encontrado",
                                   "Nenhum serviço Linx/Dtef detectado"))

    # Porta (opcional)
    if port is not None:
        conn = run_ps(
            f"(Test-NetConnection -ComputerName localhost -Port {port} "
            f"-ErrorAction SilentlyContinue).TcpTestSucceeded"
        )
        if conn.strip().lower() == "true":
            results.append(CheckResult("linx", "Porta Linx", "OK", f":{port} aberta", ""))
        else:
            results.append(CheckResult("linx", "Porta Linx", "AVISO", f":{port} fechada",
                                       f"Porta {port} não responde"))

    return results

def discover_linx_services(service_keywords: list[str]) -> list[str]:
    keyword_filter = " -or ".join(f'$_.Name -like "*{k}*"' for k in service_keywords)
    out = run_ps(
        f"(Get-Service | Where-Object {{ {keyword_filter} }}).Name -join ','"
    )
    return [s.strip() for s in out.split(",") if s.strip()]
```

- [ ] **Step 6: Rodar todos os testes**

```bash
pytest tests/test_checks.py -v
```
Esperado: todos passando

- [ ] **Step 7: Commit**

```bash
git add agent/checks/network.py agent/checks/performance.py agent/checks/linx.py tests/test_checks.py
git commit -m "feat: checks de Rede, Performance e Linx com testes"
```

---

## Task 8: Agent — Loop Principal

**Files:**
- Create: `diagnostic-agent/agent/agent.py`

- [ ] **Step 1: Implementar agent.py**

`agent/agent.py`:
```python
import json
import time
import socket
import datetime
import httpx
from pathlib import Path

from agent.checks.windows import check_windows
from agent.checks.hardware import check_hardware
from agent.checks.network import check_network
from agent.checks.performance import check_performance
from agent.checks.linx import check_linx, discover_linx_services

CONFIG_PATH = Path(__file__).parent / "agent_config.json"
SERVER_CONFIG_PATH = Path(__file__).parent / "server_config.json"

def load_config() -> dict:
    with open(CONFIG_PATH) as f:
        return json.load(f)

def load_server_config() -> dict:
    if SERVER_CONFIG_PATH.exists():
        with open(SERVER_CONFIG_PATH) as f:
            return json.load(f)
    return {
        "linx_process_names": ["linx", "linxpos"],
        "linx_service_keywords": ["linx", "dtef"],
        "linx_port": None
    }

def run_all_checks(server_cfg: dict) -> list[dict]:
    checks = []
    checks.extend(check_windows())
    checks.extend(check_hardware())
    checks.extend(check_network())
    checks.extend(check_performance())
    checks.extend(check_linx(
        process_names=server_cfg.get("linx_process_names", ["linx", "linxpos"]),
        service_keywords=server_cfg.get("linx_service_keywords", ["linx", "dtef"]),
        port=server_cfg.get("linx_port")
    ))
    return [c.to_dict() for c in checks]

def send_report(server_url: str, checks: list[dict], duration: int, server_cfg: dict):
    hostname = socket.gethostname()
    services_found = discover_linx_services(server_cfg.get("linx_service_keywords", ["linx", "dtef"]))
    payload = {
        "hostname": hostname,
        "ip": socket.gethostbyname(hostname),
        "loja": hostname,
        "timestamp": datetime.datetime.now().isoformat(),
        "duration_sec": duration,
        "linx_services_found": services_found,
        "checks": checks
    }
    httpx.post(f"{server_url}/report", json=payload, timeout=15)

def poll_once(server_url: str):
    hostname = socket.gethostname()
    try:
        r = httpx.get(f"{server_url}/pending/{hostname}", timeout=10)
        if r.status_code == 200 and r.json().get("pending"):
            server_cfg = load_server_config()
            start = time.time()
            checks = run_all_checks(server_cfg)
            duration = int(time.time() - start)
            send_report(server_url, checks, duration, server_cfg)
    except httpx.RequestError:
        pass  # Servidor inacessível — tenta na próxima rodada

def main():
    cfg = load_config()
    server_url = cfg["server_url"]
    interval = cfg.get("poll_interval_sec", 10)
    while True:
        poll_once(server_url)
        time.sleep(interval)

if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Atualizar requirements.txt com httpx**

```
fastapi==0.111.0
uvicorn==0.29.0
httpx==0.27.0
pytest==8.2.0
pytest-asyncio==0.23.0
```

- [ ] **Step 3: Testar manualmente (máquina Windows)**

```bash
# Na máquina de TI — iniciar servidor
cd diagnostic-agent
uvicorn server.main:app --reload --port 8000

# Na máquina da loja (ou na própria para testar)
python agent/agent.py
```

- [ ] **Step 4: Commit**

```bash
git add agent/agent.py requirements.txt
git commit -m "feat: agent loop de polling com orquestração de checks"
```

---

## Task 9: Script de Instalação do Agente

**Files:**
- Create: `diagnostic-agent/install_agent.ps1`

- [ ] **Step 1: Criar script de instalação**

`install_agent.ps1`:
```powershell
# Instalar agente de diagnóstico via Task Scheduler
# Uso: .\install_agent.ps1 -ServerUrl "http://192.168.0.1:8000"

param(
    [Parameter(Mandatory=$true)]
    [string]$ServerUrl
)

$AgentDir = "C:\TI\diagnostic-agent"
$ConfigPath = "$AgentDir\agent\agent_config.json"

# Criar diretório
New-Item -ItemType Directory -Force $AgentDir | Out-Null

Write-Host "Copiando arquivos do agente para $AgentDir ..."
Copy-Item -Recurse -Force ".\agent" "$AgentDir\"

# Gravar config com URL do servidor
@{
    server_url = $ServerUrl
    poll_interval_sec = 10
} | ConvertTo-Json | Set-Content $ConfigPath -Encoding UTF8

Write-Host "Configurando Task Scheduler ..."
$action = New-ScheduledTaskAction -Execute "python" -Argument "$AgentDir\agent\agent.py" -WorkingDirectory $AgentDir
$trigger = New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Seconds 60) -Once -At (Get-Date)
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -RestartCount 3

Register-ScheduledTask -TaskName "TI-DiagAgent" -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null

Write-Host "Agente instalado. Verificando..."
Start-ScheduledTask -TaskName "TI-DiagAgent"
Start-Sleep -Seconds 3
$state = (Get-ScheduledTask -TaskName "TI-DiagAgent").State
Write-Host "Status da tarefa: $state"
```

- [ ] **Step 2: Commit**

```bash
git add install_agent.ps1
git commit -m "feat: script PowerShell de instalação do agente via Task Scheduler"
```

---

## Task 10: Dashboard HTML

**Files:**
- Create: `diagnostic-agent/server/static/index.html`

- [ ] **Step 1: Implementar index.html completo**

`server/static/index.html`:
```html
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Agente de Diagnóstico — TI</title>
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
body { background: #0d1117; color: #e6edf3; font-family: 'Segoe UI', sans-serif; font-size: 13px; }
.topbar { background: #161b22; border-bottom: 1px solid #30363d; padding: 12px 24px; display: flex; justify-content: space-between; align-items: center; }
.topbar h1 { font-size: 15px; color: #58a6ff; font-weight: 600; }
.stats { display: flex; gap: 16px; font-size: 12px; color: #8b949e; }
.toolbar { padding: 12px 24px; display: flex; gap: 8px; align-items: center; border-bottom: 1px solid #30363d; background: #0d1117; }
.filter-btn { background: #21262d; border: 1px solid #30363d; color: #8b949e; border-radius: 6px; padding: 4px 12px; font-size: 12px; cursor: pointer; }
.filter-btn.active { background: #1f6feb; border-color: #388bfd; color: #fff; }
.btn-danger { background: #da3633; color: #fff; border: none; border-radius: 6px; padding: 5px 14px; font-size: 12px; cursor: pointer; font-weight: 600; margin-left: auto; }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 12px; padding: 20px 24px; }
.machine-card { background: #161b22; border: 1px solid #30363d; border-radius: 8px; overflow: hidden; cursor: pointer; transition: border-color 0.15s; }
.machine-card:hover { border-color: #58a6ff; }
.card-stripe { height: 5px; }
.card-stripe.ok { background: #2ea043; }
.card-stripe.warn { background: #d29922; }
.card-stripe.crit { background: #da3633; }
.card-stripe.pending { background: #58a6ff; animation: pulse 1s infinite; }
@keyframes pulse { 0%,100%{opacity:1} 50%{opacity:0.4} }
.card-inner { padding: 12px; }
.card-name { font-weight: 600; font-size: 13px; color: #e6edf3; margin-bottom: 2px; }
.card-host { font-size: 11px; color: #8b949e; margin-bottom: 10px; }
.cat-row { display: flex; justify-content: space-between; margin-bottom: 4px; font-size: 11px; }
.cat-label { color: #8b949e; }
.dot-ok { color: #3fb950; } .dot-warn { color: #d29922; } .dot-crit { color: #f85149; }
.card-foot { padding: 6px 12px; background: #0d1117; font-size: 10px; color: #6e7681; border-top: 1px solid #21262d; display: flex; justify-content: space-between; }
.overlay { position: fixed; inset: 0; background: rgba(0,0,0,0.6); display: flex; align-items: center; justify-content: center; z-index: 100; }
.panel { background: #161b22; border: 1px solid #30363d; border-radius: 10px; width: 540px; max-height: 85vh; overflow-y: auto; }
.panel-head { padding: 16px 20px; border-bottom: 1px solid #30363d; display: flex; justify-content: space-between; align-items: center; position: sticky; top: 0; background: #161b22; z-index: 1; }
.panel-head h2 { font-size: 14px; }
.panel-sub { font-size: 11px; color: #8b949e; margin-top: 2px; }
.panel-body { padding: 16px 20px; }
.section-label { font-size: 11px; font-weight: 700; letter-spacing: .08em; text-transform: uppercase; margin-top: 16px; margin-bottom: 8px; }
.section-label:first-child { margin-top: 0; }
.section-label.crit { color: #f85149; } .section-label.warn { color: #d29922; } .section-label.ok { color: #3fb950; }
.issue { border-radius: 6px; padding: 10px 12px; margin-bottom: 6px; }
.issue.crit { background: #1c0f0f; border-left: 3px solid #f85149; }
.issue.warn { background: #1c1700; border-left: 3px solid #d29922; }
.issue-name { font-size: 13px; font-weight: 600; }
.issue-name.crit { color: #f85149; } .issue-name.warn { color: #d29922; }
.issue-detail { font-size: 11px; color: #8b949e; margin-top: 3px; }
.issue-cat { font-size: 10px; color: #6e7681; margin-top: 2px; text-transform: uppercase; }
.ok-box { background: #0d1117; border: 1px solid #21262d; border-radius: 6px; padding: 10px 12px; font-size: 12px; color: #3fb950; }
.ok-list { color: #6e7681; font-size: 11px; margin-top: 4px; }
.btn-sm { background: #21262d; border: 1px solid #30363d; color: #8b949e; border-radius: 6px; padding: 4px 10px; font-size: 12px; cursor: pointer; }
</style>
</head>
<body>

<div class="topbar">
  <h1>Agente de Diagnóstico — TI</h1>
  <div class="stats">
    <span id="cnt-ok" style="color:#3fb950"></span>
    <span id="cnt-warn" style="color:#d29922"></span>
    <span id="cnt-crit" style="color:#f85149"></span>
    <span id="last-update" style="color:#6e7681"></span>
  </div>
</div>

<div class="toolbar">
  <button class="filter-btn active" onclick="setFilter('all',this)">Todos</button>
  <button class="filter-btn" onclick="setFilter('CRÍTICO',this)" style="color:#f85149;border-color:#f85149">Críticos</button>
  <button class="filter-btn" onclick="setFilter('AVISO',this)" style="color:#d29922;border-color:#d29922">Avisos</button>
  <button class="filter-btn" onclick="setFilter('linx',this)">Linx</button>
  <button class="btn-danger" onclick="diagnoseAll()">Diagnosticar Todas</button>
</div>

<div class="grid" id="grid"></div>

<div class="overlay" id="overlay" style="display:none" onclick="closePanel(event)">
  <div class="panel" onclick="event.stopPropagation()">
    <div class="panel-head">
      <div>
        <h2 id="panel-title"></h2>
        <div class="panel-sub" id="panel-sub"></div>
      </div>
      <div style="display:flex;gap:8px">
        <button class="btn-danger" id="panel-diag-btn">Diagnosticar</button>
        <button class="btn-sm" onclick="document.getElementById('overlay').style.display='none'">✕</button>
      </div>
    </div>
    <div class="panel-body" id="panel-body"></div>
  </div>
</div>

<script>
let machines = [];
let currentFilter = 'all';

async function loadMachines() {
  const r = await fetch('/machines');
  machines = await r.json();
  renderGrid();
  updateCounters();
  document.getElementById('last-update').textContent = '| ' + new Date().toLocaleTimeString('pt-BR');
}

function stripeClass(status) {
  if (!status) return 'pending';
  if (status === 'CRÍTICO') return 'crit';
  if (status === 'AVISO') return 'warn';
  return 'ok';
}

function dotClass(status) {
  if (status === 'CRÍTICO') return 'dot-crit';
  if (status === 'AVISO') return 'dot-warn';
  return 'dot-ok';
}

function dotChar(status) {
  if (status === 'CRÍTICO') return '✕';
  if (status === 'AVISO') return '⚠';
  return '●';
}

function categoryStatus(checks, cat) {
  if (!checks) return null;
  const catChecks = checks.filter(c => c.category === cat);
  if (!catChecks.length) return 'OK';
  if (catChecks.some(c => c.status === 'CRÍTICO')) return 'CRÍTICO';
  if (catChecks.some(c => c.status === 'AVISO')) return 'AVISO';
  return 'OK';
}

function renderGrid() {
  const grid = document.getElementById('grid');
  grid.innerHTML = '';
  const visible = machines.filter(m => {
    if (currentFilter === 'all') return true;
    if (currentFilter === 'linx') {
      const linxStatus = categoryStatus(m.latest?.checks, 'linx');
      return linxStatus && linxStatus !== 'OK';
    }
    return m.latest?.overall_status === currentFilter;
  });
  visible.forEach(m => {
    const latest = m.latest;
    const overall = latest?.overall_status;
    const cats = ['windows','hardware','rede','performance','linx'];
    const catRows = cats.map(cat => {
      const s = categoryStatus(latest?.checks, cat);
      const labels = {windows:'Windows',hardware:'Hardware',rede:'Rede',performance:'Perf',linx:'Linx'};
      return `<div class="cat-row"><span class="cat-label">${labels[cat]}</span>
        <span class="${dotClass(s)}">${dotChar(s)}</span></div>`;
    }).join('');
    const ts = latest ? new Date(latest.timestamp).toLocaleTimeString('pt-BR') : '—';
    grid.innerHTML += `
      <div class="machine-card" onclick='openPanel(${JSON.stringify(m)})'>
        <div class="card-stripe ${stripeClass(overall)}"></div>
        <div class="card-inner">
          <div class="card-name">${m.loja}</div>
          <div class="card-host">${m.hostname} · ${m.ip}</div>
          ${catRows}
        </div>
        <div class="card-foot">
          <span>${ts}</span>
          <span style="color:${overall==='CRÍTICO'?'#f85149':overall==='AVISO'?'#d29922':'#3fb950'}">${overall||'aguardando'}</span>
        </div>
      </div>`;
  });
}

function updateCounters() {
  const ok = machines.filter(m => m.latest?.overall_status === 'OK').length;
  const warn = machines.filter(m => m.latest?.overall_status === 'AVISO').length;
  const crit = machines.filter(m => m.latest?.overall_status === 'CRÍTICO').length;
  document.getElementById('cnt-ok').textContent = `● ${ok} OK`;
  document.getElementById('cnt-warn').textContent = `⚠ ${warn} Avisos`;
  document.getElementById('cnt-crit').textContent = `✕ ${crit} Críticos`;
}

function setFilter(f, btn) {
  currentFilter = f;
  document.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
  btn.classList.add('active');
  renderGrid();
}

async function diagnoseAll() {
  for (const m of machines) {
    await fetch(`/diagnose/${m.hostname}`, {method:'POST'});
  }
  renderGrid();
}

function openPanel(m) {
  document.getElementById('panel-title').textContent = `${m.loja} — ${m.hostname}`;
  const ts = m.latest ? new Date(m.latest.timestamp).toLocaleString('pt-BR') : '—';
  const dur = m.latest?.duration_sec ?? '—';
  document.getElementById('panel-sub').textContent = `${m.ip} · ${ts} · ${dur}s`;
  document.getElementById('panel-diag-btn').onclick = async () => {
    await fetch(`/diagnose/${m.hostname}`, {method:'POST'});
    document.getElementById('overlay').style.display = 'none';
  };
  const body = document.getElementById('panel-body');
  if (!m.latest) {
    body.innerHTML = '<p style="color:#8b949e">Nenhum diagnóstico ainda. Clique em Diagnosticar.</p>';
  } else {
    const checks = m.latest.checks;
    const crits = checks.filter(c => c.status === 'CRÍTICO');
    const warns = checks.filter(c => c.status === 'AVISO');
    const oks = checks.filter(c => c.status === 'OK');
    let html = '';
    if (crits.length) {
      html += `<div class="section-label crit">✕ Crítico (${crits.length})</div>`;
      crits.forEach(c => {
        html += `<div class="issue crit"><div class="issue-name crit">${c.name}</div>
          <div class="issue-detail">${c.message||c.value}</div>
          <div class="issue-cat">${c.category}</div></div>`;
      });
    }
    if (warns.length) {
      html += `<div class="section-label warn">⚠ Avisos (${warns.length})</div>`;
      warns.forEach(c => {
        html += `<div class="issue warn"><div class="issue-name warn">${c.name}</div>
          <div class="issue-detail">${c.message||c.value}</div>
          <div class="issue-cat">${c.category}</div></div>`;
      });
    }
    if (oks.length) {
      html += `<div class="section-label ok">✓ Sem problemas (${oks.length} checks)</div>
        <div class="ok-box">Todos os demais checks passaram
          <div class="ok-list">${oks.map(c=>c.name).join(' · ')}</div></div>`;
    }
    body.innerHTML = html;
  }
  document.getElementById('overlay').style.display = 'flex';
}

function closePanel(e) {
  if (e.target.id === 'overlay') document.getElementById('overlay').style.display = 'none';
}

// Auto-refresh a cada 5 segundos
setInterval(loadMachines, 5000);
loadMachines();
</script>
</body>
</html>
```

- [ ] **Step 2: Testar o dashboard manualmente**

```bash
cd diagnostic-agent
uvicorn server.main:app --reload --port 8000
# Abrir http://localhost:8000 no navegador
```
Verificar: cards aparecem, botão Diagnosticar funciona, modal abre com "Nenhum diagnóstico ainda".

- [ ] **Step 3: Commit**

```bash
git add server/static/index.html
git commit -m "feat: dashboard HTML completo com cards grid e modal problemas-primeiro"
```

---

## Task 11: Teste de Integração End-to-End

**Files:**
- Create: `diagnostic-agent/tests/test_integration.py`

- [ ] **Step 1: Escrever teste de integração**

`tests/test_integration.py`:
```python
import os, time
os.environ["DIAG_DB"] = "test_integration.db"
os.environ["DIAG_MACHINES"] = "server/machines.json"

import pytest
from fastapi.testclient import TestClient
from server.main import app
from server.database import init_db

client = TestClient(app)

@pytest.fixture(autouse=True)
def clean():
    if os.path.exists("test_integration.db"):
        os.remove("test_integration.db")
    init_db("test_integration.db")
    yield
    if os.path.exists("test_integration.db"):
        os.remove("test_integration.db")

def test_full_flow():
    # 1. Lista máquinas (sem diagnóstico ainda)
    machines = client.get("/machines").json()
    assert isinstance(machines, list)
    hostname = machines[0]["hostname"] if machines else "LOJA01-PDV1"

    if not machines:
        pytest.skip("Nenhuma máquina em machines.json para testar")

    # 2. Agenda diagnóstico
    r = client.post(f"/diagnose/{hostname}")
    assert r.status_code == 200

    # 3. Agente verifica pendência
    r = client.get(f"/pending/{hostname}")
    assert r.json()["pending"] is True

    # 4. Agente envia relatório
    payload = {
        "hostname": hostname,
        "ip": "192.168.1.10",
        "loja": "Loja 01",
        "timestamp": "2026-05-29T10:00:00",
        "duration_sec": 8,
        "linx_services_found": ["LinxPOS"],
        "checks": [
            {"category": "windows", "name": "Disco C:", "status": "OK", "value": "50 GB", "message": ""},
            {"category": "linx", "name": "Processo Linx", "status": "CRÍTICO", "value": "ausente", "message": "linx.exe não encontrado"},
        ]
    }
    r = client.post("/report", json=payload)
    assert r.status_code == 200

    # 5. Pendência foi limpa
    r = client.get(f"/pending/{hostname}")
    assert r.json()["pending"] is False

    # 6. Diagnóstico disponível
    r = client.get(f"/diagnostics/{hostname}/latest")
    assert r.status_code == 200
    result = r.json()
    assert result["overall_status"] == "CRÍTICO"
    assert len(result["checks"]) == 2

    # 7. Máquinas endpoint retorna com diagnóstico
    machines = client.get("/machines").json()
    m = next(x for x in machines if x["hostname"] == hostname)
    assert m["latest"]["overall_status"] == "CRÍTICO"
```

- [ ] **Step 2: Rodar teste de integração**

```bash
pytest tests/test_integration.py -v
```
Esperado: `1 passed`

- [ ] **Step 3: Rodar suite completa**

```bash
pytest tests/ -v
```
Esperado: todos os testes passando sem erros.

- [ ] **Step 4: Commit final**

```bash
git add tests/test_integration.py
git commit -m "test: teste de integração end-to-end do fluxo completo"
```

---

## Checklist de Spec Coverage

| Requisito do Spec | Task |
|---|---|
| Cards grid com status por categoria | Task 10 |
| Modal detalhe — problemas primeiro | Task 10 |
| Filtros (Todos/Críticos/Avisos/Linx) | Task 10 |
| Botão Diagnosticar / Diagnosticar Todas | Task 10 |
| Contador global no cabeçalho | Task 10 |
| Polling do agente a cada 10s | Task 8 |
| GET /pending/{hostname} | Task 4 |
| POST /report | Task 4 |
| POST /diagnose/{hostname} | Task 4 |
| SQLite: machines, diagnostics, checks, pending | Task 3 |
| machines.json manual | Task 1 |
| config.json com nomes Linx configuráveis | Task 1 |
| Checks Windows (5 checks) | Task 6 |
| Checks Hardware (4 checks, temp N/D) | Task 6 |
| Checks Rede (4 checks) | Task 7 |
| Checks Performance (3 checks) | Task 7 |
| Checks Linx (processo, serviços, porta) | Task 7 |
| Descoberta automática de serviços Linx/Dtef | Task 7 |
| Porta Linx = null → skip | Task 7 |
| Script install_agent.ps1 | Task 9 |
