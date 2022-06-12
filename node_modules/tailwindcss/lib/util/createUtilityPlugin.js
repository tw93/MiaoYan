"use strict";
Object.defineProperty(exports, "__esModule", {
    value: true
});
exports.default = createUtilityPlugin;
var _transformThemeValue = _interopRequireDefault(require("./transformThemeValue"));
function createUtilityPlugin(themeKey, utilityVariations = [
    [
        themeKey,
        [
            themeKey
        ]
    ]
], { filterDefault =false , ...options } = {}) {
    let transformValue = (0, _transformThemeValue).default(themeKey);
    return function({ matchUtilities , theme  }) {
        for (let utilityVariation of utilityVariations){
            let group = Array.isArray(utilityVariation[0]) ? utilityVariation : [
                utilityVariation
            ];
            var ref;
            matchUtilities(group.reduce((obj1, [classPrefix, properties])=>{
                return Object.assign(obj1, {
                    [classPrefix]: (value)=>{
                        return properties.reduce((obj, name)=>{
                            if (Array.isArray(name)) {
                                return Object.assign(obj, {
                                    [name[0]]: name[1]
                                });
                            }
                            return Object.assign(obj, {
                                [name]: transformValue(value)
                            });
                        }, {});
                    }
                });
            }, {}), {
                ...options,
                values: filterDefault ? Object.fromEntries(Object.entries((ref = theme(themeKey)) !== null && ref !== void 0 ? ref : {}).filter(([modifier])=>modifier !== "DEFAULT")) : theme(themeKey)
            });
        }
    };
}
function _interopRequireDefault(obj) {
    return obj && obj.__esModule ? obj : {
        default: obj
    };
}
