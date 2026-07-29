import fs from "node:fs";

const evidencePath = "/tests/artifacts/deletion-identity.json";
const evidence = {
  schema_version: 1,
  scenario: "deletion-and-suspension",
  state: "running",
  measured_at: new Date().toISOString(),
  assertions: [],
};
let socket;

function prove(id, condition, details = undefined) {
  if (!condition) throw new Error(`Assertion failed: ${id}`);
  evidence.assertions.push({ id, state: "passed", details });
}

async function request(path, method = "GET", payload) {
  const response = await fetch(`http://127.0.0.1:8080${path}`, {
    method,
    headers: payload ? { "content-type": "application/json" } : undefined,
    body: payload ? JSON.stringify(payload) : undefined,
    signal: AbortSignal.timeout(10000),
  });
  let body;
  try {
    body = await response.json();
  } catch {
    body = {};
  }
  return { status: response.status, body };
}

async function connect(token) {
  socket = new WebSocket(
    `ws://10.70.0.1:8080/ws/control/technician?token=${encodeURIComponent(token)}`,
  );
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("WebSocket open timeout")), 10000);
    socket.addEventListener("open", () => {
      clearTimeout(timer);
      resolve();
    }, { once: true });
    socket.addEventListener("error", () => {
      clearTimeout(timer);
      reject(new Error("WebSocket open failed"));
    }, { once: true });
  });

  let sequence = 0;
  const pending = new Map();
  socket.addEventListener("message", (event) => {
    const message = JSON.parse(event.data);
    if (message.type !== "rpc_response" || !pending.has(message.id)) return;
    const entry = pending.get(message.id);
    pending.delete(message.id);
    clearTimeout(entry.timer);
    if (message.status >= 200 && message.status < 300) entry.resolve(message.payload);
    else entry.reject(new Error(`${message.status}: ${JSON.stringify(message.payload)}`));
  });
  return (method, path, payload = {}) =>
    new Promise((resolve, reject) => {
      const id = `rpc-${++sequence}`;
      const timer = setTimeout(() => {
        pending.delete(id);
        reject(new Error(`RPC timeout: ${method} ${path}`));
      }, 10000);
      pending.set(id, { resolve, reject, timer });
      socket.send(JSON.stringify({ type: "rpc", id, method, path, payload }));
    });
}

try {
  const key = JSON.parse(
    fs.readFileSync("/tests/artifacts/keys/admin.tgdesk-key", "utf8"),
  );
  const authResult = await request(
    "/api/v1/auth/control-key/install",
    "POST",
    { key, machine_id: "testlab-admin-vm" },
  );
  if (authResult.status !== 200) {
    throw new Error(`Admin redeem ${authResult.status}: ${JSON.stringify(authResult.body)}`);
  }
  let rpc = await connect(authResult.body.token);
  const suffix = Date.now().toString(36);

  const guestA = await request("/api/v1/devices/register", "POST", {
    hostname: `DUPLICATE-${suffix}`,
    mac: `02:11:22:${suffix.slice(-2).padStart(2, "0")}:44:55`,
    role: "host",
  });
  const guestB = await request("/api/v1/devices/register", "POST", {
    hostname: `DUPLICATE-RENAMED-${suffix}`,
    mac: `02:11:22:${suffix.slice(-2).padStart(2, "0")}:44:55`,
    role: "host",
  });
  prove(
    "devices.no-duplicates",
    guestA.status === 201 &&
      guestB.status === 200 &&
      guestA.body.device_id === guestB.body.device_id,
    { first_status: guestA.status, second_status: guestB.status },
  );

  const organization = await rpc("POST", "/api/v1/organizations", {
    name: `Delete Org ${suffix}`,
  });
  const network = await rpc("POST", "/api/v1/networks", {
    organization_id: organization.id,
    name: `Delete Net ${suffix}`,
  });
  await rpc("POST", "/api/v1/pairing/bind", {
    pairing_code: guestA.body.pairing_code,
    organization_id: organization.id,
    network_id: network.id,
  });

  const activeDuplicate = await request("/api/v1/devices/register", "POST", {
    hostname: `ACTIVE-DUPLICATE-${suffix}`,
    mac: `02:11:22:${suffix.slice(-2).padStart(2, "0")}:44:55`,
    role: "host",
  });
  prove(
    "devices.no-duplicates",
    activeDuplicate.status === 409,
    { active_duplicate_status: activeDuplicate.status },
  );

  const deleted = await rpc("DELETE", `/api/v1/organizations/${organization.id}`);
  const heartbeat = await request("/api/v1/devices/heartbeat", "POST", {
    device_id: guestA.body.device_id,
    device_token: guestA.body.device_token,
  });
  prove(
    "delete.organization.cascade",
    deleted.status === "apagada" &&
      deleted.devices_desvinculados === 1 &&
      heartbeat.body.state === "guest" &&
      Boolean(heartbeat.body.pairing_code),
    { deleted, heartbeat: heartbeat.body },
  );

  await new Promise((resolve) => {
    socket.addEventListener("close", resolve, { once: true });
    socket.close();
  });
  socket = undefined;
  rpc = await connect(authResult.body.token);
  const organizations = await rpc("GET", "/api/v1/organizations");
  const networks = await rpc("GET", "/api/v1/networks");
  prove(
    "delete.no-resurrection",
    !organizations.some((item) => item.id === organization.id) &&
      !networks.some((item) => item.id === network.id),
  );

  const rejectedGuest = await request("/api/v1/devices/register", "POST", {
    hostname: `REJECT-${suffix}`,
    mac: `02:AA:BB:${suffix.slice(-2).padStart(2, "0")}:CC:DD`,
    role: "host",
  });
  const rejection = await rpc(
    "DELETE",
    `/api/v1/admin/guest-devices/${rejectedGuest.body.device_id}`,
  );
  const devices = await rpc("GET", "/api/v1/devices");
  prove(
    "delete.guest.reject",
    rejection.status === "recusado" &&
      !devices.some((item) => item.id === rejectedGuest.body.device_id),
  );

  socket.close();
  evidence.state = "passed";
  evidence.finished_at = new Date().toISOString();
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
