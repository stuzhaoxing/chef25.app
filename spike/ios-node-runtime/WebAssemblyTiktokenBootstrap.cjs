'use strict';

const path = require('node:path');
const Module = require('node:module');

const fallbackPath = path.join(__dirname, 'tiktoken-wasmless.cjs');
const originalResolveFilename = Module._resolveFilename;
const originalLoad = Module._load;
const wrappedModules = new Map();

Module._resolveFilename = function resolveTiktokenFallback(
    request,
    parent,
    isMain,
    options,
) {
    if (request === 'tiktoken') {
        return fallbackPath;
    }

    return originalResolveFilename.call(this, request, parent, isMain, options);
};

Module._load = function loadWasmlessWebpackHash(request, parent, isMain) {
    const resolved = Module._resolveFilename(request, parent, isMain);

    if (resolved.endsWith('/webpack/lib/util/createHash.js')) {
        const cached = wrappedModules.get(resolved);
        if (cached) {
            return cached;
        }

        const createHash = originalLoad.call(this, resolved, parent, isMain);
        const createHashWithoutWasm = function createHashWithoutWasm(algorithm) {
            return createHash(algorithm === 'md4' ? 'sha256' : algorithm);
        };

        wrappedModules.set(resolved, createHashWithoutWasm);
        return createHashWithoutWasm;
    }

    return originalLoad.call(this, request, parent, isMain);
};

console.info(
    '[Chef25NodeSpike] native Node.js runtime',
    process.version,
    'with WASM-free tiktoken and Webpack hash fallbacks enabled',
);
