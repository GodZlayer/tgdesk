#!/usr/bin/env bash
# Backup completo do stack de produção server-tgdesk.
# Imagens + volumes + pg_dump + config, em pasta fora do repositório.
set -euo pipefail
export MSYS_NO_PATHCONV=1

TS=$(date +%Y%m%d_%H%M%S)
DEST="C:/Users/santo/Documents/TGDESK-Backups/server-tgdesk_${TS}"
mkdir -p "$DEST/config" "$DEST/db" "$DEST/images" "$DEST/volumes"

echo "=> backup em $DEST"

# 1. config
cp server/docker-compose.yml "$DEST/config/" 2>/dev/null || true
cp server/.env "$DEST/config/" 2>/dev/null || true
cp server/.env.example "$DEST/config/" 2>/dev/null || true
docker ps -a --filter "name=server-tgdesk" --format "{{.Names}}\t{{.Image}}\t{{.Status}}" > "$DEST/config/docker_ps.txt"
docker images --format "{{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}" > "$DEST/config/docker_images.txt"
docker volume ls --format "{{.Name}}" | grep -i tgdesk > "$DEST/config/volumes.txt" || true

# 2. dump lógico do banco (é o que importa para reverter dado)
docker exec server-tgdesk-postgres-1 pg_dump -U tgdesk -d tgdesk -F c -f /tmp/tgdesk_db.dump
docker cp server-tgdesk-postgres-1:/tmp/tgdesk_db.dump "$DEST/db/tgdesk_db.dump"
docker exec server-tgdesk-postgres-1 rm -f /tmp/tgdesk_db.dump
echo "=> pg_dump ok: $(du -h "$DEST/db/tgdesk_db.dump" | cut -f1)"

# 3. volumes (cópia binária bruta, container alpine somente-leitura)
while read -r vol; do
  [ -z "$vol" ] && continue
  echo "=> volume $vol"
  docker run --rm -v "${vol}:/vol:ro" -v "${DEST}/volumes:/backup" alpine \
    tar czf "/backup/${vol}.tar.gz" -C /vol . 2>/dev/null || echo "   (falhou: $vol)"
done < "$DEST/config/volumes.txt"

# 4. imagens
for img in server-tgdesk-api-core server-tgdesk-relay server-tgdesk-rendezvous postgres:16-alpine redis:7-alpine; do
  name=$(echo "$img" | tr ':/' '__')
  echo "=> imagem $img"
  docker save "$img" -o "$DEST/images/${name}.tar" 2>/dev/null || echo "   (ausente: $img)"
done

cat > "$DEST/RESTORE.md" <<EOF
# Restauração — server-tgdesk_${TS}

## Só o dado (o caso comum)
    docker cp db/tgdesk_db.dump server-tgdesk-postgres-1:/tmp/d.dump
    docker exec server-tgdesk-postgres-1 pg_restore -U tgdesk -d tgdesk --clean --if-exists /tmp/d.dump

## Stack inteiro
1. docker compose -p server-tgdesk down
2. docker load -i images/<cada>.tar
3. para cada volume: docker volume create <nome> && \\
   docker run --rm -v <nome>:/vol -v \$PWD/volumes:/backup alpine \\
     sh -c "cd /vol && tar xzf /backup/<nome>.tar.gz"
4. docker compose -f config/docker-compose.yml -p server-tgdesk up -d
EOF

echo "=> BACKUP COMPLETO: $DEST"
du -sh "$DEST"
