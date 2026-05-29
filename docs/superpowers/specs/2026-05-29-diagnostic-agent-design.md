# Agente de Diagnóstico de Computadores — Design Spec

**Data:** 2026-05-29  
**Autor:** Daniella  
**Status:** Aprovado

---

## Visão Geral

Ferramenta para o técnico de TI diagnosticar remotamente máquinas Windows nas lojas (até 39 máquinas). O técnico aciona o diagnóstico pelo painel web, o agente coleta dados na máquina alvo e exibe os resultados em um dashboard centralizado com foco nos problemas encontrados.

---

## Arquitetura

```
┌─────────────────────────────────────────────────┐
│              MÁQUINA CENTRAL (TI)               │
│                                                 │
│  ┌──────────────┐    ┌─────────────────────┐   │
│  │ Web Dashboard│◄───│  FastAPI Server     │   │
│  │ (HTML/JS)    │    │  + SQLite           │   │
│  └──────────────┘    └──────────┬──────────┘   │
└─────────────────────────────────│───────────────┘
                                  │ WinRM
          ┌───────────────────────┼───────────────┐
          ▼                       ▼               ▼
   ┌─────────────┐       ┌─────────────┐  ┌─────────────┐
   │  LOJA 01    │       │  LOJA 02    │  │  LOJA N     │
   │  agent.py   │       │  agent.py   │  │  agent.py   │
   └──────┬──────┘       └──────┬──────┘  └──────┬──────┘
          └───────────HTTP POST─┴─────────────────┘
                      (JSON → Servidor Central)
```

### Componentes

| Componente | Tecnologia | Onde roda |
|---|---|---|
| Agente de coleta | Python script (ou `.exe` via PyInstaller) | Cada máquina das lojas |
| Servidor central | Python FastAPI + SQLite | Máquina do TI |
| Painel web | HTML + CSS + JS vanilla | Navegador do técnico |
| Cadastro de máquinas | `machines.json` (editado manualmente) | Pasta do servidor |

---

## Cadastro de Máquinas

Arquivo `machines.json` na raiz do servidor. Editado manualmente quando necessário.

```json
[
  { "loja": "Loja 01", "hostname": "LOJA01-PDV1", "ip": "192.168.1.10" },
  { "loja": "Loja 02", "hostname": "LOJA02-PDV1", "ip": "192.168.2.10" }
]
```

O servidor lê esse arquivo na inicialização. Para adicionar ou remover máquinas, basta editar o JSON e reiniciar o servidor.

### Configuração do Servidor (`config.json`)

```json
{
  "server_port": 8000,
  "winrm_user": "administrador",
  "winrm_password": "senha_aqui",
  "linx_service_names": ["Dtef", "DtefService"],
  "agent_path_on_machine": "C:\\TI\\agent.py"
}
```

O `agent.py` nas máquinas das lojas recebe a URL do servidor como argumento na hora do disparo via WinRM: `python C:\TI\agent.py --server http://192.168.0.1:8000`.

---

## Checks de Diagnóstico

O agente coleta dados em 5 categorias. Cada check retorna: `OK`, `AVISO` ou `CRÍTICO`.

### Windows (SO)

| Check | Método | Limiar de Alerta |
|---|---|---|
| Erros no Event Log (24h) | `Get-EventLog` | > 10 erros críticos → AVISO |
| Windows Update pendente | WMI `Win32_QuickFixEngineering` | > 30 dias sem instalar → AVISO |
| Espaço em disco C: | WMI `Win32_LogicalDisk` | < 10 GB livres → CRÍTICO |
| Serviços críticos (Spooler, WMI, RPC) | `Get-Service` | Qualquer parado → CRÍTICO |
| Uptime desde último boot | WMI `Win32_OperatingSystem` | > 7 dias → AVISO |

### Hardware

| Check | Método | Limiar de Alerta |
|---|---|---|
| Uso de CPU | WMI `Win32_Processor` | > 85% → AVISO |
| Uso de RAM | WMI `Win32_PhysicalMemory` | > 90% → AVISO |
| Saúde do disco (SMART) | `Get-PhysicalDisk` | Status ≠ "Healthy" → CRÍTICO |
| Temperatura CPU | WMI `MSAcpi_ThermalZoneTemperature` | > 85°C → AVISO; não disponível → exibe "N/D" |

### Rede

| Check | Método | Limiar de Alerta |
|---|---|---|
| Ping gateway | `Test-Connection` | Falha ou > 50ms → AVISO |
| Ping internet (8.8.8.8) | `Test-Connection` | Falha → CRÍTICO |
| Resolução DNS | `Resolve-DnsName` | Falha → CRÍTICO |
| Configuração IP | `Get-NetIPAddress` | IP APIPA (169.x.x.x) → CRÍTICO |

### Performance

| Check | Método | Limiar de Alerta |
|---|---|---|
| Top 5 processos por CPU | `Get-Process` | Processo > 50% CPU → AVISO |
| Tempo de boot | Event Log ID 100 | > 3 minutos → AVISO |
| Fila de disco (I/O) | Performance Counter | Fila > 2 → AVISO |

### Linx POS / ERP / Dtef

