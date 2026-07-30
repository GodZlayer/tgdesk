import fs from "node:fs";

const base = "http://10.70.0.1:8080";
const output = "/tests/artifacts/hierarchy-propagation.json";
const sockets = [];
const evidence = {
  schema_version: 1,
  scenario: "hierarchy-server-propagation",
  state: "running",
  measured_at: new Date().toISOString(),
  assertions: [],
};

async function request(path, { method = "GET", token, body, expected } = {}) {
  const response = await fetch(base + path, {
    method,
    headers: {
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...(body ? { "content-type": "application/json" } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(10000),
  });
  const raw = await response.text();
  let data = raw;
  try { data = raw ? JSON.parse(raw) : null; } catch {}
  if (expected !== undefined ? response.status !== expected : !response.ok) {
    throw new Error(`${method} ${path}: ${response.status}: ${raw}`);
  }
  return data;
}

async function redeem(key, machineID) {
  return request("/api/v1/auth/control-key/install", {
    method: "POST",
    body: { key, machine_id: machineID },
  });
}

async function openEvents(token) {
  const socket = new WebSocket(
    `ws://10.70.0.1:8080/ws/control/technician?token=${encodeURIComponent(token)}`,
  );
  sockets.push(socket);
  const snapshot = new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("snapshot timeout")), 10000);
    socket.addEventListener("message", function listener(event) {
      const message = JSON.parse(event.data);
      if (message.type !== "snapshot") return;
      clearTimeout(timer);
      socket.removeEventListener("message", listener);
      resolve(message);
    });
  });
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("websocket open timeout")), 10000);
    socket.addEventListener("open", () => { clearTimeout(timer); resolve(); }, { once: true });
    socket.addEventListener("error", () => reject(new Error("websocket open failed")), { once: true });
  });
  return { socket, snapshot: await snapshot };
}

function eventProbe(socket, type, targetID, timeout = 3000) {
  let listener;
  let timer;
  const promise = new Promise((resolve) => {
    listener = (event) => {
      const message = JSON.parse(event.data);
      if (message.type === "event" &&
          message.event?.type === type &&
          message.event?.target_id === targetID) {
        clearTimeout(timer);
        socket.removeEventListener("message", listener);
        resolve({ received: true, event: message.event });
      }
    };
    socket.addEventListener("message", listener);
    timer = setTimeout(() => {
      socket.removeEventListener("message", listener);
      resolve({ received: false });
    }, timeout);
  });
  return { promise };
}

async function createSupervisor(adminToken, suffix, label) {
  const technician = await request("/api/v1/technicians", {
    method: "POST",
    token: adminToken,
    body: { name: `${label} ${suffix}` },
  });
  const enrollment = await request(`/api/v1/technicians/${technician.id}/enrollment-key`, {
    method: "POST",
    token: adminToken,
    body: { expires_in_hours: 1 },
  });
  const auth = await redeem(enrollment, `ws-${label.toLowerCase()}-${suffix}`);
  return { technician, auth };
}

try {
  const suffix = Date.now().toString(36);
  const adminKey = JSON.parse(fs.readFileSync("/tests/artifacts/keys/admin.tgdesk-key", "utf8"));
  const admin = await redeem(adminKey, "testlab-admin-vm");

  const owner = await createSupervisor(admin.token, suffix, "Owner");
  const assigned = await createSupervisor(admin.token, suffix, "Assigned");
  const outsider = await createSupervisor(admin.token, suffix, "Outsider");

  const organizations = await request("/api/v1/organizations", { token: admin.token });
  const ownerOrganization = organizations.find(
    (item) => item.owner_technician_id === owner.technician.id,
  );
  if (!ownerOrganization) throw new Error("owner personal organization missing");
  const network = await request("/api/v1/networks", {
    method: "POST",
    token: owner.auth.token,
    body: { organization_id: ownerOrganization.id, name: `Propagation ${suffix}` },
  });
  await request("/api/v1/technicians/assignments", {
    method: "POST",
    token: admin.token,
    body: { technician_id: assigned.technician.id, network_id: network.id },
  });

  const ownerWS = await openEvents(owner.auth.token);
  const assignedWS = await openEvents(assigned.auth.token);
  const outsiderWS = await openEvents(outsider.auth.token);
  if (!ownerWS.snapshot.networks.some((item) => item.id === network.id) ||
      !assignedWS.snapshot.networks.some((item) => item.id === network.id) ||
      outsiderWS.snapshot.networks.some((item) => item.id === network.id)) {
    throw new Error("initial websocket scope is inconsistent");
  }

  const renameOwner = eventProbe(ownerWS.socket, "network_renamed", network.id);
  const renameAssigned = eventProbe(assignedWS.socket, "network_renamed", network.id);
  const renameOutsider = eventProbe(outsiderWS.socket, "network_renamed", network.id);
  await request(`/api/v1/networks/${network.id}`, {
    method: "PUT",
    token: owner.auth.token,
    body: { name: `Propagation Renamed ${suffix}` },
  });
  const renameResults = await Promise.all([
    renameOwner.promise, renameAssigned.promise, renameOutsider.promise,
  ]);

  const guest = await request("/api/v1/devices/register", {
    method: "POST",
    body: {
      hostname: `PROP-${suffix}`,
      mac: `02:73:${suffix.slice(-2).padStart(2, "0")}:11:22:33`,
      role: "host",
    },
  });
  const bindOwner = eventProbe(ownerWS.socket, "bind", guest.device_id);
  const bindAssigned = eventProbe(assignedWS.socket, "bind", guest.device_id);
  const bindOutsider = eventProbe(outsiderWS.socket, "bind", guest.device_id);
  await request("/api/v1/pairing/bind", {
    method: "POST",
    token: owner.auth.token,
    body: {
      pairing_code: guest.pairing_code,
      organization_id: ownerOrganization.id,
      network_id: network.id,
    },
  });
  const bindResults = await Promise.all([
    bindOwner.promise, bindAssigned.promise, bindOutsider.promise,
  ]);

  const passed = renameResults[0].received && renameResults[1].received &&
    !renameResults[2].received && bindResults[0].received &&
    bindResults[1].received && !bindResults[2].received;
  if (!passed) {
    throw new Error(`propagation mismatch: ${JSON.stringify({ renameResults, bindResults })}`);
  }
  evidence.assertions.push({
    id: "hierarchy.server-propagation",
    state: "passed",
    details: {
      authorized_supervisors: 2,
      unauthorized_supervisors: 1,
      events: ["network_renamed", "bind"],
      authorized_received_all: true,
      unauthorized_received: 0,
      transport: "private-websocket",
    },
  });
  evidence.state = "passed";
  evidence.finished_at = new Date().toISOString();
  evidence.resources = { network_id: network.id, device_id: guest.device_id };
  fs.writeFileSync(output, JSON.stringify(evidence, null, 2));
  process.stdout.write(JSON.stringify(evidence, null, 2));
} catch (error) {
  evidence.state = "failed";
  evidence.finished_at = new Date().toISOString();
  evidence.error = error.stack || error.message;
  fs.writeFileSync(output, JSON.stringify(evidence, null, 2));
  process.stderr.write(JSON.stringify(evidence, null, 2));
  process.exitCode = 1;
} finally {
  for (const socket of sockets) try { socket.close(); } catch {}
}
