import fs from "node:fs";

const base = "http://10.70.0.1:8080";
const out = "/tests/artifacts/management-lifecycle.json";
const evidence = {
  schema_version: 1,
  scenario: "management-rbac-lifecycle-backend",
  state: "running",
  measured_at: new Date().toISOString(),
  assertions: [],
};
const sockets = [];
const ok = (condition, id, name, details) => {
  if (!condition) throw new Error(`${id}: ${name}`);
  if (!evidence.assertions.some((item) => item.id === id)) {
    evidence.assertions.push({ id, name, state: "passed", details });
  }
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
  if (expected !== undefined) {
    if (response.status !== expected) throw new Error(`${method} ${path}: expected ${expected}, got ${response.status}: ${raw}`);
  } else if (!response.ok) {
    throw new Error(`${method} ${path}: ${response.status}: ${raw}`);
  }
  return data;
}
async function redeem(key, machine) {
  return request("/api/v1/auth/control-key/install", {
    method: "POST", body: { key, machine_id: machine },
  });
}
async function openEvents(token) {
  const socket = new WebSocket(`ws://10.70.0.1:8080/ws/control/technician?token=${encodeURIComponent(token)}`);
  sockets.push(socket);
  const ready = new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("websocket snapshot timeout")), 10000);
    const listener = (event) => {
      const message = JSON.parse(event.data);
      if (message.type !== "snapshot") return;
      clearTimeout(timer);
      socket.removeEventListener("message", listener);
      resolve();
    };
    socket.addEventListener("message", listener);
  });
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("websocket open timeout")), 10000);
    socket.addEventListener("open", () => { clearTimeout(timer); resolve(); }, { once: true });
    socket.addEventListener("error", () => reject(new Error("websocket open failed")), { once: true });
  });
  await ready;
  return socket;
}
function waitEvent(socket, type, target) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`event timeout: ${type}/${target}`)), 10000);
    const listener = (event) => {
      const message = JSON.parse(event.data);
      if (message.type !== "event" || message.event?.type !== type || message.event?.target_id !== target) return;
      clearTimeout(timer);
      socket.removeEventListener("message", listener);
      resolve(message.event);
    };
    socket.addEventListener("message", listener);
  });
}
async function registerBind(admin, network, suffix, index, role = "host") {
  const device = await request("/api/v1/devices/register", {
    method: "POST",
    body: {
      hostname: `WIN-${suffix}-${index}`,
      mac: `02:48:${String(index).padStart(2, "0")}:${suffix.slice(-2)}:10:20`,
      role,
    },
  });
  await request("/api/v1/pairing/bind", {
    method: "POST", token: admin.token,
    body: { pairing_code: device.pairing_code, organization_id: network.organization_id, network_id: network.id },
  });
  return device;
}

