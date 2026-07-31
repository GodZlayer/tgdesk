# Requisitos acumulados até v1.1.0 — checklist autoritativo

Transcrição fiel dos pedidos do usuário, numerada para rastreio de gap.

## ⚠️ Tradução de terminologia
- Nos itens **anteriores à v1.0.0**, "tech" = o papel que hoje se chama **`supervisor`**.
- A partir da **v1.0.0**, "tech" = **`freelancer`** (classe nova).
- Papéis finais: `super_admin`, `supervisor`, `cliente`, `freelancer`, `cliente_avulso`.
- Regra transversal: **toda função de supervisor existe também para super_admin.**

---

## A. Sistema de verificações pesadas (testes de qualidade)
- **A1** Botão novo na lista de dispositivos que abre tela de opções de verificações pesadas
- **A2** Testes: forçar CPU, GPU, internet, HD, verificar badblocks, entre muitos outros
- **A3** Cada teste gera log de dados
- **A4** Dados apresentados visualmente seguindo o design system do TGDesk
- **A5** Cada teste é executado **separadamente e manualmente** por um técnico, sempre via esse menu
- **A6** Os mesmos testes disponíveis **dentro da janela de acesso remoto**, no menu de opções, de forma interativa (ex.: diagnosticar lentidão durante o atendimento)
- **A7** Alertas passam a ser **por média** (não por pico isolado)

## B. Branding próprio por tech (white-label)
- **B1** Nova tela de branding
- **B2** Habilitada individualmente por tech, **pelo admin** (feature flag por tech)
- **B3** Personalizar logo e nome (ex.: TGDesk → "BE-Desk" para o tech BrasilExpress)
- **B4** Branding aparece **apenas no cliente**; o próprio tech continua vendo TGDesk na máquina dele
- **B5** Imagens armazenadas no Docker do servidor TGDesk, alimentando o ecossistema
- **B6** **Regra obrigatória:** qualquer função de tech é também função de admin

## C. Sistema de chamado / Ordem de Serviço — marco v0.4.0
- **C1** Na tela do cliente, substituir a orientação por "abrir chamado — e aguardar resposta do técnico"
- **C2** Nova tela para o tech gerenciar a fila de chamados
- **C3** Plano claro de ORDEM DE SERVIÇO / CHAMADO DE TÉCNICO que faça sentido de ponta a ponta

## D. Acesso remoto avançado (pós-v0.4.0)
- **D1** Desabilitar o controle de mouse e teclado do usuário/cliente (opcional, com atalho)
- **D2** Desenhar na tela do cliente: atalho para ativar/desativar + menu na tela do acesso com caneta, borracha, apagar tudo
- **D3** Copiar/colar integrado com transferência de arquivo dentro do acesso remoto, com comando para ativar/desativar, **desativado por padrão**

## E. Regras de nomeação
- **E1** Admin pode renomear organizações extras criadas por ele
- **E2** Organizações de tech sempre têm o nome do tech
- **E3** O nome do tech é o que ele mesmo define ao editar seu nome de dispositivo, ou o que o admin editar
- **E4** Tech edita o nome das suas próprias redes; admin edita todas

## F. Cascata de suspensão
- **F1** Suspender um tech suspende a organização dele, e por consequência as redes, e por consequência os dispositivos
- **F2** Suspender uma rede (pelo tech ou pelo admin) suspende todos os dispositivos dela

## G. Arquitetura v1.0.0
- **G1** Hierarquia: organização > rede > subrede > dispositivo
- **G2** Tech vira **supervisor**
- **G3** Nova classe "tech" = **freelancer**, atende apenas chamados
- **G4** Supervisor lança o pedido informando dados técnicos e de localização
- **G5** Servidor gerencia localização e qualidade do tech para prioridade de fila
- **G6** Fila dinâmica que aparece em tempos diferentes para cada técnico
- **G7** Techs acessam uma interface nova, possuem vinculação e rodam no mesmo programa
- **G8** Techs **não possuem rede própria**; são vinculados ao supervisor, dentro da organização dele
- **G9** Rede privada interna apenas para a lógica do sistema e o app funcionarem
- **G10** Interface própria de chamados para o tech: geolocalização, foto de comprovação, imprimir e assinar (comprova com foto) **ou** assinar digitalmente e exportar arquivo
- **G11** O tech também possui a tela de client

## H. Cliente avulso — v1.1.0
- **H1** Novo tipo de conta: cliente avulso
- **H2** Abaixo do código, um botão pequeno "solicitar acesso avulso"
- **H3** Vinculação a uma organização única e a uma rede "pública" da VPN
- **H4** Chamado em fila para os techs, que pode ser **virtual ou presencial**
- **H5** Se virtual, libera o acesso remoto ao tech **por dentro do chamado**
- **H6** Funções de verificação, teste e respostas de análise do sistema do cliente avulso

## I. Fixes
- **I1** Falta favicon, que serve para todos os ícones do client
- **I2** Sistema de crop e redimensionar, com preview, para o tech ver como vai ficar no client
- **I3** Supervisor pode criar quantas redes e subredes forem necessárias dentro da sua org
- **I4** Cada supervisor vê apenas a própria org e a org **tgdevs** (somente a rede à qual está vinculado), gerenciada pelo admin
- **I5** O acesso remoto não fica fullscreen de verdade
- **I6** Duas barras de controle do próprio acesso remoto se sobrepondo
