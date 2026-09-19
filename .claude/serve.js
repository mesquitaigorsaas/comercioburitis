const http = require('http'), fs = require('fs'), path = require('path');
const root = process.cwd();
const tipos = { '.html':'text/html; charset=utf-8', '.css':'text/css', '.js':'text/javascript',
                '.png':'image/png', '.jpg':'image/jpeg', '.jpeg':'image/jpeg',
                '.webp':'image/webp', '.svg':'image/svg+xml', '.ico':'image/x-icon' };
http.createServer((req, res) => {
  let p = decodeURIComponent(req.url.split('?')[0]);
  if (p === '/') p = '/index.html';
  const alvo = path.join(root, p);
  if (!alvo.startsWith(root)) { res.writeHead(403).end(); return; }
  fs.readFile(alvo, (e, dados) => {
    if (e) { console.log('404', p); res.writeHead(404).end('nao encontrado'); return; }
    console.log('200', p);
    res.writeHead(200, { 'Content-Type': tipos[path.extname(alvo).toLowerCase()] || 'application/octet-stream' });
    res.end(dados);
  });
}).listen(4400, () => console.log('servindo', root, 'em http://localhost:4400'));
