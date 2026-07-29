# TGDesk Deterministic Test Lab

Every phase writes a machine-readable JSON evidence file before another phase
may start. Time alone is never a success criterion.

Run the current state audit:

```powershell
.\Invoke-TGDeskStateLoop.ps1 -Action Run
```

Exit codes:

- `0`: measured criteria passed.
- `1`: a measurable validation failed.
- `2`: execution is blocked by an explicit missing prerequisite.

Artifacts are written under `artifacts/<run-id>/`. VM provisioning is allowed
only after `vm-prerequisites.json` reports `passed`.
## Backend isolado

O stack `docker-compose.test.yml` usa portas, rede lógica e volumes próprios.
Ele existe para validar exclusões, suspensões, chaves descartáveis e migrações
sem tocar nos dados persistentes do servidor de produção.

```powershell
.\testlab\Test-TGDeskIsolatedBackend.ps1 -Action Reset
```

O comando somente conclui quando Postgres e Redis estão saudáveis, a API
responde `status=ok`, cinco volumes de teste existem e os cinco volumes
persistentes de produção continuam presentes.

Para testes internos de autorização da API, uma autoridade Admin sintética e
descartável pode ser criada exclusivamente no banco isolado:

```powershell
.\testlab\New-TGDeskLabAdminKey.ps1
```

Ela é gravada sob `testlab/artifacts`, fora do versionamento, não instala
TGDesk, não cria uma VM Admin e não é válida no servidor de produção. A fábrica
de VMs permite somente `client` e `supervisor`; o Admin real continua sendo
exclusivamente o computador original.
