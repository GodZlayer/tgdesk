-- O limite de ocupação é do CONTROLADOR, não da porcentagem.
--
-- A linha genérica de 85% tratava todo disco do mundo igual, e o parque a
-- desmente: uma máquina a 98,3% responde em 0,73 ms sob carga enquanto outra a
-- 93,7% desaba para 577 ms. O que muda entre as duas não é a ocupação — é o
-- controlador ter ou não cache próprio para a tabela de mapeamento.
--
-- Sem cache DRAM, cada escrita com o disco cheio obriga o controlador a buscar
-- o mapeamento no próprio flash e a reorganizar blocos sem espaço de manobra.
-- Por isso o piso desses discos é bem mais alto que o dos demais.
INSERT INTO component_reference
    (classe, barramento, midia, metrica, valor_esperado, piso_pct, especificidade, fonte, observacao)
VALUES
    ('disco','NVMe','SSD','ocupacao_maxima_pct', 90, 100, 2,
     'faixa de classe (NVMe com cache proprio)',
     'controlador com DRAM mantem a tabela de mapeamento em memoria e tolera ocupacao mais alta'),
    ('disco','SATA','SSD','ocupacao_maxima_pct', 80, 100, 2,
     'faixa de classe (SATA SSD de consumo)',
     'sem cache DRAM o controlador busca o mapeamento no flash; a folga precisa ser maior'),
    ('disco','SATA','HDD','ocupacao_maxima_pct', 90, 100, 2,
     'faixa de classe (disco mecanico)',
     'disco mecanico nao reorganiza blocos; a ocupacao pesa por fragmentacao, nao por controlador')
ON CONFLICT DO NOTHING;
