# Verificador de Tickets Diário — Design Spec

**Data:** 2026-05-22
**Revisão:** 2026-07-02 (v2 — autenticação, agendamento, lógica pendente/divergente)
**Autor:** Daniella
**Status:** Aprovado — pronto para plano de implementação

---

## Problema

Os tickets de venda **nascem no banco de cada loja** e sobem para a retaguarda via DataSync (Linx). É preciso verificar diariamente se a quantidade de tickets do período chegou corretamente à retaguarda. Hoje isso é feito manualmente. O objetivo é automatizar a comparação e alertar, num painel HTML acessível por qualquer máquina da rede, as lojas cuja contagem divergiu.

**Direção da verdade:** origem = loja. O caso que alerta é **Retaguarda < Loja** (a loja tem ticket que não chegou na retaguarda).

---

## Solução

Script PowerShell agendado via Task Scheduler que:
1. Calcula as datas a verificar (considerando fins de semana e feriados)
2. Consulta os 38 bancos das lojas e o banco da retaguarda via SQL Server (SQL Auth)
3. Compara as contagens de tickets por loja
4. Para cada loja com Retaguarda < Loja, consulta o status do DataSync para separar "pendente" (ainda vai sincronizar) de "divergente" (faltou de verdade)
5. Gera um painel HTML acessível via `http://192.168.0.147:8080`

---

## Arquitetura

```
[Task Scheduler ~11:30] → [verifica-tickets.ps1]
                        │
                        ├── Calcula datas a verificar
                        ├── Carrega feriados (Brasil API + CSV municipal)
                        ├── Consulta 38 bancos de loja (SQL Server, SQL Auth)
                        ├── Consulta banco da retaguarda (SQL Server, SQL Auth)
                        ├── Compara contagens por loja/data
                        ├── Consulta status do DataSync (pendente vs divergente)
                        └── Gera relatorio.html
                                    │
                       [Python http.server — porta 8080]
                                    │
                       http://192.168.0.147:8080
```

Reaproveita a infra já existente do DataSync no servidor `192.168.0.147` (Python http.server na 8080, Task Scheduler).

---

## Componentes

