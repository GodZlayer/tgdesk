import fs from "node:fs";

const keyPath = "/tests/artifacts/keys/admin.tgdesk-key";
const evidencePath = "/tests/artifacts/hierarchy-integration.json";
const machineId = "testlab-admin-vm";
const evidence = {
  schema_version: 1,
  scenario: "organization-network-subnetwork-device",
  state: "running",
  measured_at: new Date().toISOString(),
  assertions: [],
};
let socket;

function assert(condition, id, name, details = undefined) {
  if (!condition) throw new Error(`Assertion failed: ${name}`);
  evidence.assertions.push({ id, name, state: "passed", details });
}

async function publicPost(path, payload) {
  const response = await fetch(`http://127.0.0.1:8080${path}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(10000),
  });
  const body = await response.json();
  if (!response.ok) {
    throw new Error(`${path} -> ${response.status}: ${JSON.stringify(body)}`);
  }
  return body;
}

try {
  const key = JSON.parse(fs.readFileSync(keyPath, "utf8"));
  const auth = await publicPost("/api/v1/auth/control-key/install", {
    key,
    machine_id: machineId,
  });
  assert(
    auth.role === "super_admin",
    "rbac.admin-superset",
    "admin key creates super_admin session",
  );

  const privateHealth = await fetch("http://10.70.0.1:8080/healthz", {
    signal: AbortSignal.timeout(10000),
  });
  assert(
    privateHealth.ok,
    "vpn.private-data-plane",
    "private VPN endpoint is reachable",
  );

  socket = new WebSocket(
    `ws://10.70.0.1:8080/ws/control/technician?token=${encodeURIComponent(auth.token)}`,
  );
  const pending = new Map();
  let sequence = 0;
  let initialSnapshot;

  const open = new Promise((resolve, reject) => {
    const timer = setTimeout(
      () => reject(new Error("WebSocket open state timeout")),
      10000,
    );
    socket.addEventListener(
      "open",
      () => {
        clearTimeout(timer);
        resolve();
      },
      { once: true },
    );
    socket.addEventListener(
      "error",
      () => {
        clearTimeout(timer);
        reject(new Error("WebSocket open failed"));
      },
      { once: true },
    );
  });
  socket.addEventListener("message", (event) => {
    const message = JSON.parse(event.data);
    if (message.type === "snapshot" && !initialSnapshot) initialSnapshot = message;
    if (message.type === "rpc_response" && pending.has(message.id)) {
      const { resolve, reject } = pending.get(message.id);
      pending.delete(message.id);
      if (message.status >= 200 && message.status < 300) resolve(message.payload);
      else reject(
        new Error(
          `${message.status} ${message.id}: ${JSON.stringify(message.payload)}`,
        ),
      );
    }
  });
  await open;

  const rpc = (method, path, payload = {}) =>
    new Promise((resolve, reject) => {
      const id = `rpc-${++sequence}`;
      const timer = setTimeout(() => {
        pending.delete(id);
        reject(new Error(`RPC state timeout: ${method} ${path}`));
      }, 10000);
      pending.set(id, {
        resolve: (value) => {
          clearTimeout(timer);
          resolve(value);
        },
        reject: (error) => {
          clearTimeout(timer);
          reject(error);
        },
      });
      socket.send(
        JSON.stringify({ type: "rpc", id, method, path, payload }),
      );
    });

  const suffix = Date.now().toString(36);
  const organization = await rpc("POST", "/api/v1/organizations", {
    name: `Org TestLab ${suffix}`,
  });
  const network = await rpc("POST", "/api/v1/networks", {
    organization_id: organization.id,
    name: `Rede ${suffix}`,
    cidr_virtual: "",
  });
  const subnetwork = await rpc("POST", "/api/v1/subnetworks", {
    network_id: network.id,
    name: `Caixa ${suffix}`,
  });
  assert(
    subnetwork.network_id === network.id && subnetwork.status === "ativa",
    "hierarchy.org-network-subnetwork-device",
    "subnetwork created in selected network",
  );

  const device = await publicPost("/api/v1/devices/register", {
    hostname: `TESTLAB-${suffix}`,
    mac: `02:00:00:${suffix.slice(-2).padStart(2, "0")}:00:01`,
    role: "host",
  });
  await rpc("POST", "/api/v1/pairing/bind", {
    pairing_code: device.pairing_code,
    organization_id: organization.id,
    network_id: network.id,
  });
  await rpc("PUT", `/api/v1/devices/${device.device_id}/subnetwork`, {
    subnetwork_id: subnetwork.id,
  });

  const suspended = await rpc(
    "POST",
    `/api/v1/subnetworks/${subnetwork.id}/suspend`,
  );
  assert(
    suspended.status === "suspensa" && suspended.devices_afetados === 1,
    "suspend.subnetwork.cascade",
    "subnetwork suspension affects exactly its device",
    suspended,
  );
  let devices = await rpc("GET", "/api/v1/devices");
  let current = devices.find((item) => item.id === device.device_id);
  assert(
    current?.state === "suspenso",
    "vpn.suspension.disconnect",
    "device state follows subnetwork suspension",
  );

  const resumed = await rpc(
    "POST",
    `/api/v1/subnetworks/${subnetwork.id}/resume`,
  );
  assert(
    resumed.status === "ativa" && resumed.devices_reativados === 1,
    "resume.same-scope-only",
    "subnetwork resume restores same-scope device",
    resumed,
  );
  devices = await rpc("GET", "/api/v1/devices");
  current = devices.find((item) => item.id === device.device_id);
  assert(
    current?.state === "ativo",
    "hierarchy.subnetwork.lifecycle",
    "device active after same-scope resume",
  );

  const subnetworks = await rpc("GET", "/api/v1/subnetworks");
  const principal = subnetworks.find(
    (item) => item.network_id === network.id && item.name === "Principal",
  );
  assert(
    Boolean(principal),
    "hierarchy.supervisor.unlimited",
    "network has deterministic Principal subnetwork",
  );
  const deleted = await rpc("DELETE", `/api/v1/subnetworks/${subnetwork.id}`);
  assert(
    deleted.status === "excluida" &&
      deleted.reassigned_to === principal.id &&
      deleted.devices_reassigned === 1,
    "hierarchy.subnetwork.lifecycle",
    "delete reassigns device to Principal",
    deleted,
  );
  devices = await rpc("GET", "/api/v1/devices");
  current = devices.find((item) => item.id === device.device_id);
  assert(
    current?.subnetwork_id === principal.id,
    "hierarchy.org-network-subnetwork-device",
    "device reports Principal after subnetwork deletion",
  );

  socket.close();
  evidence.state = "passed";
  evidence.finished_at = new Date().toISOString();
  evidence.resources = {
    organization_id: organization.id,
    network_id: network.id,
    device_id: device.device_id,
    reassigned_subnetwork_id: principal.id,
  };
  fs.writeFileSync(evidencePath, JSON.stringify(evidence, null, 2));
  process.stdout.write(JSON.stringify(evidence, null, 2));
} catch (error) {
  if (socket) socket.close();
  evidence.state = "failed";
  evidence.finished_at = new Date().toISOString();
  evidence.error = error.stack || error.message;
  fs.writeFileSync(evidencePath, JSON.stringify(evidence, null, 2));
  process.stderr.write(JSON.stringify(evidence, null, 2));
  process.exitCode = 1;
}
