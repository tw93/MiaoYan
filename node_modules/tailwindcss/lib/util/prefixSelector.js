"use strict";
Object.defineProperty(exports, "__esModule", {
    value: true
});
exports.default = _default;
var _postcssSelectorParser = _interopRequireDefault(require("postcss-selector-parser"));
function _interopRequireDefault(obj) {
    return obj && obj.__esModule ? obj : {
        default: obj
    };
}
function _default(prefix, selector, prependNegative = false) {
    return (0, _postcssSelectorParser).default((selectors)=>{
        selectors.walkClasses((classSelector)=>{
            let baseClass = classSelector.value;
            let shouldPlaceNegativeBeforePrefix = prependNegative && baseClass.startsWith("-");
            classSelector.value = shouldPlaceNegativeBeforePrefix ? `-${prefix}${baseClass.slice(1)}` : `${prefix}${baseClass}`;
        });
    }).processSync(selector);
}
