-- TGDesk 1.1.1: every supervisor starts at 5.00 and participates in Fila A.
INSERT INTO supervisor_profiles(technician_id, rating_avg, rating_count)
SELECT id, 5.00, 0 FROM technicians WHERE role='supervisor'
ON CONFLICT (technician_id) DO NOTHING;

