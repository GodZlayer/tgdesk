# Catálogo de ações administrativas

Este catálogo registra onde cada estado administrativo é exibido e qual ação
deve alternar entre suspensão e ativação. A regra é única: o ícone e o texto
sempre refletem o estado retornado pelo servidor; nenhuma tela deve oferecer
apenas uma ação unilateral.

| Tela | Entidade | Estado | Alternância | Observação |
| --- | --- | --- | --- | --- |
| Dispositivos | Organização | `status` | Suspender / Reativar | Cascateia redes e dispositivos conforme servidor |
| Dispositivos | Rede | `status` | Suspender / Reativar | Cascateia dispositivos da rede |
| Dispositivos | Sub-rede | `status` | Suspender / Reativar | Controle incluído nesta correção |
| Dispositivos | Dispositivo | `state` | Suspender / Reativar | Mantém o vínculo e interrompe a conexão |
| Técnicos | Supervisor | `status` | Suspender / Reativar | Desativa também o escopo administrado |
| Admin / Vinculados | Organização | `status` | Suspender / Reativar | O mesmo diálogo serve para cota e supervisor |
| Admin / Vinculados | Rede | `status` | Suspender / Reativar | Ação no diálogo do vínculo |
| Admin / Vinculados | Sub-rede | `status` | Suspender / Reativar | Usa os endpoints próprios da sub-rede |
| Admin / Vinculados | Dispositivo | `state` | Suspender / Reativar | Ação no diálogo do vínculo |
| Admin / Vinculados | Supervisor | `status` | Suspender / Reativar | Ação no diálogo do vínculo |

## Ações que não são suspensão

- Branding personalizado: ativar/desativar a marca do supervisor.
- Copiar e colar, transferência de arquivos e captura de teclado: controles da
  sessão remota, independentes do estado administrativo do dispositivo.
- Diagnósticos: iniciar, pausar, retomar e cancelar uma execução.
- Catálogo, regiões e taxas: ativação de registros de configuração não deve ser
  confundida com suspensão de uma organização, rede ou dispositivo.

## Verificação pendente

O código agora cobre os pares de ações e os endpoints correspondentes. Ainda é
necessário validar visualmente, em uma sessão real, cada clique nos quatro
níveis da árvore e a atualização em tempo real para outro cliente conectado.

## Matriz geral dos objetivos do TGDesk

| Frente | Critério de aceite | Situação atual |
| --- | --- | --- |
| Sessão remota | Fechar pelo X encerra a aba TGDesk, sem tela cinza | Código integrado; teste Dani ↔ Daniel ainda pendente |
| Sessão remota | Tela cheia não desloca o canvas pelo toolbar flutuante | Ajuste de cálculo de inserção aplicado; falta inspeção visual real |
| Sessão remota | Atalhos no estilo Parsec, popup e bloqueio de comandos | Atalhos principais integrados; falta matriz completa de teclas por sistema |
| Supervisor | Preview de ícones não pisca nem redimensiona em loop | Renderização estabilizada por tamanho/chave fixa; falta teste prolongado |
| Admin / Vinculados e Cotas | Um único conteúdo hierárquico organização → rede → sub-rede → dispositivo | Menu unificado e botões de gerenciamento por nível aplicados; falta inspeção visual em execução |
| Admin / Chamados e Catálogo | Uma área com três abas internas, sem preço | Componente de três abas existente; falta revisar se nenhum caminho legado ainda aparece |
| Admin / Regiões | Lista compacta, país → estado → região → cidade → bairro → rua/CEP | Cadastro de cobertura e compactação existentes; mapa regional/cidade ainda incompleto |
| Admin / Mapa | Mapa real do país, zoom por estado/região e painel contextual 70/30 | Seleção de estado, filtro de regiões por municípios, painel de cidades e malhas municipais aplicados; falta teste visual com dados reais |
| Admin / Auditoria | Dashboard interativo de todos os logs | Dashboard e drill-down existentes; falta validação com carga e filtros reais |
| Admin / Taxas | TGDesk, supervisor da OS, supervisor do vínculo, pagamento e resto do técnico | Regra server-side e tela existentes; falta validar cenários de percentuais extremos |
| Textos | Todas as telas administrativas em PT-BR, sem mojibake ou `?` | Arquivos administrativos principais normalizados; falta varredura final de strings restantes |
| Release | Cliente e servidor publicados juntos e atualização automática | Alterações desta rodada ainda não foram publicadas; nova rodada só deve sair após os testes interativos acima |
