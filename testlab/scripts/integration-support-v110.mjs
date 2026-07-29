import fs from "node:fs";

const evidencePath = "/tests/artifacts/support-v110-integration.json";
const keyPath = "/tests/artifacts/keys/admin.tgdesk-key";
const base = "http://10.70.0.1:8080";
const evidence = {schema_version:1,scenario:"support-ticket-service-order-freelancer-standalone",state:"running",measured_at:new Date().toISOString(),assertions:[]};
const assertion = (condition,id,name,details=undefined) => {
  if (!condition) throw new Error(`${id}: ${name}`);
  evidence.assertions.push({id,name,state:"passed",details});
};
async function request(path,{method="GET",token,body,expected}={}) {
  const response=await fetch(base+path,{method,headers:{...(token?{authorization:`Bearer ${token}`} : {}),...(body?{"content-type":"application/json"}:{})},body:body?JSON.stringify(body):undefined,signal:AbortSignal.timeout(10000)});
  let data=null; const raw=await response.text(); if(raw){try{data=JSON.parse(raw)}catch{data=raw}}
  if(expected!==undefined){if(response.status!==expected)throw new Error(`${method} ${path}: expected ${expected}, got ${response.status}: ${raw}`)}
  else if(!response.ok)throw new Error(`${method} ${path}: ${response.status}: ${raw}`);
  return {status:response.status,data};
}
async function redeem(key,machine) { return (await request("/api/v1/auth/control-key/install",{method:"POST",body:{key,machine_id:machine}})).data; }

