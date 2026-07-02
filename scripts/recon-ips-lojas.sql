/* =====================================================================
   RECON — Confirmar nomes de banco e coluna de loja na retaguarda
   Rode no SSMS conectado em 192.168.0.55 ("Dorinhos", SQL Auth).
   (Os IPs das 38 lojas já foram obtidos do RegSrvr.xml do SSMS.)
   Somente LEITURA — não altera nada.
   Objetivo: descobrir o nome do banco consolidado, o nome do banco Linx
   da loja, e a coluna que identifica a loja na tabela de tickets.
   ===================================================================== */

-- 1) Se você não souber o nome do banco da retaguarda, liste os bancos:
SELECT name AS banco
FROM sys.databases
WHERE database_id > 4          -- ignora master/tempdb/model/msdb
ORDER BY name;

/* --------------------------------------------------------------------
   A PARTIR DAQUI: troque <BANCO_RETAGUARDA> pelo banco correto e rode.
   -------------------------------------------------------------------- */
USE [<BANCO_RETAGUARDA>];

-- 2) Tabelas que parecem cadastro de loja/filial/empresa/unidade:
SELECT s.name AS schema_name, t.name AS tabela
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE t.name LIKE '%loja%'
   OR t.name LIKE '%filial%'
   OR t.name LIKE '%empresa%'
   OR t.name LIKE '%unidade%'
ORDER BY t.name;

-- 3) Colunas em QUALQUER tabela cujo nome sugira IP/host/servidor/endereço
--    (é aqui que o IP de cada loja pode aparecer, se estiver no banco):
SELECT t.name AS tabela, c.name AS coluna, ty.name AS tipo
FROM sys.columns c
JOIN sys.tables t   ON t.object_id = c.object_id
JOIN sys.types  ty  ON ty.user_type_id = c.user_type_id
WHERE c.name LIKE '%ip%'
   OR c.name LIKE '%host%'
   OR c.name LIKE '%servidor%'
   OR c.name LIKE '%server%'
   OR c.name LIKE '%endereco%'
   OR c.name LIKE '%endereço%'
ORDER BY t.name, c.name;

-- 4) Confirmar a coluna que identifica a loja na tabela de tickets (loja_venda):
SELECT c.name AS coluna, ty.name AS tipo
FROM sys.columns c
JOIN sys.tables  t  ON t.object_id = c.object_id
JOIN sys.types   ty ON ty.user_type_id = c.user_type_id
WHERE t.name = 'loja_venda'
  AND (c.name LIKE '%loja%' OR c.name LIKE '%filial%' OR c.name LIKE '%empresa%')
ORDER BY c.name;

/* --------------------------------------------------------------------
   5) Ao identificar a tabela de lojas (passo 2), veja o conteúdo dela.
      Troque <schema>.<tabela_de_loja> pelo nome encontrado:
   -------------------------------------------------------------------- */
-- SELECT TOP 200 * FROM <schema>.<tabela_de_loja>;
