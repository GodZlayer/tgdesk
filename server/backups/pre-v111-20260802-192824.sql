--
-- PostgreSQL database dump
--

\restrict JchEP9CfNex3E7qLAg9TUp7aJpgb3XytXrGnlbzY5anmFsDgNBtPXu7W5AXGWTl

-- Dumped from database version 16.14
-- Dumped by pg_dump version 16.14

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: assign_network_cidr(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assign_network_cidr() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.cidr_octet IS NULL THEN
        NEW.cidr_octet := nextval('network_cidr_octet_seq');
    END IF;
    IF NEW.cidr_virtual IS NULL THEN
        NEW.cidr_virtual := '10.70.' || NEW.cidr_octet || '.0/24';
    END IF;
    RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: admin_actions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.admin_actions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    actor_id uuid,
    tipo text NOT NULL,
    alvo_id uuid,
    detalhes jsonb,
    "timestamp" timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT admin_actions_tipo_check CHECK ((tipo = ANY (ARRAY['suspender_tecnico'::text, 'suspender_rede'::text, 'suspender_dispositivo'::text, 'suspender_organizacao'::text, 'vinculacao'::text, 'reativacao'::text, 'resume_tecnico'::text, 'resume_rede'::text, 'resume_dispositivo'::text, 'resume_organizacao'::text, 'wake'::text, 'delete_organizacao'::text, 'delete_rede'::text, 'delete_tecnico'::text, 'acesso_remoto'::text, 'recusar_dispositivo_guest'::text])))
);


--
-- Name: alerts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.alerts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    device_id uuid NOT NULL,
    tipo text NOT NULL,
    severidade text NOT NULL,
    mensagem text NOT NULL,
    resolvido boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT alerts_severidade_check CHECK ((severidade = ANY (ARRAY['info'::text, 'aviso'::text, 'critico'::text])))
);


--
-- Name: device_networks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.device_networks (
    device_id uuid NOT NULL,
    network_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: devices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.devices (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    network_id uuid,
    hostname text NOT NULL,
    mac text,
    wg_pubkey text,
    role text DEFAULT 'host'::text NOT NULL,
    state text DEFAULT 'guest'::text NOT NULL,
    pairing_code text,
    device_token text DEFAULT encode(public.gen_random_bytes(24), 'hex'::text) NOT NULL,
    last_seen_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    wg_virtual_ip text,
    rustdesk_id text,
    display_name text,
    suspension_scope text,
    control_technician_id uuid,
    subnetwork_id uuid,
    CONSTRAINT devices_role_check CHECK ((role = ANY (ARRAY['host'::text, 'tecnico'::text]))),
    CONSTRAINT devices_state_check CHECK ((state = ANY (ARRAY['guest'::text, 'ativo'::text, 'suspenso'::text]))),
    CONSTRAINT devices_suspension_scope_check CHECK ((suspension_scope = ANY (ARRAY['device'::text, 'network'::text, 'organization'::text, 'technician'::text])))
);


--
-- Name: diagnostic_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.diagnostic_runs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    device_id uuid NOT NULL,
    requested_by uuid,
    status text DEFAULT 'queued'::text NOT NULL,
    tests jsonb DEFAULT '[]'::jsonb NOT NULL,
    progress integer DEFAULT 0 NOT NULL,
    current_test text,
    results jsonb DEFAULT '[]'::jsonb NOT NULL,
    error text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    started_at timestamp with time zone,
    finished_at timestamp with time zone,
    CONSTRAINT diagnostic_runs_progress_check CHECK (((progress >= 0) AND (progress <= 100))),
    CONSTRAINT diagnostic_runs_status_check CHECK ((status = ANY (ARRAY['queued'::text, 'running'::text, 'completed'::text, 'failed'::text, 'cancelled'::text])))
);


