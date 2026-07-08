# Painel de Estoque Negativos — Design Spec

**Data:** 2026-07-08
**Autor:** Daniella
**Status:** Aprovado

---

## Problema

Existe uma tabela `estoque_negativos` no banco da retaguarda (Linx) que traz os itens com quantidade de estoque negativa. Hoje não há um jeito visual e automático de acompanhar esses itens — é preciso um painel HTML, gerado automaticamente todo dia, acessível por qualquer máquina da rede.

---

## Solução

Script PowerShell agendado via Task Scheduler que:
1. Roda de segunda a sexta, logo após 11:00
2. Conecta direto na retaguarda (SQL Server) a partir da máquina da Daniella
3. Consulta a tabela `estoque_negativos` (já vem filtrada, só itens negativos)
4. Gera um painel HTML acessível via `http://<ip-da-maquina-da-daniella>:8082`

---

## Arquitetura

```
[Task Scheduler, seg-sex ~11:00] → [gera-painel-negativos.ps1]
                                        │
                                        ├── Conecta na retaguarda (192.168.0.55, Dorinhos_2022)
                                        ├── SELECT * FROM estoque_negativos ORDER BY quantidade ASC
                                        ├── Gera negativos.html
                                        └── Se falhar: mantém o último HTML gerado + aviso "dados desatualizados"
                                                    │
                                       [Python http.server — porta 8082, na máquina da Daniella]
                                                    │
                                       http://<ip-daniella>:8082
```

Diferente do verificador de tickets, não há necessidade de conectar em cada uma das 39 lojas nem de checar status de sync — a tabela já é consolidada e filtrada na retaguarda.

---

## Componentes

| Arquivo | Localização | Descrição |
|---|---|---|
| `gera-painel-negativos.ps1` | máquina da Daniella | Script principal |
| `negativos.html` | pasta servida pelo http.server | Painel HTML gerado |
| Serviço web | `<ip-daniella>:8082` | Python http.server (instância separada da do verificador de tickets) |

---

## Conexão SQL Server

- **Servidor:** `192.168.0.55` (retaguarda "Dorinhos", mesma do verificador de tickets)
- **Banco:** `Dorinhos_2022`
- **Autenticação:** SQL Authentication, usuário `sa`, **senha própria** (diferente da senha compartilhada das lojas) — reaproveitar padrão de `guardar-senha-sql.ps1` / `.sql_cred_retaguarda` já usado no verificador de tickets, mas armazenado na máquina da Daniella (não na 192.168.0.147)

---

## Query SQL

```sql
SELECT loja, produto, codigo, quantidade, data
FROM estoque_negativos
ORDER BY quantidade ASC
```

> A tabela já vem só com itens negativos — não é necessário filtrar por `WHERE quantidade < 0`.
> Nomes exatos das colunas a confirmar contra o schema real antes de codar (placeholders acima: `loja`, `produto`, `codigo`, `quantidade`, `data`).

---

## Painel HTML

### Resumo (topo da página)
- Timestamp da última geração bem-sucedida
- Total de itens negativos
- Total de lojas afetadas (contagem distinta de `loja`)
- Se a última tentativa de geração falhou: aviso destacado "⚠️ dados desatualizados desde HH:MM"

### Campo de busca
- Filtro client-side (sem reload) por loja ou nome de produto

### Tabela única
| Coluna | Descrição |
|---|---|
| Loja | Número da loja |
| Produto | Nome do produto |
| Código | Código do produto |
| Quantidade | Quantidade negativa (ordenação padrão: mais negativa primeiro) |
| Data | Data do registro |

---

## Tratamento de Erros

- Se a conexão com a retaguarda falhar: mantém o `negativos.html` da última geração bem-sucedida, atualiza apenas o aviso de "dados desatualizados" — nunca mostra painel vazio ou quebrado
- Log de execução em `C:\Logs\PainelNegativos\painel_YYYY-MM-DD.log`

---

## Agendamento (Task Scheduler)

- **Trigger:** diário, segunda a sexta, logo após 11:00
- **Ação:** executar `gera-painel-negativos.ps1`
- **Conta:** conta da Daniella (acesso direto à retaguarda já confirmado)

---

## Serviço Web

- Python `http.server` servindo a pasta com `negativos.html` na porta `8082`
- Roda na máquina da Daniella (não na 192.168.0.147, que hospeda só o painel de tickets)
- URL de acesso: `http://<ip-daniella>:8082`

---

## Itens Pendentes (antes da implementação)

- [x] Confirmar nomes exatos das colunas de `estoque_negativos` contra o schema real — resolvido, ver detalhes no plano (`docs/superpowers/plans/2026-07-08-painel-negativos.md`, seção "Descobertas durante a implementação")
- [x] Decidir se o Python http.server roda manualmente, como serviço via NSSM, ou inicia junto com o Task Scheduler — resolvido: Scheduled Task com trigger `AtLogOn`
- [ ] Confirmar IP atual da máquina da Daniella para divulgar a URL de acesso

## Correções pós-descoberta do schema real (2026-07-08)

O schema real de `DANIELLA_J.estoque_negativos` é bem diferente do assumido inicialmente:
- Não existe uma coluna única de "quantidade negativa": o estoque por grade/tamanho fica em `es1`..`es10`, e a coluna `estoque` (total) é sempre positiva. O painel mostra uma linha por (loja, código, grade) sempre que `esN < 0`.
- A tabela acumula ~20 gerações semanais sem limpar as antigas — é necessário filtrar pela `data_geracao` mais recente.
- Colunas de texto (`filial`, `produto`) vêm com espaços à direita e precisam de trim.

Detalhes completos da query final e das correções de encoding/SSL estão no plano de implementação.
