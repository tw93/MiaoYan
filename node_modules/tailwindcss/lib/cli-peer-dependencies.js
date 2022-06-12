"use strict";
Object.defineProperty(exports, "__esModule", {
    value: true
});
exports.lazyPostcss = lazyPostcss;
exports.lazyPostcssImport = lazyPostcssImport;
exports.lazyAutoprefixer = lazyAutoprefixer;
exports.lazyCssnano = lazyCssnano;
function lazyPostcss() {
    return require("postcss");
}
function lazyPostcssImport() {
    return require("postcss-import");
}
function lazyAutoprefixer() {
    return require("autoprefixer");
}
function lazyCssnano() {
    return require("cssnano");
}
