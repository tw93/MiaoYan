"use strict";
Object.defineProperty(exports, "__esModule", {
    value: true
});
exports.resolveDebug = resolveDebug;
exports.NOT_ON_DEMAND = exports.sourceHashMap = exports.contextSourcesMap = exports.configContextMap = exports.contextMap = exports.env = void 0;
const env = {
    NODE_ENV: process.env.NODE_ENV,
    DEBUG: resolveDebug(process.env.DEBUG)
};
exports.env = env;
const contextMap = new Map();
exports.contextMap = contextMap;
const configContextMap = new Map();
exports.configContextMap = configContextMap;
const contextSourcesMap = new Map();
exports.contextSourcesMap = contextSourcesMap;
const sourceHashMap = new Map();
exports.sourceHashMap = sourceHashMap;
const NOT_ON_DEMAND = new String("*");
exports.NOT_ON_DEMAND = NOT_ON_DEMAND;
function resolveDebug(debug) {
    if (debug === undefined) {
        return false;
    }
    // Environment variables are strings, so convert to boolean
    if (debug === "true" || debug === "1") {
        return true;
    }
    if (debug === "false" || debug === "0") {
        return false;
    }
    // Keep the debug convention into account:
    // DEBUG=* -> This enables all debug modes
    // DEBUG=projectA,projectB,projectC -> This enables debug for projectA, projectB and projectC
    // DEBUG=projectA:* -> This enables all debug modes for projectA (if you have sub-types)
    // DEBUG=projectA,-projectB -> This enables debug for projectA and explicitly disables it for projectB
    if (debug === "*") {
        return true;
    }
    let debuggers = debug.split(",").map((d)=>d.split(":")[0]);
    // Ignoring tailwindcss
    if (debuggers.includes("-tailwindcss")) {
        return false;
    }
    // Including tailwindcss
    if (debuggers.includes("tailwindcss")) {
        return true;
    }
    return false;
}
