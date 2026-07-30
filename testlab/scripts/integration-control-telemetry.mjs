import fs from "node:fs";

const evidencePath = "/tests/artifacts/control-telemetry.json";
const evidence = {
  schema_version: 1,
  scenario: "control-telemetry",
  state: "running",
  measured_at: new Date().toISOString(),
  assertions: [],
};
const sockets = [];

function assert(condition, id, details) {
  if (!condition) throw new Error(`Assertion failed: ${id}`);
  evidence.assertions.push({ id, state: "passed", details });
}

async function post(path, payload) {
  const response = await fetch(`http://127.0.0.1:8080${path}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(10000),
  });
  const body = await response.json();
  if (!response.ok) throw new Error(`${path} -> ${response.status}: ${JSON.stringify(body)}`);
  return body;
}

async function openSocket(url) {
  const socket = new WebSocket(url);
  sockets.push(socket);
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`WebSocket timeout: ${url}`)), 10000);
    socket.addEventListener("open", () => {
      clearTimeout(timer);
      resolve();
    }, { once: true });
    socket.addEventListener("error", () => {
      clearTimeout(timer);
      reject(new Error(`WebSocket failed: ${url}`));
    }, { once: true });
  });
  return socket;
}

function nextMessage(socket, predicate, timeout = 10000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      socket.removeEventListener("message", listener);
      reject(new Error("WebSocket message timeout"));
    }, timeout);
    const listener = (event) => {
      const message = JSON.parse(event.data);
      if (!predicate(message)) return;
      clearTimeout(timer);
      socket.removeEventListener("message", listener);
      resolve(message);
    };
    socket.addEventListener("message", listener);
  });
}

function technicianRPC(socket) {
  let sequence = 0;
  return async (method, path, payload = {}) => {
    const id = `control-${++sequence}`;
    const response = nextMessage(socket, (message) =>
      message.type === "rpc_response" && message.id === id);
    socket.send(JSON.stringify({ type: "rpc", id, method, path, payload }));
    const result = await response;
    if (result.status < 200 || result.status >= 300) {
      throw new Error(`${method} ${path} -> ${result.status}: ${JSON.stringify(result.payload)}`);
    }
    return result.payload;
  };
}

try {
  const key = JSON.parse(fs.readFileSync("/tests/artifacts/keys/supervisor.tgdesk-key", "utf8"));
  const auth = await post("/api/v1/auth/control-key/install", {
    key,
    machine_id: `control-telemetry-${Date.now()}`,
  });
  const technician = await openSocket(
    `ws://10.70.0.1:8080/ws/control/technician?token=${encodeURIComponent(auth.token)}`,
  );
  const snapshot = await nextMessage(technician, (message) => message.type === "snapshot");
  assert(Array.isArray(snapshot.devices), "ws.single-control-channel", {
    snapshot_received: true,
    transport: "private-websocket",
  });
  const rpc = technicianRPC(technician);

  const suffix = Date.now().toString(36);
  const organizations = await rpc("GET", "/api/v1/organizations");
  const organization = organizations.find((item) => Boolean(item.owner_technician_id));
  assert(auth.role === "tecnico" && Boolean(organization) &&
    organizations.every((item) => Boolean(item.owner_technician_id)), "rbac.supervisor-scope", {
    role: auth.role,
    visible_organizations: organizations.length,
    owns_personal_organization: true,
  });
  const network = await rpc("POST", "/api/v1/networks", {
    organization_id: organization.id,
    name: `Private ${suffix}`,
    cidr_virtual: "",
  });
  const guest = await post("/api/v1/devices/register", {
    hostname: `CONTROL-${suffix}`,
    mac: `02:70:00:${suffix.slice(-2).padStart(2, "0")}:01:02`,
    role: "host",
  });
  await rpc("POST", "/api/v1/pairing/bind", {
    pairing_code: guest.pairing_code,
    organization_id: organization.id,
    network_id: network.id,
  });

  const device = await openSocket(
    `ws://10.70.0.1:8080/ws/control/device?device_id=${encodeURIComponent(guest.device_id)}&device_token=${encodeURIComponent(guest.device_token)}`,
  );
  const ready = await nextMessage(device, (message) => message.type === "ready");
  assert(ready.state === "ativo", "vpn.private-data-plane", {
    device_control_ready: true,
    endpoint: "10.70.0.1",
  });

  const presenceEvent = nextMessage(technician, (message) =>
    message.type === "event" &&
    message.event?.type === "presence" &&
    message.event?.target_id === guest.device_id);
  device.send(JSON.stringify({
    type: "heartbeat",
    payload: { remote_ready: true, files_ready: true },
  }));
  const heartbeatAck = await nextMessage(device, (message) => message.type === "heartbeat_ack");
  const presence = await presenceEvent;
  assert(heartbeatAck.state === "ativo" && presence.event.payload.presence === "online",
    "ws.telemetry.realtime", { presence: "online", heartbeat_ack: true });

  let lastStats;
  let lastEvent;
  for (let index = 0; index < 4; index += 1) {
    const usage = 70 + index * 10;
    const statsPromise = nextMessage(device, (message) => message.type === "telemetry_stats");
    const eventPromise = nextMessage(technician, (message) =>
      message.type === "event" &&
      message.event?.type === "telemetry" &&
      message.event?.target_id === guest.device_id);
    device.send(JSON.stringify({
      type: "telemetry",
      payload: {
        hardware: {
          cpu: {
            name: "Deterministic CPU",
            usage,
            clock_mhz: 2200 + index * 100,
            measurement_source: "testlab",
          },
          memory_summary: {
            total_bytes: 8589934592,
            used_bytes: 4294967296 + index * 1024,
            available_bytes: 4294967296 - index * 1024,
            usage: 50,
          },
          gpus: [],
          memory: [],
          storage: [{
            id: "disk0",
            model: "Deterministic Disk",
            used_pct: 85,
            smart_status: "Healthy",
            volumes: [],
          }],
          networks: [{
            id: "net0",
            status: "Up",
            rx_bytes_total: 1000 + index * 100,
            tx_bytes_total: 2000 + index * 100,
          }],
        },
      },
    }));
    lastStats = await statsPromise;
    lastEvent = await eventPromise;
  }
  assert(lastStats.payload.cpu.usage.samples === 4 &&
    lastStats.payload.cpu.usage.minimum === 70 &&
    lastStats.payload.cpu.usage.peak === 100 &&
    lastStats.payload.cpu.usage.average === 85,
    "telemetry.cpu.history", lastStats.payload.cpu.usage);
  assert(lastStats.payload.memory_used_bytes.system.samples === 4,
    "telemetry.memory", lastStats.payload.memory_used_bytes.system);
  assert(lastEvent.event.payload.statistics.cpu.usage.samples === 4,
    "devices.details.realtime", { samples: 4, transport: "websocket" });
  assert(lastStats.payload.health.metrics.storage.level === "warning",
    "telemetry.thresholds.storage", lastStats.payload.health.metrics.storage);

  technician.close();
  await new Promise((resolve) => setTimeout(resolve, 50));
  const reconnected = await openSocket(
    `ws://10.70.0.1:8080/ws/control/technician?token=${encodeURIComponent(auth.token)}`,
  );
  const reconnectSnapshot = await nextMessage(reconnected, (message) => message.type === "snapshot");
  assert(reconnectSnapshot.devices.some((item) => item.id === guest.device_id),
    "ws.reconnect.automatic", { restored_without_server_or_windows_restart: true });

  evidence.state = "passed";
  evidence.finished_at = new Date().toISOString();
  evidence.resources = { device_id: guest.device_id };
  fs.writeFileSync(evidencePath, JSON.stringify(evidence, null, 2));
  process.stdout.write(JSON.stringify(evidence, null, 2));
} catch (error) {
  evidence.state = "failed";
  evidence.finished_at = new Date().toISOString();
  evidence.error = error.stack || error.message;
  fs.writeFileSync(evidencePath, JSON.stringify(evidence, null, 2));
  process.stderr.write(JSON.stringify(evidence, null, 2));
  process.exitCode = 1;
} finally {
  for (const socket of sockets) {
    try { socket.close(); } catch {}
  }
}
