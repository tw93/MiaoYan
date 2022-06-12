"use strict";
Object.defineProperty(exports, "__esModule", {
    value: true
});
exports.default = escapeClassName;
var _postcssSelectorParser = _interopRequireDefault(require("postcss-selector-parser"));
var _escapeCommas = _interopRequireDefault(require("./escapeCommas"));
function escapeClassName(className) {
    var ref;
    let node = _postcssSelectorParser.default.className();
    node.value = className;
    var ref1;
    return (0, _escapeCommas).default((ref1 = node === null || node === void 0 ? void 0 : (ref = node.raws) === null || ref === void 0 ? void 0 : ref.value) !== null && ref1 !== void 0 ? ref1 : node.value);
}
function _interopRequireDefault(obj) {
    return obj && obj.__esModule ? obj : {
        default: obj
    };
}