--
-- Name: network_cidr_octet_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.network_cidr_octet_seq
    START WITH 2
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: networks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.networks (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    name text NOT NULL,
    cidr_virtual text,
    status text DEFAULT 'ativa'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    cidr_octet integer,
    next_host_octet integer DEFAULT 2 NOT NULL,
    suspension_scope text,
    created_by_technician_id uuid,
    CONSTRAINT networks_status_check CHECK ((status = ANY (ARRAY['ativa'::text, 'suspensa'::text]))),
    CONSTRAINT networks_suspension_scope_check CHECK ((suspension_scope = ANY (ARRAY['network'::text, 'organization'::text, 'technician'::text])))
);


--
-- Name: organizations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organizations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    status text DEFAULT 'ativa'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    owner_technician_id uuid,
    suspension_scope text,
    CONSTRAINT organizations_status_check CHECK ((status = ANY (ARRAY['ativa'::text, 'suspensa'::text]))),
    CONSTRAINT organizations_suspension_scope_check CHECK ((suspension_scope = ANY (ARRAY['organization'::text, 'technician'::text])))
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    name text NOT NULL,
    applied_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sessions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    device_id uuid NOT NULL,
    technician_id uuid NOT NULL,
    tipo text NOT NULL,
    inicio timestamp with time zone DEFAULT now() NOT NULL,
    fim timestamp with time zone,
    CONSTRAINT sessions_tipo_check CHECK ((tipo = ANY (ARRAY['tela'::text, 'usb'::text])))
);


--
-- Name: subnetworks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subnetworks (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    network_id uuid NOT NULL,
    name text NOT NULL,
    status text DEFAULT 'ativa'::text NOT NULL,
    created_by_technician_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT subnetworks_status_check CHECK ((status = ANY (ARRAY['ativa'::text, 'suspensa'::text])))
);


--
-- Name: technician_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.technician_assignments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    technician_id uuid NOT NULL,
    organization_id uuid,
    network_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT technician_assignments_check CHECK (((organization_id IS NOT NULL) OR (network_id IS NOT NULL)))
);


