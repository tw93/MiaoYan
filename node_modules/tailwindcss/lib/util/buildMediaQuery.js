"use strict";
Object.defineProperty(exports, "__esModule", {
    value: true
});
exports.default = buildMediaQuery;
function buildMediaQuery(screens) {
    screens = Array.isArray(screens) ? screens : [
        screens
    ];
    return screens.map((screen1)=>screen1.values.map((screen)=>{
            if (screen.raw !== undefined) {
                return screen.raw;
            }
            return [
                screen.min && `(min-width: ${screen.min})`,
                screen.max && `(max-width: ${screen.max})`, 
            ].filter(Boolean).join(" and ");
        })).join(", ");
}
