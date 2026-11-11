// ---------------------------------------------------------------------------
// Servidor estatico da UI ja' construida (dist/).
//
// POR QUE ELE EXISTE, em vez de `vite` em modo dev:
//
//   1. INJECAO DE RUM. O OneAgent injeta o agente de navegador reescrevendo a
//      resposta HTML. Com o vite dev ele NAO injeta -- medido no laboratorio:
//      a pagina volta sem Server-Timing e sem script, mesmo com o agente
//      comprovadamente carregado no processo do vite. Servindo o HTML ja'
//      pronto, com Content-Length, a injecao acontece sozinha:
//
//        X-OneAgent-JS-Injection: true
//        X-ruxit-JS-Agent: true
//        Server-Timing: dtTrId;desc="..."
//
//      Sem isso nao existe o salto navegador -> backend no Service flow.
//
//   2. MEMORIA. O vite dev transpila sob demanda e precisava de 1Gi de limite;
//      com menos que isso o kernel matava o processo por OOM e o Envoy
//      respondia "no healthy upstream" -- sintoma que aponta para a malha e
//      cuja causa estava no cgroup.
//
//   3. PARTIDA. Em modo dev a primeira requisicao compila a aplicacao inteira,
//      e por isso a readinessProbe precisava de ate' 3 minutos.
//
// Sem dependencia nova de propósito: so' modulos nativos do Node. Uma
// dependencia a mais no package.json seria mais uma coisa para falhar durante
// o `npm install` da aula.
// ---------------------------------------------------------------------------
const http = require("http");
const fs = require("fs");
const path = require("path");

const RAIZ = process.env.RAIZ_ESTATICA || "/bankapp/dist";
const PORTA = Number(process.env.PORT || 3000);

const TIPOS = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".ico": "image/x-icon",
  ".webp": "image/webp",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
  ".ttf": "font/ttf",
  ".map": "application/json; charset=utf-8",
};

// Resolve dentro da RAIZ e recusa qualquer caminho que escape dela: sem esta
// checagem, GET /../../etc/passwd serve o arquivo.
function resolverSeguro(urlPath) {
  const semQuery = urlPath.split("?")[0].split("#")[0];
  let decodificado;
  try {
    decodificado = decodeURIComponent(semQuery);
  } catch {
    return null; // %-encoding invalido
  }
  const destino = path.resolve(RAIZ, "." + path.posix.normalize(decodificado));
  if (destino !== RAIZ && !destino.startsWith(RAIZ + path.sep)) return null;
  return destino;
}

function enviar(res, status, corpo, tipo) {
  res.writeHead(status, {
    "Content-Type": tipo,
    // Content-Length explicito: e' o que permite a injecao do agente de RUM.
    "Content-Length": Buffer.byteLength(corpo),
  });
  res.end(corpo);
}

function enviarArquivo(res, arquivo) {
  const corpo = fs.readFileSync(arquivo);
  const tipo = TIPOS[path.extname(arquivo).toLowerCase()] || "application/octet-stream";
  res.writeHead(200, {
    "Content-Type": tipo,
    "Content-Length": corpo.length,
    // O index.html NUNCA pode ser cacheado: o entrypoint injeta nele, em tempo
    // de execucao, a origem das APIs e o agente de RUM. Os assets tem hash no
    // nome, entao podem ser cacheados para sempre.
    "Cache-Control": path.basename(arquivo) === "index.html"
      ? "no-cache, no-store, must-revalidate"
      : "public, max-age=31536000, immutable",
  });
  res.end(corpo);
}

const INDEX = path.join(RAIZ, "index.html");

const servidor = http.createServer((req, res) => {
  if (req.method !== "GET" && req.method !== "HEAD") {
    return enviar(res, 405, "Method Not Allowed", "text/plain; charset=utf-8");
  }

  const destino = resolverSeguro(req.url || "/");
  if (destino === null) {
    return enviar(res, 400, "Bad Request", "text/plain; charset=utf-8");
  }

  try {
    if (fs.existsSync(destino) && fs.statSync(destino).isFile()) {
      return enviarArquivo(res, destino);
    }
    // Rota de SPA (/login, /transactions, ...): quem responde e' o index.html,
    // e o roteador do React resolve no navegador. Sem este desvio, recarregar
    // a pagina em qualquer rota que nao a raiz devolve 404.
    if (fs.existsSync(INDEX)) {
      return enviarArquivo(res, INDEX);
    }
    return enviar(res, 404, "Not Found", "text/plain; charset=utf-8");
  } catch (e) {
    console.error("[ui] erro ao servir", req.url, e.message);
    return enviar(res, 500, "Internal Server Error", "text/plain; charset=utf-8");
  }
});

servidor.listen(PORTA, "0.0.0.0", () => {
  console.log(`[ui] servindo ${RAIZ} na porta ${PORTA}`);
});
