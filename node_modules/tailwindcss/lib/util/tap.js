"use strict";
Object.defineProperty(exports, "__esModule", {
    value: true
});
exports.tap = tap;
function tap(value, mutator) {
    mutator(value);
    return value;
}
