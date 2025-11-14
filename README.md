# ServerPerfTool - Ferramenta de Teste de Performance de Servidor

Esta é uma ferramenta de diagnóstico simples, escrita em Bash, projetada para executar um conjunto padronizado de testes de performance (CPU, RAM e I/O de Disco) em um servidor Linux.

Após a conclusão, o script oferece a opção de enviar anonimamente o log de resultados para uma API pública (`adrielso.tec.br`), que gera um link para um dashboard web interativo onde os resultados podem ser visualizados em gráficos.

## Funcionalidades

- **Teste de CPU (Multi-Core & Single-Core):** Executa um teste de estresse intensivo (baseado em `sha256sum`) para medir o tempo de processamento em todos os núcleos e em um único núcleo.
- **Teste de RAM:** Mede a velocidade de escrita sequencial da memória RAM usando o `dd` no `/dev/shm`.
- **Teste de I/O de Disco:** Mede as velocidades de escrita (`oflag=dsync`) e leitura para o disco principal (`/`).
- **Coleta de Métricas:** Coleta informações do sistema como `hostname`, modelo da CPU, threads e RAM total.
- **Prompt de Consentimento:** O script **pergunta** ao usuário (s/n) antes de enviar qualquer dado para a web.
- **Visualização Dinâmica:** Gera um link para um dashboard web (`view.php`) que exibe os resultados em gráficos interativos.

## Requisitos

Para que o script funcione corretamente, seu servidor precisa ter os seguintes utilitários instalados (a maioria já vem por padrão):

- `bash`
- `curl` (para o upload)
- `perl` (para codificação da URL)
- Utilitários GNU Core: `awk`, `nproc`, `lscpu`, `free`, `lsblk`, `dd`, `grep`, `sed`, `sleep`.

## Como Usar

A forma mais segura e recomendada de usar esta ferramenta é clonando o repositório.

**1. Clone o Repositório**

```
git clone [https://github.com/adrielso/ServerPerfTool.git](https://github.com/adrielso/ServerPerfTool.git)
cd ServerPerfTool
```

**2. Dê Permissão de Execução**

```
chmod +x perftool.sh
```

**3. Execute o Script**

```
./perftool.sh
```

## Como Funciona

1. O script executa os testes de CPU, RAM e Disco, salvando toda a saída em um arquivo de log local (ex: `performance_log_...log`).
2. Ao final, ele exibe um resumo das médias no terminal.
3. Ele então pergunta se você deseja enviar este log para o servidor `adrielso.tec.br` para visualização pública.
4. Se você digitar `s` (sim), o script envia o conteúdo do log para a API.
5. A API salva o log (`.txt`) e um arquivo de dados estruturados (`.json`).
6. O script Bash recebe de volta as URLs desses arquivos e gera o link final para o dashboard de visualização.

## Segurança e Privacidade

A transparência é fundamental ao executar scripts em um servidor.

- **Código Aberto:** O script `perftool.sh` é totalmente aberto para auditoria. Você pode (e deve) ler o código antes de executá-lo.
- **Consentimento Explícito:** Nenhum dado é enviado do seu servidor sem sua permissão explícita (o prompt `s/n`).
- **Dados Coletados:** Os únicos dados enviados são aqueles visíveis no arquivo de log (`.txt`), que incluem os resultados dos testes e os metadados do sistema (Hostname, Modelo da CPU, RAM Total).

## Contribuição

Sinta-se à vontade para abrir uma "Issue" (Problema) se encontrar bugs ou tiver sugestões de melhoria. Pull Requests são bem-vindos!

## Licença

Este projeto é distribuído sob a licença MIT.
