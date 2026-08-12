-- Ontologia derivada do corpus. GERADO por cmd/ontologia — nao editar a mao.
-- Regerar: go run ./cmd/ontologia -sql <arquivo>

BEGIN;

INSERT INTO negative_status
  (codigo, descricao, sinais, causas_candidatas, testes_discriminantes,
   limitacoes, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('desligamento_inesperado','O computador desliga ou reinicia sem aviso, incluindo tela azul.','["bugcheck","tensao","temperatura","erro_memoria","corrupcao_arquivo","processo_pesado","ventoinha","driver_falho"]','["alimentacao_instavel","disco_degradado","driver_incompativel","memoria_instavel","rede_instavel","refrigeracao_insuficiente","software_conflitante"]','["memtest","integridade_so","leitura_termica","boot_limpo","stress_cpu","leitura_eventos"]','["recurso_saturado"]','corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (codigo) DO UPDATE SET
  descricao=EXCLUDED.descricao, sinais=EXCLUDED.sinais,
  causas_candidatas=EXCLUDED.causas_candidatas,
  testes_discriminantes=EXCLUDED.testes_discriminantes,
  limitacoes=EXCLUDED.limitacoes, origem_corpus=EXCLUDED.origem_corpus,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao,
  revisado_em=now(), updated_at=now();
INSERT INTO negative_status
  (codigo, descricao, sinais, causas_candidatas, testes_discriminantes,
   limitacoes, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_persistente','O computador está sistematicamente mais lento do que deveria para o seu hardware.','["temperatura","tensao","processo_pesado","uso_memoria","corrupcao_arquivo","smart_geral","uso_cpu","ventoinha"]','["alimentacao_instavel","disco_degradado","driver_incompativel","memoria_instavel","recurso_saturado","rede_instavel","refrigeracao_insuficiente","software_conflitante"]','["boot_limpo","integridade_so","leitura_eventos","leitura_termica","smart_leitura","superficie_disco"]','[]','corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (codigo) DO UPDATE SET
  descricao=EXCLUDED.descricao, sinais=EXCLUDED.sinais,
  causas_candidatas=EXCLUDED.causas_candidatas,
  testes_discriminantes=EXCLUDED.testes_discriminantes,
  limitacoes=EXCLUDED.limitacoes, origem_corpus=EXCLUDED.origem_corpus,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao,
  revisado_em=now(), updated_at=now();
INSERT INTO negative_status
  (codigo, descricao, sinais, causas_candidatas, testes_discriminantes,
   limitacoes, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('trava_sob_carga','O computador para de responder e volta sozinho, ou precisa ser reiniciado à força.','["tensao","temperatura","bugcheck","erro_memoria","corrupcao_arquivo","erro_sistema_log","uso_cpu","uso_memoria"]','["alimentacao_instavel","disco_degradado","driver_incompativel","memoria_instavel","rede_instavel","software_conflitante"]','["boot_limpo","memtest","integridade_so","smart_leitura","leitura_eventos","stress_cpu"]','["recurso_saturado","refrigeracao_insuficiente"]','corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (codigo) DO UPDATE SET
  descricao=EXCLUDED.descricao, sinais=EXCLUDED.sinais,
  causas_candidatas=EXCLUDED.causas_candidatas,
  testes_discriminantes=EXCLUDED.testes_discriminantes,
  limitacoes=EXCLUDED.limitacoes, origem_corpus=EXCLUDED.origem_corpus,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao,
  revisado_em=now(), updated_at=now();
INSERT INTO negative_status
  (codigo, descricao, sinais, causas_candidatas, testes_discriminantes,
   limitacoes, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('nao_inicializa','O computador não completa a inicialização do sistema.','["tensao","erro_memoria","corrupcao_arquivo","bugcheck","ventoinha","erro_sistema_log","temperatura","boot_falho"]','["alimentacao_instavel","disco_degradado","memoria_instavel"]','["boot_limpo","memtest","integridade_so","leitura_eventos","superficie_disco","leitura_termica"]','["driver_incompativel","rede_instavel","refrigeracao_insuficiente","software_conflitante"]','corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (codigo) DO UPDATE SET
  descricao=EXCLUDED.descricao, sinais=EXCLUDED.sinais,
  causas_candidatas=EXCLUDED.causas_candidatas,
  testes_discriminantes=EXCLUDED.testes_discriminantes,
  limitacoes=EXCLUDED.limitacoes, origem_corpus=EXCLUDED.origem_corpus,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao,
  revisado_em=now(), updated_at=now();
INSERT INTO negative_status
  (codigo, descricao, sinais, causas_candidatas, testes_discriminantes,
   limitacoes, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('erro_de_dispositivo','O sistema operacional está reportando erro de acesso a um dispositivo.','["tensao","smart_geral","bugcheck","corrupcao_arquivo","driver_falho","erro_io_log","smart_reallocated","temperatura"]','["disco_degradado"]','["smart_leitura","superficie_disco","troca_peca","boot_limpo","integridade_so","leitura_termica"]','["alimentacao_instavel","driver_incompativel","memoria_instavel","rede_instavel"]','corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (codigo) DO UPDATE SET
  descricao=EXCLUDED.descricao, sinais=EXCLUDED.sinais,
  causas_candidatas=EXCLUDED.causas_candidatas,
  testes_discriminantes=EXCLUDED.testes_discriminantes,
  limitacoes=EXCLUDED.limitacoes, origem_corpus=EXCLUDED.origem_corpus,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao,
  revisado_em=now(), updated_at=now();
INSERT INTO negative_status
  (codigo, descricao, sinais, causas_candidatas, testes_discriminantes,
   limitacoes, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('superaquecimento','O computador opera acima da faixa térmica segura.','["temperatura","ventoinha","tensao","bugcheck","erro_sistema_log","uso_cpu"]','["refrigeracao_insuficiente"]','["leitura_termica","stress_cpu","stress_gpu","boot_limpo"]','["alimentacao_instavel","disco_degradado","memoria_instavel","recurso_saturado"]','corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (codigo) DO UPDATE SET
  descricao=EXCLUDED.descricao, sinais=EXCLUDED.sinais,
  causas_candidatas=EXCLUDED.causas_candidatas,
  testes_discriminantes=EXCLUDED.testes_discriminantes,
  limitacoes=EXCLUDED.limitacoes, origem_corpus=EXCLUDED.origem_corpus,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao,
  revisado_em=now(), updated_at=now();
INSERT INTO negative_status
  (codigo, descricao, sinais, causas_candidatas, testes_discriminantes,
   limitacoes, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('corrupcao_de_dados','Arquivos ou estruturas do sistema de arquivos estão sendo corrompidos.','["corrupcao_arquivo","smart_geral","erro_io_log","erro_memoria","smart_reallocated","bugcheck","driver_falho","temperatura"]','["disco_degradado"]','["integridade_so","smart_leitura","memtest","superficie_disco","boot_limpo","leitura_termica"]','["driver_incompativel","memoria_instavel","rede_instavel","refrigeracao_insuficiente","software_conflitante"]','corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (codigo) DO UPDATE SET
  descricao=EXCLUDED.descricao, sinais=EXCLUDED.sinais,
  causas_candidatas=EXCLUDED.causas_candidatas,
  testes_discriminantes=EXCLUDED.testes_discriminantes,
  limitacoes=EXCLUDED.limitacoes, origem_corpus=EXCLUDED.origem_corpus,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao,
  revisado_em=now(), updated_at=now();

INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('corrupcao_de_dados','disco_degradado',1.000000,43,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('desligamento_inesperado','alimentacao_instavel',0.511111,253,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('desligamento_inesperado','disco_degradado',0.141414,70,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('desligamento_inesperado','driver_incompativel',0.125253,62,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('desligamento_inesperado','memoria_instavel',0.111111,55,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('desligamento_inesperado','software_conflitante',0.050505,25,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('desligamento_inesperado','refrigeracao_insuficiente',0.036364,18,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('desligamento_inesperado','rede_instavel',0.024242,12,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('erro_de_dispositivo','disco_degradado',1.000000,79,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_persistente','recurso_saturado',0.512552,245,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_persistente','disco_degradado',0.179916,86,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_persistente','rede_instavel',0.135983,65,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_persistente','memoria_instavel',0.066946,32,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_persistente','software_conflitante',0.033473,16,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_persistente','alimentacao_instavel',0.029289,14,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_persistente','refrigeracao_insuficiente',0.023013,11,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_persistente','driver_incompativel',0.018828,9,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('nao_inicializa','disco_degradado',0.479592,47,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('nao_inicializa','memoria_instavel',0.275510,27,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('nao_inicializa','alimentacao_instavel',0.244898,24,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('superaquecimento','refrigeracao_insuficiente',1.000000,78,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('trava_sob_carga','disco_degradado',0.412935,83,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('trava_sob_carga','software_conflitante',0.144279,29,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('trava_sob_carga','memoria_instavel',0.144279,29,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('trava_sob_carga','rede_instavel',0.134328,27,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('trava_sob_carga','alimentacao_instavel',0.099502,20,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('trava_sob_carga','driver_incompativel',0.064677,13,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();

INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('corrupcao_de_dados.disco_degradado.v1','pt-BR','tecnico','Disco degradado — superfície, controladora ou interface falhando.','Disco degradado — superfície, controladora ou interface falhando. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('corrupcao_de_dados.disco_degradado.v1','pt-BR','cliente','Disco degradado — superfície, controladora ou interface falhando.','O disco (onde ficam seus arquivos) está falhando. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('desligamento_inesperado.alimentacao_instavel.v1','pt-BR','tecnico','Alimentação instável — fonte, bateria ou rede elétrica fora da faixa.','Alimentação instável — fonte, bateria ou rede elétrica fora da faixa. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('desligamento_inesperado.alimentacao_instavel.v1','pt-BR','cliente','Alimentação instável — fonte, bateria ou rede elétrica fora da faixa.','A energia que chega ao computador está oscilando. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('desligamento_inesperado.disco_degradado.v1','pt-BR','tecnico','Disco degradado — superfície, controladora ou interface falhando.','Disco degradado — superfície, controladora ou interface falhando. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('desligamento_inesperado.disco_degradado.v1','pt-BR','cliente','Disco degradado — superfície, controladora ou interface falhando.','O disco (onde ficam seus arquivos) está falhando. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('desligamento_inesperado.driver_incompativel.v1','pt-BR','tecnico','Driver incompatível ou defeituoso para o hardware presente.','Driver incompatível ou defeituoso para o hardware presente. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('desligamento_inesperado.driver_incompativel.v1','pt-BR','cliente','Driver incompatível ou defeituoso para o hardware presente.','Um programa de controle de peça está com defeito. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('desligamento_inesperado.memoria_instavel.v1','pt-BR','tecnico','Memória instável — erro de leitura/escrita em RAM sob carga.','Memória instável — erro de leitura/escrita em RAM sob carga. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('desligamento_inesperado.memoria_instavel.v1','pt-BR','cliente','Memória instável — erro de leitura/escrita em RAM sob carga.','A memória do computador está com defeito. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('desligamento_inesperado.software_conflitante.v1','pt-BR','tecnico','Software conflitante — programa ou serviço interferindo no sistema.','Software conflitante — programa ou serviço interferindo no sistema. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('desligamento_inesperado.software_conflitante.v1','pt-BR','cliente','Software conflitante — programa ou serviço interferindo no sistema.','Um programa instalado está atrapalhando o sistema. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('desligamento_inesperado.refrigeracao_insuficiente.v1','pt-BR','tecnico','Refrigeração insuficiente — dissipação abaixo do necessário para a carga.','Refrigeração insuficiente — dissipação abaixo do necessário para a carga. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('desligamento_inesperado.refrigeracao_insuficiente.v1','pt-BR','cliente','Refrigeração insuficiente — dissipação abaixo do necessário para a carga.','O computador está esquentando demais. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('desligamento_inesperado.rede_instavel.v1','pt-BR','tecnico','Rede instável — perda, latência ou saturação do enlace.','Rede instável — perda, latência ou saturação do enlace. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('desligamento_inesperado.rede_instavel.v1','pt-BR','cliente','Rede instável — perda, latência ou saturação do enlace.','A conexão de rede está instável. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('erro_de_dispositivo.disco_degradado.v1','pt-BR','tecnico','Disco degradado — superfície, controladora ou interface falhando.','Disco degradado — superfície, controladora ou interface falhando. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('erro_de_dispositivo.disco_degradado.v1','pt-BR','cliente','Disco degradado — superfície, controladora ou interface falhando.','O disco (onde ficam seus arquivos) está falhando. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_persistente.recurso_saturado.v1','pt-BR','tecnico','Recurso saturado — CPU, RAM ou I/O em uso pleno de forma sustentada.','Recurso saturado — CPU, RAM ou I/O em uso pleno de forma sustentada. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_persistente.recurso_saturado.v1','pt-BR','cliente','Recurso saturado — CPU, RAM ou I/O em uso pleno de forma sustentada.','O computador está sem folga para o que você usa. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_persistente.disco_degradado.v1','pt-BR','tecnico','Disco degradado — superfície, controladora ou interface falhando.','Disco degradado — superfície, controladora ou interface falhando. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_persistente.disco_degradado.v1','pt-BR','cliente','Disco degradado — superfície, controladora ou interface falhando.','O disco (onde ficam seus arquivos) está falhando. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_persistente.rede_instavel.v1','pt-BR','tecnico','Rede instável — perda, latência ou saturação do enlace.','Rede instável — perda, latência ou saturação do enlace. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_persistente.rede_instavel.v1','pt-BR','cliente','Rede instável — perda, latência ou saturação do enlace.','A conexão de rede está instável. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_persistente.memoria_instavel.v1','pt-BR','tecnico','Memória instável — erro de leitura/escrita em RAM sob carga.','Memória instável — erro de leitura/escrita em RAM sob carga. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_persistente.memoria_instavel.v1','pt-BR','cliente','Memória instável — erro de leitura/escrita em RAM sob carga.','A memória do computador está com defeito. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_persistente.software_conflitante.v1','pt-BR','tecnico','Software conflitante — programa ou serviço interferindo no sistema.','Software conflitante — programa ou serviço interferindo no sistema. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_persistente.software_conflitante.v1','pt-BR','cliente','Software conflitante — programa ou serviço interferindo no sistema.','Um programa instalado está atrapalhando o sistema. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_persistente.alimentacao_instavel.v1','pt-BR','tecnico','Alimentação instável — fonte, bateria ou rede elétrica fora da faixa.','Alimentação instável — fonte, bateria ou rede elétrica fora da faixa. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_persistente.alimentacao_instavel.v1','pt-BR','cliente','Alimentação instável — fonte, bateria ou rede elétrica fora da faixa.','A energia que chega ao computador está oscilando. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_persistente.refrigeracao_insuficiente.v1','pt-BR','tecnico','Refrigeração insuficiente — dissipação abaixo do necessário para a carga.','Refrigeração insuficiente — dissipação abaixo do necessário para a carga. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_persistente.refrigeracao_insuficiente.v1','pt-BR','cliente','Refrigeração insuficiente — dissipação abaixo do necessário para a carga.','O computador está esquentando demais. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_persistente.driver_incompativel.v1','pt-BR','tecnico','Driver incompatível ou defeituoso para o hardware presente.','Driver incompatível ou defeituoso para o hardware presente. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_persistente.driver_incompativel.v1','pt-BR','cliente','Driver incompatível ou defeituoso para o hardware presente.','Um programa de controle de peça está com defeito. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('nao_inicializa.disco_degradado.v1','pt-BR','tecnico','Disco degradado — superfície, controladora ou interface falhando.','Disco degradado — superfície, controladora ou interface falhando. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('nao_inicializa.disco_degradado.v1','pt-BR','cliente','Disco degradado — superfície, controladora ou interface falhando.','O disco (onde ficam seus arquivos) está falhando. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('nao_inicializa.memoria_instavel.v1','pt-BR','tecnico','Memória instável — erro de leitura/escrita em RAM sob carga.','Memória instável — erro de leitura/escrita em RAM sob carga. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('nao_inicializa.memoria_instavel.v1','pt-BR','cliente','Memória instável — erro de leitura/escrita em RAM sob carga.','A memória do computador está com defeito. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('nao_inicializa.alimentacao_instavel.v1','pt-BR','tecnico','Alimentação instável — fonte, bateria ou rede elétrica fora da faixa.','Alimentação instável — fonte, bateria ou rede elétrica fora da faixa. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('nao_inicializa.alimentacao_instavel.v1','pt-BR','cliente','Alimentação instável — fonte, bateria ou rede elétrica fora da faixa.','A energia que chega ao computador está oscilando. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('superaquecimento.refrigeracao_insuficiente.v1','pt-BR','tecnico','Refrigeração insuficiente — dissipação abaixo do necessário para a carga.','Refrigeração insuficiente — dissipação abaixo do necessário para a carga. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('superaquecimento.refrigeracao_insuficiente.v1','pt-BR','cliente','Refrigeração insuficiente — dissipação abaixo do necessário para a carga.','O computador está esquentando demais. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('trava_sob_carga.disco_degradado.v1','pt-BR','tecnico','Disco degradado — superfície, controladora ou interface falhando.','Disco degradado — superfície, controladora ou interface falhando. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('trava_sob_carga.disco_degradado.v1','pt-BR','cliente','Disco degradado — superfície, controladora ou interface falhando.','O disco (onde ficam seus arquivos) está falhando. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('trava_sob_carga.software_conflitante.v1','pt-BR','tecnico','Software conflitante — programa ou serviço interferindo no sistema.','Software conflitante — programa ou serviço interferindo no sistema. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('trava_sob_carga.software_conflitante.v1','pt-BR','cliente','Software conflitante — programa ou serviço interferindo no sistema.','Um programa instalado está atrapalhando o sistema. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('trava_sob_carga.memoria_instavel.v1','pt-BR','tecnico','Memória instável — erro de leitura/escrita em RAM sob carga.','Memória instável — erro de leitura/escrita em RAM sob carga. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('trava_sob_carga.memoria_instavel.v1','pt-BR','cliente','Memória instável — erro de leitura/escrita em RAM sob carga.','A memória do computador está com defeito. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('trava_sob_carga.rede_instavel.v1','pt-BR','tecnico','Rede instável — perda, latência ou saturação do enlace.','Rede instável — perda, latência ou saturação do enlace. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('trava_sob_carga.rede_instavel.v1','pt-BR','cliente','Rede instável — perda, latência ou saturação do enlace.','A conexão de rede está instável. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('trava_sob_carga.alimentacao_instavel.v1','pt-BR','tecnico','Alimentação instável — fonte, bateria ou rede elétrica fora da faixa.','Alimentação instável — fonte, bateria ou rede elétrica fora da faixa. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('trava_sob_carga.alimentacao_instavel.v1','pt-BR','cliente','Alimentação instável — fonte, bateria ou rede elétrica fora da faixa.','A energia que chega ao computador está oscilando. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('trava_sob_carga.driver_incompativel.v1','pt-BR','tecnico','Driver incompatível ou defeituoso para o hardware presente.','Driver incompatível ou defeituoso para o hardware presente. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('trava_sob_carga.driver_incompativel.v1','pt-BR','cliente','Driver incompatível ou defeituoso para o hardware presente.','Um programa de controle de peça está com defeito. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();

COMMIT;
