"use strict";
Object.defineProperty(exports, "__esModule", {
    value: true
});
exports.default = void 0;
var _cloneDeep = require("../util/cloneDeep");
var _defaultConfigStub = _interopRequireDefault(require("../../stubs/defaultConfig.stub"));
function _interopRequireDefault(obj) {
    return obj && obj.__esModule ? obj : {
        default: obj
    };
}
var _default = (0, _cloneDeep).cloneDeep(_defaultConfigStub.default.theme);
exports.default = _default;
