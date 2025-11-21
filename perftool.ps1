# Este script realiza benchmarks de performance para CPU, Memória e I/O de Disco.
# É uma versão nativa para Windows (PowerShell) que não requer programas de terceiros.

# --- CONFIGURAÇÕES DO SERVIÇO de UPLOAD ---
$API_URL = "https://adrielso.tec.br/perf/upload_api"
$VIEWER_URL = "https://adrielso.tec.br/perf/view"

# --- Variáveis e Configurações de Teste ---
# Número de repetições para cada teste (para média)
$TEST_ROUNDS = 3

# Teste de Disco
$FILE_SIZE_MB = 1024 # Tamanho do arquivo de teste em MB
$FILE_NAME = "testfile_${FILE_SIZE_MB}MB"

# Teste de CPU
$ITERATIONS = 6000000 # Valor ajustado para garantir um tempo de execução razoável no Windows
$CPU_CORES = [Environment]::ProcessorCount

# Teste de Memória (RAM)
$FILE_SIZE_MEM_MB = 512

# Arquivo de Log (criado dinamicamente para garantir unicidade)
$LOG_FILE = "performance_log_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Variáveis globais para armazenar metadados
$LOCAL_HOSTNAME = $env:COMPUTERNAME
$OS_INFO = ""
$SCRIPT_TARGET = "Windows (PowerShell)" 
$CPU_MODEL = ""
$TOTAL_RAM_HUMAN = ""
$TOTAL_RAM_MB = 0

# Arrays para armazenar resultados numéricos para cálculo de média
$CPU_SINGLE_TIMES = @()
$CPU_MULTI_TIMES = @()
$RAM_WRITE_SPEEDS = @()
$DISK_ROOT_WRITE_SPEEDS = @()
$DISK_ROOT_READ_SPEEDS = @()

# --- Função de Limpeza (Clean-up) ---
# Garante que arquivos temporários sejam removidos.
function Cleanup {
    Write-Host "`n⚠️ SCRIPT INTERROMPIDO. Limpando arquivos temporários..." -ForegroundColor Yellow
    Remove-Item (Join-Path $env:TEMP "ramtest.tmp") -ErrorAction SilentlyContinue
    Remove-Item $FILE_NAME -ErrorAction SilentlyContinue
    # Remove o arquivo de teste, se existir no diretório atual
    if (Test-Path $FILE_NAME) { Remove-Item $FILE_NAME -Force -ErrorAction SilentlyContinue }
    
    # Sai com erro (opcional, dependendo do sinal de interrupção)
    exit 1
}

# Configura a limpeza para interrupção de script no PowerShell
trap { Cleanup; exit 1 } SIGHUP, SIGINT, SIGTERM, EXIT
# NOTE: Em PowerShell interativo, Ctrl+C pode não ser capturado pelo trap.

# --- Funções Auxiliares ---

# Função auxiliar para calcular a média de um array de números de ponto flutuante
function Calculate-Average {
    param([Parameter(Mandatory=$true)]$Results)

    if ($Results.Count -eq 0) {
        return "0.000"
    }
    
    # Soma todos os resultados e divide pela contagem. Formata para três casas decimais.
    $Sum = ($Results | Measure-Object -Sum).Sum
    $Average = $Sum / $Results.Count
    return "{0:N3}" -f $Average
}

# --- Funções de Logging e Tabela ---

# Redireciona toda a saída para o arquivo de log e para a tela
function Start-Logging {
    "--- ⏱️ Iniciando Testes de Performance Padrão em $(Get-Date) ---" | Tee-Object -FilePath $LOG_FILE -Append
    "Log de saída sendo escrito em: $LOG_FILE" | Tee-Object -FilePath $LOG_FILE -Append
    "" | Tee-Object -FilePath $LOG_FILE -Append
}

function Print-PerformanceTable {
    @("### 📊 Tabela de Referência de Performance (Aproximada) ###",
      "| Componente | OK (Ótimo) | Razoável | Ruim |",
      "| :--- | :--- | :--- | :--- |",
      "| **CPU (Multi-Core)** | Tempo Baixo (rápido, em segundos) | Tempo Médio | Tempo Alto (lento) |",
      "| **Memória (Escrita)** | > 5,000 MB/s | 2,000 - 5,000 MB/s | < 2,000 MB/s |",
      "| **Disco SSD (Escrita/Leitura)** | > 500 MB/s | 200 - 500 MB/s | < 200 MB/s |",
      "| **Disco HDD (Escrita/Leitura)** | > 100 MB/s | 50 - 100 MB/s | < 50 MB/s |",
      "",
      "OBS: O tempo 'bom' da CPU depende do modelo do processador. O foco é a comparação entre diferentes testes.",
      "----------------------------------------"
    ) | Tee-Object -FilePath $LOG_FILE -Append
}