| Check | Método | Limiar de Alerta |
|---|---|---|
| Processo Linx POS | `Get-Process` (tenta `linx.exe` e `linxpos.exe`) | Nenhum encontrado → CRÍTICO |
| Serviço Dtef | `Get-Service` (nomes configuráveis em `config.json`) | Parado ou não encontrado → CRÍTICO |
| Porta local Linx (8080) | `Test-NetConnection` | Fechada → AVISO |

> **Nota:** Para temperatura, se WMI não suportar o hardware, retorna `"value": "N/D"` com status `OK`.

---

## Modelo de Dados (SQLite)

```sql
-- Máquinas conhecidas (carregadas do machines.json)
CREATE TABLE machines (
    id        INTEGER PRIMARY KEY,
    hostname  TEXT UNIQUE,
    ip        TEXT,
    loja_nome TEXT,
    last_seen TEXT
);

-- Sessões de diagnóstico
CREATE TABLE diagnostics (
    id             INTEGER PRIMARY KEY,
    machine_id     INTEGER REFERENCES machines(id),
    timestamp      TEXT,
    duration_sec   INTEGER,
    overall_status TEXT  -- 'OK' | 'AVISO' | 'CRÍTICO'
);

-- Checks individuais
CREATE TABLE checks (
    id            INTEGER PRIMARY KEY,
    diagnostic_id INTEGER REFERENCES diagnostics(id),
    category      TEXT,   -- 'windows' | 'hardware' | 'rede' | 'performance' | 'linx'
    name          TEXT,
    status        TEXT,   -- 'OK' | 'AVISO' | 'CRÍTICO'
    value         TEXT,
    message       TEXT
);
```

---

## API (FastAPI)

| Método | Rota | Descrição |
|---|---|---|
| `GET` | `/` | Serve o painel HTML |
| `GET` | `/machines` | Lista máquinas do `machines.json` com último status |
| `POST` | `/diagnose/{hostname}` | Dispara diagnóstico via WinRM na máquina |
| `POST` | `/report` | Agente envia resultado JSON |
| `GET` | `/diagnostics/{hostname}/latest` | Último diagnóstico de uma máquina |
| `GET` | `/diagnostics/{hostname}` | Histórico de diagnósticos |

### Payload do agente (`POST /report`)

```json
{
  "hostname": "LOJA02-PDV1",
  "ip": "192.168.2.10",
  "loja": "Loja 02",
  "timestamp": "2026-05-29T10:42:00",
  "duration_sec": 14,
  "checks": [
    {
      "category": "linx",
      "name": "Linx POS",
      "status": "CRÍTICO",
      "value": "não encontrado",
      "message": "linx.exe e linxpos.exe ausentes"
    },
    {
      "category": "hardware",
      "name": "RAM Usage",
      "status": "AVISO",
      "value": "91%",
      "message": "7.4 GB / 8 GB utilizados"
    }
  ]
}
```

---

## Painel Web (Dashboard)

### Tela Principal — Cards Grid

- Um card por máquina
- Faixa colorida no topo: verde (OK), amarelo (AVISO), vermelho (CRÍTICO)
- Cada card mostra status por categoria (●/⚠/✕)
- Barra de filtros: Todos / Críticos / Avisos / por categoria
- Contador global no cabeçalho (X OK, Y Avisos, Z Críticos)
- Botão "Diagnosticar Todas"

### Tela de Detalhe — Problemas Primeiro

Aberta ao clicar em um card (modal overlay):

1. **Críticos** — itens em vermelho, com nome, detalhe e categoria
2. **Avisos** — itens em amarelo
3. **Sem problemas** — resumo compacto verde listando todos os checks OK
4. Botão "Diagnosticar" para acionar novo diagnóstico nessa máquina

---

## Fluxo de Execução Remota

1. Técnico clica em "Diagnosticar" no painel
2. Servidor FastAPI recebe `POST /diagnose/{hostname}`
3. Servidor dispara `Invoke-Command` via WinRM para a máquina alvo
4. Agente `agent.py` (ou `agent.exe`) executa os checks (≈ 10–20 seg)
5. Agente faz `HTTP POST /report` com o JSON dos resultados
6. Servidor salva no SQLite e atualiza o estado em memória
7. Painel atualiza automaticamente (polling a cada 5 segundos)

### Pré-requisitos nas máquinas das lojas

- WinRM habilitado: `Enable-PSRemoting -Force`
- Python 3.x instalado (ou `agent.exe` distribuído)
- `agent.py` presente em `C:\TI\agent.py` (caminho configurável em `config.json`)
- Firewall liberado: porta 5985 (WinRM) e acesso HTTP de saída para o servidor central na porta 8000
- Credenciais WinRM: conta de administrador local ou de domínio configurada em `config.json`

---

## Estrutura de Arquivos

```
diagnostic-agent/
├── server/
│   ├── main.py          # FastAPI app
│   ├── database.py      # SQLite helpers
│   ├── winrm_runner.py  # Disparo via WinRM
│   ├── machines.json    # Cadastro de máquinas
│   └── static/
│       └── index.html   # Dashboard HTML/CSS/JS
├── agent/
│   └── agent.py         # Coletor de checks (roda nas lojas)
└── requirements.txt
```

---

## Fora de Escopo (por ora)

- Autenticação no painel web
- Alertas por e-mail/WhatsApp
- UI para cadastro de máquinas
- Suporte a sistemas operacionais além de Windows
- Múltiplos PDVs por loja (estrutura suporta, mas não é requisito agora)
