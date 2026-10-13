// A local stand-in for the Scareathon server's Liquid Metal arena, for testing the battle room
// without the real site. It runs the site's own route (server/routes/liquidMetal.js) on its
// own, so it needs a checkout of scareathon-v3 with server/node_modules installed.
//
//     node tools/dev_relay.mjs <path to scareathon-v3/server> [port]
//
// Then start each copy of the game with  -- --server=http://127.0.0.1:<port>

import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';

const serverDir = resolve(process.argv[2] ?? '.');
const port = Number(process.argv[3] ?? 3112);
const require = createRequire(pathToFileURL(resolve(serverDir, 'index.js')));
const Fastify = require('fastify');
const { default: routes } = await import(pathToFileURL(resolve(serverDir, 'routes/liquidMetal.js')));

const app = Fastify({ logger: { level: 'warn' } });
await app.register(routes, { prefix: '/liquid-metal' });
await app.listen({ port, host: '127.0.0.1' });
console.log(`Liquid Metal arena on ws://127.0.0.1:${port}/liquid-metal/ws`);