# --- Funções de Teste ---

function Collect-SystemInfo {
    "### 🖥️ Informações do Sistema Coletadas ###" | Tee-Object -FilePath $LOG_FILE -Append
    "Hostname: $LOCAL_HOSTNAME" | Tee-Object -FilePath $LOG_FILE -Append
    
    "" | Tee-Object -FilePath $LOG_FILE -Append
    "--- Sistema Operacional e Ambiente ---" | Tee-Object -FilePath $LOG_FILE -Append
    "Target Script Environment: $SCRIPT_TARGET" | Tee-Object -FilePath $LOG_FILE -Append
    
    # Coleta informações detalhadas do OS
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $OS_INFO = $os.Caption
    "OS: $OS_INFO" | Tee-Object -FilePath $LOG_FILE -Append

    "" | Tee-Object -FilePath $LOG_FILE -Append
    "--- CPU ---" | Tee-Object -FilePath $LOG_FILE -Append
    # Coleta informações da CPU
    $cpu = Get-CimInstance -ClassName Win32_Processor
    $CPU_MODEL = $cpu.Name[0].Trim()
    "Modelo da CPU: $CPU_MODEL" | Tee-Object -FilePath $LOG_FILE -Append
    "Cores/Threads: $CPU_CORES" | Tee-Object -FilePath $LOG_FILE -Append

    "" | Tee-Object -FilePath $LOG_FILE -Append
    "--- Memória (RAM) ---" | Tee-Object -FilePath $LOG_FILE -Append
    # Coleta informações de memória
    $ram_total_bytes = (Get-CimInstance -ClassName Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum
    $TOTAL_RAM_HUMAN = "{0:N2} GB" -f ($ram_total_bytes / 1GB)
    $TOTAL_RAM_MB = [Math]::Floor($ram_total_bytes / 1MB)
    
    "RAM Total: $TOTAL_RAM_HUMAN" | Tee-Object -FilePath $LOG_FILE -Append
    "RAM Total (MB): $TOTAL_RAM_MB (Para Parsing da API)" | Tee-Object -FilePath $LOG_FILE -Append

    "" | Tee-Object -FilePath $LOG_FILE -Append
    "--- Discos e Pontos de Montagem (Fixed Drives) ---" | Tee-Object -FilePath $LOG_FILE -Append
    Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 } | ForEach-Object {
        $drive_size = "{0:N2} GB" -f ($_.Size / 1GB)
        "• DISCO: $($_.DeviceID) - Tamanho: $drive_size" | Tee-Object -FilePath $LOG_FILE -Append
    }
    
    "----------------------------------------" | Tee-Object -FilePath $LOG_FILE -Append
}

function Test-CPUHeavy {
    "### 🧠 Teste de Performance da CPU (Intensivo) ###" | Tee-Object -FilePath $LOG_FILE -Append
    "Processadores (Threads) detectados: $CPU_CORES" | Tee-Object -FilePath $LOG_FILE -Append
    "Executando $ITERATIONS iterações de cálculo matemático por thread." | Tee-Object -FilePath $LOG_FILE -Append
    
    # Define a carga de trabalho pesada (cálculo iterativo)
    $heavy_workload = @'
        param($Iterations)
        $a = 1.0;
        for ($i = 0; $i -lt $Iterations; $i++) {
            $a = [Math]::Sqrt(($a * $i) % 99999 + 1)
        }
        # Retorna o valor de tempo (apenas o resultado do cálculo não é usado)
        return $a 
'@

    foreach ($i in 1..$TEST_ROUNDS) {
        # --- Teste Multi-Core ---
        "--- Teste Multi-Core (Rodada $i de $TEST_ROUNDS) ---" | Tee-Object -FilePath $LOG_FILE -Append
        
        $Jobs = @()
        $TotalTimeMulti = Measure-Command {
            # Inicia um job para cada core
            for ($j = 1; $j -le $CPU_CORES; $j++) {
                $Jobs += Start-Job -ScriptBlock {
                    param($workload, $iterations)
                    Invoke-Expression $workload -ArgumentList $iterations | Out-Null
                } -ArgumentList $heavy_workload, $ITERATIONS
            }
            
            # Espera por todos os jobs e os remove
            $Jobs | Wait-Job | Receive-Job | Remove-Job
            
        } 
        
        $TIME_MULTI_RAW = $TotalTimeMulti.TotalSeconds
        "{0:N3} segundos" -f $TIME_MULTI_RAW | Tee-Object -FilePath $LOG_FILE -Append
        
        $CPU_MULTI_TIMES += $TIME_MULTI_RAW

        "" | Tee-Object -FilePath $LOG_FILE -Append
        "--- Teste Single-Core (Rodada $i de $TEST_ROUNDS) ---" | Tee-Object -FilePath $LOG_FILE -Append
        
        $TotalTimeSingle = Measure-Command {
            Invoke-Expression $heavy_workload -ArgumentList $ITERATIONS | Out-Null
        }
        
        $TIME_SINGLE_RAW = $TotalTimeSingle.TotalSeconds
        "{0:N3} segundos" -f $TIME_SINGLE_RAW | Tee-Object -FilePath $LOG_FILE -Append
        
        $CPU_SINGLE_TIMES += $TIME_SINGLE_RAW
        "" | Tee-Object -FilePath $LOG_FILE -Append
    }
    
    "----------------------------------------" | Tee-Object -FilePath $LOG_FILE -Append
}

