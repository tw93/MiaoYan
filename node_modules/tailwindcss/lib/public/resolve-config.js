"use strict";
Object.defineProperty(exports, "__esModule", {
    value: true
});
exports.default = resolveConfig;
var _resolveConfig = _interopRequireDefault(require("../util/resolveConfig"));
var _getAllConfigs = _interopRequireDefault(require("../util/getAllConfigs"));
function resolveConfig(...configs) {
    let [, ...defaultConfigs] = (0, _getAllConfigs).default(configs[0]);
    return (0, _resolveConfig).default([
        ...configs,
        ...defaultConfigs
    ]);
}
function _interopRequireDefault(obj) {
    return obj && obj.__esModule ? obj : {
        default: obj
    };
}
