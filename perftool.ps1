# Este script realiza benchmarks de performance para CPU, Memória e I/O de Disco.
# É uma versão nativa para Windows (PowerShell) que não requer programas de terceiros.

# IMPORTANTE: Força a importação da Cultura Invariante para formatação JSON correta.
Add-Type -AssemblyName System.Globalization
[System.Globalization.CultureInfo]::InvariantCulture | Out-Null

# --- CONFIGURAÇÕES DO SERVIÇO de UPLOAD ---
$API_URL = "https://adrielso.tec.br/perf/upload_api"
$VIEWER_URL = "https://adrielso.tec.br/perf/view"

# --- Variáveis e Configurações de Teste ---
# Número de repetições para cada teste (para média)
$TEST_ROUNDS = 3

# Teste de Disco
$FILE_SIZE_MB = 1024 # Tamanho do arquivo de teste em MB
$FILE_NAME = "testfile_${FILE_SIZE_MB}MB"
# Define o tamanho mínimo de espaço livre necessário em bytes (1MB a mais que o arquivo)
$REQUIRED_FREE_SPACE_BYTES = ($FILE_SIZE_MB * 1MB) + 1MB 

# Teste de CPU
$ITERATIONS = 1000000 # Valor ajustado para reduzir o tempo de execução.
$CPU_CORES = [Environment]::ProcessorCount

# Teste de Memória (RAM)
$FILE_SIZE_MEM_MB = 512

# Arquivo de Log (criado dinamicamente para garantir unicidade)
$LOG_FILE = "performance_log_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Variáveis globais para armazenar metadados
$LOCAL_HOSTNAME = $env:COMPUTERNAME
$global:OS_INFO = ""
$global:SCRIPT_TARGET = "Windows (PowerShell)" 
$global:CPU_MODEL = ""
$global:TOTAL_RAM_HUMAN = ""
$global:TOTAL_RAM_MB = 0

# Arrays para armazenar resultados numéricos para cálculo de média
$global:CPU_SINGLE_TIMES = @()
$global:CPU_MULTI_TIMES = @()
$global:RAM_WRITE_SPEEDS = @()
$global:DISK_ROOT_WRITE_SPEEDS = @()
$global:DISK_ROOT_READ_SPEEDS = @()

# --- Função de Limpeza (Clean-up) ---
# Garante que arquivos temporários sejam removidos.
function Cleanup {
    Write-Host "`n⚠️ SCRIPT INTERROMPIDO. Limpando arquivos temporários..." -ForegroundColor Yellow
    
    # Arquivo de teste de RAM (Sempre em TEMP, o que está correto)
    Remove-Item (Join-Path $env:TEMP "ramtest.tmp") -ErrorAction SilentlyContinue
    
    # Arquivo de teste de Disco (Tentativa de remover o arquivo na raiz do C: caso o script falhe na inicialização)
    $TestFileC = Join-Path "C:\" $FILE_NAME
    Remove-Item $TestFileC -ErrorAction SilentlyContinue
    
    # Sai com erro (opcional, dependendo do sinal de interrupção)
    exit 1
}

# Configura a limpeza para interrupção de script no PowerShell
trap { Cleanup; exit 1 }

# --- Funções Auxiliares ---

