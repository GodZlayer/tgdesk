-- Conjunto de treino por simulacao. GERADO por cmd/treinoset.
BEGIN;
DELETE FROM training_example WHERE origem='simulado_corpus';

INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','0044d1a9-9184-47e8-b28c-11b2e9ad46f7','lentidao_persistente','disco_degradado','{"erro_io_log":{"literal":"UDMA_CRC_Error_Count -OSRCK 200 200 000 - 0","valor":0},"smart_geral":{"literal":"Power_On_Hours -O--CK 087 087 000 - 11535","valor":11535},"smart_reallocated":{"literal":"Reallocated_Sector_Ct PO--CK 100 100 036 - 0","valor":0}}',false,'treino');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','0db4e3ee-51c7-44d6-b144-91c30fb25d66','desligamento_inesperado','disco_degradado','{"erro_sistema_log":{"literal":"Log Name: System Source: Microsoft-Windows-Kernel-Power Date: 31/10/2011 4:29:53 PM Event ID: 41 Task Category: (63) Level: Critical","valor":41}}',false,'treino');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','1168c7a3-3c96-481d-a3ed-a019449f8d5c','erro_de_dispositivo','disco_degradado','{"temperatura":{"literal":"77 Celsius","valor":77}}',false,'validacao');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','167b652c-e8f7-4814-8e37-b418f03dbb91','desligamento_inesperado','driver_incompativel','{"bugcheck":{"literal":"BUGCHECK_STR: 0x9F"}}',false,'treino');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','17f23bcf-82ed-43de-a0a4-a46f899b082f','desligamento_inesperado','driver_incompativel','{"bugcheck":{"literal":"BUGCHECK_STR: 0x9F"}}',false,'treino');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','28a40b12-6901-499b-a052-b4484da15e90','desligamento_inesperado','memoria_instavel','{"bugcheck":{"literal":"BugCheck 9C"}}',false,'treino');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','2a03f95a-b918-449f-899e-ac67ad938b2a','lentidao_persistente','disco_degradado','{"erro_io_log":{"literal":"Reported_Uncorrect 0x0032 100 100 000 Old_age Always - 0","valor":0}}',false,'validacao');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','3bc89687-4271-4537-ac10-616cff9ce1d6','erro_de_dispositivo','disco_degradado','{"temperatura":{"literal":"82 Celsius","valor":82}}',false,'validacao');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','403385fa-891f-4039-b7a2-4fe3b122b130','desligamento_inesperado','memoria_instavel','{"bugcheck":{"literal":"EXCEPTION_ACCESS_VIOLATION (0xc0000005)"}}',false,'treino');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','43ec2ad0-01f8-48ee-8130-a99f04114831','erro_de_dispositivo','disco_degradado','{"temperatura":{"literal":"84 Celsius","valor":84}}',false,'validacao');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','48779df7-67b3-4b1b-948f-322d3db301eb','desligamento_inesperado','driver_incompativel','{"bugcheck":{"literal":"BUGCHECK_STR: 0x9F"}}',false,'treino');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','4fef3943-cdb5-428c-a908-442c11ceccfc','desligamento_inesperado','driver_incompativel','{"bugcheck":{"literal":"BUGCHECK_STR: 0x117"}}',false,'validacao');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','52f1da2e-2db1-4f8e-9753-4dd31481996a','erro_de_dispositivo','disco_degradado','{"temperatura":{"literal":"40 C","valor":40}}',false,'treino');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','53ec5808-77a3-4a32-bb0a-c1ff4fc9290e','lentidao_persistente','disco_degradado','{"bugcheck":{"literal":"Stop_Count 0x0032"},"erro_io_log":{"literal":"UDMA_CRC_Error_Count 0x0032 200 200 000 Old_age Always - 0","valor":0},"smart_geral":{"literal":"Power_On_Hours 0x0032 091 091 000 Old_age Always - 7047","valor":7047},"smart_pending":{"literal":"Current_Pending_Sector 0x0032 200 200 000 Old_age Always - 0","valor":0},"smart_reallocated":{"literal":"Reallocated_Sector_Ct 0x0033 200 200 140 Pre-fail Always - 0","valor":0}}',false,'treino');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','5cf39e2a-5268-4022-acdd-831be5ef479b','desligamento_inesperado','alimentacao_instavel','{"bugcheck":{"literal":"bugcheck was: 0x00000113"}}',false,'validacao');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','60d0f106-3d84-44c8-8673-26c4c4f541d0','desligamento_inesperado','memoria_instavel','{"bugcheck":{"literal":"BUGCHECK_STR: 0x3B"}}',false,'validacao');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','6309eacb-b7a3-4ea1-b1de-f91810a8099f','desligamento_inesperado','driver_incompativel','{"bugcheck":{"literal":"BugcheckOnTimeout+0x24"}}',false,'treino');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','685fca44-e98a-4ac6-b505-26493d01dd29','desligamento_inesperado','driver_incompativel','{"bugcheck":{"literal":"BUGCHECK_STR: 0xA"}}',false,'treino');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','6978ace2-f91d-42b4-ac0b-04df2c3cf9ec','desligamento_inesperado','disco_degradado','{"bugcheck":{"literal":"BSOD,14544"}}',false,'treino');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','6c08f8f6-7502-407c-a86f-3448ede184cf','desligamento_inesperado','software_conflitante','{"bugcheck":{"literal":"STOP 0x0000007F"}}',false,'treino');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','759a8722-75f2-4e2b-b578-2d7e02f322d4','lentidao_persistente','disco_degradado','{"bugcheck":{"literal":"Stop_Count 0x0032"},"erro_io_log":{"literal":"UDMA_CRC_Error_Count 0x003e 200 200 000 Old_age Always - 0","valor":0},"smart_geral":{"literal":"Power_On_Hours 0x0032 090 090 000 Old_age Always - 8967","valor":8967},"smart_pending":{"literal":"Current_Pending_Sector 0x0012 100 100 000 Old_age Always - 0","valor":0},"smart_reallocated":{"literal":"Reallocated_Sector_Ct 0x0033 051 051 036 Pre-fail Always - 2013","valor":2013}}',false,'treino');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','7644378e-f7e6-4945-a452-4b423b630205','desligamento_inesperado','driver_incompativel','{"bugcheck":{"literal":"BUGCHECK_STR: 0x9F"}}',false,'validacao');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','77ae3070-d3f6-41f4-9907-fedd21c42649','desligamento_inesperado','driver_incompativel','{"bugcheck":{"literal":"BUGCHECK_STR: 0x9F"}}',false,'treino');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','79276cc9-81e6-454b-905e-a274f419363b','desligamento_inesperado','alimentacao_instavel','{"bugcheck":{"literal":"stop control. The reason specified was: 0x40030011"}}',false,'validacao');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','7b98a8ff-eba6-4374-9ad4-671ec0604820','desligamento_inesperado','driver_incompativel','{"bugcheck":{"literal":"BUGCHECK_STR: 0x9F"}}',false,'validacao');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','81d27611-ec64-4a4b-8632-8a513cb3f555','desligamento_inesperado','driver_incompativel','{"bugcheck":{"literal":"BUGCHECK_STR: 0xD4"}}',false,'treino');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','8c4379f8-21a8-4251-9ff8-2d78fa974289','corrupcao_de_dados','disco_degradado','{"bugcheck":{"literal":"Stop_Count 0x0032"},"erro_io_log":{"literal":"UDMA_CRC_Error_Count 0x003e 200 200 000 Old_age Always - 0","valor":0},"smart_geral":{"literal":"Power_On_Hours 0x0032 100 100 000 Old_age Always - 258518376513933","valor":258518376513933},"smart_pending":{"literal":"Current_Pending_Sector 0x0012 100 100 000 Old_age Always - 0","valor":0},"smart_reallocated":{"literal":"Reallocated_Sector_Ct 0x0033 100 100 036 Pre-fail Always - 0","valor":0}}',false,'treino');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','99da9bd4-069a-4b76-a10f-9e5d60509a72','corrupcao_de_dados','disco_degradado','{"smart_geral":{"literal":"power_on_hours : 478","valor":478},"temperatura":{"literal":"49 C","valor":49}}',false,'validacao');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','9ac949d5-b339-4c62-b014-7ea5cc166fb6','trava_sob_carga','disco_degradado','{"bugcheck":{"literal":"BUGCHECK_P1: 18"}}',false,'treino');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','a193bc9c-3c7c-4683-9c7c-04e78993428f','desligamento_inesperado','driver_incompativel','{"erro_sistema_log":{"literal":"Log Name: Application Source: ESENT Date: 07/06/2012 16.01.00 Event ID: 490 Task Category: General Level: Error","valor":490}}',false,'treino');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','a530b8fa-8aa2-427f-bd56-23b9ced053fe','erro_de_dispositivo','disco_degradado','{"temperatura":{"literal":"84 Celsius","valor":84}}',false,'treino');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','a6d57248-4e4e-40a2-9033-40ad5086c4b1','desligamento_inesperado','driver_incompativel','{"bugcheck":{"literal":"BUGCHECK_STR: 0xD1"}}',false,'validacao');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','a81aad2a-adec-4d22-a2cd-f07c3fa80269','erro_de_dispositivo','disco_degradado','{"temperatura":{"literal":"110 Celsius","valor":110}}',false,'treino');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','a88eb5cd-27a8-4b07-a4ac-a1992a38b7c4','desligamento_inesperado','driver_incompativel','{"bugcheck":{"literal":"BUGCHECK_STR: 0x9F"}}',false,'treino');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','b3aff811-c720-47de-beca-d0958de13c98','trava_sob_carga','disco_degradado','{"bugcheck":{"literal":"BugCheck 1A"}}',false,'treino');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','b41cf8c1-354c-4914-af3a-77a646b74704','desligamento_inesperado','driver_incompativel','{"bugcheck":{"literal":"BUGCHECK_STR: 0x9F"}}',false,'validacao');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','b5578aa8-8393-458b-a8c0-06508d618725','desligamento_inesperado','driver_incompativel','{"bugcheck":{"literal":"BUGCHECK_STR: 0x116"}}',false,'treino');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','c4f6684c-6cab-4ed7-b5cc-59c190e13aa9','superaquecimento','refrigeracao_insuficiente','{"temperatura":{"literal":"128 C","valor":128}}',false,'treino');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','c89786be-b7df-4471-9c0b-5fa66bb3f940','desligamento_inesperado','driver_incompativel','{"bugcheck":{"literal":"BUGCHECK_STR: 0x9F"}}',false,'treino');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','d2de6226-9b35-4bc2-b07f-7500d177057f','erro_de_dispositivo','disco_degradado','{"temperatura":{"literal":"39 C","valor":39}}',false,'treino');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','dd383119-719a-40c4-9854-ff01312b1350','superaquecimento','refrigeracao_insuficiente','{"erro_sistema_log":{"literal":"Log Name: System Source: Microsoft-Windows-Kernel-Power Date: 11/10/2013 12:05:40 Event ID: 41 Task Category: (63) Level: Critical","valor":41}}',false,'validacao');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','e1ac7444-6a07-4170-a318-355052f2232d','desligamento_inesperado','driver_incompativel','{"bugcheck":{"literal":"BugCheckIfAppropriate+0x3c"}}',false,'treino');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','ebdc08d9-12b9-46b7-94db-9af358deb408','desligamento_inesperado','driver_incompativel','{"erro_sistema_log":{"literal":"Log Name: System Source: Microsoft-Windows-DriverFrameworks-UserMode Date: 28/11/2018 16:34:44 Event ID: 10111 Task Category: User-mode Driver problems. Level: Critical","valor":10111}}',false,'treino');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','f5cbfa55-95e4-4d96-b914-b738bb020394','desligamento_inesperado','driver_incompativel','{"bugcheck":{"literal":"BugCheck 9F"}}',false,'treino');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','f7365e31-d088-4e10-ab61-f4e098ff5854','lentidao_persistente','disco_degradado','{"erro_io_log":{"literal":"UDMA_CRC_Error_Count 0x0032 100 100 --- Old_age Always - 0","valor":0},"smart_geral":{"literal":"Power_On_Hours 0x0032 100 100 --- Old_age Always - 519","valor":519},"smart_reallocated":{"literal":"Reallocated_Sector_Ct 0x0032 100 100 --- Old_age Always - 0","valor":0}}',false,'validacao');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','fceb985f-c520-4139-82a6-1d71ed155ad4','corrupcao_de_dados','memoria_instavel','{"bugcheck":{"literal":"BSOD: 0x000000F4"}}',false,'validacao');
INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)
VALUES ('simulado_corpus','ff6d4d99-d565-4d02-891d-e50c9481a06b','desligamento_inesperado','driver_incompativel','{"bugcheck":{"literal":"BugCheckDispatch+0x69"}}',false,'treino');

COMMIT;