function Test-Memory {
    "### 💡 Teste de Performance da Memória RAM (Escrita Sequencial) ###" | Tee-Object -FilePath $LOG_FILE -Append
    $TestPath = Join-Path $env:TEMP "ramtest.tmp"
    
    foreach ($i in 1..$TEST_ROUNDS) {
        "--- Teste de Escrita em RAM (Rodada $i de $TEST_ROUNDS) ---" | Tee-Object -FilePath $LOG_FILE -Append
        "Escrevendo ${FILE_SIZE_MEM_MB}MB no diretório temporário (%TEMP%)..." | Tee-Object -FilePath $LOG_FILE -Append

        # Cria um array de bytes para representar o conteúdo
        $BytesToWrite = New-Object byte[] ($FILE_SIZE_MEM_MB * 1MB)
        
        $TimeWrite = Measure-Command {
            # O cmdlet Set-Content (ou Out-File) é mais rápido, mas a escrita de bytes é mais fiel ao dd
            [System.IO.File]::WriteAllBytes($TestPath, $BytesToWrite)
        }
        
        $TimeSeconds = $TimeWrite.TotalSeconds
        if ($TimeSeconds -gt 0) {
            $SpeedMBPS = $FILE_SIZE_MEM_MB / $TimeSeconds
        } else {
            $SpeedMBPS = 0
        }
        
        $RAM_WRITE_SPEEDS += $SpeedMBPS
        
        $Output = "Copiado $FILE_SIZE_MEM_MB MB em $TimeSeconds segundos, $("{0:N3}" -f $SpeedMBPS) MB/s."
        $Output | Tee-Object -FilePath $LOG_FILE -Append

        Remove-Item $TestPath -ErrorAction SilentlyContinue
        "Arquivo de teste em RAM removido." | Tee-Object -FilePath $LOG_FILE -Append
        "" | Tee-Object -FilePath $LOG_FILE -Append
    }

    "----------------------------------------" | Tee-Object -FilePath $LOG_FILE -Append
}