# FUNÇÃO REVISADA: Agora retorna o valor numérico (double) bruto, sem formatação.
function Calculate-Average {
    param([Parameter(Mandatory=$true)]$Results)

    if ($Results.Count -eq 0) {
        return 0.0
    }
    
    $Sum = ($Results | Measure-Object -Sum).Sum
    $Average = $Sum / $Results.Count
    return $Average
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
    "Target Script Environment: $global:SCRIPT_TARGET" | Tee-Object -FilePath $LOG_FILE -Append
    
    # Coleta informações detalhadas do OS
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $global:OS_INFO = $os.Caption
    "OS: $global:OS_INFO" | Tee-Object -FilePath $LOG_FILE -Append

    "" | Tee-Object -FilePath $LOG_FILE -Append
    "--- CPU ---" | Tee-Object -FilePath $LOG_FILE -Append
    # Seleciona apenas o primeiro processador encontrado para garantir o acesso correto ao Name.
    $cpu = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1
    $global:CPU_MODEL = $cpu.Name.Trim()
    "Modelo da CPU: $global:CPU_MODEL" | Tee-Object -FilePath $LOG_FILE -Append
    "Cores/Threads: $CPU_CORES" | Tee-Object -FilePath $LOG_FILE -Append

    "" | Tee-Object -FilePath $LOG_FILE -Append
    "--- Memória (RAM) ---" | Tee-Object -FilePath $LOG_FILE -Append
    # Coleta informações de memória
    $ram_total_bytes = (Get-CimInstance -ClassName Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum
    $global:TOTAL_RAM_HUMAN = "{0:N2} GB" -f ($ram_total_bytes / 1GB)
    $global:TOTAL_RAM_MB = [Math]::Floor($ram_total_bytes / 1MB)
    
    "RAM Total: $global:TOTAL_RAM_HUMAN" | Tee-Object -FilePath $LOG_FILE -Append
    "RAM Total (MB): $global:TOTAL_RAM_MB (Para Parsing da API)" | Tee-Object -FilePath $LOG_FILE -Append

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
    
    # O cálculo em si (movido para dentro dos blocos de script para evitar o erro ArgumentList)
    $CalculationScriptBlock = {
        param($Iterations)
        $a = 1.0;
        for ($i = 0; $i -lt $Iterations; $i++) {
            # Cálculo pesado de ponto flutuante (floating point)
            $a = [Math]::Sqrt(($a * $i) % 99999 + 1)
        }
        # Retorna o valor de $a, mas o Measure-Command irá descartá-lo para medir apenas o tempo
        return $a 
    }
    
    foreach ($i in 1..$TEST_ROUNDS) {
        # --- Teste Multi-Core ---
        "--- Teste Multi-Core (Rodada $i de $TEST_ROUNDS) ---" | Tee-Object -FilePath $LOG_FILE -Append
        
        $Jobs = @()
        $TotalTimeMulti = Measure-Command {
            # 1. Inicia um job para cada core
            for ($j = 1; $j -le $CPU_CORES; $j++) {
                # Passa o bloco de cálculo original e os argumentos diretamente para Start-Job
                $Jobs += Start-Job -ScriptBlock $CalculationScriptBlock -ArgumentList $ITERATIONS
            }
            
            # 2. Espera que todos os jobs terminem e descarta o output
            $Jobs | Wait-Job | Out-Null
            
            # 3. Coleta e descarta os resultados (necessário para limpar o estado do Job)
            $Jobs | Receive-Job | Out-Null

            # 4. Remove os jobs originais (CORREÇÃO DO ERRO: passa o array $Jobs diretamente para Remove-Job)
            $Jobs | Remove-Job -Force | Out-Null
            
        } 
        
        $TIME_MULTI_RAW = $TotalTimeMulti.TotalSeconds
        "{0:N3} segundos" -f $TIME_MULTI_RAW | Tee-Object -FilePath $LOG_FILE -Append
        
        # Usar $global: para garantir que o array seja populado
        $global:CPU_MULTI_TIMES += $TIME_MULTI_RAW

        "" | Tee-Object -FilePath $LOG_FILE -Append
        "--- Teste Single-Core (Rodada $i de $TEST_ROUNDS) ---" | Tee-Object -FilePath $LOG_FILE -Append
        
        $TotalTimeSingle = Measure-Command {
            # Chama o bloco de script de cálculo diretamente com o operador &
            & $CalculationScriptBlock -Iterations $ITERATIONS | Out-Null
        }
        
        $TIME_SINGLE_RAW = $TotalTimeSingle.TotalSeconds
        "{0:N3} segundos" -f $TIME_SINGLE_RAW | Tee-Object -FilePath $LOG_FILE -Append
        
        # Usar $global: para garantir que o array seja populado
        $global:CPU_SINGLE_TIMES += $TIME_SINGLE_RAW
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
            # O cmdlet Set-Content (ou Out-File) é mais fiel ao dd
            [System.IO.File]::WriteAllBytes($TestPath, $BytesToWrite)
        }
        
        $TimeSeconds = $TimeWrite.TotalSeconds
        if ($TimeSeconds -gt 0) {
            $SpeedMBPS = $FILE_SIZE_MEM_MB / $TimeSeconds
        } else {
            $SpeedMBPS = 0.0
        }
        
        # Usar $global: para garantir que o array seja populado
        $global:RAM_WRITE_SPEEDS += $SpeedMBPS
        
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
    
    $TestDir = $Mountpoint 
    $TestFile = Join-Path $TestDir $FILE_NAME

    # ----------------------------------------------------------------------------------
    # 🟢 NOVO: VERIFICAÇÃO DE ESPAÇO LIVRE ANTES DE EXECUTAR O TESTE
    # ----------------------------------------------------------------------------------
    try {
        # Obtém informações do disco (como espaço livre)
        $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$Mountpoint'"
        $freeSpace = $disk.FreeSpace
        
        if ($freeSpace -lt $REQUIRED_FREE_SPACE_BYTES) {
            $FreeSpaceGB = "{0:N2} GB" -f ($freeSpace / 1GB)
            $RequiredGB = "{0:N2} GB" -f ($REQUIRED_FREE_SPACE_BYTES / 1GB)
            "⚠️ Ponto de Montagem ${Mountpoint}: Espaço livre insuficiente. Necessário ${RequiredGB}, mas disponível ${FreeSpaceGB}. Teste pulado." | Tee-Object -FilePath $LOG_FILE -Append
            return # Sai da função se o espaço for insuficiente
        }
        
    } catch {
        "❌ ERRO ao verificar o espaço livre em ${Mountpoint}. Pulando o teste." | Tee-Object -FilePath $LOG_FILE -Append
        return
    }
    # ----------------------------------------------------------------------------------
    
    if (-not (Test-Path $TestDir -PathType Container)) {
        "AVISO: O diretório de teste '$TestDir' não é válido ou não pode ser acessado. Pulando o teste." | Tee-Object -FilePath $LOG_FILE -Append
        return
    }

    "--- Testando I/O no Ponto de Montagem: ${Mountpoint} ---" | Tee-Object -FilePath $LOG_FILE -Append
    
    foreach ($i in 1..$TEST_ROUNDS) {
        "-- Rodada $i de $TEST_ROUNDS --" | Tee-Object -FilePath $LOG_FILE -Append
        
        # --- Teste de Escrita ---
        "Testando Escrita..." | Tee-Object -FilePath $LOG_FILE -Append
        
        # Cria um array de bytes para o conteúdo (simulação do /dev/zero)
        $BytesToWrite = New-Object byte[] ($FILE_SIZE_MB * 1MB)
        
        try {
            # ESCRITA
            $TimeWrite = Measure-Command {
                [System.IO.File]::WriteAllBytes($TestFile, $BytesToWrite)
            }
            
            $TimeSecondsWrite = $TimeWrite.TotalSeconds
            $SpeedWriteMBPS = if ($TimeSecondsWrite -gt 0) { $FILE_SIZE_MB / $TimeSecondsWrite } else { 0.0 }
            
            $OutputWrite = "Escrita concluída em $TimeSecondsWrite segundos, $("{0:N3}" -f $SpeedWriteMBPS) MB/s."
            $OutputWrite | Tee-Object -FilePath $LOG_FILE -Append

            # Adicionar ao array global de escrita
            if ($Mountpoint -eq "C:") { $global:DISK_ROOT_WRITE_SPEEDS += $SpeedWriteMBPS }

            # AVISO de cache
            "AVISO: A limpeza de cache de leitura do sistema não é trivialmente suportada no PowerShell." | Tee-Object -FilePath $LOG_FILE -Append
            
            # --- Teste de Leitura ---
            "Testando Leitura (otimizado)..." | Tee-Object -FilePath $LOG_FILE -Append
            
            # Uso de try-finally para garantir que o FileStream seja fechado, liberando o recurso.
            $TimeRead = Measure-Command {
                $buffer = New-Object byte[] 65536 # Buffer de 64KB
                $fs = $null
                try {
                    $fs = [System.IO.File]::OpenRead($TestFile)
                    while ($fs.Read($buffer, 0, $buffer.Length) -gt 0) {}
                }
                finally {
                    # Garantir que o FileStream seja fechado, liberando o arquivo para remoção posterior.
                    if ($fs) { $fs.Dispose() }
                }
            }
            
            $TimeSecondsRead = $TimeRead.TotalSeconds
            $SpeedReadMBPS = if ($TimeSecondsRead -gt 0) { $FILE_SIZE_MB / $TimeSecondsRead } else { 0.0 }
            
            $OutputRead = "Leitura concluída em $TimeSecondsRead segundos, $("{0:N3}" -f $SpeedReadMBPS) MB/s."
            $OutputRead | Tee-Object -FilePath $LOG_FILE -Append

            # Adicionar ao array global de leitura
            if ($Mountpoint -eq "C:") { $global:DISK_ROOT_READ_SPEEDS += $SpeedReadMBPS }
        }
        catch {
            # Registra o erro
            $ErrorMessage = $_.Exception.Message
            "❌ ERRO de I/O na rodada ${i}: $ErrorMessage" | Tee-Object -FilePath $LOG_FILE -Append -ForegroundColor Red
            
            # Garante que as variáveis de velocidade sejam 0 para a média, caso falhe
            if ($Mountpoint -eq "C:") { 
                $global:DISK_ROOT_WRITE_SPEEDS += 0.0 
                $global:DISK_ROOT_READ_SPEEDS += 0.0
            }
        }
        finally {
            # LIMPEZA CORRETA: Remove o arquivo do disco que foi testado
            Remove-Item $TestFile -ErrorAction SilentlyContinue
            "Arquivo de teste removido." | Tee-Object -FilePath $LOG_FILE -Append
            "" | Tee-Object -FilePath $LOG_FILE -Append
        }
    }
}

function Test-AllDiskIO {
    "### 💾 Teste de Performance de I/O de Disco (${FILE_SIZE_MB}MB) em Múltiplos Discos ($TEST_ROUNDS Rodadas) ###" | Tee-Object -FilePath $LOG_FILE -Append
    
    # Filtra apenas discos locais fixos (DriveType 3)
    $Mountpoints = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 } | Select-Object -ExpandProperty DeviceID
    
    if (-not $Mountpoints) {
        "ERRO: Não foi possível detectar pontos de montagem válidos. Usando 'C:' como fallback." | Tee-Object -FilePath $LOG_FILE -Append
        $Mountpoints = @("C:") # Assume C: como disco raiz
    }

    foreach ($mp in $Mountpoints) {
        Run-IOTest $mp
    }
    
    "----------------------------------------" | Tee-Object -FilePath $LOG_FILE -Append
}

