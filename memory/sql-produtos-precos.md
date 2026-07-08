---
name: sql-produtos-precos-queries
description: Queries otimizadas para a tabela PRODUTOS_PRECOS (SQL Server)
metadata:
  type: reference
---

# PRODUTOS_PRECOS - Queries Otimizadas

## Estrutura
- **Tabela**: PRODUTOS_PRECOS
- **Chave primária**: PRODUTO + CODIGO_TAB_PRECO
- **Colunas principais**: CODIGO_TAB_PRECO, PRODUTO, PRECO1, PRECO_LIQUIDO1, ULT_ATUALIZACAO

---

## SELECT - Buscar preços de um produto

```sql
SELECT 
    CODIGO_TAB_PRECO,
    PRODUTO,
    PRECO1,
    PRECO_LIQUIDO1,
    ULT_ATUALIZACAO
FROM PRODUTOS_PRECOS
WHERE PRODUTO = '17.01.50'
ORDER BY CODIGO_TAB_PRECO;
```

**Uso**: Listar todos os preços de um produto em diferentes tabelas de preço.

---

## INSERT - Adicionar múltiplos preços (mesmo produto, códigos diferentes)

```sql
INSERT INTO PRODUTOS_PRECOS (CODIGO_TAB_PRECO, PRODUTO, PRECO1)
VALUES 
    ('32', '17.01.50', 68.74),
    ('02', '17.01.50', 77.66),
    ('31', '17.01.50', 95.01);
```

**Uso**: Inserir 3+ preços em uma operação (mais rápido que INSERTs separados).

---

## UPDATE - Alterar preço para produto + código específico

```sql
UPDATE PRODUTOS_PRECOS 
SET PRECO1 = 166.38,
    ULT_ATUALIZACAO = GETDATE()
WHERE PRODUTO = '17.01.50' 
  AND CODIGO_TAB_PRECO = '32';
```

**Uso**: Atualizar preço de UMA tabela de preço específica.

---

## UPDATE - Atualizar PRECO_LIQUIDO1 para todos os códigos de um produto

```sql
UPDATE PRODUTOS_PRECOS 
SET PRECO_LIQUIDO1 = PRECO1,
    ULT_ATUALIZACAO = GETDATE()
WHERE PRODUTO = '17.01.50';
```

**Uso**: Sincronizar preço líquido = preço1 para TODOS os códigos de um produto.

---

## UPDATE com variáveis (reutilizável)

```sql
DECLARE @PRODUTO VARCHAR(10) = '17.01.50';
DECLARE @CODIGO_TABELA VARCHAR(5) = '32';
DECLARE @NOVO_PRECO DECIMAL(10, 2) = 166.38;

UPDATE PRODUTOS_PRECOS 
SET PRECO1 = @NOVO_PRECO,
    ULT_ATUALIZACAO = GETDATE()
WHERE PRODUTO = @PRODUTO 
  AND CODIGO_TAB_PRECO = @CODIGO_TABELA;
```

**Uso**: Template reutilizável. Mude só os valores das variáveis.

---

## ⚠️ Erros Comuns

| Erro | Causa | Solução |
|------|-------|---------|
| `SELECT *` | Carrega colunas desnecessárias | Especificar colunas |
| `PRODUTO = ''` | String vazia não encontra nada | Usar `IS NOT NULL` |
| `PRECO1 = '166.38'` | String em vez de número | Remover aspas: `166.38` |
| `@NOVO_PRECO not declared` | Faltou DECLARE | Rodar DECLARE + UPDATE juntos |
| UPDATE sem WHERE específico | Afeta muitos registros | Sempre incluir PRODUTO + CODIGO_TAB_PRECO |

---

## Best Practices
- ✅ Sempre incluir `PRODUTO` + `CODIGO_TAB_PRECO` no WHERE
- ✅ Usar números sem aspas (66.38, não '66.38')
- ✅ Incluir `ULT_ATUALIZACAO = GETDATE()` em UPDATEs
- ✅ INSERTs múltiplos em uma operação (VALUES (...), (...), (...))
- ✅ Rodar DECLARE + UPDATE juntos (não separados)