function Run-IOTest {
    param([string]$Mountpoint)
    $TestFile = Join-Path $Mountpoint $FILE_NAME

    if (-not (Test-Path $Mountpoint -PathType Container)) {
        "AVISO: O ponto de montagem '$Mountpoint' não é um diretório válido. Pulando o teste." | Tee-Object -FilePath $LOG_FILE -Append
        return
    }

    "--- Testando I/O no Ponto de Montagem: ${Mountpoint} ---" | Tee-Object -FilePath $LOG_FILE -Append
    
    foreach ($i in 1..$TEST_ROUNDS) {
        "-- Rodada $i de $TEST_ROUNDS --" | Tee-Object -FilePath $LOG_FILE -Append
        
        # --- Teste de Escrita ---
        "Testando Escrita..." | Tee-Object -FilePath $LOG_FILE -Append
        
        # Cria um array de bytes para o conteúdo (simulação do /dev/zero)
        $BytesToWrite = New-Object byte[] ($FILE_SIZE_MB * 1MB)
        
        $TimeWrite = Measure-Command {
            # Set-Content com Forcing write-through (similar a dsync) não é trivial. 
            # WriteAllBytes é o método mais direto e rápido em PowerShell.
            [System.IO.File]::WriteAllBytes($TestFile, $BytesToWrite)
        }
        
        $TimeSecondsWrite = $TimeWrite.TotalSeconds
        $SpeedWriteMBPS = if ($TimeSecondsWrite -gt 0) { $FILE_SIZE_MB / $TimeSecondsWrite } else { 0.0 }
        
        $OutputWrite = "Escrita concluída em $TimeSecondsWrite segundos, $("{0:N3}" -f $SpeedWriteMBPS) MB/s."
        $OutputWrite | Tee-Object -FilePath $LOG_FILE -Append

        if ($Mountpoint -eq "C:") { $DISK_ROOT_WRITE_SPEEDS += $SpeedWriteMBPS }

        # Limpa o cache de leitura do sistema (Windows não tem um comando simples como 'drop_caches')
        # Apenas registra o aviso.
        "AVISO: A limpeza de cache de leitura do sistema não é trivialmente suportada no PowerShell." | Tee-Object -FilePath $LOG_FILE -Append
        
        # --- Teste de Leitura ---
        "Testando Leitura..." | Tee-Object -FilePath $LOG_FILE -Append
        
        $TimeRead = Measure-Command {
            # Simula a leitura para /dev/null
            [System.IO.File]::ReadAllBytes($TestFile) | Out-Null
        }
        
        $TimeSecondsRead = $TimeRead.TotalSeconds
        $SpeedReadMBPS = if ($TimeSecondsRead -gt 0) { $FILE_SIZE_MB / $TimeSecondsRead } else { 0.0 }
        
        $OutputRead = "Leitura concluída em $TimeSecondsRead segundos, $("{0:N3}" -f $SpeedReadMBPS) MB/s."
        $OutputRead | Tee-Object -FilePath $LOG_FILE -Append

        if ($Mountpoint -eq "C:") { $DISK_ROOT_READ_SPEEDS += $SpeedReadMBPS }

        Remove-Item $TestFile -ErrorAction SilentlyContinue
        "Arquivo de teste removido." | Tee-Object -FilePath $LOG_FILE -Append
        "" | Tee-Object -FilePath $LOG_FILE -Append
    }
}

function Test-AllDiskIO {
    "### 💾 Teste de Performance de I/O de Disco (${FILE_SIZE_MB}MB) em Múltiplos Discos ($TEST_ROUNDS Rodadas) ###" | Tee-Object -FilePath $LOG_FILE -Append
    
    # Filtra apenas discos locais fixos (DriveType 3)
    $Mountpoints = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 } | Select-Object -ExpandProperty DeviceID
    
    if (-not $Mountpoints) {
        "ERRO: Não foi possível detectar pontos de montagem válidos. Usando $env:TEMP como fallback." | Tee-Object -FilePath $LOG_FILE -Append
        $Mountpoints = @($env:TEMP) # Usa o diretório temporário
    }

    foreach ($mp in $Mountpoints) {
        Run-IOTest $mp
    }
    
    "----------------------------------------" | Tee-Object -FilePath $LOG_FILE -Append
}

