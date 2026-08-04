-- A migração 0033 só cobriu os supervisores existentes naquele momento.
-- CreateTechnician nunca criou supervisor_profiles automaticamente até agora,
-- então todo supervisor criado depois de 0033 ficou fora da Fila A. Este
-- backfill cobre os que já existem hoje; o código passa a criar o perfil na
-- própria criação do supervisor a partir de agora.
INSERT INTO supervisor_profiles(technician_id, rating_avg, rating_count)
SELECT id, 5.00, 0 FROM technicians WHERE role='supervisor'
ON CONFLICT (technician_id) DO NOTHING;