| Arquivo | Localização | Descrição |
|---|---|---|
| `verifica-tickets.ps1` | `C:\Users\Daniella\ti\` | Script principal |
| `lojas-config.ps1` (ou `.csv`) | `C:\Users\Daniella\ti\` | Config de conexão por loja (IP/banco/usuário/senha) — **preenchido pela Daniella** |
| `feriados_municipais.csv` | `C:\Users\Daniella\ti\` | Feriados municipais por loja |
| `feriados_cache.json` | `C:\Users\Daniella\ti\` | Cache de feriados nacionais/estaduais (gerado automaticamente) |
| `relatorio.html` | `C:\WebRelatorios\` | Painel HTML gerado |
| Serviço web | `192.168.0.147:8080` | Python http.server como serviço Windows (já existente — DataSyncHTTP) |

---

## Lógica de Datas

### Regra principal
- **Segunda-feira:** verifica sexta + sábado + domingo
- **Após feriado(s):** verifica todos os dias desde o último dia útil
- **Demais dias:** verifica apenas o dia anterior

### Fontes de feriados
- **Nacionais e estaduais:** Brasil API (`brasilapi.com.br/api/feriados/v1/{ano}`) — consultado uma vez por ano e armazenado em `feriados_cache.json`
- **Municipais:** arquivo `feriados_municipais.csv` mantido manualmente

### Formato do feriados_municipais.csv
```csv
DATA,DESCRICAO,LOJAS
2026-06-13,Santo Antonio,3|4|5
2026-07-26,Santana,21|23
```

- `DATA`: formato `YYYY-MM-DD`
- `LOJAS`: números das lojas separados por `|`. Usar `TODAS` para feriado de todas as lojas.

---

## Conexões SQL Server

**Autenticação:** SQL Auth com usuário `sa`. As **38 lojas compartilham a mesma senha**; a **retaguarda (Dorinhos) tem senha diferente**. Nenhuma senha fica no repositório — são guardadas em dois arquivos protegidos por DPAPI (`.sql_cred` para as lojas e `.sql_cred_retaguarda` para a retaguarda, em `C:\Users\Daniella\ti\`, seguindo o padrão do `.email_cred` do datasync). IPs e mapeamento de loja ficam em `scripts/lojas-config.ps1`.

### Retaguarda / Matriz
- Servidor: **`192.168.0.55`** (cadastrado como "Dorinhos" no SSMS) — **não** é o `192.168.0.147` (esse é só o servidor de automação do datasync)
- Banco: a confirmar (`SELECT name FROM sys.databases` no 192.168.0.55)
- Identificação da loja: coluna de número de loja na tabela de tickets (ex.: `loja_id` / `numero_loja` — **nome exato a confirmar**), filtrada por `WHERE <coluna_loja> = <numero>`

### Lojas (38 lojas)
**IPs já obtidos** do `RegSrvr.xml` do SSMS (Registered Servers) e gravados em `scripts/lojas-config.ps1`. Todas rodam SQL Express (`\sqlexpress`), usuário `sa`. Lojas: `3, 4, 5, 6, 7, 9, 14, 16, 17, 21, 23, 26, 28, 29, 31, 32, 33, 34, 36, 37, 38, 40, 41, 42, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57`.

Estrutura de configuração (`scripts/lojas-config.ps1`):
```powershell
$SqlUser = "sa"
$SqlCredFile           = "C:\Users\Daniella\ti\.sql_cred"            # senha das lojas
$SqlCredFileRetaguarda = "C:\Users\Daniella\ti\.sql_cred_retaguarda" # senha da retaguarda
$Retaguarda = @{ Servidor="192.168.0.55"; Banco="<BANCO_RETAGUARDA>" }
$Lojas = @(
    @{ Numero=3;  Servidor="192.168.11.100\sqlexpress" },
    ...
)
```

---

## Query SQL

**Na loja** (banco local, sem filtro de loja):
```sql
SELECT COUNT(*) AS total
FROM loja_venda
WHERE data_venda IN ('2026-05-21', '2026-05-20')
```

**Na retaguarda** (mesma tabela, filtrando pela loja):
```sql
SELECT COUNT(*) AS total
FROM loja_venda
WHERE data_venda IN ('2026-05-21', '2026-05-20')
  AND <coluna_loja> = 3