function Calculate-AndDisplayAverages {
    # --------------------------------------------------
    # Display human-readable averages
    # --------------------------------------------------
    "" | Tee-Object -FilePath $LOG_FILE -Append
    "==================================================" | Tee-Object -FilePath $LOG_FILE -Append
    "### 📊 RESULTADOS FINAIS - MÉDIA DE $TEST_ROUNDS RODADAS ###" | Tee-Object -FilePath $LOG_FILE -Append
    "==================================================" | Tee-Object -FilePath $LOG_FILE -Append

    # CPU
    $AVG_CPU_MULTI = Calculate-Average $CPU_MULTI_TIMES
    $AVG_CPU_SINGLE = Calculate-Average $CPU_SINGLE_TIMES
    "🧠 CPU Média:" | Tee-Object -FilePath $LOG_FILE -Append
    "    Multi-Core: ${AVG_CPU_MULTI} segundos (Tempo Total)" | Tee-Object -FilePath $LOG_FILE -Append
    "    Single-Core: ${AVG_CPU_SINGLE} segundos (Velocidade Pura)" | Tee-Object -FilePath $LOG_FILE -Append
    "--------------------------------------------------" | Tee-Object -FilePath $LOG_FILE -Append

    # Memória
    $AVG_RAM_WRITE = Calculate-Average $RAM_WRITE_SPEEDS
    "💡 Memória RAM Média:" | Tee-Object -FilePath $LOG_FILE -Append
    "    Escrita Sequencial: ${AVG_RAM_WRITE} MB/s" | Tee-Object -FilePath $LOG_FILE -Append
    "--------------------------------------------------" | Tee-Object -FilePath $LOG_FILE -Append

    # Disco (Apenas C: como exemplo de média)
    if ($DISK_ROOT_WRITE_SPEEDS.Count -gt 0) {
        $AVG_DISK_ROOT_WRITE = Calculate-Average $DISK_ROOT_WRITE_SPEEDS
        $AVG_DISK_ROOT_READ = Calculate-Average $DISK_ROOT_READ_SPEEDS
        "💾 Disco (Ponto de Montagem Raiz 'C:') Média:" | Tee-Object -FilePath $LOG_FILE -Append
        "    Escrita (Root C:): ${AVG_DISK_ROOT_WRITE} MB/s" | Tee-Object -FilePath $LOG_FILE -Append
        "    Leitura (Root C:): ${AVG_DISK_ROOT_READ} MB/s" | Tee-Object -FilePath $LOG_FILE -Append
        "--------------------------------------------------" | Tee-Object -FilePath $LOG_FILE -Append
    } else {
        "💾 Disco: Média do disco raiz 'C:' não disponível (ponto de montagem não detectado)." | Tee-Object -FilePath $LOG_FILE -Append
        "--------------------------------------------------" | Tee-Object -FilePath $LOG_FILE -Append
    }
    "" | Tee-Object -FilePath $LOG_FILE -Append

    # --------------------------------------------------
    # Bloco para facilitar o parsing da API
    # --------------------------------------------------
    "==================================================" | Tee-Object -FilePath $LOG_FILE -Append
    "### 🤖 MACHINE_READABLE_DATA (Para Parsing de Log) ###" | Tee-Object -FilePath $LOG_FILE -Append
    
    # Metadados de Sistema
    "HOST_NAME: $LOCAL_HOSTNAME" | Tee-Object -FilePath $LOG_FILE -Append
    "OS_INFO: $OS_INFO" | Tee-Object -FilePath $LOG_FILE -Append
    "SCRIPT_TARGET: $SCRIPT_TARGET" | Tee-Object -FilePath $LOG_FILE -Append
    "CPU_MODEL: $CPU_MODEL" | Tee-Object -FilePath $LOG_FILE -Append
    "RAM_TOTAL_MB: $TOTAL_RAM_MB" | Tee-Object -FilePath $LOG_FILE -Append

    # CPU
    "CPU_MULTI_AVG_S: ${AVG_CPU_MULTI}" | Tee-Object -FilePath $LOG_FILE -Append
    "CPU_SINGLE_AVG_S: ${AVG_CPU_SINGLE}" | Tee-Object -FilePath $LOG_FILE -Append

    # Memória
    "RAM_WRITE_AVG_MBPS: ${AVG_RAM_WRITE}" | Tee-Object -FilePath $LOG_FILE -Append

    # Disco (Root C:)
    if ($DISK_ROOT_WRITE_SPEEDS.Count -gt 0) {
        "DISK_ROOT_WRITE_AVG_MBPS: ${AVG_DISK_ROOT_WRITE}" | Tee-Object -FilePath $LOG_FILE -Append
        "DISK_ROOT_READ_AVG_MBPS: ${AVG_DISK_ROOT_READ}" | Tee-Object -FilePath $LOG_FILE -Append
    } else {
        "DISK_ROOT_WRITE_AVG_MBPS: 0.000" | Tee-Object -FilePath $LOG_FILE -Append
        "DISK_ROOT_READ_AVG_MBPS: 0.000" | Tee-Object -FilePath $LOG_FILE -Append
    }
    "==================================================" | Tee-Object -FilePath $LOG_FILE -Append
    "" | Tee-Object -FilePath $LOG_FILE -Append
}

