"use strict";
Object.defineProperty(exports, "__esModule", {
    value: true
});
exports.default = toColorValue;
function toColorValue(maybeFunction) {
    return typeof maybeFunction === "function" ? maybeFunction({}) : maybeFunction;
}
