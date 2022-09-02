import JavaScriptCore

enum ConfigurationKey: String {
    case parser = "parser"
    case rangeStart = "rangeStart"
    case rangeEnd = "rangeEnd"
    case cursorOffset = "cursorOffset"
    case plugins = "plugins"
    case printWidth = "printWidth"
    case tabWidth = "tabWidth"
    case useTabs = "useTabs"
    case semicolons = "semi"
    case singleQuote = "singleQuote"
    case quoteProperties = "quoteProps"
    case jsxSingleQuote = "jsxSingleQuote"
    case trailingCommas = "trailingComma"
    case bracketSpacing = "bracketSpacing"
    case bracketSameLine = "bracketSameLine"
    case arrowFunctionParentheses = "arrowParens"
    case proseWrap = "proseWrap"
    case htmlWhitespaceSensitivity = "htmlWhitespaceSensitivity"
    case vueIndentScriptAndStyle = "vueIndentScriptAndStyle"
    case endOfLine = "endOfLine"
    case embeddedLanguageFormatting = "embeddedLanguageFormatting"
}

extension JSValue {
    func setObject(_ object: Any!, forKeyedSubscript key: ConfigurationKey) {
        setObject(object, forKeyedSubscript: key.rawValue)
    }
}
