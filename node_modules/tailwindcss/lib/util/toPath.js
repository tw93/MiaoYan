"use strict";
Object.defineProperty(exports, "__esModule", {
    value: true
});
exports.toPath = toPath;
function toPath(path) {
    if (Array.isArray(path)) return path;
    let openBrackets = path.split("[").length - 1;
    let closedBrackets = path.split("]").length - 1;
    if (openBrackets !== closedBrackets) {
        throw new Error(`Path is invalid. Has unbalanced brackets: ${path}`);
    }
    return path.split(/\.(?![^\[]*\])|[\[\]]/g).filter(Boolean);
}
