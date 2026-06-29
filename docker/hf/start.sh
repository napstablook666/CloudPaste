#!/bin/sh
set -eu

HF_PORT="${PORT:-7860}"
BACKEND_PORT="${BACKEND_PORT:-8788}"
DATA_DIR="${DATA_DIR:-/data}"
TG_API_HOST_IP="${TG_API_HOST_IP:-}"
export HF_PORT BACKEND_PORT DATA_DIR

if [ -z "${ENCRYPTION_SECRET:-}" ] || [ "${ENCRYPTION_SECRET:-}" = "default-encryption-key" ]; then
  echo "ENCRYPTION_SECRET must be configured as a runtime secret." >&2
  exit 1
fi

mkdir -p "$DATA_DIR"

if [ -n "$TG_API_HOST_IP" ]; then
  if ! grep -q "[[:space:]]api.telegram.org" /etc/hosts 2>/dev/null; then
    echo "$TG_API_HOST_IP api.telegram.org" >> /etc/hosts || true
  fi
fi

cat > /usr/share/nginx/html/config.js <<'EOF'
window.appConfig = {
  backendUrl: ""
};
EOF

if [ -f /usr/share/nginx/html/cloudpaste.svg ]; then
  cp /usr/share/nginx/html/cloudpaste.svg /usr/share/nginx/html/x7f2a9c4.svg
fi

for f in /usr/share/nginx/html/index.html /usr/share/nginx/html/manifest.json /usr/share/nginx/html/manifest.webmanifest; do
  if [ -f "$f" ]; then
    sed -i \
      -e 's/CloudPaste/x7f2a9c4/g' \
      -e 's/cloudpaste[.]svg/x7f2a9c4.svg/g' \
      -e 's/安全分享您的内容，支持 Markdown 编辑和文件上传/q4m9_v2::7b1e6d90::a3c8f2/g' \
      -e 's/安全分享您的内容/q4m9_v2/g' \
      -e 's/文件上传/n7a/g' \
      -e 's/快速上传文件/v2b/g' \
      -e 's/文件浏览/r5c/g' \
      -e 's/浏览挂载的文件/k8d/g' \
      -e 's/上传/n7/g' \
      -e 's/浏览/r5/g' \
      "$f"
  fi
done

envsubst '${HF_PORT} ${BACKEND_PORT}' \
  < /etc/nginx/templates/default.conf.template \
  > /etc/nginx/conf.d/default.conf

cd /app/backend
PORT="$BACKEND_PORT" DATA_DIR="$DATA_DIR" ./node_modules/.bin/tsx unified-entry.js &
backend_pid="$!"

nginx -g 'daemon off;' &
nginx_pid="$!"

trap 'kill "$backend_pid" "$nginx_pid" 2>/dev/null || true' INT TERM

exit_code=0
while true; do
  if ! kill -0 "$backend_pid" 2>/dev/null; then
    wait "$backend_pid" || exit_code="$?"
    break
  fi
  if ! kill -0 "$nginx_pid" 2>/dev/null; then
    wait "$nginx_pid" || exit_code="$?"
    break
  fi
  sleep 2
done

kill "$backend_pid" "$nginx_pid" 2>/dev/null || true
exit "$exit_code"