function Calculate-AndDisplayAverages {
    # --------------------------------------------------
    # Cálculo das médias (Retorna valores DOUBLE brutos)
    # --------------------------------------------------
    
    $RAW_CPU_MULTI = Calculate-Average $global:CPU_MULTI_TIMES
    $RAW_CPU_SINGLE = Calculate-Average $global:CPU_SINGLE_TIMES
    $RAW_RAM_WRITE = Calculate-Average $global:RAM_WRITE_SPEEDS
    
    # Apenas se o array de resultados de I/O tiver sido populado
    if ($global:DISK_ROOT_WRITE_SPEEDS.Count -gt 0) {
        $RAW_DISK_ROOT_WRITE = Calculate-Average $global:DISK_ROOT_WRITE_SPEEDS
        $RAW_DISK_ROOT_READ = Calculate-Average $global:DISK_ROOT_READ_SPEEDS
    } else {
        $RAW_DISK_ROOT_WRITE = 0.0
        $RAW_DISK_ROOT_READ = 0.0
    }

    # --------------------------------------------------
    # Formatação para Saída (Console/Humana - Usa Vírgula)
    # --------------------------------------------------
    # Usa o formato de localização do sistema para exibir no console
    $AVG_CPU_MULTI_HUMAN = "{0:N3}" -f $RAW_CPU_MULTI
    $AVG_CPU_SINGLE_HUMAN = "{0:N3}" -f $RAW_CPU_SINGLE
    $AVG_RAM_WRITE_HUMAN = "{0:N3}" -f $RAW_RAM_WRITE
    $AVG_DISK_ROOT_WRITE_HUMAN = "{0:N3}" -f $RAW_DISK_ROOT_WRITE
    $AVG_DISK_ROOT_READ_HUMAN = "{0:N3}" -f $RAW_DISK_ROOT_READ

    # --------------------------------------------------
    # Formatação para Parsing (Máquina/JSON - Usa Ponto e SEM separador de milhar)
    # CRÍTICO: Usa F3 (Fixed Point) com InvariantCulture para remover o separador de milhar (vírgula)
    $AVG_CPU_MULTI_MACHINE = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:F3}", $RAW_CPU_MULTI)
    $AVG_CPU_SINGLE_MACHINE = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:F3}", $RAW_CPU_SINGLE)
    $AVG_RAM_WRITE_MACHINE = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:F3}", $RAW_RAM_WRITE)
    $AVG_DISK_ROOT_WRITE_MACHINE = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:F3}", $RAW_DISK_ROOT_WRITE)
    $AVG_DISK_ROOT_READ_MACHINE = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:F3}", $RAW_DISK_ROOT_READ)

    # --------------------------------------------------
    # Serialização dos Arrays de Dados Brutos para Máquina
    # Usa virgula como separador (join) e ponto como decimal (F3)
    # --------------------------------------------------
    $RAW_CPU_MULTI_TIMES_STR = ($global:CPU_MULTI_TIMES | ForEach-Object { [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:F3}", $_) }) -join ','
    $RAW_CPU_SINGLE_TIMES_STR = ($global:CPU_SINGLE_TIMES | ForEach-Object { [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:F3}", $_) }) -join ','
    $RAW_RAM_WRITE_SPEEDS_STR = ($global:RAM_WRITE_SPEEDS | ForEach-Object { [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:F3}", $_) }) -join ','
    $RAW_DISK_WRITE_SPEEDS_STR = ($global:DISK_ROOT_WRITE_SPEEDS | ForEach-Object { [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:F3}", $_) }) -join ','
    $RAW_DISK_READ_SPEEDS_STR = ($global:DISK_ROOT_READ_SPEEDS | ForEach-Object { [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:F3}", $_) }) -join ','


    # --------------------------------------------------
    # Display human-readable averages (USANDO VARIÁVEIS HUMAN)
    # --------------------------------------------------
    "" | Tee-Object -FilePath $LOG_FILE -Append
    "==================================================" | Tee-Object -FilePath $LOG_FILE -Append
    "### 📊 RESULTADOS FINAIS - MÉDIA DE $TEST_ROUNDS RODADAS ###" | Tee-Object -FilePath $LOG_FILE -Append
    "==================================================" | Tee-Object -FilePath $LOG_FILE -Append

    # CPU
    "🧠 CPU Média:" | Tee-Object -FilePath $LOG_FILE -Append
    "    Multi-Core: ${AVG_CPU_MULTI_HUMAN} segundos (Tempo Total)" | Tee-Object -FilePath $LOG_FILE -Append
    "    Single-Core: ${AVG_CPU_SINGLE_HUMAN} segundos (Velocidade Pura)" | Tee-Object -FilePath $LOG_FILE -Append
    "--------------------------------------------------" | Tee-Object -FilePath $LOG_FILE -Append

    # Memória
    "💡 Memória RAM Média:" | Tee-Object -FilePath $LOG_FILE -Append
    "    Escrita Sequencial: ${AVG_RAM_WRITE_HUMAN} MB/s" | Tee-Object -FilePath $LOG_FILE -Append
    "--------------------------------------------------" | Tee-Object -FilePath $LOG_FILE -Append

    # Disco (Apenas C: como exemplo de média)
    if ($global:DISK_ROOT_WRITE_SPEEDS.Count -gt 0) {
        "💾 Disco (Ponto de Montagem Raiz 'C:') Média:" | Tee-Object -FilePath $LOG_FILE -Append
        "    Escrita (Root C:): ${AVG_DISK_ROOT_WRITE_HUMAN} MB/s" | Tee-Object -FilePath $LOG_FILE -Append
        "    Leitura (Root C:): ${AVG_DISK_ROOT_READ_HUMAN} MB/s" | Tee-Object -FilePath $LOG_FILE -Append
        "--------------------------------------------------" | Tee-Object -FilePath $LOG_FILE -Append
    } else {
        "💾 Disco: Média do disco raiz 'C:' não disponível (teste pulado ou falhou)." | Tee-Object -FilePath $LOG_FILE -Append
        "--------------------------------------------------" | Tee-Object -FilePath $LOG_FILE -Append
    }
    
    # --------------------------------------------------
    # Bloco para facilitar o parsing da API (USANDO VARIÁVEIS MACHINE)
    # --------------------------------------------------
    "" | Tee-Object -FilePath $LOG_FILE -Append
    "==================================================" | Tee-Object -FilePath $LOG_FILE -Append
    "### 🤖 MACHINE_READABLE_DATA (Para Parsing de Log) ###" | Tee-Object -FilePath $LOG_FILE -Append
    
    # Metadados de Sistema
    "HOST_NAME: $LOCAL_HOSTNAME" | Tee-Object -FilePath $LOG_FILE -Append
    "OS_INFO: $global:OS_INFO" | Tee-Object -FilePath $LOG_FILE -Append
    "SCRIPT_TARGET: $global:SCRIPT_TARGET" | Tee-Object -FilePath $LOG_FILE -Append
    "CPU_MODEL: $global:CPU_MODEL" | Tee-Object -FilePath $LOG_FILE -Append
    "RAM_TOTAL_MB: $global:TOTAL_RAM_MB" | Tee-Object -FilePath $LOG_FILE -Append

    # Dados Brutos de Média
    "CPU_MULTI_AVG_S: ${AVG_CPU_MULTI_MACHINE}" | Tee-Object -FilePath $LOG_FILE -Append
    "CPU_SINGLE_AVG_S: ${AVG_CPU_SINGLE_MACHINE}" | Tee-Object -FilePath $LOG_FILE -Append
    "RAM_WRITE_AVG_MBPS: ${AVG_RAM_WRITE_MACHINE}" | Tee-Object -FilePath $LOG_FILE -Append
    "DISK_ROOT_WRITE_AVG_MBPS: ${AVG_DISK_ROOT_WRITE_MACHINE}" | Tee-Object -FilePath $LOG_FILE -Append
    "DISK_ROOT_READ_AVG_MBPS: ${AVG_DISK_ROOT_READ_MACHINE}" | Tee-Object -FilePath $LOG_FILE -Append
    
    # Dados Brutos de Rodadas (NOVOS CAMPOS)
    "RAW_CPU_MULTI_S: ${RAW_CPU_MULTI_TIMES_STR}" | Tee-Object -FilePath $LOG_FILE -Append
    "RAW_CPU_SINGLE_S: ${RAW_CPU_SINGLE_TIMES_STR}" | Tee-Object -FilePath $LOG_FILE -Append
    "RAW_RAM_WRITE_MBPS: ${RAW_RAM_WRITE_SPEEDS_STR}" | Tee-Object -FilePath $LOG_FILE -Append
    "RAW_DISK_WRITE_MBPS: ${RAW_DISK_WRITE_SPEEDS_STR}" | Tee-Object -FilePath $LOG_FILE -Append
    "RAW_DISK_READ_MBPS: ${RAW_DISK_READ_SPEEDS_STR}" | Tee-Object -FilePath $LOG_FILE -Append


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
    Write-Host "⚠️  PERMISSÃO PARA UPLOAD PÚBLICO"
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
    
    # 6. Removido o comando inválido 'trap - ...' do Bash.
}