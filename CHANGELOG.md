# Changelog - DataSync Automação

## [2026-05-29] - Fix ENVIA pular pedidos entre ciclos

### Problema
A partir de sexta-feira 23/05, pedidos criados entre os ciclos não eram enviados.
O ciclo das 10:30 enviava normalmente, mas 14:30 e 16:30 pulavam todas as lojas.

### Causa
O pre-check de log (adicionado para RECEBE das lojas 31/03) estava sendo aplicado
também no ENVIA. Após o ENVIA das 10:30, os ciclos seguintes encontravam o log de
sucesso do dia e marcavam "já concluído" — sem enviar os pedidos novos.

### Fix (`data-sync-automacao.ps1`)
- Pre-check agora executa **somente para RECEBE** (`if ($Tipo -eq "RECEBE")`)
- ENVIA sempre roda o atalho, independente de logs anteriores do dia

---

## [2026-05-29] - Fix E-COMMERCE filtro de log + painel "sem dados"

### Problema 1 — E-COMMERCE falso negativo
O script reportava "Log do Linx não gerado" para E-COMMERCE, mas o Linx havia
sincronizado normalmente. O atalho do E-COMMERCE gerava log com nome
`LOG-...-SANTA RITA-E-COMMERCE-2.log` (sem prefixo "LOJA").

### Fix (`data-sync-automacao.ps1`)
- Adicionado `$lojaFiltro`: lojas numéricas usam `*LOJA $Loja*`, demais usam `*$Loja*`
- Aplicado nos dois pontos do `$jobBlock`: pre-check e verificação pós-execução

### Problema 2 — Painel mostrando "sem registro hoje" / "sem dados"
Após mudar o script para "39 LOJAS", o painel continuava buscando "38 LOJAS" no log
e nunca encontrava o bloco do ciclo — timing e totais ficavam em branco.

### Fix (`gerar-painel-datasync.ps1`)
- Regex alterada de `'SINCRONIZANDO 38 LOJAS'` para `'SINCRONIZANDO \d+ LOJAS'`

---

## [2026-05-29] - Agente Clebson no cabeçalho do painel

### Alteração (`gerar-painel-datasync.ps1`)
- Adicionada linha "Agente: **Clebson**" abaixo do título no cabeçalho do painel

---

## [2026-05-29] - Servidor HTTP do painel restaurado

### Problema
Painel inacessível pela rede. Tarefa `DataSyncHTTP` havia parado em 19/05 com erro.
`HttpListener` não subia porque a URL ACL `http://+:8080/` não estava registrada.

### Fix
- Registrado `netsh http add urlacl url=http://+:8080/` com SDDL universal
- Tarefa `DataSyncHTTP` reiniciada — painel acessível em `http://192.168.0.147:8080/painel.html`

---

## [2026-05-26] - E-COMMERCE adicionado ao fluxo + fix painel

### Alterações (`data-sync-automacao.ps1`)
- 39ª loja E-COMMERCE adicionada ao ciclo completo (RECEBE e ENVIA)
- Após o lote numérico, roda E-COMMERCE sequencialmente via mesmo `$jobBlock`
- Contagem atualizada: "39 LOJAS" em todos os logs de resumo

### Alterações (`gerar-painel-datasync.ps1`)
- Regex de leitura de status: `loja_(\d+)\.txt` → `loja_([^.]+)\.txt` (aceita E-COMMERCE)
- Célula E-Commerce adicionada ao grid de progresso do painel

---

## [2026-05-25] - Fix loja 31 + pre-check de log + lojas lentas ENVIA

### Problema — Loja 31 sempre falhava
Dois bugs combinados:
1. Filtro de log com espaço obrigatório após número (`*LOJA 31 *`) não batia com
   `LOJA 31-SHOP` (hífen, não espaço)
2. O Linx para as lojas 31 e 03 demora 4h em background — o atalho encerra em
   segundos, mas o log só fica pronto horas depois. O ciclo das 10:30 sempre falhava,
   mas o das 16:30 encontrava o log já completo.

### Fixes (`data-sync-automacao.ps1`)
- Filtro corrigido: `*LOJA $Loja *` → `*LOJA $Loja*` (sem espaço obrigatório)
- Pre-check adicionado no `$jobBlock`: antes de executar o atalho, verifica se o log
  de hoje já tem linha de sucesso → marca OK direto (resolve lojas com sync longo)
- Lotes de ENVIA separados: lojas lentas (03, 38, 47, 48, 52, 53) com timeout 15 min;
  demais com 8 min
- Batch size aumentado: 5 → 10 lojas por lote
- RECEBE timeout: 2 min → 4 min (cobre delta de segunda-feira ~2:20 min)

---

## Arquitetura atual

| Arquivo | Localização servidor | Função |
|---|---|---|
| `data-sync-automacao.ps1` | `C:\Users\Datasync\Desktop\ti\` | Script principal de sync |
| `gerar-painel-datasync.ps1` | `C:\Users\Datasync\Desktop\ti\` | Gerador do painel HTML (loop 30s) |
| `servidor-painel-http.ps1` | `C:\Users\Datasync\Desktop\ti\` | Servidor HTTP porta 8080 |

### Tarefas agendadas
| Tarefa | Horário | Função |
|---|---|---|
| `DataSync_1030` | 10:30 | Ciclo de sync |
| `DataSync_1430` | 14:30 | Ciclo de sync |
| `DataSync_1630` | 16:30 | Ciclo de sync |
| `DataSyncPainel` | contínuo | Gera painel.html a cada 30s |
| `DataSyncHTTP` | contínuo | Serve painel na porta 8080 |

### Comportamentos conhecidos
- **Lojas 31 e 03:** Linx demora 4h no primeiro sync do dia — pre-check no RECEBE
  detecta o log completo no ciclo das 14:30/16:30 e marca OK sem re-executar
- **Segunda-feira:** delta de 3 dias faz RECEBE demorar ~2:20 min (coberto pelo timeout de 4 min)
- **E-COMMERCE:** log do Linx não tem prefixo "LOJA" no nome — filtro especial aplicado
- **ENVIA:** sempre executa o atalho (sem pre-check) para garantir envio de pedidos novos
