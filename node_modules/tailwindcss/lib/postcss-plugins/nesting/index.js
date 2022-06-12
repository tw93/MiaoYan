"use strict";
Object.defineProperty(exports, "__esModule", {
    value: true
});
exports.default = void 0;
var _plugin = require("./plugin");
var _default = Object.assign(function(opts) {
    return {
        postcssPlugin: "tailwindcss/nesting",
        Once (root, { result  }) {
            return (0, _plugin).nesting(opts)(root, result);
        }
    };
}, {
    postcss: true
});
exports.default = _default;
