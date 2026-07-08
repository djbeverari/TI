# Agente de Diagnóstico de Computadores — Design Spec

**Data:** 2026-05-29  
**Autor:** Daniella  
**Status:** Aprovado (v2 — polling model, sem WinRM)

---

## Visão Geral

Ferramenta para o técnico de TI diagnosticar remotamente máquinas Windows nas lojas (até 39 máquinas). O técnico aciona o diagnóstico pelo painel web; o agente instalado em cada máquina busca comandos pendentes no servidor, executa os checks e envia os resultados. O dashboard exibe o estado centralizado com foco nos problemas encontrados.

---

## Arquitetura

```
┌──────────────────────────────────────────────────┐
│              MÁQUINA CENTRAL (TI)                │
│                                                  │
│  ┌──────────────┐    ┌──────────────────────┐   │
│  │ Web Dashboard│◄───│  FastAPI Server      │   │
│  │ (HTML/JS)    │    │  + SQLite            │   │
│  └──────────────┘    └──────────┬───────────┘   │
└─────────────────────────────────│────────────────┘
                                  │ HTTP (porta 8000)
          ┌───────────────────────┼───────────────┐
          ▼                       ▼               ▼
   ┌─────────────┐       ┌─────────────┐  ┌─────────────┐
   │  LOJA 01    │       │  LOJA 02    │  │  LOJA N     │
   │  agent.py   │       │  agent.py   │  │  agent.py   │
   │  (polling)  │       │  (polling)  │  │  (polling)  │
   └─────────────┘       └─────────────┘  └─────────────┘
```

**Modelo de comunicação — Agent Pull (sem WinRM):**

1. Cada agente roda como Tarefa Agendada no Windows (a cada 10 segundos)
2. Agente chama `GET /pending/{hostname}` — se não há diagnóstico pendente, encerra
3. Técnico clica "Diagnosticar" no painel → servidor registra comando pendente
4. Na próxima rodada (≤ 10 seg), agente detecta o pedido, executa os checks e envia o resultado via `POST /report`
5. Dashboard atualiza automaticamente (polling a cada 5 segundos)

**Vantagens sobre WinRM:**
- Não requer privilégios de administrador nas máquinas
- Não requer configuração de firewall de entrada
- Funciona em qualquer ambiente Windows sem pré-requisitos especiais

### Componentes

| Componente | Tecnologia | Onde roda |
|---|---|---|
| Agente de coleta | Python 3 (Task Scheduler) | Cada máquina das lojas |
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

### Configuração do Servidor (`config.json`)

```json
{
  "server_port": 8000,
  "linx_process_names": ["linx.exe", "linxpos.exe"],
  "linx_service_keywords": ["linx", "dtef"],
  "linx_port": null
}
```

- `linx_service_keywords`: agente filtra todos os serviços instalados cujo nome contém essas palavras. Na primeira execução, o relatório inclui a lista completa de serviços Linx/Dtef encontrados para identificação.
- `linx_port`: se `null`, o check de porta é pulado com status `OK` e mensagem "porta não configurada".

### Configuração do Agente (`agent_config.json`) — fica em `C:\TI\`

```json
{
  "server_url": "http://192.168.0.1:8000",
  "poll_interval_sec": 10
}
```

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
| Temperatura CPU | WMI `MSAcpi_ThermalZoneTemperature` | > 85°C → AVISO; não disponível → exibe "N/D", status OK |

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
| Processo Linx POS | `Get-Process` (nomes em `config.json`) | Nenhum encontrado → CRÍTICO |
| Serviços Linx/Dtef | `Get-Service` filtrado por keywords | Qualquer parado → CRÍTICO; lista completa retornada no relatório |
| Porta Linx | `Test-NetConnection` (se configurada) | Fechada → AVISO; não configurada → OK / "não configurada" |

> **Descoberta de serviços:** na primeira execução, o agente lista todos os serviços cujo nome contém "linx" ou "dtef" e inclui no relatório como `"linx_services_found"`. Isso permite identificar o nome exato do Dtef sem precisar acessar a máquina manualmente.

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

-- Comandos pendentes (criados pelo painel, consumidos pelo agente)
CREATE TABLE pending_commands (
    id         INTEGER PRIMARY KEY,
    hostname   TEXT,
    created_at TEXT,
    status     TEXT  -- 'pending' | 'running' | 'done'
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
| `GET` | `/machines` | Lista máquinas com último status |
| `POST` | `/diagnose/{hostname}` | Registra diagnóstico pendente para a máquina |
| `GET` | `/pending/{hostname}` | Agente verifica se há diagnóstico pendente |
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
  "linx_services_found": ["LinxPOS", "DtefSvc"],
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
- Indicador de agente: "online" se fez polling nos últimos 30 seg, "offline" caso contrário

### Tela de Detalhe — Problemas Primeiro

Aberta ao clicar em um card (modal overlay):

1. **Críticos** — itens em vermelho, com nome, detalhe e categoria
2. **Avisos** — itens em amarelo
3. **Sem problemas** — resumo compacto verde listando todos os checks OK
4. Botão "Diagnosticar" para acionar novo diagnóstico nessa máquina
5. Seção "Serviços Linx encontrados" exibida na primeira execução para auxiliar configuração

---

## Fluxo de Execução

1. Técnico clica em "Diagnosticar" no painel
2. Servidor registra `pending_command` para o hostname no SQLite
3. Painel exibe "aguardando agente..." no card
4. Agente na máquina (rodando via Task Scheduler a cada 10s) chama `GET /pending/{hostname}`
5. Servidor retorna `{ "pending": true }` — agente executa os checks (≈ 10–20 seg)
6. Agente faz `POST /report` com o JSON dos resultados
7. Servidor salva no SQLite, marca `pending_command` como `done`
8. Painel atualiza (polling a cada 5s) e exibe o resultado

### Instalação do Agente nas Máquinas das Lojas

```powershell
# Executar uma vez por máquina (não requer admin)
New-Item -ItemType Directory -Force "C:\TI"
# Copiar agent.py e agent_config.json para C:\TI\

# Criar Tarefa Agendada (roda a cada 1 minuto, agent controla intervalo interno)
schtasks /create /tn "TI-DiagAgent" /tr "python C:\TI\agent.py" /sc MINUTE /mo 1 /f
```

> Pré-requisito: Python 3 instalado na máquina (ou distribuir `agent.exe` compilado com PyInstaller — sem necessidade de Python).

---

## Estrutura de Arquivos

```
diagnostic-agent/
├── server/
│   ├── main.py          # FastAPI app + endpoints
│   ├── database.py      # SQLite helpers
│   ├── config.json      # Configurações (porta, nomes Linx)
│   ├── machines.json    # Cadastro de máquinas
│   └── static/
│       └── index.html   # Dashboard HTML/CSS/JS
├── agent/
│   ├── agent.py         # Coletor de checks + polling
│   └── agent_config.json # URL do servidor
└── requirements.txt
```

---

## Fora de Escopo (por ora)

- Autenticação no painel web
- Alertas por e-mail/WhatsApp
- UI para cadastro de máquinas
- Suporte a sistemas operacionais além de Windows
- Múltiplos PDVs por loja (estrutura suporta, mas não é requisito agora)
- WinRM / execução remota ativa (substituído por polling)
