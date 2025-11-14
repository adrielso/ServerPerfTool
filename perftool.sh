#!/bin/bash

# --- CORREÇÃO DE LOCALE ---
# FORÇA O PONTO (.) COMO SEPARADOR DECIMAL PARA GARANTIR CÁLCULOS CORRETOS NO AWK.
export LC_NUMERIC="C"

# --- CONFIGURAÇÕES DO SERVIÇO DE UPLOAD ---
# ATUALIZADO: URLs agora sem .php (URLs amigáveis)
API_URL="https://adrielso.tec.br/perf/upload_api"
VIEWER_URL="https://adrielso.tec.br/perf/view"

# --- Variáveis e Configurações de Teste ---
# Número de repetições para cada teste (para média)
TEST_ROUNDS=3

# Teste de Disco
FILE_SIZE_MB=1024
FILE_NAME="testfile_${FILE_SIZE_MB}MB"

# Teste de CPU
# Valor ajustado para 600 iterações para garantir um tempo de execução estável e preciso.
ITERATIONS=600 
CPU_CORES=$(nproc)

# Teste de Memória (Memória Compartilhada / RAM)
FILE_SIZE_MEM_MB=512

# Arquivo de Log (criado dinamicamente para garantir unicidade)
LOG_FILE="performance_log_$(date +%Y%m%d_%H%M%S).log"

# Arrays para armazenar resultados numéricos para cálculo de média
CPU_SINGLE_TIMES=()
CPU_MULTI_TIMES=()
RAM_WRITE_SPEEDS=()
DISK_ROOT_WRITE_SPEEDS=()
DISK_ROOT_READ_SPEEDS=()

