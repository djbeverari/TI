# Verificador de Tickets Diário — Design Spec

**Data:** 2026-05-22  
**Autor:** Daniella  
**Status:** Aprovado

---

## Problema

Após a sincronização diária (datasync) dos bancos das 38 lojas com a retaguarda, é preciso verificar manualmente se a quantidade de tickets de venda do dia anterior chegou corretamente ao banco da retaguarda. O processo é feito manualmente hoje e precisa ser automatizado com um painel visual acessível por qualquer máquina da rede.

---

## Solução

Script PowerShell agendado via Task Scheduler que:
1. Calcula as datas a verificar (considerando fins de semana e feriados)
2. Consulta os 38 bancos das lojas e o banco da retaguarda via SQL Server
3. Compara as contagens de tickets por loja
4. Gera um painel HTML acessível via `http://192.168.0.147:8080`

---

## Arquitetura

```
[Task Scheduler] → [verifica-tickets.ps1]
                        │
                        ├── Calcula datas a verificar
                        ├── Carrega feriados (API + CSV municipal)
                        ├── Consulta 38 bancos de loja (SQL Server)
                        ├── Consulta banco da retaguarda (SQL Server)
                        ├── Compara contagens por loja/data
                        └── Gera relatorio.html
                                    │
                       [Python http.server — porta 8080]
                                    │
                       http://192.168.0.147:8080
```

---

## Componentes

| Arquivo | Localização | Descrição |
|---|---|---|
| `verifica-tickets.ps1` | `C:\Users\Daniella\ti\` | Script principal |
| `feriados_municipais.csv` | `C:\Users\Daniella\ti\` | Feriados municipais por loja |
| `feriados_cache.json` | `C:\Users\Daniella\ti\` | Cache de feriados nacionais/estaduais (gerado automaticamente) |
| `relatorio.html` | `C:\WebRelatorios\` | Painel HTML gerado |
| Serviço web | `192.168.0.147:8080` | Python http.server como serviço Windows |

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

### Retaguarda
- IP: `192.168.0.147`
- Banco: a definir (informado pela Daniella)
- Autenticação: Windows Authentication ou SQL Authentication (a definir)

### Lojas (38 lojas)
IPs e nomes de banco a serem fornecidos pela Daniella. As lojas existentes são:
`3, 4, 5, 6, 7, 9, 14, 16, 17, 21, 23, 26, 28, 29, 31, 32, 33, 34, 36, 37, 38, 40, 41, 42, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57`

Estrutura de configuração no script:
```powershell
$Lojas = @(
    @{ Numero=3;  IP="192.168.X.X"; Banco="NOME_BANCO"; Usuario="sa"; Senha="senha" },
    ...
)
```

---

## Query SQL

```sql
SELECT COUNT(*) AS total
FROM loja_venda
WHERE data_venda IN ('2026-05-21', '2026-05-20')
```

A mesma query é executada tanto no banco da loja quanto no banco da retaguarda (filtrando por loja na retaguarda, se necessário).

---

## Painel HTML

### Resumo (topo da página)
- Timestamp da última atualização
- Período verificado
- Total de lojas OK
- Total de lojas com divergência
- Total geral de tickets (soma de todas as lojas)

### Tabela de lojas
| Coluna | Descrição |
|---|---|
| Loja | Número da loja |
| Tickets Loja | Contagem no banco local da loja |
| Tickets Retaguarda | Contagem no banco da retaguarda |
| Diferença | Tickets Loja − Tickets Retaguarda |
| Status | ✅ OK ou ❌ DIVERGENTE |

### Visual
- Linha **verde** = OK (contagens iguais)
- Linha **vermelha** = DIVERGENTE (contagens diferentes)
- Linha **cinza** = loja sem movimento no período (ambos zerados)
- Linha de **TOTAL GERAL** ao final da tabela

---

## Tratamento de Erros

- Se um banco de loja estiver inacessível: exibe `ERRO DE CONEXÃO` em amarelo na linha da loja
- Se a Brasil API estiver offline: usa apenas o cache local; se o cache também falhar, usa só os feriados nacionais fixos hardcoded
- Log de execução gravado em `C:\Logs\VerificaTickets\verifica_YYYY-MM-DD.log`

---

## Agendamento (Task Scheduler)

- **Trigger:** diário, de segunda a sexta, às **08:00**
- **Ação:** executar `verifica-tickets.ps1`
- **Conta:** conta de serviço com acesso à rede e aos bancos

> Horário de 08:00 pressupõe que o datasync das 07:xx já finalizou. Ajustar conforme horário real do último sync.

---

## Serviço Web

- Python `http.server` servindo `C:\WebRelatorios\` na porta `8080`
- Configurado como serviço Windows via `NSSM` (Non-Sucking Service Manager) para iniciar automaticamente
- URL de acesso: `http://192.168.0.147:8080`

---

## Itens Pendentes (necessários antes da implementação)

- [ ] Lista completa de IPs e nomes de bancos das 38 lojas
- [ ] Nome do banco da retaguarda e tipo de autenticação (Windows ou SQL)
- [ ] Nome exato da tabela e coluna de data (`loja_venda.data_venda` — confirmar)
- [ ] Confirmar horário ideal para agendamento (após término do datasync)
- [ ] Na retaguarda, como a loja é identificada? (coluna `loja_id`, `numero_loja`, etc.)
