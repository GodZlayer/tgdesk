-- Ontologia derivada do corpus. GERADO por cmd/ontologia — nao editar a mao.
-- Regerar: go run ./cmd/ontologia -sql <arquivo>

BEGIN;

INSERT INTO negative_status
  (codigo, descricao, sinais, causas_candidatas, testes_discriminantes,
   limitacoes, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('desligamento_inesperado','O computador desliga ou reinicia sem aviso, incluindo tela azul.','["bateria","bugcheck","desligamento_subito","driver_falho","erro_memoria","erro_sistema_log","servico_caiu","temperatura","tensao","ventoinha"]','["alimentacao_instavel","bateria_degradada","driver_incompativel","fonte_falhando","gpu_falhando","memoria_instavel","placa_ou_capacitor","refrigeracao_insuficiente","software_conflitante"]','["memtest","integridade_so","leitura_termica","boot_limpo","stress_cpu","leitura_eventos"]','["placa_ou_capacitor"]','corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
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
VALUES ('lentidao_nao_caracterizada','O computador está lento, e ainda não se sabe se são engasgos curtos ou períodos longos.','["bugcheck","driver_falho","erro_io_log","erro_sistema_log","latencia_disco","processo_dominante","processo_pesado","servico_caiu","smart_desgaste","smart_geral","smart_pending","smart_reallocated","temperatura","uso_cpu","uso_memoria","ventoinha"]','["ambiente_quente","cpu_insuficiente","dentro_do_esperado","disco_cheio","disco_degradado","disco_desgastado","disco_lento","driver_incompativel","inicializacao_pesada","memoria_insuficiente","processo_em_segundo_plano","rede_instavel","rede_insuficiente","refrigeracao_insuficiente","software_conflitante"]','["boot_limpo","leitura_termica","smart_leitura","integridade_so","troca_peca","leitura_eventos"]','[]','corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
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
VALUES ('trava_sob_carga','O computador para de responder e volta sozinho, ou precisa ser reiniciado à força.','["bugcheck","corrupcao_arquivo","desligamento_subito","driver_falho","erro_io_log","erro_memoria","erro_sistema_log","servico_caiu","smart_geral","smart_pending","smart_reallocated","temperatura","tensao","uso_memoria","ventoinha"]','["disco_degradado","driver_incompativel","fonte_falhando","gpu_falhando","mau_contato","memoria_instavel","memoria_insuficiente","placa_ou_capacitor","refrigeracao_insuficiente","sistema_corrompido","software_conflitante"]','["boot_limpo","memtest","integridade_so","smart_leitura","leitura_eventos","stress_cpu"]','["mau_contato","placa_ou_capacitor"]','corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
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
VALUES ('nao_inicializa','O computador não completa a inicialização do sistema.','["corrupcao_arquivo","desligamento_subito","erro_io_log","erro_memoria","processo_pesado","smart_geral","smart_pending","smart_reallocated","tensao"]','["alimentacao_instavel","disco_cheio","disco_degradado","fonte_falhando","mau_contato","memoria_instavel","placa_ou_capacitor","sistema_corrompido"]','["boot_limpo","memtest","integridade_so","leitura_eventos","superficie_disco","leitura_termica"]','["mau_contato","placa_ou_capacitor"]','corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
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
VALUES ('erro_de_dispositivo','O sistema operacional está reportando erro de acesso a um dispositivo.','["erro_io_log","processo_pesado","smart_desgaste","smart_geral","smart_pending","smart_reallocated"]','["disco_cheio","disco_degradado","disco_desgastado","mau_contato"]','["smart_leitura","superficie_disco","troca_peca","boot_limpo","integridade_so","leitura_termica"]','["mau_contato"]','corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
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
VALUES ('superaquecimento','O computador opera acima da faixa térmica segura.','["temperatura","ventoinha"]','["ambiente_quente","refrigeracao_insuficiente"]','["leitura_termica","stress_cpu","stress_gpu","boot_limpo"]','[]','corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
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
VALUES ('lentidao_profunda','O computador entra em períodos longos em que tudo fica lento, e não melhora sozinho.','["erro_io_log","latencia_disco","processo_dominante","processo_pesado","smart_desgaste","smart_geral","smart_pending","smart_reallocated","uso_cpu","uso_memoria"]','["cpu_insuficiente","dentro_do_esperado","disco_cheio","disco_degradado","disco_desgastado","disco_lento","memoria_insuficiente","processo_em_segundo_plano","rede_instavel","rede_insuficiente"]','["integridade_so","boot_limpo","leitura_eventos","superficie_disco","smart_leitura","troca_peca"]','[]','corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
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
VALUES ('corrupcao_de_dados','Arquivos ou estruturas do sistema de arquivos estão sendo corrompidos.','["corrupcao_arquivo","erro_io_log","erro_memoria","smart_geral","smart_pending","smart_reallocated"]','["disco_degradado","memoria_instavel","sistema_corrompido"]','["integridade_so","smart_leitura","memtest","superficie_disco","boot_limpo","leitura_termica"]','[]','corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
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
VALUES ('lentidao_intermitente','O computador engasga por segundos e volta ao normal sozinho, várias vezes ao dia.','["bugcheck","driver_falho","erro_sistema_log","processo_dominante","processo_pesado","servico_caiu","temperatura","uso_cpu","uso_memoria","ventoinha"]','["ambiente_quente","cpu_insuficiente","dentro_do_esperado","disco_cheio","driver_incompativel","inicializacao_pesada","memoria_insuficiente","processo_em_segundo_plano","rede_instavel","refrigeracao_insuficiente","software_conflitante"]','["smart_leitura","superficie_disco"]','[]','corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
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
VALUES ('congelamento_breve_repetido','O computador para totalmente por alguns segundos e volta sozinho, várias vezes.','["bugcheck","driver_falho","erro_memoria","latencia_disco","temperatura","ventoinha"]','["disco_lento","driver_incompativel","gpu_falhando","memoria_instavel","refrigeracao_insuficiente"]','["all_tests"]','[]','corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (codigo) DO UPDATE SET
  descricao=EXCLUDED.descricao, sinais=EXCLUDED.sinais,
  causas_candidatas=EXCLUDED.causas_candidatas,
  testes_discriminantes=EXCLUDED.testes_discriminantes,
  limitacoes=EXCLUDED.limitacoes, origem_corpus=EXCLUDED.origem_corpus,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao,
  revisado_em=now(), updated_at=now();

INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('congelamento_breve_repetido','disco_lento',0.200000,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('congelamento_breve_repetido','driver_incompativel',0.200000,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('congelamento_breve_repetido','gpu_falhando',0.200000,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('congelamento_breve_repetido','memoria_instavel',0.200000,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('congelamento_breve_repetido','refrigeracao_insuficiente',0.200000,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('corrupcao_de_dados','disco_degradado',0.980392,43,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('corrupcao_de_dados','memoria_instavel',0.009804,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('corrupcao_de_dados','sistema_corrompido',0.009804,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('desligamento_inesperado','alimentacao_instavel',0.511202,251,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('desligamento_inesperado','bateria_degradada',0.041752,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('desligamento_inesperado','driver_incompativel',0.122200,60,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('desligamento_inesperado','fonte_falhando',0.041752,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('desligamento_inesperado','gpu_falhando',0.041752,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('desligamento_inesperado','memoria_instavel',0.112016,55,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('desligamento_inesperado','placa_ou_capacitor',0.041752,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('desligamento_inesperado','refrigeracao_insuficiente',0.036660,18,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('desligamento_inesperado','software_conflitante',0.050916,25,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('erro_de_dispositivo','disco_cheio',0.009709,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('erro_de_dispositivo','disco_degradado',0.970874,79,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('erro_de_dispositivo','disco_desgastado',0.009709,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('erro_de_dispositivo','mau_contato',0.009709,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_intermitente','ambiente_quente',0.090909,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_intermitente','cpu_insuficiente',0.090909,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_intermitente','dentro_do_esperado',0.090909,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_intermitente','disco_cheio',0.090909,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_intermitente','driver_incompativel',0.090909,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_intermitente','inicializacao_pesada',0.090909,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_intermitente','memoria_insuficiente',0.090909,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_intermitente','processo_em_segundo_plano',0.090909,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_intermitente','rede_instavel',0.090909,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_intermitente','refrigeracao_insuficiente',0.090909,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_intermitente','software_conflitante',0.090909,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_nao_caracterizada','ambiente_quente',0.010787,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_nao_caracterizada','cpu_insuficiente',0.519417,214,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_nao_caracterizada','dentro_do_esperado',0.010787,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_nao_caracterizada','disco_cheio',0.010787,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_nao_caracterizada','disco_degradado',0.157767,65,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_nao_caracterizada','disco_desgastado',0.010787,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_nao_caracterizada','disco_lento',0.010787,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_nao_caracterizada','driver_incompativel',0.019417,8,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_nao_caracterizada','inicializacao_pesada',0.010787,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_nao_caracterizada','memoria_insuficiente',0.010787,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_nao_caracterizada','processo_em_segundo_plano',0.010787,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_nao_caracterizada','rede_instavel',0.143204,59,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_nao_caracterizada','rede_insuficiente',0.010787,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_nao_caracterizada','refrigeracao_insuficiente',0.026699,11,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_nao_caracterizada','software_conflitante',0.036408,15,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_profunda','cpu_insuficiente',0.524109,30,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_profunda','dentro_do_esperado',0.009259,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_profunda','disco_cheio',0.009259,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_profunda','disco_degradado',0.401817,23,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_profunda','disco_desgastado',0.009259,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_profunda','disco_lento',0.009259,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_profunda','memoria_insuficiente',0.009259,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_profunda','processo_em_segundo_plano',0.009259,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_profunda','rede_instavel',0.009259,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('lentidao_profunda','rede_insuficiente',0.009259,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('nao_inicializa','alimentacao_instavel',0.233236,24,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('nao_inicializa','disco_cheio',0.009524,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('nao_inicializa','disco_degradado',0.456754,47,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('nao_inicializa','fonte_falhando',0.009524,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('nao_inicializa','mau_contato',0.009524,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('nao_inicializa','memoria_instavel',0.262391,27,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('nao_inicializa','placa_ou_capacitor',0.009524,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('nao_inicializa','sistema_corrompido',0.009524,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('superaquecimento','ambiente_quente',0.009901,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('superaquecimento','refrigeracao_insuficiente',0.990099,77,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('trava_sob_carga','disco_degradado',0.406091,80,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('trava_sob_carga','driver_incompativel',0.065990,13,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('trava_sob_carga','fonte_falhando',0.034083,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('trava_sob_carga','gpu_falhando',0.034083,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('trava_sob_carga','mau_contato',0.034083,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('trava_sob_carga','memoria_instavel',0.147208,29,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('trava_sob_carga','memoria_insuficiente',0.034083,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('trava_sob_carga','placa_ou_capacitor',0.034083,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('trava_sob_carga','refrigeracao_insuficiente',0.034083,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('trava_sob_carga','sistema_corrompido',0.034083,0,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();
INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)
VALUES ('trava_sob_carga','software_conflitante',0.142132,28,1.0)
ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET
  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();

INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('congelamento_breve_repetido.disco_lento.v1','pt-BR','tecnico','Disco funcional porém lento — latência alta com SMART saudável.','Disco funcional porém lento — latência alta com SMART saudável. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('congelamento_breve_repetido.disco_lento.v1','pt-BR','cliente','Disco funcional porém lento — latência alta com SMART saudável.','O disco funciona, mas é lento para o que você faz. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('congelamento_breve_repetido.driver_incompativel.v1','pt-BR','tecnico','Driver incompatível ou defeituoso para o hardware presente.','Driver incompatível ou defeituoso para o hardware presente. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('congelamento_breve_repetido.driver_incompativel.v1','pt-BR','cliente','Driver incompatível ou defeituoso para o hardware presente.','Um programa de controle de peça está com defeito. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('congelamento_breve_repetido.gpu_falhando.v1','pt-BR','tecnico','Placa de vídeo instável — reinícios de driver ou erro de hardware.','Placa de vídeo instável — reinícios de driver ou erro de hardware. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('congelamento_breve_repetido.gpu_falhando.v1','pt-BR','cliente','Placa de vídeo instável — reinícios de driver ou erro de hardware.','A placa de vídeo está com problema. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('congelamento_breve_repetido.memoria_instavel.v1','pt-BR','tecnico','Memória instável — erro de leitura/escrita em RAM sob carga.','Memória instável — erro de leitura/escrita em RAM sob carga. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('congelamento_breve_repetido.memoria_instavel.v1','pt-BR','cliente','Memória instável — erro de leitura/escrita em RAM sob carga.','A memória do computador está com defeito. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('congelamento_breve_repetido.refrigeracao_insuficiente.v1','pt-BR','tecnico','Refrigeração insuficiente — dissipação abaixo do necessário para a carga.','Refrigeração insuficiente — dissipação abaixo do necessário para a carga. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('congelamento_breve_repetido.refrigeracao_insuficiente.v1','pt-BR','cliente','Refrigeração insuficiente — dissipação abaixo do necessário para a carga.','O computador está esquentando demais. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
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
VALUES ('corrupcao_de_dados.memoria_instavel.v1','pt-BR','tecnico','Memória instável — erro de leitura/escrita em RAM sob carga.','Memória instável — erro de leitura/escrita em RAM sob carga. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('corrupcao_de_dados.memoria_instavel.v1','pt-BR','cliente','Memória instável — erro de leitura/escrita em RAM sob carga.','A memória do computador está com defeito. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('corrupcao_de_dados.sistema_corrompido.v1','pt-BR','tecnico','Sistema de arquivos ou componentes do sistema corrompidos.','Sistema de arquivos ou componentes do sistema corrompidos. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('corrupcao_de_dados.sistema_corrompido.v1','pt-BR','cliente','Sistema de arquivos ou componentes do sistema corrompidos.','Arquivos do sistema estão danificados. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('desligamento_inesperado.alimentacao_instavel.v1','pt-BR','tecnico','Alimentação externa instável — rede elétrica fora da faixa.','Alimentação externa instável — rede elétrica fora da faixa. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('desligamento_inesperado.alimentacao_instavel.v1','pt-BR','cliente','Alimentação externa instável — rede elétrica fora da faixa.','A energia que chega ao computador está oscilando. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('desligamento_inesperado.bateria_degradada.v1','pt-BR','tecnico','Bateria com capacidade muito abaixo da nominal.','Bateria com capacidade muito abaixo da nominal. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('desligamento_inesperado.bateria_degradada.v1','pt-BR','cliente','Bateria com capacidade muito abaixo da nominal.','A bateria já não segura carga. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
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
VALUES ('desligamento_inesperado.fonte_falhando.v1','pt-BR','tecnico','Fonte de alimentação instável sob carga.','Fonte de alimentação instável sob carga. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('desligamento_inesperado.fonte_falhando.v1','pt-BR','cliente','Fonte de alimentação instável sob carga.','A fonte de energia do computador está falhando. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('desligamento_inesperado.gpu_falhando.v1','pt-BR','tecnico','Placa de vídeo instável — reinícios de driver ou erro de hardware.','Placa de vídeo instável — reinícios de driver ou erro de hardware. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('desligamento_inesperado.gpu_falhando.v1','pt-BR','cliente','Placa de vídeo instável — reinícios de driver ou erro de hardware.','A placa de vídeo está com problema. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
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
VALUES ('desligamento_inesperado.placa_ou_capacitor.v1','pt-BR','tecnico','Suspeita de falha na placa-mãe — não separável à distância.','Suspeita de falha na placa-mãe — não separável à distância. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('desligamento_inesperado.placa_ou_capacitor.v1','pt-BR','cliente','Suspeita de falha na placa-mãe — não separável à distância.','Pode ser um problema na placa; só dá para saber presencialmente. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
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
VALUES ('erro_de_dispositivo.disco_cheio.v1','pt-BR','tecnico','Disco sem espaço livre — sem folga para paginação, cache e temporários.','Disco sem espaço livre — sem folga para paginação, cache e temporários. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('erro_de_dispositivo.disco_cheio.v1','pt-BR','cliente','Disco sem espaço livre — sem folga para paginação, cache e temporários.','O disco está quase cheio, e isso deixa tudo mais devagar. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
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
VALUES ('erro_de_dispositivo.disco_desgastado.v1','pt-BR','tecnico','SSD com vida útil consumida — escrita restante abaixo do seguro.','SSD com vida útil consumida — escrita restante abaixo do seguro. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('erro_de_dispositivo.disco_desgastado.v1','pt-BR','cliente','SSD com vida útil consumida — escrita restante abaixo do seguro.','O disco está chegando ao fim da vida útil dele. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('erro_de_dispositivo.mau_contato.v1','pt-BR','tecnico','Suspeita de mau contato ou cabo — não separável à distância.','Suspeita de mau contato ou cabo — não separável à distância. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('erro_de_dispositivo.mau_contato.v1','pt-BR','cliente','Suspeita de mau contato ou cabo — não separável à distância.','Pode ser mau contato; só dá para verificar presencialmente. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_intermitente.ambiente_quente.v1','pt-BR','tecnico','Temperatura do ambiente acima do adequado para o equipamento.','Temperatura do ambiente acima do adequado para o equipamento. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_intermitente.ambiente_quente.v1','pt-BR','cliente','Temperatura do ambiente acima do adequado para o equipamento.','O lugar onde o computador fica está quente demais. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_intermitente.cpu_insuficiente.v1','pt-BR','tecnico','Processador insuficiente para a carga — uso sustentado no teto.','Processador insuficiente para a carga — uso sustentado no teto. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_intermitente.cpu_insuficiente.v1','pt-BR','cliente','Processador insuficiente para a carga — uso sustentado no teto.','O processador não dá conta do que você usa. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_intermitente.dentro_do_esperado.v1','pt-BR','tecnico','Equipamento operando dentro do esperado para a classe dele.','Equipamento operando dentro do esperado para a classe dele. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_intermitente.dentro_do_esperado.v1','pt-BR','cliente','Equipamento operando dentro do esperado para a classe dele.','O computador está funcionando como o esperado para o que ele é. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_intermitente.disco_cheio.v1','pt-BR','tecnico','Disco sem espaço livre — sem folga para paginação, cache e temporários.','Disco sem espaço livre — sem folga para paginação, cache e temporários. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_intermitente.disco_cheio.v1','pt-BR','cliente','Disco sem espaço livre — sem folga para paginação, cache e temporários.','O disco está quase cheio, e isso deixa tudo mais devagar. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_intermitente.driver_incompativel.v1','pt-BR','tecnico','Driver incompatível ou defeituoso para o hardware presente.','Driver incompatível ou defeituoso para o hardware presente. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_intermitente.driver_incompativel.v1','pt-BR','cliente','Driver incompatível ou defeituoso para o hardware presente.','Um programa de controle de peça está com defeito. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_intermitente.inicializacao_pesada.v1','pt-BR','tecnico','Inicialização carregada — muitos programas subindo com o sistema.','Inicialização carregada — muitos programas subindo com o sistema. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_intermitente.inicializacao_pesada.v1','pt-BR','cliente','Inicialização carregada — muitos programas subindo com o sistema.','Muita coisa abre sozinha quando o computador liga. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_intermitente.memoria_insuficiente.v1','pt-BR','tecnico','Memória insuficiente para a carga — uso no teto com paginação.','Memória insuficiente para a carga — uso no teto com paginação. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_intermitente.memoria_insuficiente.v1','pt-BR','cliente','Memória insuficiente para a carga — uso no teto com paginação.','O computador tem menos memória do que precisa para o que você usa. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_intermitente.processo_em_segundo_plano.v1','pt-BR','tecnico','Processo ou serviço em segundo plano consumindo recurso.','Processo ou serviço em segundo plano consumindo recurso. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_intermitente.processo_em_segundo_plano.v1','pt-BR','cliente','Processo ou serviço em segundo plano consumindo recurso.','Um programa trabalhando escondido está consumindo o computador. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_intermitente.rede_instavel.v1','pt-BR','tecnico','Rede instável — perda, latência ou saturação do enlace.','Rede instável — perda, latência ou saturação do enlace. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_intermitente.rede_instavel.v1','pt-BR','cliente','Rede instável — perda, latência ou saturação do enlace.','A conexão de rede está instável. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_intermitente.refrigeracao_insuficiente.v1','pt-BR','tecnico','Refrigeração insuficiente — dissipação abaixo do necessário para a carga.','Refrigeração insuficiente — dissipação abaixo do necessário para a carga. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_intermitente.refrigeracao_insuficiente.v1','pt-BR','cliente','Refrigeração insuficiente — dissipação abaixo do necessário para a carga.','O computador está esquentando demais. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_intermitente.software_conflitante.v1','pt-BR','tecnico','Software conflitante — programa ou serviço interferindo no sistema.','Software conflitante — programa ou serviço interferindo no sistema. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_intermitente.software_conflitante.v1','pt-BR','cliente','Software conflitante — programa ou serviço interferindo no sistema.','Um programa instalado está atrapalhando o sistema. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_nao_caracterizada.ambiente_quente.v1','pt-BR','tecnico','Temperatura do ambiente acima do adequado para o equipamento.','Temperatura do ambiente acima do adequado para o equipamento. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_nao_caracterizada.ambiente_quente.v1','pt-BR','cliente','Temperatura do ambiente acima do adequado para o equipamento.','O lugar onde o computador fica está quente demais. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_nao_caracterizada.cpu_insuficiente.v1','pt-BR','tecnico','Processador insuficiente para a carga — uso sustentado no teto.','Processador insuficiente para a carga — uso sustentado no teto. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_nao_caracterizada.cpu_insuficiente.v1','pt-BR','cliente','Processador insuficiente para a carga — uso sustentado no teto.','O processador não dá conta do que você usa. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_nao_caracterizada.dentro_do_esperado.v1','pt-BR','tecnico','Equipamento operando dentro do esperado para a classe dele.','Equipamento operando dentro do esperado para a classe dele. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_nao_caracterizada.dentro_do_esperado.v1','pt-BR','cliente','Equipamento operando dentro do esperado para a classe dele.','O computador está funcionando como o esperado para o que ele é. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_nao_caracterizada.disco_cheio.v1','pt-BR','tecnico','Disco sem espaço livre — sem folga para paginação, cache e temporários.','Disco sem espaço livre — sem folga para paginação, cache e temporários. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_nao_caracterizada.disco_cheio.v1','pt-BR','cliente','Disco sem espaço livre — sem folga para paginação, cache e temporários.','O disco está quase cheio, e isso deixa tudo mais devagar. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_nao_caracterizada.disco_degradado.v1','pt-BR','tecnico','Disco degradado — superfície, controladora ou interface falhando.','Disco degradado — superfície, controladora ou interface falhando. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_nao_caracterizada.disco_degradado.v1','pt-BR','cliente','Disco degradado — superfície, controladora ou interface falhando.','O disco (onde ficam seus arquivos) está falhando. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_nao_caracterizada.disco_desgastado.v1','pt-BR','tecnico','SSD com vida útil consumida — escrita restante abaixo do seguro.','SSD com vida útil consumida — escrita restante abaixo do seguro. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_nao_caracterizada.disco_desgastado.v1','pt-BR','cliente','SSD com vida útil consumida — escrita restante abaixo do seguro.','O disco está chegando ao fim da vida útil dele. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_nao_caracterizada.disco_lento.v1','pt-BR','tecnico','Disco funcional porém lento — latência alta com SMART saudável.','Disco funcional porém lento — latência alta com SMART saudável. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_nao_caracterizada.disco_lento.v1','pt-BR','cliente','Disco funcional porém lento — latência alta com SMART saudável.','O disco funciona, mas é lento para o que você faz. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_nao_caracterizada.driver_incompativel.v1','pt-BR','tecnico','Driver incompatível ou defeituoso para o hardware presente.','Driver incompatível ou defeituoso para o hardware presente. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_nao_caracterizada.driver_incompativel.v1','pt-BR','cliente','Driver incompatível ou defeituoso para o hardware presente.','Um programa de controle de peça está com defeito. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_nao_caracterizada.inicializacao_pesada.v1','pt-BR','tecnico','Inicialização carregada — muitos programas subindo com o sistema.','Inicialização carregada — muitos programas subindo com o sistema. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_nao_caracterizada.inicializacao_pesada.v1','pt-BR','cliente','Inicialização carregada — muitos programas subindo com o sistema.','Muita coisa abre sozinha quando o computador liga. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_nao_caracterizada.memoria_insuficiente.v1','pt-BR','tecnico','Memória insuficiente para a carga — uso no teto com paginação.','Memória insuficiente para a carga — uso no teto com paginação. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_nao_caracterizada.memoria_insuficiente.v1','pt-BR','cliente','Memória insuficiente para a carga — uso no teto com paginação.','O computador tem menos memória do que precisa para o que você usa. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_nao_caracterizada.processo_em_segundo_plano.v1','pt-BR','tecnico','Processo ou serviço em segundo plano consumindo recurso.','Processo ou serviço em segundo plano consumindo recurso. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_nao_caracterizada.processo_em_segundo_plano.v1','pt-BR','cliente','Processo ou serviço em segundo plano consumindo recurso.','Um programa trabalhando escondido está consumindo o computador. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_nao_caracterizada.rede_instavel.v1','pt-BR','tecnico','Rede instável — perda, latência ou saturação do enlace.','Rede instável — perda, latência ou saturação do enlace. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_nao_caracterizada.rede_instavel.v1','pt-BR','cliente','Rede instável — perda, latência ou saturação do enlace.','A conexão de rede está instável. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_nao_caracterizada.rede_insuficiente.v1','pt-BR','tecnico','Banda de rede abaixo do necessário para o uso.','Banda de rede abaixo do necessário para o uso. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_nao_caracterizada.rede_insuficiente.v1','pt-BR','cliente','Banda de rede abaixo do necessário para o uso.','A internet contratada é menor do que o uso pede. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_nao_caracterizada.refrigeracao_insuficiente.v1','pt-BR','tecnico','Refrigeração insuficiente — dissipação abaixo do necessário para a carga.','Refrigeração insuficiente — dissipação abaixo do necessário para a carga. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_nao_caracterizada.refrigeracao_insuficiente.v1','pt-BR','cliente','Refrigeração insuficiente — dissipação abaixo do necessário para a carga.','O computador está esquentando demais. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_nao_caracterizada.software_conflitante.v1','pt-BR','tecnico','Software conflitante — programa ou serviço interferindo no sistema.','Software conflitante — programa ou serviço interferindo no sistema. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_nao_caracterizada.software_conflitante.v1','pt-BR','cliente','Software conflitante — programa ou serviço interferindo no sistema.','Um programa instalado está atrapalhando o sistema. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_profunda.cpu_insuficiente.v1','pt-BR','tecnico','Processador insuficiente para a carga — uso sustentado no teto.','Processador insuficiente para a carga — uso sustentado no teto. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_profunda.cpu_insuficiente.v1','pt-BR','cliente','Processador insuficiente para a carga — uso sustentado no teto.','O processador não dá conta do que você usa. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_profunda.dentro_do_esperado.v1','pt-BR','tecnico','Equipamento operando dentro do esperado para a classe dele.','Equipamento operando dentro do esperado para a classe dele. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_profunda.dentro_do_esperado.v1','pt-BR','cliente','Equipamento operando dentro do esperado para a classe dele.','O computador está funcionando como o esperado para o que ele é. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_profunda.disco_cheio.v1','pt-BR','tecnico','Disco sem espaço livre — sem folga para paginação, cache e temporários.','Disco sem espaço livre — sem folga para paginação, cache e temporários. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_profunda.disco_cheio.v1','pt-BR','cliente','Disco sem espaço livre — sem folga para paginação, cache e temporários.','O disco está quase cheio, e isso deixa tudo mais devagar. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_profunda.disco_degradado.v1','pt-BR','tecnico','Disco degradado — superfície, controladora ou interface falhando.','Disco degradado — superfície, controladora ou interface falhando. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_profunda.disco_degradado.v1','pt-BR','cliente','Disco degradado — superfície, controladora ou interface falhando.','O disco (onde ficam seus arquivos) está falhando. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_profunda.disco_desgastado.v1','pt-BR','tecnico','SSD com vida útil consumida — escrita restante abaixo do seguro.','SSD com vida útil consumida — escrita restante abaixo do seguro. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_profunda.disco_desgastado.v1','pt-BR','cliente','SSD com vida útil consumida — escrita restante abaixo do seguro.','O disco está chegando ao fim da vida útil dele. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_profunda.disco_lento.v1','pt-BR','tecnico','Disco funcional porém lento — latência alta com SMART saudável.','Disco funcional porém lento — latência alta com SMART saudável. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_profunda.disco_lento.v1','pt-BR','cliente','Disco funcional porém lento — latência alta com SMART saudável.','O disco funciona, mas é lento para o que você faz. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_profunda.memoria_insuficiente.v1','pt-BR','tecnico','Memória insuficiente para a carga — uso no teto com paginação.','Memória insuficiente para a carga — uso no teto com paginação. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_profunda.memoria_insuficiente.v1','pt-BR','cliente','Memória insuficiente para a carga — uso no teto com paginação.','O computador tem menos memória do que precisa para o que você usa. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_profunda.processo_em_segundo_plano.v1','pt-BR','tecnico','Processo ou serviço em segundo plano consumindo recurso.','Processo ou serviço em segundo plano consumindo recurso. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_profunda.processo_em_segundo_plano.v1','pt-BR','cliente','Processo ou serviço em segundo plano consumindo recurso.','Um programa trabalhando escondido está consumindo o computador. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_profunda.rede_instavel.v1','pt-BR','tecnico','Rede instável — perda, latência ou saturação do enlace.','Rede instável — perda, latência ou saturação do enlace. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_profunda.rede_instavel.v1','pt-BR','cliente','Rede instável — perda, latência ou saturação do enlace.','A conexão de rede está instável. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_profunda.rede_insuficiente.v1','pt-BR','tecnico','Banda de rede abaixo do necessário para o uso.','Banda de rede abaixo do necessário para o uso. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('lentidao_profunda.rede_insuficiente.v1','pt-BR','cliente','Banda de rede abaixo do necessário para o uso.','A internet contratada é menor do que o uso pede. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('nao_inicializa.alimentacao_instavel.v1','pt-BR','tecnico','Alimentação externa instável — rede elétrica fora da faixa.','Alimentação externa instável — rede elétrica fora da faixa. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('nao_inicializa.alimentacao_instavel.v1','pt-BR','cliente','Alimentação externa instável — rede elétrica fora da faixa.','A energia que chega ao computador está oscilando. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('nao_inicializa.disco_cheio.v1','pt-BR','tecnico','Disco sem espaço livre — sem folga para paginação, cache e temporários.','Disco sem espaço livre — sem folga para paginação, cache e temporários. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('nao_inicializa.disco_cheio.v1','pt-BR','cliente','Disco sem espaço livre — sem folga para paginação, cache e temporários.','O disco está quase cheio, e isso deixa tudo mais devagar. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
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
VALUES ('nao_inicializa.fonte_falhando.v1','pt-BR','tecnico','Fonte de alimentação instável sob carga.','Fonte de alimentação instável sob carga. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('nao_inicializa.fonte_falhando.v1','pt-BR','cliente','Fonte de alimentação instável sob carga.','A fonte de energia do computador está falhando. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('nao_inicializa.mau_contato.v1','pt-BR','tecnico','Suspeita de mau contato ou cabo — não separável à distância.','Suspeita de mau contato ou cabo — não separável à distância. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('nao_inicializa.mau_contato.v1','pt-BR','cliente','Suspeita de mau contato ou cabo — não separável à distância.','Pode ser mau contato; só dá para verificar presencialmente. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
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
VALUES ('nao_inicializa.placa_ou_capacitor.v1','pt-BR','tecnico','Suspeita de falha na placa-mãe — não separável à distância.','Suspeita de falha na placa-mãe — não separável à distância. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('nao_inicializa.placa_ou_capacitor.v1','pt-BR','cliente','Suspeita de falha na placa-mãe — não separável à distância.','Pode ser um problema na placa; só dá para saber presencialmente. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('nao_inicializa.sistema_corrompido.v1','pt-BR','tecnico','Sistema de arquivos ou componentes do sistema corrompidos.','Sistema de arquivos ou componentes do sistema corrompidos. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('nao_inicializa.sistema_corrompido.v1','pt-BR','cliente','Sistema de arquivos ou componentes do sistema corrompidos.','Arquivos do sistema estão danificados. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('superaquecimento.ambiente_quente.v1','pt-BR','tecnico','Temperatura do ambiente acima do adequado para o equipamento.','Temperatura do ambiente acima do adequado para o equipamento. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('superaquecimento.ambiente_quente.v1','pt-BR','cliente','Temperatura do ambiente acima do adequado para o equipamento.','O lugar onde o computador fica está quente demais. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
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
VALUES ('trava_sob_carga.driver_incompativel.v1','pt-BR','tecnico','Driver incompatível ou defeituoso para o hardware presente.','Driver incompatível ou defeituoso para o hardware presente. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('trava_sob_carga.driver_incompativel.v1','pt-BR','cliente','Driver incompatível ou defeituoso para o hardware presente.','Um programa de controle de peça está com defeito. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('trava_sob_carga.fonte_falhando.v1','pt-BR','tecnico','Fonte de alimentação instável sob carga.','Fonte de alimentação instável sob carga. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('trava_sob_carga.fonte_falhando.v1','pt-BR','cliente','Fonte de alimentação instável sob carga.','A fonte de energia do computador está falhando. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('trava_sob_carga.gpu_falhando.v1','pt-BR','tecnico','Placa de vídeo instável — reinícios de driver ou erro de hardware.','Placa de vídeo instável — reinícios de driver ou erro de hardware. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('trava_sob_carga.gpu_falhando.v1','pt-BR','cliente','Placa de vídeo instável — reinícios de driver ou erro de hardware.','A placa de vídeo está com problema. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('trava_sob_carga.mau_contato.v1','pt-BR','tecnico','Suspeita de mau contato ou cabo — não separável à distância.','Suspeita de mau contato ou cabo — não separável à distância. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('trava_sob_carga.mau_contato.v1','pt-BR','cliente','Suspeita de mau contato ou cabo — não separável à distância.','Pode ser mau contato; só dá para verificar presencialmente. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
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
VALUES ('trava_sob_carga.memoria_insuficiente.v1','pt-BR','tecnico','Memória insuficiente para a carga — uso no teto com paginação.','Memória insuficiente para a carga — uso no teto com paginação. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('trava_sob_carga.memoria_insuficiente.v1','pt-BR','cliente','Memória insuficiente para a carga — uso no teto com paginação.','O computador tem menos memória do que precisa para o que você usa. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('trava_sob_carga.placa_ou_capacitor.v1','pt-BR','tecnico','Suspeita de falha na placa-mãe — não separável à distância.','Suspeita de falha na placa-mãe — não separável à distância. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('trava_sob_carga.placa_ou_capacitor.v1','pt-BR','cliente','Suspeita de falha na placa-mãe — não separável à distância.','Pode ser um problema na placa; só dá para saber presencialmente. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('trava_sob_carga.refrigeracao_insuficiente.v1','pt-BR','tecnico','Refrigeração insuficiente — dissipação abaixo do necessário para a carga.','Refrigeração insuficiente — dissipação abaixo do necessário para a carga. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('trava_sob_carga.refrigeracao_insuficiente.v1','pt-BR','cliente','Refrigeração insuficiente — dissipação abaixo do necessário para a carga.','O computador está esquentando demais. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('trava_sob_carga.sistema_corrompido.v1','pt-BR','tecnico','Sistema de arquivos ou componentes do sistema corrompidos.','Sistema de arquivos ou componentes do sistema corrompidos. Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET
  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,
  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();
INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)
VALUES ('trava_sob_carga.sistema_corrompido.v1','pt-BR','cliente','Sistema de arquivos ou componentes do sistema corrompidos.','Arquivos do sistema estão danificados. Fale com um tecnico.','["valor_medido","limiar_esperado","probabilidade"]',1,'corpusderiva/ontologia@superuser-dump','corpusderiva/ontologia@superuser-dump', now())
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

COMMIT;