# Função auxiliar para calcular a média de um array de números de ponto flutuante
function calculate_average() {
    local results=("$@")
    if [ ${#results[@]} -eq 0 ]; then
        echo "0"
        return
    fi
    # Usa 'awk' para somar todos os valores e dividir, formatando para três casas decimais.
    # ARGV[1:] pula o nome do script (ARGV[0]) e trata o restante como dados.
    awk "BEGIN { sum = 0; count = 0; for (i=1; i<=ARGC; i++) { sum += ARGV[i]; count++; } printf \"%.3f\", sum / count }" "${results[@]}"
}

# --- Funções de Logging e Tabela ---

# Redireciona toda a saída (stdout e stderr) para o arquivo de log e para a tela
function start_logging() {
    echo "--- ⏱️ Iniciando Testes de Performance Padrão em $(date) ---"
    echo "Log de saída sendo escrito em: $LOG_FILE"
    echo ""
    # Esta linha redireciona a saída do script para o log e para a tela
    exec > >(tee -a "$LOG_FILE") 2>&1
}

function print_performance_table() {
    echo "### 📊 Tabela de Referência de Performance (Aproximada) ###"
    echo "| Componente | OK (Ótimo) | Razoável | Ruim |"
    echo "| :--- | :--- | :--- | :--- |"
    echo "| **CPU (Multi-Core)** | Tempo Baixo (rápido, em segundos) | Tempo Médio | Tempo Alto (lento) |"
    echo "| **Memória (Escrita)** | > 5,000 MB/s | 2,000 - 5,000 MB/s | < 2,000 MB/s |"
    echo "| **Disco SSD (Escrita/Leitura)** | > 500 MB/s | 200 - 500 MB/s | < 200 MB/s |"
    echo "| **Disco HDD (Escrita/Leitura)** | > 100 MB/s | 50 - 100 MB/s | < 50 MB/s |"
    echo ""
    echo "OBS: O tempo 'bom' da CPU depende do modelo do processador. O foco é a comparação entre diferentes testes."
    echo "----------------------------------------"
}

# --- Funções de Teste ---

function collect_system_info() {
    echo "### 🖥️ Informações do Sistema Coletadas ###"
    # ATUALIZADO: Adicionado Hostname
    LOCAL_HOSTNAME=$(hostname)
    echo "Hostname: $LOCAL_HOSTNAME"
    
    echo "--- CPU ---"
    CPU_MODEL=$(lscpu | grep 'Model name' | sed 's/Model name:[[:space:]]*//' | head -n 1)
    echo "Modelo da CPU: $CPU_MODEL"
    echo "Cores/Threads: $CPU_CORES"

    echo ""
    echo "--- Memória (RAM) ---"
    TOTAL_RAM=$(free -h | grep 'Mem:' | awk '{print $2}')
    echo "RAM Total: $TOTAL_RAM"

    echo ""
    echo "--- Discos e Pontos de Montagem ---"
    lsblk -o NAME,SIZE,TYPE,MODEL,MOUNTPOINT -e7,11 -P | while read -r line; do
        eval $line
        if [ "$TYPE" = "disk" ]; then
            echo "• DISCO: $NAME ($MODEL) - Tamanho: $SIZE"
        elif [ "$TYPE" = "part" ] && [ ! -z "$MOUNTPOINT" ] && [ "$MOUNTPOINT" != "[SWAP]" ]; then
            echo "  └─ Montagem: $MOUNTPOINT - Partição: $NAME"
        fi
    done
    
    echo "----------------------------------------"
}

# Função de teste de CPU intensiva
function test_cpu_heavy() {
    local cpu_count=$CPU_CORES
    echo "### 🧠 Teste de Performance da CPU (Intensivo) ###"
    echo "Processadores (Threads) detectados: $cpu_count"
    echo "Executando $ITERATIONS iterações de hashing e cálculo de primos por thread."
    
    # Usamos o TIMEFORMAT original apenas para a exibição no log.
    TIMEFORMAT="%3R segundos"
    local heavy_workload="
        for (( i = 0; i < $ITERATIONS; i++ )); do
            echo \$i | sha256sum > /dev/null
            a=\$((i * 12345 % 997));
        done
    "
    
    for i in $(seq 1 $TEST_ROUNDS); do
        echo "--- Teste Multi-Core (Rodada $i de $TEST_ROUNDS) ---"
        
        PIDS=()
        # Captura o tempo RAW (%R) para o cálculo da média
        TIME_MULTI_RAW=$( (TIMEFORMAT='%R'; time {
            for j in $(seq 1 $cpu_count); do
                /bin/bash -c "$heavy_workload" &
                PIDS+=($!) 
            done
            wait "${PIDS[@]}"
        }) 2>&1 | grep -oE '[0-9]+\.?[0-9]*' | head -n 1) # Filtra o número RAW
        
        # Imprime o tempo formatado para o log (para o usuário ver)
        echo "$TIME_MULTI_RAW segundos"
        
        # Armazena o tempo RAW (limpo) para o cálculo da média
        CPU_MULTI_TIMES+=("$TIME_MULTI_RAW")

        echo ""
        echo "--- Teste Single-Core (Rodada $i de $TEST_ROUNDS) ---"
        
        TIME_SINGLE_RAW=$( (TIMEFORMAT='%R'; time /bin/bash -c "$heavy_workload") 2>&1 | grep -oE '[0-9]+\.?[0-9]*' | head -n 1)
        
        # Imprime o tempo formatado para o log
        echo "$TIME_SINGLE_RAW segundos"

        # Armazena o tempo RAW (limpo) para o cálculo da média
        CPU_SINGLE_TIMES+=("$TIME_SINGLE_RAW")
        echo ""
    done
    
    echo "----------------------------------------"
}

function test_memory() {
    echo "### 💡 Teste de Performance da Memória RAM (Escrita Sequencial) ###"
    
    for i in $(seq 1 $TEST_ROUNDS); do
        echo "--- Teste de Escrita em RAM (Rodada $i de $TEST_ROUNDS) ---"
        echo "Copiando ${FILE_SIZE_MEM_MB}MB para o /dev/shm (diretório em RAM)..."
        
        SPEED_OUTPUT=$(dd if=/dev/zero of=/dev/shm/ramtest.tmp bs=1M count="${FILE_SIZE_MEM_MB}" status=progress 2>&1 | tail -n 1)
        echo "$SPEED_OUTPUT"

        # Extrai o valor numérico da velocidade (e ignora MB/s ou GB/s)
        RAM_SPEED=$(echo "$SPEED_OUTPUT" | awk '{for(i=1; i<=NF; i++) { if($i ~ /B\/s/) { print $(i-1) } } }')
        RAM_WRITE_SPEEDS+=("$RAM_SPEED")
        
        rm -f /dev/shm/ramtest.tmp
        echo "Arquivo de teste em RAM removido."
        echo ""
    done

    echo "----------------------------------------"
}

function run_io_test() {
    local mountpoint=$1
    local test_file="${mountpoint}/${FILE_NAME}"

    if [ ! -d "$mountpoint" ]; then
        echo "AVISO: O ponto de montagem '$mountpoint' não é um diretório válido. Pulando o teste."
        return
    fi

    echo "--- Testando I/O no Ponto de Montagem: ${mountpoint} ---"
    
    for i in $(seq 1 $TEST_ROUNDS); do
        echo "-- Rodada $i de $TEST_ROUNDS --"
        
        # --- Teste de Escrita ---
        echo "Testando Escrita..."
        WRITE_OUTPUT=$(dd if=/dev/zero of="${test_file}" bs=1M count="${FILE_SIZE_MB}" oflag=dsync status=progress 2>&1 | tail -n 1)
        echo "$WRITE_OUTPUT"
        
        WRITE_SPEED=$(echo "$WRITE_OUTPUT" | awk '{for(i=1; i<=NF; i++) { if($i ~ /B\/s/) { print $(i-1) } } }')

        # Armazena apenas se for o disco raiz (/)
        if [ "$mountpoint" = "/" ]; then
            DISK_ROOT_WRITE_SPEEDS+=("$WRITE_SPEED")
        fi

        if [ $(id -u) -eq 0 ]; then
            echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || echo "Tentativa de limpar o cache (requer root)..."
            echo "Cache de leitura do sistema limpo."
        fi

        # --- Teste de Leitura ---
        echo "Testando Leitura..."
        READ_OUTPUT=$(dd if="${test_file}" of=/dev/null bs=1M count="${FILE_SIZE_MB}" status=progress 2>&1 | tail -n 1)
        echo "$READ_OUTPUT"

        READ_SPEED=$(echo "$READ_OUTPUT" | awk '{for(i=1; i<=NF; i++) { if($i ~ /B\/s/) { print $(i-1) } } }')
        
        # Armazena apenas se for o disco raiz (/)
        if [ "$mountpoint" = "/" ]; then
            DISK_ROOT_READ_SPEEDS+=("$READ_SPEED")
        fi

        rm -f "${test_file}"
        echo "Arquivo de teste removido."
        echo ""
    done
}

function test_all_disk_io() {
    echo "### 💾 Teste de Performance de I/O de Disco (${FILE_SIZE_MB}MB) em Múltiplos Discos ($TEST_ROUNDS Rodadas) ###"
    
    MOUNTPOINTS=$(lsblk -o MOUNTPOINT -n | grep -v 'MOUNTPOINT' | grep -v '\[.*\]' | grep -v '\[SWAP\]' | grep -v '^$' | sort -u)

    if [ -z "$MOUNTPOINTS" ]; then
        echo "ERRO: Não foi possível detectar pontos de montagem válidos. Usando /tmp como fallback."
        MOUNTPOINTS="/tmp"
    fi

    for mp in $MOUNTPOINTS; do
        if df -t ext4 -t xfs -t btrfs -t fat -t ntfs | grep -q "$mp" || [ "$mp" = "/" ] || [ "$mp" = "/tmp" ]; then
            run_io_test "$mp"
        fi
    done
    
    echo "----------------------------------------"
}

function calculate_and_display_averages() {
    echo ""
    echo "=================================================="
    echo "### 📊 RESULTADOS FINAIS - MÉDIA DE $TEST_ROUNDS RODADAS ###"
    echo "=================================================="

    # CPU
    AVG_CPU_MULTI=$(calculate_average "${CPU_MULTI_TIMES[@]}")
    AVG_CPU_SINGLE=$(calculate_average "${CPU_SINGLE_TIMES[@]}")
    echo "🧠 CPU Média:"
    echo "   Multi-Core: ${AVG_CPU_MULTI} segundos (Tempo Total)"
    echo "   Single-Core: ${AVG_CPU_SINGLE} segundos (Velocidade Pura)"
    echo "--------------------------------------------------"

    # Memória
    AVG_RAM_WRITE=$(calculate_average "${RAM_WRITE_SPEEDS[@]}")
    echo "💡 Memória RAM Média:"
    echo "   Escrita Sequencial: ${AVG_RAM_WRITE} MB/s"
    echo "--------------------------------------------------"

    # Disco (Apenas Root como exemplo de média)
    if [ ${#DISK_ROOT_WRITE_SPEEDS[@]} -gt 0 ]; then
        AVG_DISK_ROOT_WRITE=$(calculate_average "${DISK_ROOT_WRITE_SPEEDS[@]}")
        AVG_DISK_ROOT_READ=$(calculate_average "${DISK_ROOT_READ_SPEEDS[@]}")
        echo "💾 Disco (Ponto de Montagem Raiz '/') Média:"
        echo "   Escrita (Root /): ${AVG_DISK_ROOT_WRITE} MB/s"
        echo "   Leitura (Root /): ${AVG_DISK_ROOT_READ} MB/s"
        echo "--------------------------------------------------"
    else
        echo "💾 Disco: Média do disco raiz '/' não disponível (ponto de montagem não detectado)."
        echo "--------------------------------------------------"
    fi
    echo ""
}

# --- Função de Upload ---

function upload_log() {
    # ATUALIZADO: O redirecionamento de log agora é parado ANTES de chamar esta função.
    
    echo ""
    echo "--- 📤 Iniciando Upload Público do Log para API PHP ---"
    echo "Arquivo de log a ser enviado: $LOG_FILE"
    echo "Enviando para: $API_URL"

    # Lê o conteúdo do arquivo
    LOG_CONTENT=$(cat "$LOG_FILE")

    # URL-encode do conteúdo do log usando perl.
    LOG_CONTENT_ENCODED=$(echo -n "$LOG_CONTENT" | perl -pe 's/([^a-zA-Z0-9_.-])/sprintf("%%%02X", ord($1))/ge')

    # Comando CURL para upload com dados no formato POST
    UPLOAD_RESPONSE=$(curl -s -X POST \
        -d "log_content=${LOG_CONTENT_ENCODED}" \
        "$API_URL"
    )

    # 2. Verifica e exibe a resposta da API
    if [ $? -eq 0 ]; then
        echo "✅ Upload de log concluído."
        
        # Busca por 'url_json' e 'url_txt' na nova resposta JSON da API.
        URL_JSON=$(echo "$UPLOAD_RESPONSE" | grep -o '"url_json":"[^"]*"' | sed 's/"url_json":"//;s/"//')
        URL_TXT=$(echo "$UPLOAD_RESPONSE" | grep -o '"url_txt":"[^"]*"' | sed 's/"url_txt":"//;s/"//')

        if [ ! -z "$URL_JSON" ]; then
            # Limpa o URL removendo qualquer barra invertida remanescente
            CLEAN_URL_JSON=$(echo "$URL_JSON" | sed 's/\\//g')
            CLEAN_URL_TXT=$(echo "$URL_TXT" | sed 's/\\//g')

            echo ""
            echo "🔗 LINK PARA DADOS ESTRUTURADOS (JSON): $CLEAN_URL_JSON"
            echo "🔗 LINK PARA LOG BRUTO (TXT): $CLEAN_URL_TXT"
            
            # --- BLOCO ATUALIZADO ---
            echo ""
            echo "============================================================"
            echo "📊 LINK PARA O DASHBOARD DE VISUALIZAÇÃO:"
            echo "${VIEWER_URL}?json=${CLEAN_URL_JSON}&txt=${CLEAN_URL_TXT}"
            echo "============================================================"
            # --- FIM DO BLOCO ATUALIZADO ---
            
        else
            echo "❌ ERRO: Falha ao extrair URLs da resposta da API. Resposta bruta:"
            echo "$UPLOAD_RESPONSE"
        fi
    else
        echo "❌ ERRO: Ocorreu um erro durante a conexão com o servidor."
    fi
    echo "--- Fim do Envio ---"
}


# --- EXECUÇÃO PRINCIPAL ---

# 1. Abre um novo descritor de arquivo (fd 3) para o stdout original
exec 3>&1

# 2. Inicia o logging (redireciona stdout e stderr para o log e tela)
start_logging

# 3. Execução dos Testes
print_performance_table
collect_system_info
test_cpu_heavy # Chamando a função intensiva
test_memory
test_all_disk_io

# 4. Cálculo e exibição das médias
calculate_and_display_averages

# 5. Mensagem final dentro do log
echo "--- ✅ Testes Concluídos em $(date) ---"
echo "O log completo do teste foi salvo em: $LOG_FILE"

# 6. ATUALIZADO: Bloco de Consentimento
# Para o logging (volta ao stdout normal) para fazer a pergunta
exec >&3 2>&1 

# ADICIONADO: Pequeno 'sleep' para garantir que o buffer do 'tee'
# (especialmente a linha "Testes Concluídos") seja impresso ANTES do prompt.
sleep 0.5

echo ""
echo "============================================================"
echo "⚠️  PERMISSÃO PARA UPLOAD PÚBLICO"
echo "O log deste teste (arquivo $LOG_FILE) pode ser enviado para $API_URL"
echo "Isso tornará os resultados publicamente visíveis."
echo ""
echo "Você deseja enviar este log? (s/n)"
read -p "> " user_consent

if [[ "$user_consent" == "s" || "$user_consent" == "S" ]]; then
    # O usuário consentiu.
    upload_log
else
    echo "Upload cancelado pelo usuário."
    echo "Seu log completo está salvo localmente em: $LOG_FILE"
fi


# 7. Fecha o descritor de arquivo
exec 3>&-