function Upload-Log {
    "--- 📤 Iniciando Upload Público do Log para API PHP ---" | Tee-Object -FilePath $LOG_FILE -Append
    "Arquivo de log a ser enviado: $LOG_FILE" | Tee-Object -FilePath $LOG_FILE -Append
    "Enviando para: $API_URL" | Tee-Object -FilePath $LOG_FILE -Append

    # O Invoke-WebRequest é o cmdlet nativo do PowerShell para requisições HTTP
    try {
        # O corpo da requisição deve ser um hash table para ser enviado como form-data
        $LogContent = Get-Content $LOG_FILE -Raw
        $Body = @{
            'log_content' = $LogContent
        }

        # Faz o upload e captura a resposta
        $UploadResponse = Invoke-WebRequest -Uri $API_URL -Method Post -Body $Body -ContentType "application/x-www-form-urlencoded" -TimeoutSec 30
        
        if ($UploadResponse.StatusCode -eq 200) {
            "✅ Upload de log concluído." | Tee-Object -FilePath $LOG_FILE -Append
            
            # Converte a resposta JSON em um objeto PowerShell
            $JsonResponse = $UploadResponse.Content | ConvertFrom-Json
            
            $CLEAN_URL_JSON = $JsonResponse.url_json
            $CLEAN_URL_TXT = $JsonResponse.url_txt

            if (-not [string]::IsNullOrEmpty($CLEAN_URL_JSON)) {
                "" | Tee-Object -FilePath $LOG_FILE -Append
                "🔗 LINK PARA DADOS ESTRUTURADOS (JSON): $CLEAN_URL_JSON" | Tee-Object -FilePath $LOG_FILE -Append
                "🔗 LINK PARA LOG BRUTO (TXT): $CLEAN_URL_TXT" | Tee-Object -FilePath $LOG_FILE -Append
                
                "" | Tee-Object -FilePath $LOG_FILE -Append
                "============================================================" | Tee-Object -FilePath $LOG_FILE -Append
                "📊 LINK PARA O DASHBOARD DE VISUALIZAÇÃO:" | Tee-Object -FilePath $LOG_FILE -Append
                "${VIEWER_URL}?json=${CLEAN_URL_JSON}&txt=${CLEAN_URL_TXT}" | Tee-Object -FilePath $LOG_FILE -Append
                "============================================================" | Tee-Object -FilePath $LOG_FILE -Append
                
            } else {
                "❌ ERRO: Falha ao extrair URLs da resposta da API. Resposta bruta:" | Tee-Object -FilePath $LOG_FILE -Append
                $UploadResponse.Content | Tee-Object -FilePath $LOG_FILE -Append
            }
        } else {
            "❌ ERRO: Ocorreu um erro durante a conexão com o servidor. Status Code: $($UploadResponse.StatusCode)" | Tee-Object -FilePath $LOG_FILE -Append
        }
    }
    catch {
        "❌ ERRO: Falha na requisição. Verifique sua conexão ou a URL da API. Mensagem de erro: $($_.Exception.Message)" | Tee-Object -FilePath $LOG_FILE -Append
    }
    "--- Fim do Envio ---" | Tee-Object -FilePath $LOG_FILE -Append
}


# --- EXECUÇÃO PRINCIPAL ---
# O bloco principal é envolvido em try/finally para garantir que todos os logs sejam gravados antes do upload.
try {
    # 1. Inicia o logging
    Start-Logging

    # 2. Execução dos Testes
    Print-PerformanceTable
    Collect-SystemInfo
    Test-CPUHeavy
    Test-Memory
    Test-AllDiskIO

    # 3. Cálculo e exibição das médias
    Calculate-AndDisplayAverages

    # 4. Mensagem final dentro do log
    "--- ✅ Testes Concluídos em $(Get-Date) ---" | Tee-Object -FilePath $LOG_FILE -Append
    "O log completo do teste foi salvo em: $LOG_FILE" | Tee-Object -FilePath $LOG_FILE -Append
    
}
finally {
    # 5. Bloco de Consentimento (Executado mesmo em caso de erro nos testes)
    
    # Para o logging para garantir que o prompt apareça no console
    # Em PowerShell, o Tee-Object envia para o console automaticamente,
    # então o prompt final só precisa ser direcionado ao host.
    
    Write-Host "`n============================================================"
    Write-Host "⚠️  PERMISSÃO PARA UPLOAD PÚBLICO"
    Write-Host "O log deste teste (arquivo $LOG_FILE) pode ser enviado para $API_URL"
    Write-Host "Isso tornará os resultados publicamente visíveis."
    Write-Host ""
    
    $user_consent = Read-Host "Você deseja enviar este log? (s/n)"

    if ($user_consent -ceq "s") { # -ceq é case-sensitive
        Upload-Log
    } else {
        Write-Host "Upload cancelado pelo usuário."
        Write-Host "Seu log completo está salvo localmente em: $LOG_FILE"
    }
    
    # 6. Remove a limpeza para evitar chamadas desnecessárias (já foi tratada pelo trap e finally)
    trap - SIGHUP, SIGINT, SIGTERM, EXIT
}