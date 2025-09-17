#!/usr/bin/env bash
set -euo pipefail

echo "=== Pluralis One-Click Installer (Dropxtor) ==="
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
echo "=================================="


# === VARIABLES À MODIFIER ===
HF_TOKEN="TON_TOKEN_HF_ICI"
EMAIL="ton@email.com"
HOST_PORT=49200
DASH_PORT=3000
WORKDIR="/opt/pluralis"

# 1) Prérequis
apt update -y && apt upgrade -y
apt install -y git curl wget jq build-essential docker.io nodejs npm

# 2) Récupération node0
mkdir -p $WORKDIR && cd $WORKDIR
if [ ! -d node0 ]; then
  git clone https://github.com/PluralisResearch/node0.git
fi

# 3) Build image Docker
cd node0
docker build . -t pluralis_node0
cd ..

# 4) Lancer container node
docker rm -f pluralis_node0 >/dev/null 2>&1 || true
docker run -d --name pluralis_node0 \
  -e HF_TOKEN=$HF_TOKEN \
  -e EMAIL=$EMAIL \
  -p ${HOST_PORT}:${HOST_PORT} \
  pluralis_node0

# 5) Installer dashboard interactif animé
if [ ! -d dashboard ]; then
  mkdir dashboard && cd dashboard
  npm init -y
  npm install express socket.io
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
  </script>
</body>
</html>
HTML
  cd ..
fi

# 6) Lancer dashboard
pkill -f "node dashboard/server.js" || true
nohup node dashboard/server.js --port $DASH_PORT > /var/log/pluralis_dashboard.log 2>&1 &

echo "=== Installation terminée ==="
echo "Node lancé sur le port $HOST_PORT"
echo "Dashboard: http://<server-ip>:$DASH_PORT"
