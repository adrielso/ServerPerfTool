#!/bin/bash

# Este script realiza benchmarks de performance para CPU, Memória e I/O de Disco.
# As melhorias incluem: tratamento de interrupções (trap/cleanup), normalização
# das unidades de velocidade (MB/s) para cálculo preciso de média, uso do
# jq para parsing robusto de JSON, se disponível, e coleta de metadados OS/Target.

# --- CORREÇÃO DE LOCALE ---
# FORÇA O PONTO (.) COMO SEPARADOR DECIMAL PARA GARANTIR CÁLCULOS CORRETOS NO AWK E PARA A API.
export LC_NUMERIC="C"

# --- CONFIGURAÇÕES DO SERVIÇO de UPLOAD ---
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

# Variáveis globais para armazenar metadados
CPU_MODEL=""
TOTAL_RAM=""
LOCAL_HOSTNAME=""
OS_INFO=""
SCRIPT_TARGET="Linux" # Variável de filtro para distinguir ambientes (Linux vs. Windows)

# Arrays para armazenar resultados numéricos para cálculo de média
CPU_SINGLE_TIMES=()
CPU_MULTI_TIMES=()
RAM_WRITE_SPEEDS=()
DISK_ROOT_WRITE_SPEEDS=()
DISK_ROOT_READ_SPEEDS=()

# Espaço mínimo necessário para o teste de I/O de disco
# (FILE_SIZE_MB = 1024MB) + 200MB de buffer de segurança.
REQUIRED_SPACE_MB=$((FILE_SIZE_MB + 200))


# --- Função de Limpeza de Emergência (Clean-up) ---
function cleanup() {
    echo ""
    echo "⚠️ SCRIPT INTERROMPIDO. Limpando arquivos temporários..." >&2 # Direciona para stderr
    rm -f /dev/shm/ramtest.tmp
    # Tenta remover o arquivo de teste no diretório atual e no raiz (se for o caso)
    rm -f "${FILE_NAME}"
    if [ -f "/${FILE_NAME}" ]; then
        rm -f "/${FILE_NAME}"
    fi
    # Tenta fechar o descritor de arquivo 3 (usado para logging) se estiver aberto
    exec 3>&- 2>/dev/null
    exit 1
}

# Configura o trap para chamar 'cleanup' em sinais de interrupção, etc.
trap cleanup SIGINT SIGTERM SIGHUP

# --- Funções Auxiliares ---

