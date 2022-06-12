"use strict";
Object.defineProperty(exports, "__esModule", {
    value: true
});
exports.default = responsive;
var _postcss = _interopRequireDefault(require("postcss"));
var _cloneNodes = _interopRequireDefault(require("./cloneNodes"));
function responsive(rules) {
    return _postcss.default.atRule({
        name: "responsive"
    }).append((0, _cloneNodes).default(Array.isArray(rules) ? rules : [
        rules
    ]));
}
function _interopRequireDefault(obj) {
    return obj && obj.__esModule ? obj : {
        default: obj
    };
}
