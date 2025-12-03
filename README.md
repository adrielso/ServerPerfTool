# 🖥️ ServerPerfTool  
Ferramenta multiplataforma de diagnóstico e teste de performance de servidores (Linux e Windows).

---

## 🚀 Funcionalidades
- **Teste de CPU**  
  - Multi-Core: mede tempo de processamento em todos os núcleos  
  - Single-Core: mede tempo de processamento em um núcleo específico  
- **Teste de RAM**  
  - Velocidade de escrita sequencial  
- **Teste de I/O de Disco**  
  - Escrita com sincronização (`oflag=dsync` no Linux)  
  - Leitura do disco principal  
- **Coleta de Métricas**  
  - Hostname, modelo da CPU, número de threads, RAM total  
- **Prompt de Consentimento**  
  - Pergunta ao usuário antes de enviar dados para a web  
- **Visualização Dinâmica**  
  - Gera link para dashboard interativo com gráficos  

---

## 📋 Requisitos

| Sistema | Script | Requisitos |
|---------|--------|------------|
| 🐧 **Linux** | `perftool.sh` | bash, curl, perl, awk, nproc, lscpu, free, lsblk, dd, grep, sed, sleep |
| 🖥️ **Windows** | `perftool.ps1` | PowerShell 5.1+, cmdlets nativos (Get-CimInstance, Measure-Command, Start-Job, Invoke-WebRequest), classes .NET |

---

## ⚙️ Como Usar

### 1. Clone o Repositório
```bash
git clone https://github.com/adrielso/ServerPerfTool.git
cd ServerPerfTool
```

### 2. Execute o Script
| Sistema | Comando |
|---------|----------|
| Linux | `chmod +x perftool.sh && ./perftool.sh` |
| Windows | `.\perftool.ps1` |

> 💡 **Nota Windows**: Se bloqueado pela política de execução, rode:  
```powershell
Set-ExecutionPolicy RemoteSigned -Scope Process
```

---

## 🔎 Como Funciona
1. Executa testes de CPU, RAM e Disco  
2. Salva saída em log local (`performance_log_...log`)  
3. Exibe resumo no terminal  
4. Pergunta se deseja enviar log para **adrielso.tec.br**  
5. Caso aceite:  
   - API recebe log (.txt) e dados (.json)  
   - Retorna URLs para visualização  
   - Gera link final para dashboard interativo  

---

## 🔐 Segurança e Privacidade
- **Código Aberto**: scripts disponíveis para auditoria  
- **Consentimento Explícito**: nada é enviado sem autorização  
- **Dados Coletados**: apenas resultados dos testes e metadados básicos (hostname, CPU, RAM)  

---

## 🤝 Contribuição
- Abra uma *Issue* para bugs ou sugestões  
- Pull Requests são bem-vindos  

---

## 📜 Licença
Distribuído sob a licença **MIT**  