try {
  const adminKey = JSON.parse(fs.readFileSync("/tests/artifacts/keys/admin.tgdesk-key", "utf8"));
  const suffix = Date.now().toString(36);
  // The isolated authority deliberately has one Admin machine. Reuse that
  // synthetic machine identity; creating a second one must remain impossible.
  const admin = await redeem(adminKey, "testlab-admin-vm");
  const adminWS = await openEvents(admin.token);

  const extraOrg = await request("/api/v1/organizations", {
    method: "POST", token: admin.token, body: { name: `Extra ${suffix}` },
  });
  const renamedOrgEvent = waitEvent(adminWS, "organization_renamed", extraOrg.id);
  await request(`/api/v1/organizations/${extraOrg.id}`, {
    method: "PUT", token: admin.token, body: { name: `Extra Renamed ${suffix}` },
  });
  await renamedOrgEvent;

  const supervisor = await request("/api/v1/technicians", {
    method: "POST", token: admin.token, body: { name: `Supervisor ${suffix}` },
  });
  let organizations = await request("/api/v1/organizations", { token: admin.token });
  const personalOrg = organizations.find((item) => item.owner_technician_id === supervisor.id);
  ok(personalOrg?.name === supervisor.username, "hierarchy.names.rules",
    "supervisor organization is created with supervisor name");

  const enrollment = await request(`/api/v1/technicians/${supervisor.id}/enrollment-key`, {
    method: "POST", token: admin.token, body: { expires_in_hours: 1 },
  });
  const supervisorAuth = await redeem(enrollment, `management-supervisor-${suffix}`);
  const supervisorWS = await openEvents(supervisorAuth.token);
  const ownNetwork = await request("/api/v1/networks", {
    method: "POST", token: supervisorAuth.token,
    body: { organization_id: extraOrg.id, name: `Own ${suffix}` },
  });
  const otherNetwork = await request("/api/v1/networks", {
    method: "POST", token: admin.token,
    body: { organization_id: extraOrg.id, name: `Other ${suffix}` },
  });
  const renameEvent = waitEvent(adminWS, "network_renamed", ownNetwork.id);
  await request(`/api/v1/networks/${ownNetwork.id}`, {
    method: "PUT", token: supervisorAuth.token, body: { name: `Own Renamed ${suffix}` },
  });
  await renameEvent;
  await request(`/api/v1/networks/${otherNetwork.id}`, {
    method: "PUT", token: supervisorAuth.token, body: { name: "Forbidden" }, expected: 403,
  });
  await request(`/api/v1/networks/${otherNetwork.id}`, {
    method: "PUT", token: admin.token, body: { name: `Admin Renamed ${suffix}` },
  });
  ok(true, "hierarchy.network.rename", "owner renames own network, admin renames all, non-owner is forbidden");

  const control = await registerBind(admin, ownNetwork, suffix, 1, "tecnico");
  await request(`/api/v1/devices/${control.device_id}/control-machine`, {
    method: "POST", token: supervisorAuth.token, body: {},
  });
  const deviceRenameEvent = waitEvent(adminWS, "device_renamed", control.device_id);
  await request(`/api/v1/devices/${control.device_id}/display-name`, {
    method: "PATCH", token: supervisorAuth.token, body: { display_name: `Novo Supervisor ${suffix}` },
  });
  await deviceRenameEvent;
  organizations = await request("/api/v1/organizations", { token: admin.token });
  const devicesAfterRename = await request("/api/v1/devices", { token: admin.token });
  const renamedControl = devicesAfterRename.find((item) => item.id === control.device_id);
  ok(renamedControl.display_name === `Novo Supervisor ${suffix}` &&
    renamedControl.hostname === `WIN-${suffix}-1`,
    "devices.display-name", "display name changes without modifying Windows hostname");
  ok(organizations.find((item) => item.owner_technician_id === supervisor.id)?.name === `Novo Supervisor ${suffix}`,
    "hierarchy.names.rules", "supervisor organization follows control-device display name");

  await request(`/api/v1/devices/${control.device_id}/networks`, {
    method: "PUT", token: supervisorAuth.token,
    body: { network_ids: [ownNetwork.id, otherNetwork.id] }, expected: 403,
  });
  await request("/api/v1/technicians/assignments", {
    method: "POST", token: admin.token,
    body: { technician_id: supervisor.id, network_id: otherNetwork.id },
  });
  await request(`/api/v1/devices/${control.device_id}/networks`, {
    method: "PUT", token: supervisorAuth.token,
    body: { network_ids: [ownNetwork.id, otherNetwork.id] },
  });
  const client = await registerBind(admin, ownNetwork, suffix, 2);
  await request(`/api/v1/devices/${client.device_id}/networks`, {
    method: "PUT", token: admin.token,
    body: { network_ids: [ownNetwork.id, otherNetwork.id] }, expected: 403,
  });
  ok(true, "hierarchy.multi-network.control-only",
    "control device can join authorized multiple networks while client is rejected");

  await request(`/api/v1/admin/suspend/device/${client.device_id}`, {
    method: "POST", token: admin.token, body: {},
  });
  let list = await request("/api/v1/devices", { token: admin.token });
  ok(list.find((x) => x.id === client.device_id)?.state === "suspenso" &&
    list.find((x) => x.id === control.device_id)?.state === "ativo",
    "suspend.device.only", "individual suspension does not affect sibling device");
  await request(`/api/v1/admin/resume/device/${client.device_id}`, {
    method: "POST", token: admin.token, body: {},
  });

  await request(`/api/v1/networks/${ownNetwork.id}/suspend`, {
    method: "POST", token: supervisorAuth.token, body: {},
  });
  list = await request("/api/v1/devices", { token: admin.token });
  ok(list.filter((x) => [client.device_id, control.device_id].includes(x.id)).every((x) => x.state === "suspenso"),
    "suspend.network.cascade", "network suspension preserves links and suspends members");
  await request(`/api/v1/networks/${ownNetwork.id}/resume`, {
    method: "POST", token: supervisorAuth.token, body: {},
  });

  await request(`/api/v1/admin/suspend/technician/${supervisor.id}`, {
    method: "POST", token: admin.token, body: {},
  });
  organizations = await request("/api/v1/organizations", { token: admin.token });
  const networks = await request("/api/v1/networks", { token: admin.token });
  list = await request("/api/v1/devices", { token: admin.token });
  ok(organizations.find((x) => x.id === personalOrg.id)?.status === "suspensa" &&
    networks.filter((x) => x.organization_id === personalOrg.id).every((x) => x.status === "suspensa"),
    "suspend.technician.cascade", "supervisor suspension cascades to owned organization and networks");
  await request(`/api/v1/admin/resume/technician/${supervisor.id}`, {
    method: "POST", token: admin.token, body: {},
  });

  const orgCascade = await request("/api/v1/organizations", {
    method: "POST", token: admin.token, body: { name: `Cascade ${suffix}` },
  });
  const orgNetwork = await request("/api/v1/networks", {
    method: "POST", token: admin.token, body: { organization_id: orgCascade.id, name: `CascadeNet ${suffix}` },
  });
  const orgDevice = await registerBind(admin, orgNetwork, suffix, 3);
  await request(`/api/v1/admin/suspend/organization/${orgCascade.id}`, {
    method: "POST", token: admin.token, body: {},
  });
  list = await request("/api/v1/devices", { token: admin.token });
  ok(list.find((x) => x.id === orgDevice.device_id)?.state === "suspenso",
    "suspend.organization.cascade", "organization suspension preserves binding and suspends descendant");
  await request(`/api/v1/admin/resume/organization/${orgCascade.id}`, {
    method: "POST", token: admin.token, body: {},
  });

  const deleteNetwork = await request("/api/v1/networks", {
    method: "POST", token: admin.token, body: { organization_id: orgCascade.id, name: `Delete ${suffix}` },
  });
  const deleteDevice = await registerBind(admin, deleteNetwork, suffix, 4);
  await request(`/api/v1/networks/${deleteNetwork.id}`, { method: "DELETE", token: admin.token });
  list = await request("/api/v1/devices", { token: admin.token });
  const guestAgain = list.find((x) => x.id === deleteDevice.device_id);
  ok(guestAgain?.state === "guest" && !guestAgain.network_id,
    "delete.network.unbind", "deleting sole network returns device to guest with no network");

  evidence.state = "passed";
  evidence.finished_at = new Date().toISOString();
  evidence.resources = { supervisor_id: supervisor.id, devices: [control.device_id, client.device_id, orgDevice.device_id] };
  fs.writeFileSync(out, JSON.stringify(evidence, null, 2));
  process.stdout.write(JSON.stringify(evidence, null, 2));
} catch (error) {
  evidence.state = "failed";
  evidence.finished_at = new Date().toISOString();
  evidence.error = error.stack || error.message;
  fs.writeFileSync(out, JSON.stringify(evidence, null, 2));
  process.stderr.write(JSON.stringify(evidence, null, 2));
  process.exitCode = 1;
} finally {
  for (const socket of sockets) try { socket.close(); } catch {}
}
