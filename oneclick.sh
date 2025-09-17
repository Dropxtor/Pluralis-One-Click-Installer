#!/usr/bin/env bash
set -euo pipefail

echo "=== Pluralis One-Click Installer Optimisé (Dropxtor) ==="

# --- VARIABLES (à personnaliser) ---
HF_TOKEN="${HF_TOKEN:-TON_TOKEN_HF_ICI}"  # Token HuggingFace
EMAIL="${EMAIL:-ton@email.com}"
HOST_PORT="${HOST_PORT:-49200}"
DASH_PORT="${DASH_PORT:-3000}"
WORKDIR="${WORKDIR:-/opt/pluralis}"

# --- ASCII Header ---
echo " _______                                        __                       
|       \                                      |  \                      
| ▓▓▓▓▓▓▓\ ______   ______   ______  __    __ _| ▓▓_    ______   ______  
| ▓▓  | ▓▓/      \ /      \ /      \|  \  /  \   ▓▓ \  /      \ /      \ 
| ▓▓  | ▓▓  ▓▓▓▓▓▓\  ▓▓▓▓▓▓\  ▓▓▓▓▓▓\\▓▓\/  ▓▓\▓▓▓▓▓▓ |  ▓▓▓▓▓▓\  ▓▓▓▓▓▓\
| ▓▓  | ▓▓ ▓▓   \▓▓ ▓▓  | ▓▓ ▓▓  | ▓▓ >▓▓ ▓▓  | ▓▓ __| ▓▓  |  ▓▓  ▓▓   \▓▓_   
| ▓▓    ▓▓ ▓▓      \▓▓    ▓▓ ▓▓    ▓▓  ▓▓ ▓▓\  \▓▓  ▓▓\▓▓     ▓▓  ▓▓      
 \▓▓▓▓▓▓▓ \▓▓       \▓▓▓▓▓▓| ▓▓▓▓▓▓▓ \▓▓   \▓▓   \▓▓▓▓  \▓▓▓▓▓▓   ▓▓      
                           | ▓▓                                          
                           | ▓▓                                          
"

# --- 1) Nettoyer paquets conflictuels ---
echo "🧹 Suppression anciennes versions Node.js / npm / containerd..."
sudo apt remove -y nodejs npm containerd containerd.io || true
sudo apt autoremove -y
sudo apt purge -y nodejs npm containerd containerd.io || true
sudo apt-mark unhold nodejs npm || true

# --- 2) Mise à jour système ---
echo "📦 Mise à jour des paquets..."
sudo apt update && sudo apt upgrade -y

# --- 3) Installer Node.js 18 proprement ---
echo "🟢 Installation Node.js 18 + npm..."
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs build-essential
echo "✔ Node.js $(node -v) / npm $(npm -v) installés"

# --- 4) Installer Docker ---
echo "🐳 Installation Docker + Docker Compose..."
sudo apt install -y docker.io docker-compose
sudo systemctl enable docker
sudo systemctl start docker
echo "✔ Docker $(docker -v) / Docker Compose $(docker-compose -v)"

# --- 5) Préparer dossier de travail ---
echo "📂 Création dossier de travail..."
sudo mkdir -p "$WORKDIR"
sudo chown $USER:$USER "$WORKDIR"
cd "$WORKDIR"

# --- 6) Cloner node0 ---
if [ ! -d node0 ]; then
  echo "📥 Clonage dépôt node0..."
  git clone https://github.com/PluralisResearch/node0.git
fi

# --- 7) Build Docker image ---
cd node0
docker build -t pluralis_node0 .
cd ..

# --- 8) Vérifier port libre ---
if lsof -Pi :$HOST_PORT -sTCP:LISTEN -t >/dev/null ; then
    echo "⚠️ Port $HOST_PORT déjà utilisé, changez HOST_PORT et relancez"
    exit 1
fi

# --- 9) Lancer container Node ---
docker rm -f pluralis_node0 >/dev/null 2>&1 || true
docker run -d --name pluralis_node0 \
  -e HF_TOKEN="$HF_TOKEN" \
  -e EMAIL="$EMAIL" \
  -p ${HOST_PORT}:${HOST_PORT} \
  pluralis_node0

# --- 10) Installer dashboard ---
if [ ! -d dashboard ]; then
  mkdir dashboard && cd dashboard
  npm init -y >/dev/null
  npm install express socket.io >/dev/null

  # server.js
  cat > server.js <<'NODEJS'
const express = require('express');
const { exec } = require('child_process');
const http = require('http');
const socketio = require('socket.io');
const app = express();
const server = http.createServer(app);
const io = socketio(server);
const PORT = process.env.PORT || 3000;

app.use(express.static(__dirname + '/public'));

io.on('connection', socket => {
  socket.on('cmd', cmd => {
    let shell = '';
    switch(cmd){
      case 'status': shell = 'docker ps --filter name=pluralis_node0'; break;
      case 'logs': shell = 'docker logs --tail=50 -f pluralis_node0'; break;
      case 'restart': shell = 'docker restart pluralis_node0'; break;
    }
    const child = exec(shell);
    child.stdout.on('data', data => socket.emit('output', data));
    child.stderr.on('data', data => socket.emit('output', `ERR: ${data}`));
  });
});

server.listen(PORT, ()=> console.log(`Dashboard running on port ${PORT}`));
NODEJS

  # frontend
  mkdir public
  cat > public/index.html <<'HTML'
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>Pluralis Dashboard - Dropxtor</title>
<script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-gray-900 text-gray-100 flex flex-col items-center justify-center min-h-screen">
<h1 class="text-3xl font-bold mb-6 animate-pulse">🚀 Pluralis Node Dashboard</h1>
<div class="flex gap-4 mb-4">
<button onclick="send('status')" class="px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded-lg shadow-md transition transform hover:scale-105">Status</button>
<button onclick="send('logs')" class="px-4 py-2 bg-green-600 hover:bg-green-700 rounded-lg shadow-md transition transform hover:scale-105">Logs</button>
<button onclick="send('restart')" class="px-4 py-2 bg-red-600 hover:bg-red-700 rounded-lg shadow-md transition transform hover:scale-105">Restart</button>
</div>
<pre id="out" class="w-3/4 h-96 p-4 bg-black text-green-400 overflow-y-scroll rounded-xl shadow-inner border border-green-700 transition-all"></pre>
<script src="/socket.io/socket.io.js"></script>
<script>
const socket = io();
const out = document.getElementById('out');
function send(cmd){ 
  out.textContent = "⏳ Executing " + cmd + "...";
  socket.emit('cmd', cmd); 
}
socket.on('output', txt => { 
  out.textContent += "\\n" + txt; 
  out.scrollTop = out.scrollHeight; 
});
setInterval(()=>send('status'),5000); // auto-refresh status
</script>
</body>
</html>
HTML
  cd ..
fi

# --- 11) Lancer dashboard ---
pkill -f "node dashboard/server.js" || true
nohup node dashboard/server.js --port $DASH_PORT > /var/log/pluralis_dashboard.log 2>&1 &

echo "=== Installation terminée ==="
echo "Node lancé sur le port $HOST_PORT"
echo "Dashboard: http://<server-ip>:$DASH_PORT"