# Função auxiliar para calcular a média de um array de números de ponto flutuante
function calculate_average() {
    local results=("$@")
    if [ ${#results[@]} -eq 0 ]; then
        echo "0.000"
        return
    fi
    # Usa 'awk' para somar todos os valores e dividir, formatando para três casas decimais.
    # ARGV[1:] pula o nome do script (ARGV[0]) e trata o restante como dados.
    awk "BEGIN { sum = 0; count = 0; for (i=1; i<=ARGC; i++) { sum += ARGV[i]; count++; } printf \"%.3f\", sum / count }" "${results[@]}"
}

# NOVA FUNÇÃO: Junta elementos de um array em uma string separada por vírgula.
# Isso é necessário para gerar os campos RAW_... da API.
function join_array_to_string() {
    local array=("$@")
    # Define o separador interno (IFS) como vírgula APENAS para esta subshell
    local IFS=','
    echo "${array[*]}"
}

# FUNÇÃO ATUALIZADA: Extrai a velocidade de I/O e normaliza para MB/s
function extract_speed_mbps() {
    local speed_output="$1"
    # Awk detecta a unidade (kB/s, MB/s, GB/s, TB/s) e converte tudo para MB/s.
    echo "$speed_output" | awk '
    {
        for(i=1; i<=NF; i++) {
            # Verifica se o campo é uma unidade de velocidade (ex: 'kB/s', 'MB/s')
            if ($i ~ /B\/s/) {
                val = $(i-1);
                unit = $i;

                # Converte para a unidade base MB/s
                if (unit == "kB/s") {
                    printf "%.3f", val / 1024;
                    exit;
                } else if (unit == "MB/s") {
                    printf "%.3f", val;
                    exit;
                } else if (unit == "GB/s") {
                    printf "%.3f", val * 1024;
                    exit;
                } else if (unit == "TB/s") {
                    printf "%.3f", val * 1024 * 1024;
                    exit;
                }
            }
        }
        # Retorna 0.000 se a velocidade não for encontrada/válida
        print "0.000"
    }'
}

# --- Funções de Logging e Tabela ---

# Redireciona toda a saída (stdout e stderr) para o arquivo de log e para a tela
function start_logging() {
    echo "--- ⏱️ Iniciando Testes de Performance Padrão em $(date) ---"
    echo "Log de saída sendo escrito em: $LOG_FILE"
    echo ""
    # Redireciona a saída do script para o log e para a tela
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

# FUNÇÃO ATUALIZADA: Adiciona Hostname, OS e SCRIPT_TARGET
function collect_system_info() {
    echo "### 🖥️ Informações do Sistema Coletadas ###"
    # Popula a variável global LOCAL_HOSTNAME
    LOCAL_HOSTNAME=$(hostname)
    echo "Hostname: $LOCAL_HOSTNAME"
    
    echo ""
    echo "--- Sistema Operacional e Ambiente ---"
    # Popula a variável global SCRIPT_TARGET
    # Usado para que o visualizador possa distinguir entre Linux e Windows (futuro)
    echo "Target Script Environment: $SCRIPT_TARGET" 
    
    # Popula a variável global OS_INFO
    if [ -f /etc/os-release ]; then
        # Extrai o nome amigável (Pretty Name)
        OS_INFO=$(grep PRETTY_NAME /etc/os-release | sed 's/PRETTY_NAME=//g' | tr -d '"' | head -n 1)
    else
        # Fallback para o kernel e versão
        OS_INFO=$(uname -s -r)
    fi
    echo "OS: $OS_INFO"

    echo ""
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

# FUNÇÃO ATUALIZADA: Agora usa a função extract_speed_mbps para garantir precisão
function test_memory() {
    echo "### 💡 Teste de Performance da Memória RAM (Escrita Sequencial) ###"
    
    for i in $(seq 1 $TEST_ROUNDS); do
        echo "--- Teste de Escrita em RAM (Rodada $i de $TEST_ROUNDS) ---"
        echo "Copiando ${FILE_SIZE_MEM_MB}MB para o /dev/shm (diretório em RAM)..."
        
        SPEED_OUTPUT=$(dd if=/dev/zero of=/dev/shm/ramtest.tmp bs=1M count="${FILE_SIZE_MEM_MB}" status=progress 2>&1 | tail -n 1)
        echo "$SPEED_OUTPUT"

        # EXTRAÇÃO ATUALIZADA: Normaliza a velocidade para MB/s
        RAM_SPEED_MBPS=$(extract_speed_mbps "$SPEED_OUTPUT")
        RAM_WRITE_SPEEDS+=("$RAM_SPEED_MBPS")
        
        rm -f /dev/shm/ramtest.tmp
        echo "Arquivo de teste em RAM removido."
        echo ""
    done

    echo "----------------------------------------"
}

# FUNÇÃO CORRIGIDA: Usa grep 'copied' | tail -n 1 para evitar poluição de dados I/O
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
        echo "Testando Escrita (com dsync)..."
        # CORREÇÃO DE DD: Captura APENAS a linha de resumo (onde está a velocidade final)
        WRITE_OUTPUT=$(dd if=/dev/zero of="${test_file}" bs=1M count="${FILE_SIZE_MB}" oflag=dsync 2>&1 | grep 'copied' | tail -n 1)
        echo "$WRITE_OUTPUT"
        
        # EXTRAÇÃO: Normaliza a velocidade para MB/s
        WRITE_SPEED_MBPS=$(extract_speed_mbps "$WRITE_OUTPUT")

        # Armazena apenas se for o disco raiz (/)
        if [ "$mountpoint" = "/" ]; then
            DISK_ROOT_WRITE_SPEEDS+=("$WRITE_SPEED_MBPS")
        fi

        if [ $(id -u) -eq 0 ]; then
            echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || echo "Tentativa de limpar o cache (requer root)..."
            echo "Cache de leitura do sistema limpo."
        fi

        # --- Teste de Leitura ---
        echo "Testando Leitura..."
        # CORREÇÃO DE DD: Captura APENAS a linha de resumo (onde está a velocidade final)
        READ_OUTPUT=$(dd if="${test_file}" of=/dev/null bs=1M count="${FILE_SIZE_MB}" 2>&1 | grep 'copied' | tail -n 1)
        echo "$READ_OUTPUT"

        # EXTRAÇÃO: Normaliza a velocidade para MB/s
        READ_SPEED_MBPS=$(extract_speed_mbps "$READ_OUTPUT")
        
        # Armazena apenas se for o disco raiz (/)
        if [ "$mountpoint" = "/" ]; then
            DISK_ROOT_READ_SPEEDS+=("$READ_SPEED_MBPS")
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
    # --------------------------------------------------
    # Display human-readable averages
    # --------------------------------------------------
    echo ""
    echo "=================================================="
    echo "### 📊 RESULTADOS FINAIS - MÉDIA DE $TEST_ROUNDS RODADAS ###"
    echo "=================================================="

    # CPU
    AVG_CPU_MULTI=$(calculate_average "${CPU_MULTI_TIMES[@]}")
    AVG_CPU_SINGLE=$(calculate_average "${CPU_SINGLE_TIMES[@]}")
    echo "🧠 CPU Média:"
    echo "    Multi-Core: ${AVG_CPU_MULTI} segundos (Tempo Total)"
    echo "    Single-Core: ${AVG_CPU_SINGLE} segundos (Velocidade Pura)"
    echo "--------------------------------------------------"

    # Memória
    AVG_RAM_WRITE=$(calculate_average "${RAM_WRITE_SPEEDS[@]}")
    echo "💡 Memória RAM Média:"
    echo "    Escrita Sequencial: ${AVG_RAM_WRITE} MB/s"
    echo "--------------------------------------------------"

    # Disco (Apenas Root como exemplo de média)
    if [ ${#DISK_ROOT_WRITE_SPEEDS[@]} -gt 0 ]; then
        AVG_DISK_ROOT_WRITE=$(calculate_average "${DISK_ROOT_WRITE_SPEEDS[@]}")
        AVG_DISK_ROOT_READ=$(calculate_average "${DISK_ROOT_READ_SPEEDS[@]}")
        echo "💾 Disco (Ponto de Montagem Raiz '/') Média:"
        echo "    Escrita (Root /): ${AVG_DISK_ROOT_WRITE} MB/s"
        echo "    Leitura (Root /): ${AVG_DISK_ROOT_READ} MB/s"
        echo "--------------------------------------------------"
    else
        echo "💾 Disco: Média do disco raiz '/' não disponível (ponto de montagem não detectado)."
        echo "--------------------------------------------------"
    fi
    echo ""

    # --------------------------------------------------
    # CRIAÇÃO DOS ARRAYS BRUTOS PARA O PARSING DA API
    # --------------------------------------------------
    RAW_CPU_MULTI_TIMES_STR=$(join_array_to_string "${CPU_MULTI_TIMES[@]}")
    RAW_CPU_SINGLE_TIMES_STR=$(join_array_to_string "${CPU_SINGLE_TIMES[@]}")
    RAW_RAM_WRITE_SPEEDS_STR=$(join_array_to_string "${RAM_WRITE_SPEEDS[@]}")

    if [ ${#DISK_ROOT_WRITE_SPEEDS[@]} -gt 0 ]; then
        RAW_DISK_WRITE_SPEEDS_STR=$(join_array_to_string "${DISK_ROOT_WRITE_SPEEDS[@]}")
        RAW_DISK_READ_SPEEDS_STR=$(join_array_to_string "${DISK_ROOT_READ_SPEEDS[@]}")
    else
        # Se os testes de disco falharem, usa o fallback de '0.000'
        RAW_DISK_WRITE_SPEEDS_STR="0.000"
        RAW_DISK_READ_SPEEDS_STR="0.000"
    fi


    # --------------------------------------------------
    # NOVO: Bloco para facilitar o parsing da API
    # --------------------------------------------------
    echo "=================================================="
    echo "### 🤖 MACHINE_READABLE_DATA (Para Parsing de Log) ###"
    
    # Metadados de Sistema
    echo "HOST_NAME: $LOCAL_HOSTNAME"
    echo "OS_INFO: $OS_INFO"
    echo "SCRIPT_TARGET: $SCRIPT_TARGET"
    # Informações de CPU/RAM (Adicionadas para a API)
    echo "CPU_MODEL: $CPU_MODEL"
    echo "RAM_TOTAL: $TOTAL_RAM" # Mantendo RAM_TOTAL no formato humano para a API
    
    # Médias
    echo "CPU_MULTI_AVG_S: ${AVG_CPU_MULTI}"
    echo "CPU_SINGLE_AVG_S: ${AVG_CPU_SINGLE}"
    echo "RAM_WRITE_AVG_MBPS: ${AVG_RAM_WRITE}"

    # Disco (Root)
    echo "DISK_ROOT_WRITE_AVG_MBPS: ${AVG_DISK_ROOT_WRITE}"
    echo "DISK_ROOT_READ_AVG_MBPS: ${AVG_DISK_ROOT_READ}"
    
    # DADOS BRUTOS (ARRAYS): CORRIGIDOS E INCLUÍDOS
    echo "RAW_CPU_MULTI_S: ${RAW_CPU_MULTI_TIMES_STR}"
    echo "RAW_CPU_SINGLE_S: ${RAW_CPU_SINGLE_TIMES_STR}"
    echo "RAW_RAM_WRITE_MBPS: ${RAW_RAM_WRITE_SPEEDS_STR}"
    echo "RAW_DISK_WRITE_MBPS: ${RAW_DISK_WRITE_SPEEDS_STR}"
    echo "RAW_DISK_READ_MBPS: ${RAW_DISK_READ_SPEEDS_STR}"

    echo "=================================================="
    echo ""
}

# FUNÇÃO ATUALIZADA: Usa 'jq' para parsing de JSON robusto, se disponível
function upload_log() {
    # ATUALIZADO: O redirecionamento de log agora é parado ANTES de chamar esta função.
    
    echo ""
    echo "--- 📤 Iniciando Upload Público do Log para API PHP ---"
    echo "Arquivo de log a ser enviado: $LOG_FILE"
    echo "Enviando para: $API_URL"

    # Checa se 'jq' está instalado
    JQ_AVAILABLE=0
    if command -v jq &> /dev/null; then
        JQ_AVAILABLE=1
    fi

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
        
        if [ $JQ_AVAILABLE -eq 1 ]; then
            echo "INFO: Usando 'jq' para parsing de JSON."
            URL_JSON=$(echo "$UPLOAD_RESPONSE" | jq -r '.url_json')
            URL_TXT=$(echo "$UPLOAD_RESPONSE" | jq -r '.url_txt')
            CLEAN_URL_JSON="$URL_JSON"
            CLEAN_URL_TXT="$URL_TXT"
        else
            echo "AVISO: 'jq' não encontrado. Usando método de extração frágil (grep/sed)."
            URL_JSON=$(echo "$UPLOAD_RESPONSE" | grep -o '"url_json":"[^"]*"' | sed 's/"url_json":"//;s/"//')
            URL_TXT=$(echo "$UPLOAD_RESPONSE" | grep -o '"url_txt":"[^"]*"' | sed 's/"url_txt":"//;s/"//')
            CLEAN_URL_JSON=$(echo "$URL_JSON" | sed 's/\\//g')
            CLEAN_URL_TXT=$(echo "$URL_TXT" | sed 's/\\//g')
        fi

        if [ ! -z "$CLEAN_URL_JSON" ]; then
            echo ""
            echo "🔗 LINK PARA DADOS ESTRUTURADOS (JSON): $CLEAN_URL_JSON"
            echo "🔗 LINK PARA LOG BRUTO (TXT): $CLEAN_URL_TXT"
            
            echo ""
            echo "============================================================"
            echo "📊 LINK PARA O DASHBOARD DE VISUALIZAÇÃO:"
            echo "${VIEWER_URL}?json=${CLEAN_URL_JSON}&txt=${CLEAN_URL_TXT}"
            echo "============================================================"
            
        else
            echo "❌ ERRO: Falha ao extrair URLs da resposta da API. Resposta bruta:"
            echo "$UPLOAD_RESPONSE"
        fi
    else
        echo "❌ ERRO: Ocorreu um erro durante a conexão com o servidor."
    fi
    echo "--- Fim do Envio ---"
}

# --- NOVA FUNÇÃO: VERIFICA ESPAÇO LIVRE ---
function check_free_space() {
    # Assume que o teste será feito no ponto de montagem raiz (/) para o I/O de disco.
    local mountpoint="/"

    echo "--- 🔍 Verificando Espaço em Disco Disponível no Mountpoint ${mountpoint} ---"
    
    # Obtém o espaço livre no ponto de montagem (em Megabytes)
    # Coluna 4 (Available) de df -m
    AVAILABLE_SPACE_MB=$(df -m "${mountpoint}" 2>/dev/null | tail -n 1 | awk '{print $4}')

    # Caso o df falhe ou o resultado seja vazio, assume que não há espaço ou o mountpoint não é acessível.
    if [ -z "$AVAILABLE_SPACE_MB" ]; then
        echo "❌ ERRO CRÍTICO: Não foi possível determinar o espaço livre em ${mountpoint}. Abortando."
        return 1
    fi
    
    if [ "$AVAILABLE_SPACE_MB" -lt "$REQUIRED_SPACE_MB" ]; then
        echo "❌ ERRO CRÍTICO: Espaço em disco insuficiente em '${mountpoint}'. A execução foi abortada."
        echo "Espaço necessário para o arquivo de I/O (${FILE_SIZE_MB}MB) + buffer: ${REQUIRED_SPACE_MB}MB"
        echo "Espaço disponível detectado: ${AVAILABLE_SPACE_MB}MB"
        return 1
    fi

    echo "✅ Espaço em disco suficiente (${AVAILABLE_SPACE_MB}MB disponível). Continuando..."
    echo "----------------------------------------------------"
    return 0
}


# --- EXECUÇÃO PRINCIPAL ---

# 1. Abre um novo descritor de arquivo (fd 3) para o stdout original
exec 3>&1

# 🟢 NOVO: VERIFICA ESPAÇO ANTES DE TUDO (MESMO ANTES DO LOGGING)
if ! check_free_space; then
    cleanup # Limpa arquivos temporários (se houver, mas não deve haver) e sai
fi

# 2. Inicia o logging (redireciona stdout e stderr para o log e tela)
start_logging

# 3. Execução dos Testes
print_performance_table
collect_system_info
test_cpu_heavy
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

# Pequeno 'sleep' para garantir que o buffer do 'tee' seja impresso ANTES do prompt.
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
    upload_log
else
    echo "Upload cancelado pelo usuário."
    echo "Seu log completo está salvo localmente em: $LOG_FILE"
fi

# 7. Fecha o descritor de arquivo
exec 3>&-

# Remove o trap para evitar chamadas de cleanup desnecessárias após a execução normal
trap - SIGINT SIGTERM SIGHUP