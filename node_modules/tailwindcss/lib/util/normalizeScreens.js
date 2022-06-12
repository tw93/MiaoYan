"use strict";
Object.defineProperty(exports, "__esModule", {
    value: true
});
exports.normalizeScreens = normalizeScreens;
function normalizeScreens(screens, root = true) {
    if (Array.isArray(screens)) {
        return screens.map((screen)=>{
            if (root && Array.isArray(screen)) {
                throw new Error("The tuple syntax is not supported for `screens`.");
            }
            if (typeof screen === "string") {
                return {
                    name: screen.toString(),
                    values: [
                        {
                            min: screen,
                            max: undefined
                        }
                    ]
                };
            }
            let [name, options] = screen;
            name = name.toString();
            if (typeof options === "string") {
                return {
                    name,
                    values: [
                        {
                            min: options,
                            max: undefined
                        }
                    ]
                };
            }
            if (Array.isArray(options)) {
                return {
                    name,
                    values: options.map((option)=>resolveValue(option))
                };
            }
            return {
                name,
                values: [
                    resolveValue(options)
                ]
            };
        });
    }
    return normalizeScreens(Object.entries(screens !== null && screens !== void 0 ? screens : {}), false);
}
function resolveValue({ "min-width": _minWidth , min =_minWidth , max , raw  } = {}) {
    return {
        min,
        max,
        raw
    };
}