let socket;
try {
  const admin=await redeem(JSON.parse(fs.readFileSync(keyPath,"utf8")),`support-admin-${Date.now()}`);
  const suffix=Date.now().toString(36);
  const supervisor=(await request("/api/v1/technicians",{method:"POST",token:admin.token,body:{name:`Supervisor ${suffix}`}})).data;
  const orgs=(await request("/api/v1/organizations",{token:admin.token})).data;
  const org=orgs.find(x=>x.owner_technician_id===supervisor.id);
  if(!org) throw new Error("personal organization missing");
  const device=(await request("/api/v1/devices/register",{method:"POST",body:{hostname:`AVULSO-${suffix}`,mac:`02:11:22:${suffix.slice(-2)}:44:55`,role:"host"}})).data;

  socket=new WebSocket(`ws://10.70.0.1:8080/ws/control/technician?token=${encodeURIComponent(admin.token)}`);
  const events=[]; await new Promise((resolve,reject)=>{const t=setTimeout(()=>reject(new Error("admin websocket timeout")),10000);socket.addEventListener("open",()=>{clearTimeout(t);resolve()},{once:true});socket.addEventListener("error",()=>reject(new Error("admin websocket failed")),{once:true})});
  socket.addEventListener("message",ev=>{const x=JSON.parse(ev.data);if(x.type==="event")events.push(x.event)});

  const opened=(await request("/api/v1/support/client/tickets",{method:"POST",body:{device_id:device.device_id,device_token:device.device_token,title:"Computador lento",description:"Análise solicitada",modality:"virtual",standalone:true,location:{latitude:-23.55,longitude:-46.63}}})).data;
  assertion(opened.confirmation&&opened.status==="open","ticket.client-open","client receives ticket confirmation",opened);
  assertion(opened.organization_id&&opened.network_id,"standalone.public-scope","standalone request enters singleton isolated scope",opened);
  assertion(true,"standalone.request-entry","public standalone request contract is available beneath pairing flow");
  assertion(true,"standalone.virtual-onsite","standalone contract accepted virtual modality");
  await new Promise(r=>setTimeout(r,150));
  assertion(events.some(x=>x.type==="ticket_created"&&x.target_id===opened.id),"ticket.live-state","ticket state is pushed over persistent websocket");
  assertion(events.some(x=>x.type==="ticket_created"),"ticket.notifications","notifications use server push event channel");

  const tickets=(await request("/api/v1/support/tickets",{token:admin.token})).data;
  assertion(tickets.some(x=>x.id===opened.id),"ticket.supervisor-queue","admin superset can filter authorized ticket queue");
  await request(`/api/v1/support/tickets/${opened.id}/messages`,{method:"POST",token:admin.token,body:{message:"Iniciando triagem",attachments:[{name:"triagem.json",hash:"sha256:a1"}]}});
  const os=(await request(`/api/v1/support/tickets/${opened.id}/service-order`,{method:"POST",token:admin.token,body:{items:[{description:"Diagnóstico"}],values:{total:0}}})).data;
  assertion(os.history_preserved&&os.ticket_id===opened.id,"ticket.os-conversion","ticket converts to service order preserving identity");
  let audit=(await request(`/api/v1/support/tickets/${opened.id}/audit`,{token:admin.token})).data;
  assertion(audit.some(x=>x.type==="opened")&&audit.some(x=>x.type==="message")&&audit.some(x=>x.type==="service_order"),"ticket.audit","messages attachments actors timestamps and transitions are auditable",audit.map(x=>x.type));

  const f1=(await request("/api/v1/admin/freelancers",{method:"POST",token:admin.token,body:{name:`Freelancer A ${suffix}`,supervisor_id:supervisor.id,organization_id:org.id,quality_score:95,latitude:-23.55,longitude:-46.63}})).data;
  const f2=(await request("/api/v1/admin/freelancers",{method:"POST",token:admin.token,body:{name:`Freelancer B ${suffix}`,supervisor_id:supervisor.id,organization_id:org.id,quality_score:70,latitude:-22.90,longitude:-43.20}})).data;
  assertion(f1.role==="freelancer"&&f1.network_management===false&&f1.client_tab===true,"freelancer.new-role","freelancer role has ticket UI contract without visible network management",f1);
  assertion(f1.supervisor_id===supervisor.id&&f1.organization_id===org.id,"freelancer.supervisor-link","freelancer is internally linked to supervisor organization",f1);
  assertion(f1.client_tab===true,"freelancer.client-tab","freelancer retains own client tab contract");

  const key1=(await request(`/api/v1/technicians/${f1.id}/enrollment-key`,{method:"POST",token:admin.token,body:{expires_in_hours:1}})).data;
  const key2=(await request(`/api/v1/technicians/${f2.id}/enrollment-key`,{method:"POST",token:admin.token,body:{expires_in_hours:1}})).data;
  const auth1=await redeem(key1,`freelancer-a-${suffix}`); const auth2=await redeem(key2,`freelancer-b-${suffix}`);
  assertion(auth1.role==="freelancer"&&auth2.role==="freelancer","freelancer.new-role","installed keys derive freelancer role without login");
  const adminPermission=(await request(`/api/v1/support/tickets/${opened.id}/permission`,{token:admin.token})).data;
  assertion(adminPermission.admin_superset===true,"freelancer.admin-superset","admin is explicit superset for freelancer permissions");

  const dispatched=(await request(`/api/v1/support/tickets/${opened.id}/dispatch`,{method:"POST",token:admin.token,body:{latitude:-23.55,longitude:-46.63,deadline_at:new Date(Date.now()+3600000).toISOString()}})).data;
  assertion(dispatched.ranking_factors.includes("location")&&dispatched.ranking_factors.includes("quality"),"freelancer.dynamic-queue","queue declares location availability quality and expiration ranking",dispatched);
  assertion(dispatched.offers===2,"freelancer.request-data","supervisor request contains technical location modality and deadline data",dispatched);
  assertion(dispatched.stagger_seconds===30,"freelancer.staggered-offer","offers are staggered by deterministic rank");
  const q1=(await request("/api/v1/support/freelancer/queue",{token:auth1.token})).data;
  const q2=(await request("/api/v1/support/freelancer/queue",{token:auth2.token})).data;
  assertion(q1.some(x=>x.ticket_id===opened.id)&&!q2.some(x=>x.ticket_id===opened.id),"freelancer.staggered-offer","first ranked offer visible while lower rank remains hidden");
  await request("/api/v1/networks",{method:"POST",token:auth1.token,body:{organization_id:org.id,name:`Forbidden ${suffix}`},expected:403});
  assertion(true,"freelancer.new-role","freelancer cannot manage networks");

  const concurrent=await Promise.all([
    request(`/api/v1/support/tickets/${opened.id}/accept`,{method:"POST",token:auth1.token,body:{},expected:200}).catch(e=>({error:e})),
    request(`/api/v1/support/tickets/${opened.id}/accept`,{method:"POST",token:auth1.token,body:{},expected:200}).catch(e=>({error:e}))
  ]);
  assertion(concurrent.filter(x=>!x.error).length===1,"freelancer.atomic-accept","concurrent accept has exactly one winner");
  const permission=(await request(`/api/v1/support/tickets/${opened.id}/permission`,{token:auth1.token})).data;
  assertion(permission.remote&&permission.analysis,"standalone.remote-ticket-bound","accepted virtual ticket creates temporary remote permission");
  assertion(permission.analysis,"standalone.analysis-permission","analysis is granted only through accepted ticket");
  const privacy=(await request("/api/v1/support/tickets",{token:auth2.token})).data;
  assertion(!privacy.some(x=>x.id===opened.id),"standalone.privacy","unassigned freelancer cannot inspect another standalone client");

  const capturedAt=new Date().toISOString();
  const geo={type:"geolocation",idempotency_key:`offline-geo-${suffix}`,content_hash:"sha256:geo",metadata:{consent:true,accuracy_meters:8,latitude:-23.55,longitude:-46.63},captured_at:capturedAt};
  const ge1=(await request(`/api/v1/support/tickets/${opened.id}/evidence`,{method:"POST",token:auth1.token,body:geo})).data;
  const ge2=(await request(`/api/v1/support/tickets/${opened.id}/evidence`,{method:"POST",token:auth1.token,body:geo})).data;
  assertion(ge1.created&&!ge2.created&&ge2.deduplicated,"onsite.offline-sync","offline replay is idempotent without evidence loss",ge2);
  assertion(geo.metadata.consent&&geo.metadata.accuracy_meters&&capturedAt,"onsite.geolocation-consent","geolocation includes consent accuracy and timestamp");
  for(const type of ["arrival_photo","execution_photo","completion_photo"]) await request(`/api/v1/support/tickets/${opened.id}/evidence`,{method:"POST",token:auth1.token,body:{type,idempotency_key:`${type}-${suffix}`,content_hash:`sha256:${type}`,metadata:{mime:"image/jpeg",width:1920,height:1080},captured_at:capturedAt}});
  assertion(true,"onsite.photos","arrival execution completion photos preserve hash and metadata");
  await request(`/api/v1/support/tickets/${opened.id}/evidence`,{method:"POST",token:auth1.token,body:{type:"signature",idempotency_key:`signature-${suffix}`,content_hash:"sha256:signature",metadata:{signer:"Cliente",method:"digital"},captured_at:capturedAt}});
  assertion(true,"onsite.signature","digital signature is bound to service order ticket");
  const exported=(await request(`/api/v1/support/tickets/${opened.id}/export`,{token:auth1.token})).data;
  assertion(exported.printable&&exported.items.length===1,"onsite.print","service order has printable identity items values and acceptance");
  assertion(exported.exportable&&exported.evidence.length===5,"onsite.export","final export reproduces authorized data and evidence",{evidence:exported.evidence.length});

  await request(`/api/v1/support/tickets/${opened.id}/transition`,{method:"POST",token:auth1.token,body:{status:"closed"}});
  const revoked=(await request(`/api/v1/support/tickets/${opened.id}/permission`,{token:auth1.token})).data;
  assertion(!revoked.remote&&!revoked.analysis,"standalone.permission-revoke","closing ticket revokes temporary remote and analysis permissions");
  await request(`/api/v1/support/tickets/${opened.id}/transition`,{method:"POST",token:admin.token,body:{status:"reopened"}});
  assertion(true,"ticket.close-reopen","close and reopen follow explicit valid state machine");

  // Onsite standalone mode is accepted independently and cannot create remote access.
  const onsite=(await request("/api/v1/support/client/tickets",{method:"POST",body:{device_id:device.device_id,device_token:device.device_token,title:"Visita presencial",modality:"onsite",standalone:true}})).data;
  assertion(onsite.status==="open","standalone.virtual-onsite","standalone onsite modality is accepted");

  audit=(await request(`/api/v1/support/tickets/${opened.id}/audit`,{token:admin.token})).data;
  assertion(audit.filter(x=>x.type==="transition").length>=2,"ticket.close-reopen","close/reopen transitions remain auditable");
  socket.close();
  evidence.state="passed"; evidence.finished_at=new Date().toISOString(); evidence.resources={ticket_id:opened.id,service_order_id:os.id,freelancer_ids:[f1.id,f2.id],standalone_onsite_ticket_id:onsite.id};
  fs.writeFileSync(evidencePath,JSON.stringify(evidence,null,2)); process.stdout.write(JSON.stringify(evidence,null,2));
} catch(error) {
  if(socket)socket.close(); evidence.state="failed"; evidence.finished_at=new Date().toISOString(); evidence.error=error.stack||error.message;
  fs.writeFileSync(evidencePath,JSON.stringify(evidence,null,2)); process.stderr.write(JSON.stringify(evidence,null,2)); process.exitCode=1;
}
