# =====================================================================
# lojas-config.ps1 — Configuração de conexão do Verificador de Tickets
# Gerado a partir do RegSrvr.xml do SSMS (Registered Servers).
# NÃO comitar senha aqui. A senha do 'sa' é lida de um arquivo protegido.
# =====================================================================

# --- Credenciais (sa) ------------------------------------------------
# As 38 LOJAS compartilham a MESMA senha do sa.
# A RETAGUARDA (Dorinhos) tem uma senha DIFERENTE.
# Ambas guardadas protegidas por DPAPI (só o seu usuário lê).
# Ver guardar-senha-sql.ps1.
$SqlUser = "sa"
$SqlCredFile           = "C:\Users\Daniella\ti\.sql_cred"            # senha das lojas
$SqlCredFileRetaguarda = "C:\Users\Daniella\ti\.sql_cred_retaguarda" # senha da retaguarda

# --- Bancos (confirmar nomes reais) ----------------------------------
# Nome do banco Linx em CADA loja (SQL Express local). Costuma ser igual
# em todas. Confirmar com: SELECT name FROM sys.databases;
$BancoLoja = "<BANCO_LINX_LOJA>"          # ex.: LinxPOS / Linx / etc.
# Nome do banco consolidado na retaguarda (Dorinhos / 192.168.0.55):
$BancoRetaguarda = "<BANCO_RETAGUARDA>"   # confirmar no SSMS

# --- Coluna que identifica a loja na tabela de tickets da retaguarda --
$ColunaLojaRetaguarda = "<coluna_loja>"   # ex.: loja_id / numero_loja

# --- Retaguarda / Matriz ---------------------------------------------
$Retaguarda = @{ Numero="RETAGUARDA"; Servidor="192.168.0.55"; Banco=$BancoRetaguarda }

# --- 38 lojas: Numero -> Servidor SQL (IP\instância) -----------------
$Lojas = @(
    @{ Numero=3;  Servidor="192.168.11.100\sqlexpress" },
    @{ Numero=4;  Servidor="192.168.47.100\sqlexpress" },
    @{ Numero=5;  Servidor="192.168.12.101\sqlexpress" },
    @{ Numero=6;  Servidor="192.168.13.100\sqlexpress" },
    @{ Numero=7;  Servidor="192.168.14.101\sqlexpress" },
    @{ Numero=9;  Servidor="192.168.4.101\sqlexpress"  },
    @{ Numero=14; Servidor="192.168.18.101\sqlexpress" },
    @{ Numero=16; Servidor="192.168.20.100\sqlexpress" },
    @{ Numero=17; Servidor="192.168.21.101\sqlexpress" },
    @{ Numero=21; Servidor="192.168.25.100\sqlexpress" },
    @{ Numero=23; Servidor="192.168.27.101\sqlexpress" },
    @{ Numero=26; Servidor="192.168.30.100\sqlexpress" },
    @{ Numero=28; Servidor="192.168.31.101\sqlexpress" },
    @{ Numero=29; Servidor="192.168.32.100\sqlexpress" },
    @{ Numero=31; Servidor="192.168.6.100\sqlexpress"  },
    @{ Numero=32; Servidor="192.168.34.101\sqlexpress" },
    @{ Numero=33; Servidor="192.168.35.101\sqlexpress" },
    @{ Numero=34; Servidor="192.168.36.101\sqlexpress" },
    @{ Numero=36; Servidor="192.168.37.100\sqlexpress" },
    @{ Numero=37; Servidor="192.168.38.100\sqlexpress" },
    @{ Numero=38; Servidor="192.168.39.100\sqlexpress" },
    @{ Numero=40; Servidor="192.168.41.100\sqlexpress" },
    @{ Numero=41; Servidor="192.168.42.100\sqlexpress" },
    @{ Numero=42; Servidor="192.168.43.100\sqlexpress" },
    @{ Numero=44; Servidor="192.168.45.101\sqlexpress" },
    @{ Numero=45; Servidor="192.168.46.101\sqlexpress" },
    @{ Numero=46; Servidor="192.168.8.100\sqlexpress"  },
    @{ Numero=47; Servidor="192.168.48.100\sqlexpress" },
    @{ Numero=48; Servidor="192.168.44.100\sqlexpress" },
    @{ Numero=49; Servidor="192.168.40.100\sqlexpress" },
    @{ Numero=50; Servidor="192.168.3.100\sqlexpress"  },
    @{ Numero=51; Servidor="192.168.9.100\sqlexpress"  },
    @{ Numero=52; Servidor="192.168.10.101\sqlexpress" },
    @{ Numero=53; Servidor="192.168.19.100\sqlexpress" },
    @{ Numero=54; Servidor="192.168.15.101\sqlexpress" },
    @{ Numero=55; Servidor="192.168.49.100\sqlexpress" },
    @{ Numero=56; Servidor="192.168.5.100\sqlexpress"  },
    @{ Numero=57; Servidor="192.168.57.100\sqlexpress" }
)

# Total: 38 lojas. Fonte: RegSrvr.xml (SSMS Registered Servers), 2026-07-02.