```

`loja_venda.data_venda` confirmado; 1 ticket = 1 linha. Nome da `<coluna_loja>` na retaguarda a confirmar no config.

---

## Lógica de Status (pendente vs divergente)

Para cada loja, comparando `TicketsLoja` (origem) com `TicketsRetaguarda`:

| Situação | Significado | Status | Cor |
|---|---|---|---|
| `Retaguarda == Loja` | tudo subiu | **OK** | Verde |
| `Retaguarda < Loja` **e** loja ainda **não** completou o sync de hoje | sync atrasado, deve resolver nos próximos ciclos | **PENDENTE** | Amarelo |
| `Retaguarda < Loja` **e** loja **já** sincronizou hoje | ticket da loja não chegou — falha real | **DIVERGENTE** | Vermelho |
| `Retaguarda > Loja` | retaguarda tem a mais (possível duplicação) | **ATENÇÃO** | Laranja |
| ambos zerados | sem movimento no período | **SEM MOVIMENTO** | Cinza |
| banco inacessível | falha de conexão | **ERRO DE CONEXÃO** | Laranja (com ícone distinto) |

### Fonte do status de sync
O DataSync grava um arquivo de status por loja (padrão `loja_<numero>.txt`, lido hoje pelo `gerar-painel-datasync.ps1`). O verificador lê esse status para saber se a loja já completou o sync do dia. **Caminho e formato exatos a confirmar contra o script do datasync no servidor** (`C:\Users\Datasync\Desktop\ti\`).

> Racional do agendamento: rodar às 11:30, logo após o ciclo `DataSync_1030`, pega o dia anterior já consolidado na maioria das lojas. Lojas notoriamente lentas (ex.: 31, 03) podem não ter sincronizado ainda — por isso a distinção pendente/divergente via status do datasync, para evitar alarme falso.

---

## Painel HTML

### Resumo (topo da página)
- Timestamp da última atualização
- Período verificado
- Total de lojas OK
- Total de lojas PENDENTES
- Total de lojas DIVERGENTES
- Total de lojas em ATENÇÃO / ERRO
- Total geral de tickets (soma de todas as lojas)

### Tabela de lojas
| Coluna | Descrição |
|---|---|
| Loja | Número da loja |
| Tickets Loja | Contagem no banco local da loja |
| Tickets Retaguarda | Contagem no banco da retaguarda |
| Diferença | Tickets Loja − Tickets Retaguarda |
| Sync hoje | Se a loja já completou o sync do dia (do status do datasync) |
| Status | OK / PENDENTE / DIVERGENTE / ATENÇÃO / SEM MOVIMENTO / ERRO |

### Visual
- Linha **verde** = OK
- Linha **amarela** = PENDENTE (sync atrasado)
- Linha **vermelha** = DIVERGENTE (falha real — destaque forte)
- Linha **laranja** = ATENÇÃO (retaguarda > loja) ou ERRO DE CONEXÃO
- Linha **cinza** = sem movimento no período
- Linha de **TOTAL GERAL** ao final da tabela

---

## Tratamento de Erros

- Se um banco de loja estiver inacessível: linha **ERRO DE CONEXÃO** (laranja), não conta como divergência
- Se o status do datasync não puder ser lido: assume "sync não confirmado" e trata Retaguarda < Loja como PENDENTE (conservador, evita falso vermelho)
- Se a Brasil API estiver offline: usa apenas o cache local; se o cache também falhar, usa só os feriados nacionais fixos hardcoded
- Log de execução gravado em `C:\Logs\VerificaTickets\verifica_YYYY-MM-DD.log`

---

## Agendamento (Task Scheduler)

- **Trigger:** diário, de segunda a sexta, às **11:30**
- **Ação:** executar `verifica-tickets.ps1`
- **Conta:** conta de serviço com acesso à rede e aos bancos
- **Racional:** logo após o término do ciclo `DataSync_1030` (~10:30 + ~45 min), verificando o dia anterior

---

## Serviço Web

- Python `http.server` servindo `C:\WebRelatorios\` na porta `8080` (serviço `DataSyncHTTP` já existente)
- URL de acesso: `http://192.168.0.147:8080`
- O `relatorio.html` do verificador pode ganhar um nome próprio (ex.: `tickets.html`) para não colidir com o painel do datasync — a confirmar na implementação

---

## Itens Pendentes

**Resolvidos:**
- [x] IPs das 38 lojas — obtidos do SSMS, em `scripts/lojas-config.ps1`
- [x] Servidor da retaguarda — `192.168.0.55` ("Dorinhos")
- [x] Autenticação — SQL Auth, `sa` (senha das lojas compartilhada; retaguarda com senha própria)
- [x] Banco de cada loja — padrão `Loja<NN>` (loja 03 = `Loja03`), derivado do número
- [x] Banco da retaguarda — `Dorinhos_2022`
- [x] Coluna de loja na retaguarda — `codigo_filial` (`WHERE codigo_filial = <numero>`)
- [x] Status do datasync — `C:\Logs\DataSync\status\loja_<num>.txt`, conteúdo `Tipo|Status|Hora`

**A confirmar no dry-run (com as lojas online):**
- [ ] Gravar as senhas do `sa` via `guardar-senha-sql.ps1` (`.sql_cred` + `.sql_cred_retaguarda`)
- [ ] Confirmar que `codigo_filial` usa o mesmo número da loja (3,4,…57), não um código interno
- [ ] Confirmar tabela/coluna `loja_venda.data_venda` no banco real (loja e retaguarda)
- [ ] Confirmar horário do agendamento (11:30) vs. término real do ciclo 10:30
- [ ] Confirmar a pasta servida pelo `DataSyncHTTP` (para o `tickets.html` aparecer na 8080)