--
-- Name: technician_enrollment_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.technician_enrollment_keys (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    technician_id uuid NOT NULL,
    secret_hash bytea NOT NULL,
    expires_at timestamp with time zone,
    consumed_at timestamp with time zone,
    consumed_machine_id text,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: technician_host_octet_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.technician_host_octet_seq
    START WITH 2
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: technician_machine_credentials; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.technician_machine_credentials (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    technician_id uuid NOT NULL,
    machine_id text NOT NULL,
    credential_hash bytea NOT NULL,
    status text DEFAULT 'ativo'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    last_used_at timestamp with time zone,
    control_role text DEFAULT 'tecnico'::text NOT NULL,
    machine_fingerprint text NOT NULL,
    CONSTRAINT technician_machine_credentials_control_role_check CHECK ((control_role = ANY (ARRAY['super_admin'::text, 'tecnico'::text]))),
    CONSTRAINT technician_machine_credentials_status_check CHECK ((status = ANY (ARRAY['ativo'::text, 'revogado'::text])))
);


--
-- Name: technicians; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.technicians (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    username text NOT NULL,
    password_hash text NOT NULL,
    role text NOT NULL,
    created_via_env boolean DEFAULT false NOT NULL,
    status text DEFAULT 'ativo'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    wg_pubkey text,
    wg_virtual_ip text,
    branding_enabled boolean DEFAULT false NOT NULL,
    brand_name text DEFAULT ''::text NOT NULL,
    brand_logo_file text DEFAULT ''::text NOT NULL,
    branding_updated_at timestamp with time zone DEFAULT now() NOT NULL,
    brand_favicon_file text DEFAULT ''::text NOT NULL,
    CONSTRAINT technicians_role_check CHECK ((role = ANY (ARRAY['super_admin'::text, 'tecnico'::text]))),
    CONSTRAINT technicians_status_check CHECK ((status = ANY (ARRAY['ativo'::text, 'suspenso'::text])))
);


--
-- Name: telemetry_snapshots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.telemetry_snapshots (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    device_id uuid NOT NULL,
    coletado_em timestamp with time zone DEFAULT now() NOT NULL,
    hardware jsonb DEFAULT '{}'::jsonb NOT NULL
);


--
-- Data for Name: admin_actions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.admin_actions (id, actor_id, tipo, alvo_id, detalhes, "timestamp") FROM stdin;
\.


--
-- Data for Name: alerts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.alerts (id, device_id, tipo, severidade, mensagem, resolvido, created_at) FROM stdin;
\.


--
-- Data for Name: device_networks; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.device_networks (device_id, network_id, created_at) FROM stdin;
\.


--
-- Data for Name: devices; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.devices (id, network_id, hostname, mac, wg_pubkey, role, state, pairing_code, device_token, last_seen_at, created_at, updated_at, wg_virtual_ip, rustdesk_id, display_name, suspension_scope, control_technician_id, subnetwork_id) FROM stdin;
9bad6eac-134e-4394-99ee-9ce1bdf81787	\N	Dani	7a:79:19:27:7c:c7	\N	host	guest	22DGVJ	092296f38597462cfc461683ce7741ae9c76805b2be5c509	2026-08-02 22:28:21.184439+00	2026-07-30 18:28:20.762597+00	2026-08-02 22:28:21.75534+00	\N	\N	\N	\N	\N	\N
60938edc-b0cb-41a7-8911-5b72cad66358	\N	DESKTOP-JE50P4E	7a:79:19:27:75:7d	\N	host	guest	9RSTEE	10eb1fc53cb81942c55c9f3aaf2c57f5240ddceef1552f14	2026-08-02 22:28:23.462765+00	2026-07-30 17:37:16.934513+00	2026-08-02 00:00:50.130883+00	\N	\N	\N	\N	\N	\N
\.


--
-- Data for Name: diagnostic_runs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.diagnostic_runs (id, device_id, requested_by, status, tests, progress, current_test, results, error, created_at, started_at, finished_at) FROM stdin;
\.


--
-- Data for Name: networks; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.networks (id, organization_id, name, cidr_virtual, status, created_at, cidr_octet, next_host_octet, suspension_scope, created_by_technician_id) FROM stdin;
\.


--
-- Data for Name: organizations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.organizations (id, name, status, created_at, owner_technician_id, suspension_scope) FROM stdin;
\.


--
-- Data for Name: schema_migrations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.schema_migrations (name, applied_at) FROM stdin;
0001_init.sql	2026-07-22 00:02:38.862911+00
0002_wireguard.sql	2026-07-22 00:23:31.422125+00
0003_backfill_cidr.sql	2026-07-22 00:24:24.693448+00
0004_rustdesk_id.sql	2026-07-22 04:08:09.083499+00
0005_technician_wg.sql	2026-07-22 04:52:25.537942+00
0006_wake_action.sql	2026-07-22 07:53:28.282128+00
0007_delete_admin.sql	2026-07-22 17:31:43.21829+00
0008_telemetry_disks.sql	2026-07-24 00:52:10.160861+00
0009_hardware_telemetry.sql	2026-07-25 15:43:54.991439+00
0010_technician_enrollment_keys.sql	2026-07-25 15:43:55.01443+00
0011_control_installation_keys.sql	2026-07-25 17:04:20.961793+00
0012_device_display_name.sql	2026-07-28 11:09:29.993372+00
0013_suspension_scope.sql	2026-07-28 11:43:53.842138+00
0014_management_actions.sql	2026-07-28 11:50:29.923518+00
0015_remote_access_audit.sql	2026-07-28 20:46:55.837282+00
0016_unique_device_identity.sql	2026-07-29 00:18:09.425691+00
0017_guest_rejection_audit.sql	2026-07-29 00:25:18.786162+00
0018_technician_owned_networks.sql	2026-07-29 02:28:45.030255+00
0019_diagnostic_runs.sql	2026-07-29 05:09:48.037391+00
0020_technician_branding.sql	2026-07-29 05:36:29.821536+00
0021_technician_suspension_cascade.sql	2026-07-29 06:33:37.648516+00
0022_brand_favicon.sql	2026-07-29 06:53:55.121314+00
0023_subnetworks.sql	2026-07-29 07:09:45.134799+00
\.


--
-- Data for Name: sessions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.sessions (id, device_id, technician_id, tipo, inicio, fim) FROM stdin;
\.


--
-- Data for Name: subnetworks; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.subnetworks (id, network_id, name, status, created_by_technician_id, created_at) FROM stdin;
\.


--
-- Data for Name: technician_assignments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.technician_assignments (id, technician_id, organization_id, network_id, created_at) FROM stdin;
\.


--
-- Data for Name: technician_enrollment_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.technician_enrollment_keys (id, technician_id, secret_hash, expires_at, consumed_at, consumed_machine_id, created_by, created_at) FROM stdin;
7a32836c-a53d-4f22-b9f0-f843779dbe71	651a4b65-3441-479b-8619-0c2a46ff88bf	\\x26c5946fc215f61a007b75c2f1c52afb79af7aae22272c19f03e5bc8f1663ac8	2026-08-02 17:34:57.647035+00	2026-07-30 17:36:15.294117+00	1134fa9d-cd21-472a-a765-656edec6c59f|03000200-0400-0500-0006-000700080009|None	651a4b65-3441-479b-8619-0c2a46ff88bf	2026-07-30 17:34:57.647035+00
fd8ff39e-7802-48b5-8b92-9813deabd4b9	651a4b65-3441-479b-8619-0c2a46ff88bf	\\x067dc42188500c5b88f99e4a6094d7540d3cc52fc217d3fba39dfdfb43ec5c1b	2026-08-02 22:15:59.673808+00	2026-08-02 22:00:59.947604+00	1134fa9d-cd21-472a-a765-656edec6c59f	651a4b65-3441-479b-8619-0c2a46ff88bf	2026-08-02 22:00:59.673808+00
a0687feb-4bf4-4961-b033-259bcc374d97	651a4b65-3441-479b-8619-0c2a46ff88bf	\\x92588390d08f9c9e17ccc69d9f66469a93e16187c1020fc8b469bbac9a53d7c7	2026-08-02 22:16:20.237565+00	2026-08-02 22:01:20.478446+00	1134fa9d-cd21-472a-a765-656edec6c59f	651a4b65-3441-479b-8619-0c2a46ff88bf	2026-08-02 22:01:20.237565+00
211f133a-586a-4457-ae0a-f8305a78ddbf	651a4b65-3441-479b-8619-0c2a46ff88bf	\\x51eeca7d36fec6f5cff74578e11539225d99adc271e263da4a0179f0cf4ef928	2026-08-02 22:16:47.829278+00	2026-08-02 22:01:48.056396+00	1134fa9d-cd21-472a-a765-656edec6c59f	651a4b65-3441-479b-8619-0c2a46ff88bf	2026-08-02 22:01:47.829278+00
\.


--
-- Data for Name: technician_machine_credentials; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.technician_machine_credentials (id, technician_id, machine_id, credential_hash, status, created_at, last_used_at, control_role, machine_fingerprint) FROM stdin;
3a006287-152e-4cfa-9efd-2f7cc9ff26ad	651a4b65-3441-479b-8619-0c2a46ff88bf	1134fa9d-cd21-472a-a765-656edec6c59f|03000200-0400-0500-0006-000700080009|None	\\xa39453a7bd31d82af01b253dfe6c62ac425d5389d8eacdf9a61c156f882f0eb7	revogado	2026-07-30 17:36:15.294117+00	2026-07-30 17:37:25.9116+00	super_admin	1134fa9d-cd21-472a-a765-656edec6c59f|03000200-0400-0500-0006-000700080009|None
1840fcda-d24d-47a1-aaa6-d899314d1c32	651a4b65-3441-479b-8619-0c2a46ff88bf	1134fa9d-cd21-472a-a765-656edec6c59f	\\x2d073941cb544876958bfccd8bf148fc41b143464279072842c40b5db7ceeffd	ativo	2026-08-02 22:00:59.947604+00	2026-08-02 22:02:22.465556+00	super_admin	1134fa9d-cd21-472a-a765-656edec6c59f
\.


--
-- Data for Name: technicians; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.technicians (id, username, password_hash, role, created_via_env, status, created_at, wg_pubkey, wg_virtual_ip, branding_enabled, brand_name, brand_logo_file, branding_updated_at, brand_favicon_file) FROM stdin;
651a4b65-3441-479b-8619-0c2a46ff88bf	admin	!	super_admin	f	ativo	2026-07-30 17:34:57.306925+00	Ye6VZwpJMDAzBybQ3b8zlnPJZ4yBEMZ1XbVibcxLtls=	10.70.1.5	f			2026-07-30 17:34:57.306925+00	
\.


--
-- Data for Name: telemetry_snapshots; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.telemetry_snapshots (id, device_id, coletado_em, hardware) FROM stdin;
\.


--
-- Name: network_cidr_octet_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.network_cidr_octet_seq', 151, true);


--
-- Name: technician_host_octet_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.technician_host_octet_seq', 5, true);


--
-- Name: admin_actions admin_actions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_actions
    ADD CONSTRAINT admin_actions_pkey PRIMARY KEY (id);


--
-- Name: alerts alerts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alerts
    ADD CONSTRAINT alerts_pkey PRIMARY KEY (id);


--
-- Name: device_networks device_networks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_networks
    ADD CONSTRAINT device_networks_pkey PRIMARY KEY (device_id, network_id);


--
-- Name: devices devices_device_token_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devices
    ADD CONSTRAINT devices_device_token_key UNIQUE (device_token);


--
-- Name: devices devices_pairing_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devices
    ADD CONSTRAINT devices_pairing_code_key UNIQUE (pairing_code);


--
-- Name: devices devices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devices
    ADD CONSTRAINT devices_pkey PRIMARY KEY (id);


--
-- Name: diagnostic_runs diagnostic_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.diagnostic_runs
    ADD CONSTRAINT diagnostic_runs_pkey PRIMARY KEY (id);


--
-- Name: networks networks_cidr_octet_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.networks
    ADD CONSTRAINT networks_cidr_octet_key UNIQUE (cidr_octet);


--
-- Name: networks networks_organization_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.networks
    ADD CONSTRAINT networks_organization_id_name_key UNIQUE (organization_id, name);


--
-- Name: networks networks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.networks
    ADD CONSTRAINT networks_pkey PRIMARY KEY (id);


--
-- Name: organizations organizations_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_name_key UNIQUE (name);


--
-- Name: organizations organizations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (name);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: subnetworks subnetworks_network_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subnetworks
    ADD CONSTRAINT subnetworks_network_id_name_key UNIQUE (network_id, name);


--
-- Name: subnetworks subnetworks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subnetworks
    ADD CONSTRAINT subnetworks_pkey PRIMARY KEY (id);


--
-- Name: technician_assignments technician_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.technician_assignments
    ADD CONSTRAINT technician_assignments_pkey PRIMARY KEY (id);


--
-- Name: technician_assignments technician_assignments_technician_id_organization_id_networ_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.technician_assignments
    ADD CONSTRAINT technician_assignments_technician_id_organization_id_networ_key UNIQUE (technician_id, organization_id, network_id);


--
-- Name: technician_enrollment_keys technician_enrollment_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.technician_enrollment_keys
    ADD CONSTRAINT technician_enrollment_keys_pkey PRIMARY KEY (id);


--
-- Name: technician_machine_credentials technician_machine_credentials_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.technician_machine_credentials
    ADD CONSTRAINT technician_machine_credentials_pkey PRIMARY KEY (id);


--
-- Name: technician_machine_credentials technician_machine_credentials_technician_id_machine_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.technician_machine_credentials
    ADD CONSTRAINT technician_machine_credentials_technician_id_machine_id_key UNIQUE (technician_id, machine_id);


--
-- Name: technicians technicians_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.technicians
    ADD CONSTRAINT technicians_pkey PRIMARY KEY (id);


--
-- Name: technicians technicians_username_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.technicians
    ADD CONSTRAINT technicians_username_key UNIQUE (username);


--
-- Name: telemetry_snapshots telemetry_snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_snapshots
    ADD CONSTRAINT telemetry_snapshots_pkey PRIMARY KEY (id);


--
-- Name: devices_unique_mac; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX devices_unique_mac ON public.devices USING btree (lower(btrim(mac))) WHERE ((mac IS NOT NULL) AND (btrim(mac) <> ''::text));


--
-- Name: idx_assignments_technician; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_assignments_technician ON public.technician_assignments USING btree (technician_id);


--
-- Name: idx_device_networks_network; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_device_networks_network ON public.device_networks USING btree (network_id, device_id);


--
-- Name: idx_devices_network; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_devices_network ON public.devices USING btree (network_id);


--
-- Name: idx_diagnostic_runs_device_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_diagnostic_runs_device_created ON public.diagnostic_runs USING btree (device_id, created_at DESC);


--
-- Name: idx_diagnostic_runs_dispatch; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_diagnostic_runs_dispatch ON public.diagnostic_runs USING btree (device_id, status, created_at);


--
-- Name: idx_networks_org; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_networks_org ON public.networks USING btree (organization_id);


--
-- Name: idx_organizations_one_per_technician; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_organizations_one_per_technician ON public.organizations USING btree (owner_technician_id) WHERE (owner_technician_id IS NOT NULL);


--
-- Name: idx_subnetworks_network; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_subnetworks_network ON public.subnetworks USING btree (network_id, created_at);


--
-- Name: idx_technician_enrollment_keys_technician; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_technician_enrollment_keys_technician ON public.technician_enrollment_keys USING btree (technician_id, created_at DESC);


--
-- Name: idx_technician_machine_credentials_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_technician_machine_credentials_lookup ON public.technician_machine_credentials USING btree (id, status);


--
-- Name: idx_telemetry_device_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_telemetry_device_time ON public.telemetry_snapshots USING btree (device_id, coletado_em DESC);


--
-- Name: idx_telemetry_hardware_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_telemetry_hardware_gin ON public.telemetry_snapshots USING gin (hardware);


--
-- Name: uq_single_active_tgdesk_admin; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_single_active_tgdesk_admin ON public.technician_machine_credentials USING btree (control_role) WHERE ((control_role = 'super_admin'::text) AND (status = 'ativo'::text));


--
-- Name: networks trg_assign_network_cidr; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_assign_network_cidr BEFORE INSERT ON public.networks FOR EACH ROW EXECUTE FUNCTION public.assign_network_cidr();


--
-- Name: admin_actions admin_actions_actor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_actions
    ADD CONSTRAINT admin_actions_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES public.technicians(id) ON DELETE SET NULL;


--
-- Name: alerts alerts_device_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alerts
    ADD CONSTRAINT alerts_device_id_fkey FOREIGN KEY (device_id) REFERENCES public.devices(id) ON DELETE CASCADE;


--
-- Name: device_networks device_networks_device_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_networks
    ADD CONSTRAINT device_networks_device_id_fkey FOREIGN KEY (device_id) REFERENCES public.devices(id) ON DELETE CASCADE;


--
-- Name: device_networks device_networks_network_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_networks
    ADD CONSTRAINT device_networks_network_id_fkey FOREIGN KEY (network_id) REFERENCES public.networks(id) ON DELETE CASCADE;


--
-- Name: devices devices_control_technician_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devices
    ADD CONSTRAINT devices_control_technician_id_fkey FOREIGN KEY (control_technician_id) REFERENCES public.technicians(id) ON DELETE SET NULL;


--
-- Name: devices devices_network_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devices
    ADD CONSTRAINT devices_network_id_fkey FOREIGN KEY (network_id) REFERENCES public.networks(id) ON DELETE SET NULL;


--
-- Name: devices devices_subnetwork_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devices
    ADD CONSTRAINT devices_subnetwork_id_fkey FOREIGN KEY (subnetwork_id) REFERENCES public.subnetworks(id) ON DELETE SET NULL;


--
-- Name: diagnostic_runs diagnostic_runs_device_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.diagnostic_runs
    ADD CONSTRAINT diagnostic_runs_device_id_fkey FOREIGN KEY (device_id) REFERENCES public.devices(id) ON DELETE CASCADE;


--
-- Name: diagnostic_runs diagnostic_runs_requested_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.diagnostic_runs
    ADD CONSTRAINT diagnostic_runs_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES public.technicians(id) ON DELETE SET NULL;


--
-- Name: networks networks_created_by_technician_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.networks
    ADD CONSTRAINT networks_created_by_technician_id_fkey FOREIGN KEY (created_by_technician_id) REFERENCES public.technicians(id) ON DELETE SET NULL;


--
-- Name: networks networks_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.networks
    ADD CONSTRAINT networks_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: organizations organizations_owner_technician_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_owner_technician_id_fkey FOREIGN KEY (owner_technician_id) REFERENCES public.technicians(id) ON DELETE CASCADE;


--
-- Name: sessions sessions_device_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_device_id_fkey FOREIGN KEY (device_id) REFERENCES public.devices(id) ON DELETE CASCADE;


--
-- Name: sessions sessions_technician_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_technician_id_fkey FOREIGN KEY (technician_id) REFERENCES public.technicians(id) ON DELETE CASCADE;


--
-- Name: subnetworks subnetworks_created_by_technician_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subnetworks
    ADD CONSTRAINT subnetworks_created_by_technician_id_fkey FOREIGN KEY (created_by_technician_id) REFERENCES public.technicians(id) ON DELETE SET NULL;


--
-- Name: subnetworks subnetworks_network_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subnetworks
    ADD CONSTRAINT subnetworks_network_id_fkey FOREIGN KEY (network_id) REFERENCES public.networks(id) ON DELETE CASCADE;


--
-- Name: technician_assignments technician_assignments_network_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.technician_assignments
    ADD CONSTRAINT technician_assignments_network_id_fkey FOREIGN KEY (network_id) REFERENCES public.networks(id) ON DELETE CASCADE;


--
-- Name: technician_assignments technician_assignments_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.technician_assignments
    ADD CONSTRAINT technician_assignments_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;


--
-- Name: technician_assignments technician_assignments_technician_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.technician_assignments
    ADD CONSTRAINT technician_assignments_technician_id_fkey FOREIGN KEY (technician_id) REFERENCES public.technicians(id) ON DELETE CASCADE;


--
-- Name: technician_enrollment_keys technician_enrollment_keys_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.technician_enrollment_keys
    ADD CONSTRAINT technician_enrollment_keys_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.technicians(id) ON DELETE SET NULL;


--
-- Name: technician_enrollment_keys technician_enrollment_keys_technician_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.technician_enrollment_keys
    ADD CONSTRAINT technician_enrollment_keys_technician_id_fkey FOREIGN KEY (technician_id) REFERENCES public.technicians(id) ON DELETE CASCADE;


--
-- Name: technician_machine_credentials technician_machine_credentials_technician_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.technician_machine_credentials
    ADD CONSTRAINT technician_machine_credentials_technician_id_fkey FOREIGN KEY (technician_id) REFERENCES public.technicians(id) ON DELETE CASCADE;


--
-- Name: telemetry_snapshots telemetry_snapshots_device_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_snapshots
    ADD CONSTRAINT telemetry_snapshots_device_id_fkey FOREIGN KEY (device_id) REFERENCES public.devices(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict JchEP9CfNex3E7qLAg9TUp7aJpgb3XytXrGnlbzY5anmFsDgNBtPXu7W5AXGWTl

