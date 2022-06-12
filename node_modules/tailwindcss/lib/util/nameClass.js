"use strict";
Object.defineProperty(exports, "__esModule", {
    value: true
});
exports.default = nameClass;
exports.asClass = asClass;
exports.formatClass = formatClass;
var _escapeClassName = _interopRequireDefault(require("./escapeClassName"));
var _escapeCommas = _interopRequireDefault(require("./escapeCommas"));
function nameClass(classPrefix, key) {
    return asClass(formatClass(classPrefix, key));
}
function _interopRequireDefault(obj) {
    return obj && obj.__esModule ? obj : {
        default: obj
    };
}
function asClass(name) {
    return (0, _escapeCommas).default(`.${(0, _escapeClassName).default(name)}`);
}
function formatClass(classPrefix, key) {
    if (key === "DEFAULT") {
        return classPrefix;
    }
    if (key === "-" || key === "-DEFAULT") {
        return `-${classPrefix}`;
    }
    if (key.startsWith("-")) {
        return `-${classPrefix}${key}`;
    }
    return `${classPrefix}-${key}`;
}
